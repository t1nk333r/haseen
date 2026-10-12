#!/usr/bin/env python3
"""Read literal Security enablement without loading inventory/provisioning code."""
import argparse
import json
import os
from pathlib import Path
import sys

def observed_resolve(path, root, trace=None):
    """Resolve absolute symlink targets within the fixture, never the host."""
    boundary = Path(root) if root else Path('/')
    pending = list(Path(path).relative_to(boundary).parts)
    current, links = boundary, 0
    while pending:
        part = pending.pop(0)
        if part == '..':
            if current == boundary:
                raise ValueError('symlink escapes observation root')
            current = current.parent
            continue
        current = current / part
        if trace is not None:
            trace.append(current)
        if current.is_symlink():
            links += 1
            if links > 40:
                raise ValueError('symlink loop')
            target = Path(os.readlink(current))
            if root and target.is_absolute() and target.is_relative_to(boundary):
                target = Path('/') / target.relative_to(boundary)
            current = boundary if target.is_absolute() else current.parent
            pending = list(target.parts[1:] if target.is_absolute() else target.parts) + pending
    return current


def merged(base, user):
    result = dict(base)
    for key, value in user.items():
        result[key] = merged(result[key], value) if isinstance(result.get(key), dict) and isinstance(value, dict) else value
    return result


def menu():
    layer = Path(__file__).resolve().parent
    root = os.environ.get('HASEEN_SYSROOT', '').rstrip('/')
    config = os.environ.get('HASEEN_USER_CONFIG', os.environ.get('XDG_CONFIG_HOME', os.environ['HOME'] + '/.config') + '/haseen')
    path = config + '/shell.json'
    if not path.startswith('/') or '..' in Path(path).parts or any(ord(c) < 32 or 127 <= ord(c) <= 159 for c in path):
        raise ValueError('invalid owned absolute path')
    target = observed_resolve(Path(root + path), root)
    base = json.loads((layer.parent.parent / 'default/shell.json').read_text())
    user = json.loads(target.read_text()) if target.exists() else {}
    if not isinstance(user, dict):
        raise ValueError('shell configuration must be an object')
    plugins = merged(base, user).get('plugins', {})
    entry = plugins.get('haseen.security', {}) if isinstance(plugins, dict) else {}
    return {'schemaVersion': 1, 'plugin': 'haseen.security', 'enabled': isinstance(entry, dict) and entry.get('enabled') is True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--enabled', action='store_true')
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        result = menu()
        print(json.dumps(result) if args.json else str(result['enabled']).lower())
        return 0 if not args.enabled or result['enabled'] else 1
    except (OSError, ValueError, TypeError) as error:
        reason = ''.join(c for c in str(error) if c >= ' ' and c != '\x7f' and not '\x80' <= c <= '\x9f')
        print('vapt: ' + reason, file=sys.stderr)
        if args.json:
            print(json.dumps({'schemaVersion': 1, 'error': {'state': 'unavailable', 'reason': reason}}))
        return 1


if __name__ == '__main__':
    sys.exit(main())
