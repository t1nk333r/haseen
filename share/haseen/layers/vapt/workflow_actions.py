#!/usr/bin/env python3
"""Verified service/local action metadata and foreground byte serving."""
import argparse
import base64
import functools
import http.server
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import ssl
import stat
import subprocess
import sys
import urllib.parse

import workflow as wf
import metadata as meta
from workflow_support import validate_endpoint, selected_owned_file, local_addresses, inspect_certificate, inspect_certificate_data, read_certificate_bytes

FAMILIES = [('ssh', ['openssh']), ('postgresql', ['postgresql']), ('apache', ['apache']),
            ('nginx', ['nginx']), ('beef', ['beef', 'beef-xss'])]
# Reviewed concrete adapter bindings, never package-basename inference.
ADAPTERS = {'listener': ('openbsd-netcat', '/usr/bin/nc'), 'http-server': ('python', '/usr/bin/python'),
            'enumeration-host': ('python', '/usr/bin/python'), 'proxy-ca': ('openssl', '/usr/bin/openssl'),
            'remmina': ('remmina', '/usr/bin/remmina')}
COMMANDS = {'listener': 'net-listener', 'http-server': 'net-http-server',
            'enumeration-host': 'net-file-server', 'proxy-ca': 'net-proxy-ca', 'remmina': 'net-remmina'}
UNIT = re.compile(r'[A-Za-z0-9_.:-]+\.service')


def snapshot():
    config, repos, _ = wf.source_snapshot()
    records = meta.installed(wf.ROOT)
    return records, wf.file_owners(records), config, repos


def adapter(name):
    package, path = ADAPTERS[name]
    records, owners, config, repos = snapshot()
    matches = [(index, record) for index, record in enumerate(records) if record.get('name') == package
               and wf.package_sources(record, config, repos)]
    if len(matches) != 1:
        raise ValueError('supported adapter package provenance missing or ambiguous: ' + package)
    target = wf.owned_file(path, matches[0][0], owners)
    if target is None or not os.access(target, os.X_OK):
        raise ValueError('reviewed adapter entry is not uniquely owned and executable: ' + path)
    return path


def manager_state(unit):
    if wf.ROOT:
        fixture = wf.read_json('/var/lib/haseen/vapt/services.json', {})
        return fixture.get(unit, {})
    result = subprocess.run(['/usr/bin/systemctl', 'show', '--property=FragmentPath,ActiveState,SubState,LoadState', '--', unit],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    if result.returncode:
        return {}
    return dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)


def service_list():
    records, owners, config, repos = snapshot()
    services = []
    for name, packages in FAMILIES:
        matches = [(index, record) for index, record in enumerate(records) if record.get('name') in packages]
        row = {'id': name, 'installed': bool(matches), 'package': None, 'ownership': 'missing', 'unit': None,
               'fragmentPath': None, 'state': 'unknown', 'activeState': None, 'subState': None,
               'exposure': 'unknown', 'reason': 'supported package missing; exposure unknown'}
        if matches:
            row['package'] = wf.clean(matches[0][1]['name'])
            candidates = []
            for index, record in matches:
                if not wf.package_sources(record, config, repos):
                    continue
                for path in owners:
                    if path.startswith('/usr/lib/systemd/system/') and UNIT.fullmatch(Path(path).name):
                        if wf.owned_file(path, index, owners) is not None:
                            candidates.append((path, index))
            if not candidates:
                row.update(ownership='refused', reason='no verified package-owned non-template service unit; exposure unknown')
            elif len(candidates) != 1:
                row.update(ownership='ambiguous', reason='several owned units; no implicit selection; exposure unknown')
            else:
                path, index = candidates[0]
                unit = Path(path).name
                current = manager_state(unit)
                fragment = current.get('FragmentPath', '')
                row.update(unit=unit, fragmentPath=wf.clean(fragment) or None,
                           activeState=wf.clean(current.get('ActiveState', '')) or None,
                           subState=wf.clean(current.get('SubState', '')) or None)
                if not current:
                    row.update(ownership='unknown', reason='service manager state unreadable; exposure unknown')
                elif current.get('LoadState') not in (None, 'loaded') or not fragment or wf.owned_file(fragment, index, owners) is None or wf.physical(fragment) != wf.physical(path):
                    row.update(ownership='refused', reason='FragmentPath changed, overridden or unowned; exposure unknown')
                else:
                    row.update(ownership='verified', reason='installed unit and current FragmentPath ownership verified; exposure unknown')
                    active = current.get('ActiveState')
                    row['state'] = 'running' if active == 'active' else 'stopped' if active == 'inactive' else 'failed' if active == 'failed' else 'transitioning' if active in ('activating', 'deactivating', 'reloading') else 'unknown'
        services.append(row)
    return {'schemaVersion': 1, 'services': services}


def service_selected(name):
    if name not in {n for n, _ in FAMILIES}:
        raise ValueError('unknown service id')
    row = next(r for r in service_list()['services'] if r['id'] == name)
    if row['ownership'] != 'verified':
        raise ValueError(row['reason'])
    return row


def local_capabilities(values):
    records, _, _, _ = snapshot()
    packages = {r.get('name') for r in records}
    result = []
    settings_error = None
    try:
        wf.validate_settings(values)
    except (ValueError, KeyError, TypeError) as error:
        settings_error = wf.clean(error)
    for name, (package, _) in ADAPTERS.items():
        installed = package in packages
        row = {'id': name, 'command': COMMANDS[name], 'installed': installed, 'available': False, 'state': 'missing',
               'prerequisitePackages': [package], 'reason': 'supported prerequisite package missing'}
        if settings_error:
            row.update(state='refused', reason=settings_error)
            result.append(row)
            continue
        try:
            adapter(name)
            if name == 'enumeration-host':
                if not values['enumerationScript']:
                    row.update(state='selection-required', reason='select one verified package-owned regular file')
                    result.append(row)
                    continue
                selected_owned_file(values['enumerationScript'], records, wf.ROOT, meta.observed_resolve)
            if name == 'proxy-ca':
                # The system trust updater must also be installed and owned.
                updater_owned()
                row['prerequisitePackages'].append('ca-certificates-utils')
                from workflow_ca import ca_status
                current = ca_status(wf.ROOT)
                if current['state'] not in ('none', 'owned'):
                    raise ValueError(current['reason'])
            row.update(available=True, state='available', reason='reviewed installed adapter and prerequisites verified; explicit selection/confirmation still required')
        except (OSError, ValueError, KeyError, TypeError) as error:
            row.update(state='refused' if installed else 'missing', reason=wf.clean(error))
        result.append(row)
    return result


def updater_owned():
    records, owners, config, repos = snapshot()
    matches = [(index, record) for index, record in enumerate(records) if record.get('name') == 'ca-certificates-utils'
               and wf.package_sources(record, config, repos)]
    if len(matches) != 1:
        raise ValueError('system trust updater package provenance missing or ambiguous')
    target = wf.owned_file('/usr/bin/update-ca-trust', matches[0][0], owners)
    if target is None or not os.access(target, os.X_OK):
        raise ValueError('system trust updater is not an owned executable')


def endpoint_plan(kind, address, port, path):
    values = wf.settings()
    wf.validate_settings(values)
    endpoint = validate_endpoint(address or values['bindAddress'], port)
    program = adapter(kind)
    selected = None
    if kind == 'http-server':
        if not path:
            raise ValueError('select an explicit directory')
        selected = wf.physical(path)
        if not selected.is_dir():
            raise ValueError('selected path is not a directory')
    elif kind == 'enumeration-host':
        chosen = path or values['enumerationScript']
        if not chosen:
            raise ValueError('select an explicit package-owned file')
        selected = selected_owned_file(chosen, meta.installed(wf.ROOT), wf.ROOT, meta.observed_resolve)
    identity = {'device': selected.stat().st_dev, 'inode': selected.stat().st_ino} if selected else None
    return {'schemaVersion': 1, 'kind': kind, 'endpoint': endpoint, 'path': wf.logical(selected) if selected else None,
            'adapter': program, 'selectionIdentity': identity, 'dryRun': True, 'reason': 'preview only; no bind, serving or execution performed'}


class ConfinedHandler(http.server.BaseHTTPRequestHandler):
    """Byte-only handler: dirfd + O_NOFOLLOW at every request component.

    No directory listings, CGI, uploads, redirects to outside roots or symlink
    traversal. The selected root fd remains bound even if its name is replaced.
    """
    def __init__(self, *args, root_fd, file_fd=None, **kwargs):
        self.root_fd, self.file_fd = root_fd, file_fd
        super().__init__(*args, **kwargs)

    def log_message(self, format, *args):
        pass  # Ephemeral local helpers keep no request/address log.

    def do_HEAD(self):
        self._send(False)

    def do_GET(self):
        self._send(True)

    def _send(self, body):
        fd = None
        try:
            path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path, errors='strict')
            if self.file_fd is not None:
                if path != '/file':
                    raise FileNotFoundError()
                fd = os.dup(self.file_fd)
            else:
                parts = path.lstrip('/').split('/')
                if not parts or any(p in ('', '.', '..') or '\x00' in p for p in parts):
                    raise FileNotFoundError()
                parent = os.dup(self.root_fd)
                try:
                    for part in parts[:-1]:
                        child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
                        os.close(parent)
                        parent = child
                    fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
                finally:
                    os.close(parent)
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode):
                raise FileNotFoundError()
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Length', str(info.st_size))
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers()
            if body:
                offset = 0
                while offset < info.st_size:
                    chunk = os.pread(fd, min(65536, info.st_size - offset), offset)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    offset += len(chunk)
        except (OSError, ValueError, UnicodeError):
            self.send_error(404, 'Selected bytes unavailable')
        finally:
            if fd is not None:
                os.close(fd)


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


def serve(kind, address, port, path, expected):
    if wf.ROOT:
        raise ValueError('foreground serving refused with HASEEN_SYSROOT')
    plan = endpoint_plan(kind, address, port, path)
    if plan != json.loads(expected):
        raise ValueError('approved endpoint/selection changed before serving')
    endpoint = plan['endpoint']
    target = wf.physical(plan['path'])
    root_fd = file_fd = None
    try:
        if kind == 'http-server':
            root_fd = open_selected(target, directory=True)
        else:
            # Hold the selected file, recheck inventory ownership immediately
            # after opening, and serve only that inode behind the fixed /file.
            file_fd = open_selected(target)
            checked = selected_owned_file(plan['path'], meta.installed(''), '', meta.observed_resolve)
            if not checked.is_file() or (os.fstat(file_fd).st_dev, os.fstat(file_fd).st_ino) != (checked.stat().st_dev, checked.stat().st_ino):
                raise ValueError('selected file changed during open')
        bound = os.fstat(root_fd if root_fd is not None else file_fd)
        if {'device': bound.st_dev, 'inode': bound.st_ino} != plan['selectionIdentity']:
            raise ValueError('selected inode changed before serving')
        family = socket.AF_INET6 if endpoint['family'] == 'ipv6' else socket.AF_INET
        class Server(http.server.HTTPServer):
            address_family = family
            allow_reuse_address = False
        handler = functools.partial(ConfinedHandler, root_fd=root_fd, file_fd=file_fd)
        with Server((endpoint['address'], endpoint['port']), handler) as server:
            print('Foreground byte server; Ctrl-C stops. Endpoint: ' + ('/file' if file_fd is not None else 'explicit files only'), flush=True)
            server.serve_forever()
    finally:
        if root_fd is not None:
            os.close(root_fd)
        if file_fd is not None:
            os.close(file_fd)


def certificate_payload(path, fingerprint):
    target = wf.physical(path)
    data = read_certificate_bytes(target)
    row = inspect_certificate_data(data)
    if row['state'] != 'valid' or row['certificate']['sha256'] != fingerprint:
        raise ValueError('certificate changed or no longer valid; no trust operation')
    der = ssl.PEM_cert_to_DER_cert(data.decode('ascii')) if b'-----BEGIN CERTIFICATE-----' in data else data
    import hashlib
    if hashlib.sha256(der).hexdigest().upper() != fingerprint:
        raise ValueError('certificate bytes changed during inspection')
    return base64.b64encode(der).decode('ascii')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['service-list', 'service-plan', 'adapter', 'endpoint-plan', 'serve', 'addresses', 'inspect', 'ca-payload', 'ca-status', 'selection', 'ca-updater', 'ca-trust-check'])
    parser.add_argument('operands', nargs='*')
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    expected = {'service-list': 0, 'service-plan': 1, 'adapter': 1, 'endpoint-plan': 4, 'serve': 5, 'addresses': 0, 'inspect': 1, 'ca-payload': 2, 'ca-status': 0, 'selection': 0, 'ca-updater': 0, 'ca-trust-check': 1}
    if len(args.operands) != expected[args.command]:
        parser.error('malformed operands')
    try:
        if args.command in ('ca-updater', 'ca-trust-check'):
            updater_owned()
            if args.command == 'ca-trust-check':
                from workflow_ca import ca_status
                current = ca_status(wf.ROOT)
                if current['state'] not in ('none', 'owned') or (current['anchor'] and current['anchor']['sha256'] != args.operands[0]):
                    raise ValueError('foreign, modified, incomplete or different CA anchor preserved')
            return 0
        if args.command == 'selection':
            values = wf.settings()
            wf.validate_settings(values)
            print(values['enumerationScript'] or '')
            return 0
        if args.command == 'service-list':
            result = service_list()
        elif args.command == 'service-plan':
            result = service_selected(args.operands[0])
        elif args.command == 'adapter':
            print(adapter(args.operands[0]))
            return 0
        elif args.command in ('endpoint-plan', 'serve'):
            if args.command == 'serve':
                serve(*args.operands)
                return 0
            result = endpoint_plan(*args.operands)
        elif args.command == 'addresses':
            result = {'schemaVersion': 1, 'addresses': local_addresses(wf.ROOT)}
        elif args.command == 'inspect':
            adapter('proxy-ca')
            result = inspect_certificate(wf.physical(args.operands[0]))
        elif args.command == 'ca-payload':
            print(certificate_payload(*args.operands))
            return 0
        else:
            from workflow_ca import ca_status
            result = ca_status(wf.ROOT)
        if args.json or args.command in ('service-plan', 'endpoint-plan'):
            print(json.dumps(result))
        elif args.command == 'service-list':
            for row in result['services']:
                print(row['id'] + ': ' + row['state'] + ' (' + row['ownership'] + ') ' + row['reason'])
        elif args.command == 'addresses':
            for row in result['addresses']:
                print(row['interface'] + ' ' + row['address'])
        else:
            print(json.dumps(result))
        return 1 if result.get('state') in ('invalid', 'refused', 'modified', 'foreign', 'unknown') else 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        reason = wf.clean(error)
        print('vapt: ' + reason, file=sys.stderr)
        if args.json:
            failure = {'schemaVersion': 1, 'state': 'refused', 'reason': reason}
            if args.command == 'inspect':
                failure['certificate'] = None
            print(json.dumps(failure))
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == '__main__':
    sys.exit(main())
