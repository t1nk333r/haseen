#!/usr/bin/env python3
"""Offline installed-file discovery and explicit documentation presentation.

Installation metadata is evidence of ownership, not attestation of retained bytes.
Never import an installed distribution or execute a discovered entry to inspect it.
"""
import argparse
import configparser
import contextlib
import csv
import gzip
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys

import metadata as meta
from workflow_support import validate_endpoint, inspect_certificate, confined_path, selected_owned_file, local_addresses

LAYER = Path(__file__).resolve().parent
ROOT = os.environ.get('HASEEN_SYSROOT', '').rstrip('/')
CONFIG = os.environ.get('HASEEN_USER_CONFIG', os.environ.get('XDG_CONFIG_HOME', os.environ['HOME'] + '/.config') + '/haseen')
STATE = os.environ.get('HASEEN_USER_STATE', os.environ.get('XDG_STATE_HOME', os.environ['HOME'] + '/.local/state') + '/haseen')
DATA = os.environ.get('XDG_DATA_HOME', os.environ['HOME'] + '/.local/share')


def clean(value):
    return ''.join(c for c in str(value) if c >= ' ' and c != '\x7f' and not '\x80' <= c <= '\x9f')


def physical(path):
    if not isinstance(path, str) or not path.startswith('/') or '..' in Path(path).parts or clean(path) != path:
        raise ValueError('invalid owned absolute path')
    return meta.observed_resolve(Path(ROOT + path), ROOT)


def logical(path):
    return '/' + str(Path(path).relative_to(Path(ROOT or '/')))


def read_json(path, default=None):
    target = physical(path)
    return json.loads(target.read_text()) if target.exists() else default


def inventory():
    items = {}
    for path in sorted((LAYER / 'packages/security').glob('*.txt')):
        for line in path.read_text().splitlines():
            name = line.split('#', 1)[0].strip()
            if not name:
                continue
            if not meta.NAME.fullmatch(name):
                raise ValueError('invalid inventory')
            items.setdefault(name, []).append(path.stem)
    native = {}
    for line in (LAYER / 'packages/security/native.tsv').read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        group, name, _, _, spec, probe = line.split('\t')
        group = group.removeprefix('security/')
        if group not in items.setdefault(name, []):
            items[name].append(group)
        native[name] = (spec, probe)
    return items, native


def source_snapshot():
    config = meta.read_config(ROOT)
    repos = meta.repositories(ROOT)
    private = meta.oniomarchy_canary(ROOT)
    # Use the provisioning verifier's recorded private evidence, never a
    # fresh signature operation or a second provenance policy.
    if private['state'] == 'usable':
        config['oniomarchy'] = [meta.ONIOMARCHY_POLICY, 'Server = ' + meta.ONIOMARCHY_SERVER]
        repos['oniomarchy'] = meta.retained_private_records(ROOT)
    return config, repos, private


def package_sources(record, config, repos):
    if not meta.allowed_local(record, config, repos):
        return []
    return [source for source in config if meta.repository_safe(source, config) and meta.ALLOWED.fullmatch(source)
            and meta.closure_identity_ok(source, record)
            and any(p.get('name') == record['name'] and p.get('version') == record.get('version')
                    and p.get('url', '').rstrip('/') == record.get('url', '').rstrip('/')
                    and not p.get('metadata_unknown') and not meta.forbidden(p) for p in repos.get(source, []))]


def file_owners(records):
    owners = {}
    for index, record in enumerate(records):
        for path in record.get('files', []):
            if not isinstance(path, str) or path.endswith('/'):
                continue
            rel = path.lstrip('/')
            if not rel or '..' in Path(rel).parts or clean(rel) != rel:
                continue
            owners.setdefault('/' + rel, set()).add(index)
    return owners


def owned_file(path, owner, owners):
    """Every symlink hop must remain uniquely owned by the selected package."""
    if owners.get(path) != {owner}:
        return None
    trace = []
    try:
        target = meta.observed_resolve(Path(ROOT + path), ROOT, trace)
        # Directory aliases such as /bin -> /usr/bin are not file authority.
        if any(p.is_symlink() and owners.get(logical(p)) != {owner} for p in trace):
            return None
        if owners.get(logical(target)) != {owner} or not target.is_file():
            return None
        return target
    except (OSError, ValueError):
        return None


def documentation(entry, paths):
    basename = Path(entry).name
    docs = []
    for path in paths:
        name = Path(path).name.removesuffix('.gz')
        if path.startswith('/usr/share/man/') and re.fullmatch(re.escape(basename) + r'\.[1-9][a-z]*', name):
            docs.append({'path': path, 'kind': 'man'})
        elif '/share/doc/' in path and name in (basename + '.txt', basename + '.md', basename + '.rst', basename + '-help.txt'):
            docs.append({'path': path, 'kind': 'document'})
    return sorted(docs, key=lambda d: (d['kind'] != 'man', d['path']))


def package_entries(record, index, owners):
    files, entries, desktops = [], [], []
    for path in sorted(p for p, ids in owners.items() if index in ids):
        target = owned_file(path, index, owners)
        if target is None:
            continue
        files.append(path)
        if os.access(target, os.X_OK):
            entries.append({'id': path, 'path': path, 'kind': 'executable', 'documentation': []})
        if path.startswith('/usr/share/applications/') and path.endswith('.desktop'):
            parser = configparser.ConfigParser(interpolation=None, strict=True)
            try:
                parser.read_string(target.read_text())
                section = parser['Desktop Entry']
                if section.get('Type') == 'Application' and section.get('Hidden', 'false') != 'true':
                    desktops.append({'path': path, 'name': clean(section.get('Name', '')), 'terminal': section.get('Terminal') == 'true'})
            except (OSError, UnicodeError, configparser.Error, KeyError):
                pass
    for entry in entries:
        entry['documentation'] = documentation(entry['path'], files)
    return files, entries, desktops


def native_evidence(name, spec, probe):
    home = DATA + '/haseen/vapt/pipx'
    probe = 'smbserver.py' if name == 'impacket' else probe
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        meta.native_state(ROOT + home, name, spec, probe, ROOT + STATE, ROOT)
    state = output.getvalue().strip()
    evidence = {'state': state, 'spec': spec, 'files': [], 'entrypoints': []}
    if state != 'exact':
        return evidence
    distribution = 'netexec' if spec.startswith('git+') else spec.split('==')[0]
    venv = physical(home + '/venvs/' + meta.norm(distribution))
    matches = [(info, msg) for info, msg in meta.distribution_metadata(venv) if meta.norm(msg.get('Name', '')) == meta.norm(distribution)]
    if len(matches) != 1:
        evidence['state'] = 'unknown'
        return evidence
    info, _ = matches[0]
    # RECORD, rather than guessed console command names, grants file evidence.
    try:
        rows = csv.reader(io.StringIO(meta.metadata_read(info / 'RECORD')))
        for row in rows:
            if not row or clean(row[0]) != row[0] or Path(row[0]).is_absolute():
                continue
            target = meta.observed_resolve(info.parent / row[0], ROOT)
            if target.is_relative_to(venv) and target.is_file():
                evidence['files'].append(logical(target))
        for path in sorted(set(evidence['files'])):
            target = physical(path)
            if target.parent == venv / 'bin' and os.access(target, os.X_OK):
                evidence['entrypoints'].append({'id': path, 'path': path, 'kind': 'native', 'documentation': documentation(path, evidence['files'])})
    except (OSError, ValueError):
        evidence['state'] = 'unknown'
        evidence['entrypoints'] = []
    return evidence

def report_resolution():
    """Report attempts for diagnostics only, never installation authority."""
    result = {}
    path = Path(ROOT + STATE + '/vapt/report.tsv')
    if not path.is_file():
        return result
    for line in meta.metadata_read(path).splitlines():
        fields = line.split('\t')
        if len(fields) != 8 or not meta.NAME.fullmatch(fields[0]) or any(clean(f) != f for f in fields):
            continue
        name, _, source, target, resolution, _, reason, _ = fields
        result[name] = {'state': resolution if resolution in ('resolved', 'unresolved') else 'unknown',
                        'source': source or None, 'target': target or None, 'reason': reason,
                        'evidence': 'provisioning-report-only; not installed-entrypoint evidence'}
    return result



def discover():
    items, native = inventory()
    config, repos, private = source_snapshot()
    records = meta.installed(ROOT)
    owners = file_owners(records)
    _, policies, aliases, _ = meta.vapt_tables()
    resolution = report_resolution()
    # Exact logical name plus reviewed repository aliases only. Never Provides
    # or suffix stripping; the transaction report is not installation evidence.
    tools = []
    for name, groups in sorted(items.items()):
        tool = {'id': name, 'groups': sorted(groups), 'state': 'missing', 'reason': 'no installed package identity',
                'packages': [], 'entrypoints': [], 'desktopEntries': [], 'native': None}
        for index, record in enumerate(records):
            pkg = record.get('name', '')
            sources = package_sources(record, config, repos)
            mapped = [s for s in sources if aliases.get((s, pkg), pkg) == name]
            if pkg != name and not mapped:
                continue
            files, entries, desktops = package_entries(record, index, owners)
            verified = bool(mapped) and policies.get(name) != 'blocked'
            tool['packages'].append({'name': clean(pkg), 'version': clean(record.get('version', '')), 'source': mapped,
                                     'provenance': 'verified' if verified else 'unknown', 'files': files})
            if verified and 'files' in record:
                tool['entrypoints'].extend(entries)
                tool['desktopEntries'].extend(desktops)
            if verified and 'files' in record:
                tool['state'], tool['reason'] = 'installed', 'installed package identity and file inventory verified'
            elif tool['state'] != 'installed':
                tool['state'], tool['reason'] = 'unknown', 'package provenance or owned file inventory unavailable'
        if name in native:
            evidence = native_evidence(name, *native[name])
            tool['native'] = evidence
            if evidence['state'] == 'exact':
                tool['state'], tool['reason'] = 'installed', 'owned pinned native metadata verified'
                tool['entrypoints'].extend(evidence['entrypoints'])
            elif evidence['state'] != 'missing' and tool['state'] != 'installed':
                tool['state'], tool['reason'] = 'unknown', 'native metadata ' + evidence['state']
        if policies.get(name) == 'blocked':
            tool['state'], tool['reason'], tool['entrypoints'] = 'unknown', 'inventory identity blocked by reviewed policy', []
        tool['resolution'] = resolution.get(name, {'state': 'unknown', 'source': None, 'target': None,
                                                  'reason': 'no recorded resolution attempt'})
        tool['ownership'] = 'present' if tool['packages'] or (tool['native'] and tool['native']['state'] == 'exact') else 'missing'
        tool['provenance'] = 'verified' if tool['state'] == 'installed' else 'unknown'
        tool['entrypoints'] = sorted(tool['entrypoints'], key=lambda e: e['id'])
        tool['dataOnly'] = tool['state'] == 'installed' and not tool['entrypoints']
        for entry in tool['entrypoints']:
            try:
                usage = usage_evidence(tool, entry)
                entry['usage'] = {'state': 'ready', 'kind': usage['kind'], 'reason': 'unique owned usage evidence'}
            except ValueError as error:
                entry['usage'] = {'state': 'unavailable', 'kind': None, 'reason': str(error)}
        tools.append(tool)
    sources = [{'name': s, 'state': 'safe' if meta.repository_safe(s, config) else 'unavailable',
                'cachedPackages': len(repos.get(s, [])), 'evidence': 'cached metadata; database authentication not checked by discovery',
                'reason': 'reviewed source configuration' if meta.repository_safe(s, config) else 'source configuration unavailable/refused'}
               for s in config if s != 'options']
    return {'schemaVersion': 1, 'tools': tools, 'sources': sources, 'privateSource': private}


def settings():
    default = json.loads((LAYER.parent.parent / 'default/vapt/workflow.json').read_text())
    user = read_json(CONFIG + '/vapt/workflow.json', {})
    if not isinstance(user, dict):
        raise ValueError('workflow settings must be an object')
    return {**default, **user}


def validate_settings(values):
    if values.get('schemaVersion') != 1:
        raise ValueError('unsupported workflow schema')
    validate_endpoint(values['bindAddress'], 1024)
    script = values['enumerationScript']
    if script is not None and (not isinstance(script, str) or clean(script) != script):
        raise ValueError('enumerationScript must be a control-free string or null')
    if not isinstance(values['showLocalAddresses'], bool):
        raise ValueError('showLocalAddresses must be boolean')


def merged(base, user):
    result = dict(base)
    for key, value in user.items():
        result[key] = merged(result[key], value) if isinstance(result.get(key), dict) and isinstance(value, dict) else value
    return result


def menu():
    base = json.loads((LAYER.parent.parent / 'default/shell.json').read_text())
    user = read_json(CONFIG + '/shell.json', {})
    if not isinstance(user, dict):
        raise ValueError('shell configuration must be an object')
    plugins = merged(base, user).get('plugins', {})
    entry = plugins.get('haseen.security', {}) if isinstance(plugins, dict) else {}
    return {'schemaVersion': 1, 'plugin': 'haseen.security', 'enabled': isinstance(entry, dict) and entry.get('enabled') is True}


def capabilities(result):
    """Fixed local action prerequisites, without executing adapters.

    Action adapters belong to the local-action slice; unsupported or absent
    adapters remain explicit unavailable records rather than guessed commands.
    """
    config, repos, _ = source_snapshot()
    records = meta.installed(ROOT)
    installed = {r.get('name') for r in records if package_sources(r, config, repos)}
    requirements = [('listener', ['openbsd-netcat']), ('http-server', ['python']),
                    ('enumeration-host', ['python']), ('proxy-ca', ['openssl', 'ca-certificates-utils']),
                    ('remmina', ['remmina'])]
    settings_valid = True
    try:
        validate_settings(result['workflow']['settings'])
    except (ValueError, KeyError, TypeError):
        settings_valid = False
    values = []
    for name, packages in requirements:
        present = all(p in installed for p in packages)
        state = 'unknown' if present else 'missing'
        reason = 'installed prerequisites; supported action adapter not established' if present else 'verified prerequisite package missing'
        if not settings_valid:
            state, reason = 'refused', 'effective workflow settings invalid'
        elif present and name == 'enumeration-host' and not result['workflow']['settings']['enumerationScript']:
            state, reason = 'selection-required', 'select one verified package-owned regular file'
        values.append({'id': name, 'installed': present, 'available': False, 'state': state,
                       'prerequisitePackages': packages, 'reason': reason})
    return values


def selected(tool_id, entry_id):
    tool = next((t for t in discover()['tools'] if t['id'] == tool_id), None)
    if not tool or tool['state'] != 'installed':
        raise ValueError('tool has no verified installed identity')
    entries = tool['entrypoints']
    if entry_id:
        entries = [e for e in entries if e['id'] == entry_id]
    if len(entries) != 1:
        raise ValueError('missing or ambiguous entry evidence; choose an owned --entry ID from tool-list')
    return tool, entries[0]


def usage_evidence(tool, entry):
    docs = entry['documentation']
    if docs:
        preferred = [d for d in docs if d['kind'] == docs[0]['kind']]
        if len(preferred) != 1:
            raise ValueError('ambiguous owned matching documentation')
        return {'kind': preferred[0]['kind'], 'path': preferred[0]['path'], 'argv': []}
    registry = json.loads((LAYER / 'files/help-bindings.json').read_text())
    bindings = [b for b in registry['bindings'] if b['tool'] == tool['id'] and b['entry'] == entry['path']
                and any(p['name'] == b['package'] and p['provenance'] == 'verified' for p in tool['packages'])]
    if len(bindings) != 1:
        raise ValueError('no unique owned documentation or reviewed help-only argv binding; refused')
    binding = bindings[0]
    if not binding.get('review') or not isinstance(binding.get('args'), list) or not all(isinstance(a, str) and clean(a) == a for a in binding['args']):
        raise ValueError('invalid reviewed binding')
    return {'kind': 'reviewed-argv', 'review': binding['review'], 'argv': [entry['path'], *binding['args']]}


def shell_path():
    shells = physical('/etc/shells')
    approved = shells.read_text().splitlines() if shells.is_file() else []
    requested = os.environ.get('SHELL', '')
    for candidate in (requested, '/bin/bash', '/usr/bin/bash'):
        if candidate not in approved:
            continue
        path = physical(candidate)
        if path.is_file() and os.access(path, os.X_OK):
            return candidate
    raise ValueError('no independently installed executable login shell')


def show_help(args):
    tool, entry = selected(args.tool, args.entry)
    evidence = usage_evidence(tool, entry)
    shell = shell_path() if args.command == 'tool-run' else None
    effective = settings()
    validate_settings(effective)
    if args.dry_run:
        print(json.dumps({'schemaVersion': 1, 'tool': tool['id'], 'entry': entry['id'], 'evidence': evidence,
                          'shellArgv': [shell, '-i'] if shell else [], 'dryRun': True}))
        # Address output is explicit usage-only, not inventory/status evidence.
        # Dry-run does not observe even local interface state.
        return 0
    if ROOT and (shell or evidence['kind'] == 'reviewed-argv'):
        raise ValueError('explicit help/session execution refused with HASEEN_SYSROOT; use --dry-run')
    if evidence['kind'] == 'reviewed-argv':
        env = dict(os.environ, PAGER='cat', MANPAGER='cat', TERM='dumb')
        result = subprocess.run(evidence['argv'], env=env, check=False)
        if result.returncode:
            return 1
    else:
        path = physical(evidence['path'])
        data = gzip.decompress(path.read_bytes()) if path.name.endswith('.gz') else path.read_bytes()
        # Print document bytes as text: no man macros, pager, terminal or
        # helper execution. Keep line breaks, remove terminal control bytes.
        print('\n'.join(clean(line) for line in data.decode('utf-8', errors='replace').splitlines()))
    if effective['showLocalAddresses']:
        for row in local_addresses(ROOT):
            print('Local address: ' + row['interface'] + ' ' + row['address'])
    if shell:
        os.execv(shell, [shell, '-i'])
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['tool-list', 'tool-help', 'tool-run', 'status', 'doctor', 'menu'])
    parser.add_argument('tool', nargs='?')
    parser.add_argument('--entry')
    parser.add_argument('--group')
    parser.add_argument('--all', action='store_true')
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--enabled', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    args.status_code = int(os.environ.get('VAPT_WORKFLOW_STATUS_CODE', '0'))
    action = args.command in ('tool-help', 'tool-run')
    if (action != bool(args.tool) or (action and (args.json or args.all or args.group or args.enabled))
            or (args.entry and not action) or (args.enabled and args.command != 'menu')
            or ((args.all or args.group) and args.command != 'tool-list')):
        parser.error('unsupported or missing operands')
    try:
        if action:
            return show_help(args)
        if args.command == 'menu':
            result = menu()
            print(json.dumps(result) if args.json else str(result['enabled']).lower())
            return 0 if not args.enabled or result['enabled'] else 1
        result = discover()
        if args.command == 'tool-list':
            groups = {g for t in result['tools'] for g in t['groups']}
            if args.group and args.group not in groups:
                parser.error('unknown inventory group')
            result['tools'] = [t for t in result['tools'] if (args.all or t['state'] == 'installed') and (not args.group or args.group in t['groups'])]
            if not args.all:
                for tool in result['tools']:
                    tool.pop('resolution', None)
        else:
            result['provisioning'] = {'state': ['healthy', 'missing', 'degraded'][args.status_code], 'exitCode': args.status_code,
                                      'diagnostics': [clean(line) for line in sys.stdin.read().splitlines()],
                                      'resolutions': [{'id': name, **record} for name, record in sorted(report_resolution().items()) if name in {t['id'] for t in result['tools']}]}
            for tool in result['tools']:
                tool.pop('resolution', None)
            result['workflow'] = {'settings': settings(), 'menu': menu(), 'entrypoints': sum(len(t['entrypoints']) for t in result['tools']),
                                  'documentationReady': sum(e['usage']['state'] == 'ready' for t in result['tools'] for e in t['entrypoints'])}
            if args.command == 'doctor':
                result['workflow']['capabilities'] = capabilities(result)
        if args.json:
            print(json.dumps(result, ensure_ascii=True))
        elif args.command == 'tool-list':
            for tool in result['tools']:
                print(tool['id'] + ': ' + tool['state'] + ' (' + tool['reason'] + ')')
                for entry in tool['entrypoints']:
                    print('  ' + entry['id'])
                if tool['state'] == 'installed' and not tool['entrypoints']:
                    print('  no owned executable (data-only or unavailable entry evidence)')
        else:
            print('\n'.join(result['provisioning']['diagnostics']))
            print('workflow: ' + str(result['workflow']['entrypoints']) + ' owned entrypoints; ' + str(result['workflow']['documentationReady']) + ' with matching documents')
        return args.status_code if args.command == 'status' else (1 if args.command == 'doctor' and args.status_code else 0)
    except (OSError, ValueError, KeyError, TypeError, UnicodeError) as error:
        reason = clean(error)
        print('vapt: ' + reason, file=sys.stderr)
        if args.json:
            print(json.dumps({'schemaVersion': 1, 'error': {'state': 'unavailable', 'reason': reason}}))
        return (args.status_code or 2) if args.command == 'status' else 1


if __name__ == '__main__':
    sys.exit(main())
