"""Shared explicit local-action validation; never binds or changes trust."""
import ctypes
import json
import socket
import datetime
import ipaddress
import os
from pathlib import Path
import re
import subprocess
import ssl

def local_addresses(root=''):
    """Read assigned local interface state only; no DNS or network probes."""
    if root:
        path = Path(root + '/var/lib/haseen/vapt/addresses.json')
        rows = json.loads(path.read_text()) if path.is_file() else []
        valid = []
        for row in rows:
            address = ipaddress.ip_address(row['address'])
            interface = row['interface']
            prefix = row['prefixLength']
            if not re.fullmatch(r'[A-Za-z0-9_.:-]{1,64}', interface) or not isinstance(prefix, int) or not 0 <= prefix <= address.max_prefixlen:
                raise ValueError('invalid fixture interface metadata')
            valid.append({'interface': interface, 'address': str(address), 'family': 'ipv4' if address.version == 4 else 'ipv6',
                          'scope': 'loopback' if address.is_loopback else 'link' if address.is_link_local else 'global', 'prefixLength': prefix})
        return valid
    class Address(ctypes.Structure):
        _fields_ = [('family', ctypes.c_ushort), ('data', ctypes.c_ubyte * 26)]
    class Interface(ctypes.Structure):
        pass
    Interface._fields_ = [('next', ctypes.POINTER(Interface)), ('name', ctypes.c_char_p), ('flags', ctypes.c_uint),
                          ('address', ctypes.POINTER(Address)), ('mask', ctypes.POINTER(Address)),
                          ('other', ctypes.c_void_p), ('data', ctypes.c_void_p)]
    libc = ctypes.CDLL(None, use_errno=True)
    libc.getifaddrs.argtypes = [ctypes.POINTER(ctypes.POINTER(Interface))]
    libc.getifaddrs.restype = ctypes.c_int
    libc.freeifaddrs.argtypes = [ctypes.POINTER(Interface)]
    first = ctypes.POINTER(Interface)()
    if libc.getifaddrs(ctypes.byref(first)):
        raise OSError(ctypes.get_errno(), 'local interface state unavailable')
    rows = []
    try:
        cursor = first
        while cursor:
            item = cursor.contents
            cursor = item.next
            if not item.address or not item.mask:
                continue
            family = item.address.contents.family
            if family not in (socket.AF_INET, socket.AF_INET6):
                continue
            offset, length = (2, 4) if family == socket.AF_INET else (6, 16)
            raw = bytes(item.address.contents.data)[offset:offset + length]
            mask = bytes(item.mask.contents.data)[offset:offset + length]
            address = ipaddress.ip_address(raw)
            interface = item.name.decode('utf-8')
            if not re.fullmatch(r'[A-Za-z0-9_.:-]{1,64}', interface):
                continue
            text = str(address)
            if address.version == 6 and address.is_link_local:
                text += '%' + interface
            rows.append({'interface': interface, 'address': text, 'family': 'ipv4' if family == socket.AF_INET else 'ipv6',
                         'scope': 'loopback' if address.is_loopback else 'link' if address.is_link_local else 'global',
                         'prefixLength': sum(byte.bit_count() for byte in mask)})
    finally:
        libc.freeifaddrs(first)
    return sorted(rows, key=lambda row: (row['interface'], row['address']))



def validate_endpoint(address, port):
    """No DNS, no privileged ports; caller confirms every non-loopback bind.

    This validates intent, not availability of an interface or successful bind.
    Scoped IPv6 literals retain their explicit local interface identifier.
    """
    if not isinstance(address, str) or not address or any(c.isspace() for c in address):
        raise ValueError('bind address must be an IP literal')
    if '%' in address:
        _, scope = address.rsplit('%', 1)
        if not re.fullmatch(r'[A-Za-z0-9_.-]{1,64}', scope):
            raise ValueError('invalid IPv6 interface scope')
    try:
        ip = ipaddress.ip_address(address)
    except ValueError as error:
        raise ValueError('bind address must be an IP literal; no DNS lookup') from error
    if isinstance(port, bool) or not isinstance(port, (int, str)) or not re.fullmatch(r'[0-9]{1,5}', str(port)):
        raise ValueError('port must be an integer from 1024 to 65535')
    port = int(port)
    if not 1024 <= port <= 65535:
        raise ValueError('port must be from 1024 to 65535')
    loopback = ip.is_loopback or bool(getattr(ip, 'ipv4_mapped', None) and ip.ipv4_mapped.is_loopback)
    return {'address': str(ip), 'port': port, 'family': 'ipv4' if ip.version == 4 else 'ipv6',
            'loopback': loopback, 'requiresConfirmation': not loopback}


def open_selected(path, directory=False):
    """Open every ancestor through no-follow descriptors, retaining one inode."""
    parent = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        parts = Path(path).parts[1:]
        if not parts:
            if not directory:
                raise ValueError('root is not a regular file')
            return os.dup(parent)
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            os.close(parent)
            parent = child
        flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
        if directory:
            flags |= os.O_DIRECTORY
        return os.open(parts[-1], flags, dir_fd=parent)
    finally:
        os.close(parent)


def selected_directory(path):
    if not isinstance(path, str) or not path:
        raise ValueError('select an explicit directory')
    directory = Path(path).resolve(strict=True)
    if not directory.is_dir():
        raise ValueError('selection is not a directory')
    return directory


def confined_path(directory, relative):
    """Resolve a serving request beneath its selected root; refuse escapes.

    The serving slice must open/revalidate the selected file immediately before
    reading bytes; this helper is not an open file descriptor or race guarantee.
    """
    root = selected_directory(str(directory))
    if not isinstance(relative, str) or '\x00' in relative or Path(relative).is_absolute():
        raise ValueError('invalid relative serving path')
    candidate = (root / relative).resolve(strict=True)
    if not candidate.is_relative_to(root):
        raise ValueError('serving path escapes selected directory')
    return candidate


def selected_owned_file(path, records, root, resolve):
    """Explicit one-file selection needs unique package inventory ownership.

    RESOLVE is metadata.observed_resolve; every file symlink hop must share the
    same unique owner. No directory, executable invocation or path guess.
    """
    if not isinstance(path, str) or not path.startswith('/') or '..' in Path(path).parts:
        raise ValueError('select an explicit package-owned regular file')
    owners = {}
    for index, record in enumerate(records):
        for member in record.get('files', []):
            if isinstance(member, str) and not member.endswith('/'):
                owners.setdefault('/' + member.lstrip('/'), set()).add(index)
    expected = owners.get(path, set())
    if len(expected) != 1:
        raise ValueError('selected file ownership missing or ambiguous')
    trace = []
    target = resolve(Path(root + path), root, trace)
    boundary = Path(root or '/')
    if not target.is_file() or target.stat().st_nlink != 1 or owners.get('/' + str(target.relative_to(boundary))) != expected:
        raise ValueError('selected file is not an exclusively linked owned regular file')
    if any(p.is_symlink() and owners.get('/' + str(p.relative_to(boundary))) != expected for p in trace):
        raise ValueError('selected file symlink crosses ownership')
    return target


def _der_complete(data):
    if len(data) < 2 or data[0] != 0x30:
        return False
    size = data[1]
    if size < 128:
        return len(data) == size + 2
    count = size & 0x7f
    if not 1 <= count <= 4 or len(data) < 2 + count:
        return False
    return len(data) == int.from_bytes(data[2:2 + count], 'big') + 2 + count


def _basic_constraints_ca(der):
    """Decode the actual extension, not OpenSSL's raw malformed-text fallback."""
    crypto = ctypes.CDLL('/usr/lib/libcrypto.so.3')
    octets = ctypes.POINTER(ctypes.c_ubyte)
    crypto.d2i_X509.argtypes = [ctypes.c_void_p, ctypes.POINTER(octets), ctypes.c_long]
    crypto.d2i_X509.restype = ctypes.c_void_p
    crypto.X509_check_ca.argtypes = [ctypes.c_void_p]
    crypto.X509_check_ca.restype = ctypes.c_int
    crypto.X509_free.argtypes = [ctypes.c_void_p]
    crypto.X509_free.restype = None
    source = ctypes.cast(ctypes.c_char_p(der), octets)
    certificate = crypto.d2i_X509(None, ctypes.byref(source), len(der))
    if not certificate:
        raise ValueError('invalid DER certificate')
    try:
        # Exactly 1 means proper X509v3 basicConstraints CA:TRUE.
        # Legacy v1/keyUsage/Netscape CA results (3/4/5) are not accepted.
        return crypto.X509_check_ca(certificate) == 1
    finally:
        crypto.X509_free(certificate)


def inspect_certificate_data(data, openssl='/usr/bin/openssl'):
    """Read one CA certificate and return only nonsecret metadata.

    OpenSSL is an absolute trusted workstation parser, not a discovered tool,
    invoked only for explicit inspection; discovery/doctor never call this.
    """
    result = {'schemaVersion': 1, 'state': 'invalid', 'reason': '', 'certificate': None}
    try:
        if not isinstance(data, bytes) or len(data) > 1024 * 1024:
            raise ValueError('certificate input exceeds size limit')
        if b'PRIVATE KEY' in data:
            result.update(state='refused', reason='private-key input refused')
            return result
        pem = b'-----BEGIN CERTIFICATE-----' in data
        if pem:
            if data.count(b'-----BEGIN CERTIFICATE-----') != 1 or data.count(b'-----END CERTIFICATE-----') != 1:
                raise ValueError('select exactly one certificate; bundles refused')
            if re.fullmatch(rb'\s*-----BEGIN CERTIFICATE-----\s+[A-Za-z0-9+/=\r\n]+-----END CERTIFICATE-----\s*', data) is None:
                raise ValueError('unsupported additional PEM material')
        elif not _der_complete(data):
            raise ValueError('invalid or bundled DER certificate')
        env = {key: os.environ[key] for key in ('HOME',) if key in os.environ}
        env.update(PATH='/usr/bin:/bin', LC_ALL='C', OPENSSL_CONF='/dev/null')
        parsed = subprocess.run([openssl, 'x509', '-inform', 'PEM' if pem else 'DER', '-noout', '-subject', '-issuer',
                                 '-dates', '-fingerprint', '-sha256'], input=data,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, check=False)
        if parsed.returncode:
            raise ValueError('invalid certificate')
        text = parsed.stdout.decode('utf-8', errors='strict')
        fields = dict(line.split('=', 1) for line in text.splitlines() if '=' in line)
        fingerprint = fields.get('sha256 Fingerprint', fields.get('SHA256 Fingerprint', '')).replace(':', '')
        if not re.fullmatch(r'[A-Fa-f0-9]{64}', fingerprint):
            raise ValueError('certificate fingerprint unavailable')
        def date(key):
            return datetime.datetime.strptime(fields[key], '%b %d %H:%M:%S %Y GMT').replace(tzinfo=datetime.timezone.utc)
        before, after = date('notBefore'), date('notAfter')
        der = ssl.PEM_cert_to_DER_cert(data.decode('ascii')) if pem else data
        is_ca = _basic_constraints_ca(der)
        sanitize = lambda s: ''.join(c for c in s if c >= ' ' and not '\x7f' <= c <= '\x9f')
        result['certificate'] = {'subject': sanitize(fields['subject']), 'issuer': sanitize(fields['issuer']),
                                 'sha256': fingerprint.upper(), 'notBefore': before.isoformat().replace('+00:00', 'Z'),
                                 'notAfter': after.isoformat().replace('+00:00', 'Z'), 'isCa': is_ca, 'containsPrivateKey': False}
        now = datetime.datetime.now(datetime.timezone.utc)
        if not is_ca:
            result.update(state='refused', reason='certificate is not a CA')
        elif not before <= now <= after:
            result.update(state='refused', reason='certificate is not currently valid')
        else:
            result.update(state='valid', reason='one currently valid CA certificate; trust not changed')
    except (OSError, ValueError, KeyError, UnicodeError):
        result.update(state='invalid', reason='invalid, unreadable or unsupported single certificate input')
    return result

def read_certificate_bytes(path):
    """Read bounded immutable input without following the final link."""
    fd = None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        import stat
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > 1024 * 1024:
            raise ValueError('certificate must be one bounded regular file')
        data = bytearray()
        while len(data) <= 1024 * 1024:
            chunk = os.read(fd, min(65536, 1024 * 1024 + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        if len(data) > 1024 * 1024:
            raise ValueError('certificate exceeds read limit')
        return bytes(data)
    finally:
        if fd is not None:
            os.close(fd)

def inspect_certificate(path, openssl='/usr/bin/openssl'):
    """Inspect immutable selected bytes, not a second read of a mutable path."""
    try:
        return inspect_certificate_data(read_certificate_bytes(path), openssl)
    except (OSError, ValueError):
        return {'schemaVersion': 1, 'state': 'invalid', 'reason': 'certificate selection unreadable, redirected or not one bounded regular file', 'certificate': None}
