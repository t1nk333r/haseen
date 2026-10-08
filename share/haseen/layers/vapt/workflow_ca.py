#!/usr/bin/env python3
"""One fingerprint-bound system anchor; called through the VAPT root gateway."""
import argparse
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import ssl
import stat
import subprocess
import sys

# -I -S disables startup hooks; only this haseen module directory is added.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from workflow_support import inspect_certificate_data

STATE = '/var/lib/haseen/vapt'
ANCHORS = '/etc/ca-certificates/trust-source/anchors'
RECORD = 'proxy-ca.json'
FINGERPRINT = re.compile(r'[A-F0-9]{64}')


def directory_fd(path, create=False, fixture=False):
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in Path(path).parts[1:]:
            try:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    raise
                os.mkdir(part, 0o755, dir_fd=fd)
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            info = os.fstat(child)
            if not fixture and (info.st_uid != 0 or info.st_mode & 0o022):
                os.close(child)
                raise ValueError('unsafe CA state/anchor ancestry')
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def read_owned(fd, name, fixture=False):
    source = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    try:
        info = os.fstat(source)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > 1024 * 1024 or (not fixture and (info.st_uid != 0 or info.st_mode & 0o022)):
            raise ValueError('CA state/anchor file is not safe and exclusively owned')
        data = bytearray()
        while len(data) <= 1024 * 1024:
            chunk = os.read(source, min(65536, 1024 * 1024 + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        if len(data) > 1024 * 1024:
            raise ValueError('CA state/anchor exceeds read limit')
        return bytes(data)
    finally:
        os.close(source)


def atomic_write(fd, name, data):
    temporary = '.' + name + '.' + os.urandom(8).hex()
    out = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644, dir_fd=fd)
    try:
        view = memoryview(data)
        while view:
            view = view[os.write(out, view):]
        os.fsync(out)
    finally:
        os.close(out)
    try:
        os.rename(temporary, name, src_dir_fd=fd, dst_dir_fd=fd)
        os.fsync(fd)
    finally:
        try:
            os.unlink(temporary, dir_fd=fd)
        except FileNotFoundError:
            pass


def record_read(fd, fixture=False):
    try:
        row = json.loads(read_owned(fd, RECORD, fixture))
    except FileNotFoundError:
        return None
    if row.get('schemaVersion') != 1 or not FINGERPRINT.fullmatch(row.get('sha256', '')) or not re.fullmatch(r'[a-f0-9]{64}', row.get('contentSha256', '')) or row.get('state') not in ('pending', 'created', 'removing'):
        raise ValueError('CA ownership record malformed')
    return row


def anchor_name(fingerprint):
    if not FINGERPRINT.fullmatch(fingerprint):
        raise ValueError('fingerprint must be 64 uppercase SHA-256 hexadecimal digits')
    return 'haseen-vapt-' + fingerprint + '.crt'


def ca_status(root=''):
    result = {'schemaVersion': 1, 'state': 'none', 'reason': 'no haseen-owned proxy CA anchor', 'anchor': None}
    state_fd = anchor_fd = None
    try:
        try:
            state_fd = directory_fd(root + STATE, fixture=bool(root))
            row = record_read(state_fd, bool(root))
        except FileNotFoundError:
            row = None
        try:
            anchor_fd = directory_fd(root + ANCHORS, fixture=bool(root))
            names = [n for n in os.listdir(anchor_fd) if n.startswith('haseen-vapt-') and n.endswith('.crt')]
        except FileNotFoundError:
            names = []
        if row is None:
            if names:
                result.update(state='foreign', reason='unrecorded haseen-named anchor preserved')
            return result
        name = anchor_name(row['sha256'])
        if any(n != name for n in names):
            result.update(state='foreign', reason='additional unowned haseen-named anchor preserved')
            return result
        try:
            data = read_owned(anchor_fd, name, bool(root)) if anchor_fd is not None else None
        except FileNotFoundError:
            data = None
        unchanged = data is not None and hashlib.sha256(data).hexdigest() == row['contentSha256']
        result['anchor'] = {'sha256': row['sha256'], 'subject': row.get('subject', ''), 'issuer': row.get('issuer', ''),
                            'path': ANCHORS + '/' + name, 'unchanged': unchanged}
        result.update(state='owned' if unchanged else 'modified', reason='unchanged fingerprint-bound owned anchor' if unchanged else 'owned anchor missing or modified; preserved')
        if unchanged and row['state'] != 'created':
            result.update(state='unknown', reason='owned anchor transaction incomplete; no success assumed')
    except (OSError, ValueError, TypeError, KeyError):
        result.update(state='unknown', reason='CA ownership state unsafe or unreadable; preserved')
    finally:
        if state_fd is not None:
            os.close(state_fd)
        if anchor_fd is not None:
            os.close(anchor_fd)
    return result


def mutate(action, fingerprint, der=None, root='', updater=None):
    """FD-bound root transaction. ROOT/updater are library-only test seams.

    CLI never accepts a sysroot or test updater. Pending records retain honest
    ownership after updater failure; no foreign/modified file is overwritten.
    """
    name = anchor_name(fingerprint)
    if not root and os.geteuid() != 0:
        raise ValueError('CA mutation requires the privileged VAPT gateway')
    certificate = None
    if action == 'trust':
        certificate = inspect_certificate_data(der)
        if certificate['state'] != 'valid' or certificate['certificate']['sha256'] != fingerprint:
            raise ValueError('CA bytes no longer match the accepted valid fingerprint')
    state_fd = directory_fd(root + STATE, create=True, fixture=bool(root))
    anchor_fd = lock_fd = None
    try:
        lock_fd = os.open('proxy-ca.lock', os.O_RDONLY | os.O_CREAT | os.O_NOFOLLOW, 0o644, dir_fd=state_fd)
        lock_info = os.fstat(lock_fd)
        if not stat.S_ISREG(lock_info.st_mode) or lock_info.st_nlink != 1 or (not root and (lock_info.st_uid != 0 or lock_info.st_mode & 0o022)):
            raise ValueError('CA lock authority unsafe')
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        anchor_fd = directory_fd(root + ANCHORS, create=True, fixture=bool(root))
        row = record_read(state_fd, bool(root))
        names = [n for n in os.listdir(anchor_fd) if n.startswith('haseen-vapt-') and n.endswith('.crt')]
        if any(n != name for n in names) or (row and row['sha256'] != fingerprint):
            raise ValueError('another owned/foreign anchor exists; preserved')
        try:
            old = read_owned(anchor_fd, name, bool(root))
        except FileNotFoundError:
            old = None
        if row is None and old is not None:
            raise ValueError('foreign anchor preserved')
        if row and (old is None or hashlib.sha256(old).hexdigest() != row['contentSha256']) and not (action == 'remove' and row['state'] == 'removing' and old is None):
            raise ValueError('modified or missing owned anchor preserved')
        if action == 'trust':
            pem = ssl.DER_cert_to_PEM_cert(der).encode('ascii')
            if row and old != pem:
                raise ValueError('retained anchor bytes disagree with accepted certificate; preserved')
            row = {'schemaVersion': 1, 'state': 'pending', 'sha256': fingerprint,
                   'contentSha256': hashlib.sha256(pem).hexdigest(), 'subject': certificate['certificate']['subject'],
                   'issuer': certificate['certificate']['issuer']}
            atomic_write(state_fd, RECORD, json.dumps(row).encode())
            if old is None:
                out = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644, dir_fd=anchor_fd)
                try:
                    view = memoryview(pem)
                    while view:
                        view = view[os.write(out, view):]
                    os.fsync(out)
                finally:
                    os.close(out)
                os.fsync(anchor_fd)
        elif action == 'remove':
            if row is None:
                raise ValueError('no unchanged owned anchor to remove')
            row['state'] = 'removing'
            atomic_write(state_fd, RECORD, json.dumps(row).encode())
            if old is not None:
                os.unlink(name, dir_fd=anchor_fd)
                os.fsync(anchor_fd)
        else:
            raise ValueError('unsupported CA mutation')
        try:
            if updater is None:
                subprocess.run(['/usr/bin/update-ca-trust'], check=True)
            else:
                updater()
        except (OSError, subprocess.CalledProcessError) as error:
            raise ValueError('system trust updater failed; anchor changes and ownership journal retained, no complete success claimed') from error
        if action == 'trust':
            row['state'] = 'created'
            atomic_write(state_fd, RECORD, json.dumps(row).encode())
        else:
            os.unlink(RECORD, dir_fd=state_fd)
            os.fsync(state_fd)
    finally:
        if lock_fd is not None:
            os.close(lock_fd)
        if anchor_fd is not None:
            os.close(anchor_fd)
        os.close(state_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['trust', 'remove'])
    parser.add_argument('fingerprint')
    args = parser.parse_args()
    try:
        if os.environ.get('HASEEN_SYSROOT'):
            raise ValueError('live CA mutation refuses HASEEN_SYSROOT')
        data = sys.stdin.buffer.read(2 * 1024 * 1024) if args.action == 'trust' else b''
        der = base64.b64decode(data, validate=True) if args.action == 'trust' else None
        mutate(args.action, args.fingerprint, der)
        print('Owned proxy CA ' + args.action + ' completed; system trust updater returned success')
        return 0
    except (OSError, ValueError, TypeError) as error:
        print('vapt: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
