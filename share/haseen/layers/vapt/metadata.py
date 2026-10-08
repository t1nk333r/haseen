#!/usr/bin/env python3
"""Read provisioning metadata only; never import or execute installed tools.

Fixture protocol: /var/lib/haseen/vapt/repositories.json maps repositories to
lists of {name, version, url, provides, depends, install, hooks} records.
installed.json is a list with the same fields. Package membership .pkgs remains
usable for resolution, but cannot prove identity/dependency/install safety.
"""
import argparse
import ctypes
import email
import errno
import fcntl
import hashlib
import locale
import glob
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import tempfile

# ASCII only and locale-independent, exactly lib/packages.sh's PKG_NAME_RE.
NAME = re.compile(r"^[a-z0-9@._+][a-z0-9@._+-]*$")
ALLOWED = re.compile(r"^(core|extra|multilib|blackarch|chaotic-aur|oniomarchy|cachyos(?:-[a-z0-9-]+)?)$")
# Base vendor: the only sources whose packages may vouch for reviewed stock
# maintenance programs. Narrower than ALLOWED: never BlackArch, Chaotic or
# the private oniomarchy source.
BASE_VENDOR = re.compile(r"^(core|extra|multilib|cachyos(?:-[a-z0-9-]+)?)$")
ACTIVATION = re.compile(r"(?:systemctl|service|rc-update|sv)\s+(?:[^\n;]*\s)?(?:enable|start|restart|preset|add)\b|(?:ln|install|cp)\s+[^\n]*\.wants/|omarchy", re.I)
# The reviewed BlackArch stanza. A bootstrap stages it in memory for the
# private review and frozen commit; it reaches /etc/pacman.conf only after the
# reviewed full upgrade succeeded (--with-blackarch).
BLACKARCH_STANZA = ('SigLevel = Required DatabaseOptional', 'Server = https://blackarch.org/blackarch/$repo/os/$arch')
WITH_BLACKARCH = False
# The private oniomarchy source (plan 083). Its approved descriptor lives only
# under haseen's root state and enters VAPT's own configuration only for an
# operation that opted in (--with-oniomarchy); a host [oniomarchy] section is
# reported, never adopted. Never a base vendor; never written to pacman.conf.
ONIOMARCHY = 'oniomarchy'
ONIOMARCHY_SERVER = 'https://pkgs.oniomarchy.com/$arch'
ONIOMARCHY_POLICY = 'SigLevel = Required DatabaseRequired'
ONIOMARCHY_USAGE = 'Usage = Sync Search Install'
ONIOMARCHY_DESCRIPTOR = ('[oniomarchy]\n' + ONIOMARCHY_POLICY + '\nServer = ' + ONIOMARCHY_SERVER + '\n').encode()
ONIOMARCHY_STATE = '/var/lib/haseen/vapt/sources'
ONIOMARCHY_KEYRING_FILES = ('usr/share/pacman/keyrings/oniomarchy.gpg', 'usr/share/pacman/keyrings/oniomarchy-trusted',
                            'usr/share/pacman/keyrings/oniomarchy-revoked')
ONIOMARCHY_ADMITTED = 52
WITH_ONIOMARCHY = False
HOST_STANZAS = {}


def unquoted_text(text):
    """The characters of TEXT outside single/double quotes (TEXT already
    passed shlex.split, so its quotes are balanced)."""
    kept, quote = [], None
    for char in text:
        if quote:
            if char == quote:
                quote = None
        elif char in '\'"':
            quote = char
        else:
            kept.append(char)
    return ''.join(kept)


def unquoted_expansions(text):
    """For each shell word of TEXT (as shlex.split yields them; TEXT holds no
    backslash, $, backquote or operators), whether bash would expand it: an
    unquoted { } * ? or [ anywhere, or an unquoted leading ~."""
    flags, expands, in_word, quote = [], False, False, None
    for char in text:
        if quote:
            if char == quote:
                quote = None
            continue
        if char in ' \t':
            if in_word:
                flags.append(expands)
            expands, in_word = False, False
            continue
        if char in '\'"':
            quote = char
        elif char in '{}*?[' or (char == '~' and not in_word):
            expands = True
        in_word = True
    if in_word:
        flags.append(expands)
    return flags


def norm(value):
    return re.sub(r"[-_.]+", "-", value).lower()


def field_data(text):
    data, key = {}, None
    for line in text.splitlines():
        if line.startswith('%') and line.endswith('%'):
            key = line.strip('%').lower()
            data[key] = []
        elif line and key:
            data[key].append(line)
    scalar = ('name', 'version', 'url', 'filename', 'base', 'sha256sum')
    return {k: (v[0] if v else '') if k in scalar else v for k, v in data.items()}


def metadata_member(name):
    """Members libalpm reads as package/sync metadata: sync desc records,
    .PKGINFO, .INSTALL and hook files."""
    return name.endswith('/desc') or name in ('.INSTALL', '.PKGINFO') or name.endswith('.hook')


def metadata_texts(entries, contents):
    """(name, text) of regular metadata members in archive order, from one
    read_archive snapshot: exact member names, never a pattern lookup."""
    for name in entries:
        if metadata_member(name) and name in contents:
            if len(contents[name]) > 4 * 1024 * 1024:
                raise ValueError('oversized metadata/script requires manual review ' + name)
            yield name, contents[name].decode('utf-8', 'replace')


def archive_members(source):
    """Metadata members of a sync database or package (a path or an in-memory
    snapshot), through libalpm's own archive library."""
    entries, contents = read_archive(source, contents=True, wanted=metadata_member)
    yield from metadata_texts(entries, contents)

_LIBARCHIVE = None


def libarchive():
    """libalpm's own archive library, bound read-only through ctypes."""
    global _LIBARCHIVE
    if _LIBARCHIVE is not None:
        return _LIBARCHIVE
    try:
        library = ctypes.CDLL('libarchive.so.13')
        signatures = {
            'archive_read_new': ([], ctypes.c_void_p),
            'archive_read_support_filter_all': ([ctypes.c_void_p], ctypes.c_int),
            'archive_read_support_format_all': ([ctypes.c_void_p], ctypes.c_int),
            'archive_read_support_format_mtree': ([ctypes.c_void_p], ctypes.c_int),
            'archive_read_set_format_option': ([ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p], ctypes.c_int),
            'archive_read_open_memory': ([ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t], ctypes.c_int),
            'archive_read_open_fd': ([ctypes.c_void_p, ctypes.c_int, ctypes.c_size_t], ctypes.c_int),
            'archive_read_next_header': ([ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)], ctypes.c_int),
            'archive_entry_pathname': ([ctypes.c_void_p], ctypes.c_char_p),
            'archive_entry_pathname_utf8': ([ctypes.c_void_p], ctypes.c_char_p),
            'archive_entry_filetype': ([ctypes.c_void_p], ctypes.c_uint),
            'archive_entry_symlink': ([ctypes.c_void_p], ctypes.c_char_p),
            'archive_entry_symlink_utf8': ([ctypes.c_void_p], ctypes.c_char_p),
            'archive_entry_hardlink': ([ctypes.c_void_p], ctypes.c_char_p),
            'archive_entry_mode': ([ctypes.c_void_p], ctypes.c_uint),
            'archive_entry_uid': ([ctypes.c_void_p], ctypes.c_int64),
            'archive_entry_gid': ([ctypes.c_void_p], ctypes.c_int64),
            'archive_entry_xattr_count': ([ctypes.c_void_p], ctypes.c_int),
            'archive_entry_size': ([ctypes.c_void_p], ctypes.c_int64),
            'archive_read_free': ([ctypes.c_void_p], ctypes.c_int),
            'archive_read_data': ([ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t], ctypes.c_ssize_t),
            'archive_error_string': ([ctypes.c_void_p], ctypes.c_char_p),
        }
        for name, (arguments, result) in signatures.items():
            function = getattr(library, name)
            function.argtypes, function.restype = arguments, result
    except (OSError, AttributeError) as error:
        raise ValueError('libarchive reader unavailable') from error
    _LIBARCHIVE = library
    return library


def read_archive(source, contents=False, limit=512 * 1024 * 1024, wanted=None):
    """One read-only libarchive pass over SOURCE (a path or an in-memory byte
    snapshot). Returns {member: (filetype, symlink, hardlink, raw spelling,
    permission bits, uid, gid, xattr count, data size)} — the metadata libalpm
    extraction applies (OWNER|PERM|XATTR, and a hardlink entry's body) — and,
    with CONTENTS, {member: bytes} of regular members (only WANTED ones when
    given). Names are UTF-8: pax names are never converted through the C
    locale."""
    library, entries, data, total = libarchive(), {}, {}, 0
    if isinstance(source, bytearray):
        source = bytes(source)
    fd = None
    if not isinstance(source, (bytes, bytearray)):
        fd = metadata_fd(Path(source).resolve() if not Path(source).is_absolute() else Path(source))
    archive = library.archive_read_new()
    buffer = ctypes.create_string_buffer(1 << 20)
    def text(utf8, raw):
        value = utf8 if utf8 is not None else raw
        return None if value is None else value.decode('utf-8', 'surrogateescape')
    try:
        if (not archive or library.archive_read_support_filter_all(archive) != 0
                or library.archive_read_support_format_all(archive) != 0):
            raise ValueError('unreadable package archive')
        opened = (library.archive_read_open_fd(archive, fd, 65536) if fd is not None
                  else library.archive_read_open_memory(archive, bytes(source), len(source)))
        if opened != 0:
            raise ValueError('unreadable package archive')
        entry = ctypes.c_void_p()
        while True:
            result = library.archive_read_next_header(archive, ctypes.byref(entry))
            if result == 1:
                return (entries, data) if contents else entries
            if result not in (0, -20):  # ARCHIVE_OK; ARCHIVE_WARN handled below
                raise ValueError('malformed package archive')
            mbs, utf8 = library.archive_entry_pathname(entry), library.archive_entry_pathname_utf8(entry)
            if result == -20:
                # The only tolerated warning is libarchive's pathname charset
                # conversion notice (non-ASCII names under LC_ALL=C, as root
                # pacman runs). The stored raw path bytes, which extraction
                # writes, must themselves be exact UTF-8. Any other warning
                # (link names, pax attributes, ...) fails closed.
                message = (library.archive_error_string(archive) or b'').decode('utf-8', 'replace')
                # Upstream wording: libarchive archive_read_support_format_tar.c
                # set_conversion_failed_error(a, sconv, "Pathname").
                if (not re.fullmatch(r"Pathname can't be converted from \S+ to current locale", message)
                        or mbs is None):
                    raise ValueError('malformed package archive: ' + message)
                try:
                    raw = mbs.decode('utf-8', 'strict')
                except UnicodeDecodeError as error:
                    raise ValueError('archive member name is not exact UTF-8') from error
            else:
                raw = text(utf8, mbs)
            if raw is None:
                raise ValueError('archive member without a path')
            name = str(Path(raw.removeprefix('./').rstrip('/')))
            if name in entries:
                raise ValueError('ambiguous duplicate archive member ' + name)
            kind = library.archive_entry_filetype(entry)
            hardlink = text(None, library.archive_entry_hardlink(entry))
            entries[name] = (kind, text(library.archive_entry_symlink_utf8(entry), library.archive_entry_symlink(entry)),
                             hardlink, raw, library.archive_entry_mode(entry) & 0o7777,
                             library.archive_entry_uid(entry), library.archive_entry_gid(entry),
                             library.archive_entry_xattr_count(entry), library.archive_entry_size(entry))
            if contents and kind == stat.S_IFREG and hardlink is None and (
                    wanted is None or (wanted(name) if callable(wanted) else name in wanted)):
                chunks = []
                while (size := library.archive_read_data(archive, buffer, len(buffer))) > 0:
                    chunks.append(buffer.raw[:size])
                    total += size
                    if total > limit:
                        raise ValueError('oversized package archive')
                if size < 0:
                    raise ValueError('malformed package archive member ' + name)
                data[name] = b''.join(chunks)
    finally:
        if archive:
            library.archive_read_free(archive)
        if fd is not None:
            os.close(fd)


def snapshot_identity(data):
    """(pkgname, pkgver) and .PKGINFO fields of an in-memory archive snapshot."""
    _, contents = read_archive(data, contents=True)
    fields = {}
    for line in contents.get('.PKGINFO', b'').decode('utf-8', 'replace').splitlines():
        if ' = ' in line:
            key, value = line.split(' = ', 1)
            fields.setdefault(key, []).append(value)
    if len(fields.get('pkgname', [])) != 1 or len(fields.get('pkgver', [])) != 1:
        return None, fields
    return (fields['pkgname'][0], fields['pkgver'][0]), fields




def ini_lines(text, context):
    # pacman INI comments occupy whole lines; '#' inside values is literal.
    for raw in text.split('\n'):
        if '\0' in raw or len(raw.encode('utf-8')) >= 4095:
            raise ValueError('unsupported NUL/overlong INI line in ' + context)
        line = raw.strip(' \t\r\v\f')
        if line and not line.startswith('#'):
            yield line


def hook_words(value, context):
    # libalpm wordsplit is not shell lexing: only quotes are escaped, and
    # neither comments nor expansions nor backslash-whitespace exist.
    words, word, quote, started = [], [], None, False
    index = 0
    while index < len(value):
        char = value[index]
        if char == '\\' and index + 1 < len(value) and (
                value[index + 1] == quote if quote else value[index + 1] in ('"', "'")):
            index += 1
            word.append(value[index])
            started = True
        elif quote:
            if char == quote:
                quote = None
            else:
                word.append(char)
        elif char in ('"', "'"):
            quote, started = char, True
        elif char in ' \t\r\n\v\f':
            if started:
                words.append(''.join(word))
                word, started = [], False
        else:
            word.append(char)
            started = True
        index += 1
    if quote:
        raise ValueError('unbalanced hook Exec quotes in ' + context)
    if started:
        words.append(''.join(word))
    if not words or not words[0]:
        raise ValueError('empty hook Exec in ' + context)
    return words


def parse_hook(text, context):
    section, triggers, action = None, [], {}
    for line in ini_lines(text, context):
        if line.startswith('[') and line.endswith(']'):
            section = line[1:-1]
            if section not in ('Trigger', 'Action'):
                raise ValueError('invalid hook section in ' + context)
            if section == 'Trigger':
                triggers.append({'Type': '', 'Operation': [], 'Target': []})
            continue
        key, separator, value = line.partition('=')
        key, value = key.strip(' \t\r\v\f'), value.strip(' \t\r\v\f')
        if section == 'Trigger':
            trigger = triggers[-1]
            if not separator or key not in trigger:
                raise ValueError('invalid hook trigger option in ' + context)
            if key == 'Type':
                if value not in ('Package', 'Path', 'File'):
                    raise ValueError('invalid hook trigger type in ' + context)
                trigger[key] = value
            elif key == 'Operation':
                if value not in ('Install', 'Upgrade', 'Remove'):
                    raise ValueError('invalid hook operation in ' + context)
                trigger[key].append(value)
            else:
                trigger[key].append(value)
        elif section == 'Action':
            if key in ('AbortOnFail', 'NeedsTargets'):
                action[key] = True
            elif not separator or key not in ('When', 'Exec', 'Description', 'Depends'):
                raise ValueError('invalid hook action option in ' + context)
            elif key == 'When':
                if value not in ('PreTransaction', 'PostTransaction'):
                    raise ValueError('invalid hook action timing in ' + context)
                action[key] = value
            elif key == 'Exec':
                action[key] = hook_words(value, context)
            else:
                action[key] = value
        else:
            raise ValueError('hook option outside section in ' + context)
    if any(not all(trigger.values()) for trigger in triggers):
        raise ValueError('missing required hook trigger fields in ' + context)
    if triggers and ('Exec' not in action or 'When' not in action):
        raise ValueError('missing required hook action fields in ' + context)
    return triggers, action


def mtree_entries(data):
    """Yield (path, filetype) from libalpm's libarchive mtree decoder.

    checkfs stays disabled: entry paths are metadata, never filesystem reads."""
    library = libarchive()
    archive = library.archive_read_new()
    if not archive:
        raise ValueError('libarchive mtree reader allocation failed')
    try:
        if (library.archive_read_support_filter_all(archive) != 0
                or library.archive_read_support_format_mtree(archive) != 0
                or library.archive_read_set_format_option(archive, b'mtree', b'checkfs', None) != 0
                or library.archive_read_open_memory(archive, data, len(data)) != 0):
            raise ValueError('unreadable/unsupported .MTREE')
        entry = ctypes.c_void_p()
        while True:
            result = library.archive_read_next_header(archive, ctypes.byref(entry))
            if result == 1:  # ARCHIVE_EOF
                return
            if result != 0:  # reject warnings as well as failed parses
                raise ValueError('malformed/ambiguous .MTREE')
            raw = library.archive_entry_pathname(entry)
            if raw is None:
                raise ValueError('missing .MTREE entry path')
            yield os.fsdecode(raw).removeprefix('./'), library.archive_entry_filetype(entry)
    finally:
        library.archive_read_free(archive)


def mtree_paths(data):
    # Use libalpm's libarchive mtree decoder, not a second mtree grammar. DATA
    # is the .MTREE member of the audited archive snapshot.
    if len(data) > 64 * 1024 * 1024:
        raise ValueError('oversized .MTREE requires manual review')
    paths = set()
    for name, kind in mtree_entries(data):
        if name.startswith('.'):
            continue  # same metadata-path exclusion as libalpm
        if (not name or name.startswith('/') or '..' in Path(name).parts
                or str(Path(name)) != name.rstrip('/') or not kind):
            raise ValueError('unsupported .MTREE entry path/type')
        if kind == stat.S_IFDIR and not name.endswith('/'):
            name += '/'
        elif kind != stat.S_IFDIR and name.endswith('/'):
            raise ValueError('ambiguous .MTREE non-directory slash')
        if name in paths:
            raise ValueError('ambiguous duplicate .MTREE entry')
        paths.add(name)
    return paths



def read_config(root):
    sections = {'options': []}
    section = 'options'
    stack = set()
    def parse(path):
        nonlocal section
        real = observed_resolve(path, root)
        if real in stack:
            raise ValueError('cyclic pacman Include')
        stack.add(real)
        for line in ini_lines(real.read_bytes().decode('utf-8'), str(real)):
            if line.startswith('[') and line.endswith(']'):
                section = line[1:-1]
                sections.setdefault(section, [])
            elif line.split('=', 1)[0].strip(' \t\r\v\f') == 'Include' and '=' in line:
                pattern = line.split('=', 1)[1].strip(' \t\r\v\f')
                if not pattern.startswith('/'):
                    raise ValueError('relative pacman Include is not supported')
                parent = Path(pattern).parent
                if root and any(c in str(parent) for c in '*?['):
                    raise ValueError('fixture Include directory wildcards require explicit paths')
                directory = observed_resolve(Path(str(root) + str(parent)), root)
                matches = sorted(glob.glob(str(directory / Path(pattern).name)))
                if not matches:
                    raise ValueError('unreadable pacman Include ' + pattern)
                for match in matches:
                    parse(Path(match))
            else:
                sections[section].append(line)
        stack.remove(real)
    parse(Path(str(root) + '/etc/pacman.conf'))
    # A host [oniomarchy] section is foreign: recorded for reporting, never a
    # VAPT repository. Only the approved private descriptor, for an operation
    # that opted in, adds the source, and always after every other one.
    HOST_STANZAS[str(root)] = sections.pop(ONIOMARCHY, None)
    if WITH_BLACKARCH and 'blackarch' not in sections:
        sections['blackarch'] = list(BLACKARCH_STANZA)
    if WITH_ONIOMARCHY and oniomarchy_descriptor(root) == 'approved':
        sections[ONIOMARCHY] = [ONIOMARCHY_POLICY, 'Server = ' + ONIOMARCHY_SERVER, ONIOMARCHY_USAGE]
    return sections


def repositories(root, dbpath=None):
    """Sync records per repository. Any oniomarchy database in a system or
    fixture sync directory is ignored: the private source's records come only
    from its own signed database (the approved cache, or the copy placed in a
    private DBPATH), filtered by the fixed admission table."""
    records = sync_repositories(root, dbpath)
    records.pop(ONIOMARCHY, None)
    if WITH_ONIOMARCHY:
        if dbpath:
            database = Path(dbpath) / 'sync' / 'oniomarchy.db'
        else:
            database = Path(str(root) + ONIOMARCHY_STATE + '/sync/oniomarchy.db')
        try:
            records[ONIOMARCHY] = oniomarchy_records(database)
        except (OSError, ValueError):
            records[ONIOMARCHY] = []
    return records


def sync_repositories(root, dbpath=None):
    if root:
        # Fixture DB protocol, honouring DBPATH like libalpm: the sync DB of
        # DBPATH (a copied pre-refresh snapshot or a private refresh), else
        # the system sync DB; var/lib/haseen/vapt/repositories.json stands for
        # both when a fixture models no separate sync DB state.
        sync = Path(dbpath) / 'sync' if dbpath else Path(str(root) + '/var/lib/pacman/sync')
        fixture = observed_resolve(sync / 'repositories.json', root)
        if not fixture.exists():
            fixture = observed_resolve(Path(str(root) + '/var/lib/haseen/vapt/repositories.json'), root)
        records = json.loads(fixture.read_text()) if fixture.exists() else {}
        # Membership-only fixtures resolve ordinary exact names, but leave
        # closure unknown rather than inventing dependency safety evidence.
        directory = observed_resolve(Path(str(root) + '/var/lib/pacman/sync'), root)
        for path in directory.glob('*.pkgs'):
            path = observed_resolve(path, root)
            records.setdefault(path.stem, [{'name': n, 'version': '', 'url': '', 'metadata_unknown': True}
                                          for n in path.read_text().splitlines() if NAME.fullmatch(n)])
        return records
    records = {}
    for path in Path(dbpath or '/var/lib/pacman').joinpath('sync').glob('*.db'):
        try:
            records[path.stem] = [field_data(text) for name, text in archive_members(path) if name.endswith('/desc')]
        except (OSError, ValueError):
            continue
    return records


def installed(root):
    fixture = observed_resolve(Path(str(root) + '/var/lib/haseen/vapt/installed.json'), root)
    if root and fixture.exists():
        return json.loads(fixture.read_text())
    result = []
    directory = observed_resolve(Path(str(root) + '/var/lib/pacman/local'), root)
    if not directory.is_dir():
        return result
    for child in directory.iterdir():
        path = observed_resolve(child / 'desc', root)
        if not path.is_file():
            continue
        data = field_data(path.read_text())
        other = observed_resolve(child / 'depends', root)
        if other.exists():
            data.update(field_data(other.read_text()))
        files = observed_resolve(child / 'files', root)
        if files.is_file():
            data.update(field_data(files.read_text()))
        result.append(data)
    return result


def emit_snapshot(root, offline):
    config = read_config(root)
    for repo, lines in config.items():
        if repo == 'options' or not ALLOWED.fullmatch(repo):
            continue
        print('repo', repo, 'enabled', sep='\t')
        if not repository_policy_safe(repo, lines):
            print('unsafe', repo, 'insecure signature policy', sep='\t')
        for line in lines:
            if line.startswith('Server') and not repository_mirror_safe(repo, line.split('=', 1)[1]):
                print('unsafe', repo, mirror_refusal(repo, line.split('=', 1)[1]) + ' mirror URL', sep='\t')
    for repo, records in repositories(root).items():
        if repo not in config or not ALLOWED.fullmatch(repo):
            continue
        if repo == ONIOMARCHY and not records:
            continue  # no admitted record: the private database is unavailable
        print('database', repo, 'available', sep='\t')
        for record in records:
            fields = (record['name'], record.get('version') or '-', record.get('url') or '-',
                      ','.join(record.get('provides', [])) or '-')
            if not emit_safe(*fields):
                # A tab or newline would shift the columns the shell reads; a
                # control byte would reach a terminal. Refused, not encoded.
                label = record['name'] if emit_safe(record['name']) and NAME.fullmatch(record['name']) else 'with an unprintable name'
                print('rejected', repo, 'package record ' + label
                      + ' has a tab, newline or control character in its metadata; not offered', sep='\t')
                continue
            print('package', repo, *fields, sep='\t')


# Tab/newline (field- and row-breaking) and any other C0/C1 control or DEL.
CONTROL = re.compile('[\x00-\x1f\x7f-\x9f]')


def emit_safe(*fields):
    """True when no field could break a tab-separated row or carry a
    terminal control sequence into emitted metadata."""
    return not any(CONTROL.search(str(field)) for field in fields)


def render_config(root, frozen=None, local=False):
    config = read_config(root)
    print('[options]')
    # Keep effective host options, but replace paths/include directives that
    # could smuggle arbitrary repositories or execute unreviewed hooks.
    blocked = {'RootDir', 'DBPath', 'LogFile', 'CacheDir', 'HookDir', 'XferCommand', 'LocalFileSigLevel', 'RemoteFileSigLevel', 'SigLevel'}
    for line in config.get('options', []):
        if line.split('=', 1)[0].strip() not in blocked:
            print(line)
    print('SigLevel = Required DatabaseOptional\nLocalFileSigLevel = Required TrustedOnly\nRemoteFileSigLevel = Required TrustedOnly')
    # HookDir paths are retained and audited before transactions, not disabled.
    for line in config.get('options', []):
        if line.startswith('HookDir'):
            print(line)
    if local:
        return  # exact audited archives only: no repository can resolve anything
    for repo, lines in config.items():
        if not ALLOWED.fullmatch(repo):
            continue
        if not repository_policy_safe(repo, lines):
            raise ValueError('insecure repository ' + repo)
        print('[' + repo + ']')
        for line in lines:
            key = line.split('=', 1)[0].strip()
            if key == 'Server':
                if not repository_mirror_safe(repo, line.split('=', 1)[1]):
                    raise ValueError(mirror_refusal(repo, line.split('=', 1)[1]) + ' repository mirror ' + repo)
                print('Server = file://' + frozen + '/' + repo if frozen else line)
            elif key in ('SigLevel', 'Usage'):
                if key == 'SigLevel':
                    # The private source keeps its stricter declared policy in
                    # sync, frozen and recovery configurations alike.
                    print(ONIOMARCHY_POLICY if repo == ONIOMARCHY else 'SigLevel = Required DatabaseOptional')
                else:
                    print(line)

def cache_permissions(root, path):
    if not re.fullmatch(r'/var/cache/haseen-vapt\.[A-Za-z0-9]+/packages', path):
        raise ValueError('unexpected root package cache path')
    config = read_config(root)
    users = [line.split('=', 1)[1].strip() for line in config.get('options', []) if line.startswith('DownloadUser') and '=' in line]
    if len(users) > 1:
        raise ValueError('ambiguous DownloadUser')
    destination = str(root) + path
    if users:
        accounts = [line.split(':') for line in Path(str(root) + '/etc/passwd').read_text().splitlines()]
        account = next((a for a in accounts if a[0] == users[0] and len(a) == 7), None)
        if account is None:
            raise ValueError('DownloadUser account unavailable')
        os.chown(destination, 0, int(account[3]), follow_symlinks=False)
        os.chmod(destination, 0o775, follow_symlinks=False)
    else:
        os.chmod(destination, 0o755, follow_symlinks=False)


def satisfies(record, dep):
    name = re.split(r'[<>=]', dep, maxsplit=1)[0]
    candidates = [record.get('name', '')] + record.get('provides', [])
    for item in candidates:
        if re.split(r'[<>=]', item, maxsplit=1)[0] != name:
            continue
        match = re.fullmatch(r'[^<>=]+([<>=]+)(.+)', dep)
        if not match:
            return True
        version = item.split('=', 1)[1] if '=' in item else record.get('version', '') if item == record.get('name') else ''
        if not version:
            continue
        compare = subprocess.run(['vercmp', version, match[2]], capture_output=True, text=True, check=True)
        result = int(compare.stdout.strip())
        if {'=': result == 0, '>': result > 0, '<': result < 0, '>=': result >= 0, '<=': result <= 0}.get(match[1], False):
            return True
    return False


def forbidden(record):
    return record.get('name', '').startswith('omarchy') or any('omarchy' in d for d in record.get('depends', []))


def omarchy_refusal(*texts):
    """The label of a refusal by the generic 'omarchy' substring rules. They
    also match this private source's own name; that stays refused, but is
    reported for review rather than mislabelled as Omarchy."""
    lowered = ' '.join(texts).lower()
    if 'omarchy' in lowered.replace(ONIOMARCHY, ''):
        return 'forbidden Omarchy'
    return 'oniomarchy self-reference requires review' if 'omarchy' in lowered else 'forbidden'


def activation_refusal(text):
    """'' unless ACTIVATION matches TEXT; then 'activation' or the Omarchy
    label (omarchy_refusal) of the match."""
    match = ACTIVATION.search(text)
    if not match:
        return ''
    return omarchy_refusal(text) if match.group(0).lower() == 'omarchy' else 'activation'


def repository_mirror_safe(repo, url):
    """One mirror rule for snapshot, rendering, closure and bootstrap: HTTPS
    and no Omarchy host for every source; the private source only at its one
    exact HTTPS root (no credentials, port, query, fragment or other path)."""
    url = url.strip(' \t\r\v\f')
    if repo == ONIOMARCHY:
        return url in (ONIOMARCHY_SERVER, 'https://pkgs.oniomarchy.com/x86_64')
    return url.startswith('https://') and 'omarchy' not in url.lower()


def mirror_refusal(repo, url):
    """Why repository_mirror_safe refused URL, for the report."""
    if repo == ONIOMARCHY:
        return 'not the reviewed private source root:'
    if 'omarchy' in url.lower():
        return omarchy_refusal(url) + ':'
    return 'non-HTTPS'


def repository_policy_safe(repo, lines):
    """Never/TrustAll are refused everywhere. The private source must declare
    exactly Required DatabaseRequired (trusted-only package and database
    signatures), with no other signature, include or option line."""
    levels = [line for line in lines if line.split('=', 1)[0].strip() == 'SigLevel']
    if any(re.search(r'Never|TrustAll', line) for line in levels):
        return False
    if repo != ONIOMARCHY:
        return True
    keys = [line.split('=', 1)[0].strip() for line in lines]
    usage = [line for line in lines if line.split('=', 1)[0].strip() == 'Usage']
    return (len(levels) == 1 and levels[0].split('=', 1)[1].split() == ['Required', 'DatabaseRequired']
            and keys.count('Server') >= 1 and set(keys) <= {'SigLevel', 'Server', 'Usage'}
            and all(line == ONIOMARCHY_USAGE for line in usage))


def repository_safe(source, config):
    if not ALLOWED.fullmatch(source) or source not in config:
        return False
    return (repository_policy_safe(source, config[source])
            and all(repository_mirror_safe(source, line.split('=', 1)[1])
                    for line in config[source] if line.startswith('Server')))


def oniomarchy_path(root, name):
    return Path(str(root) + ONIOMARCHY_STATE + '/' + name)


ONIOMARCHY_STATE_FILES = ('oniomarchy.conf', 'oniomarchy.authority', 'oniomarchy.database',
                          'sync/oniomarchy.db', 'sync/oniomarchy.db.sig')


def oniomarchy_state_safe(root, name):
    """The path of a root-owned, single-link regular state file under the
    private source directory (the caller's own in a fixture sysroot) whose
    ancestry nobody else can replace; None when absent. Anything else is a
    conflict."""
    path = oniomarchy_path(root, name)
    if not os.path.lexists(path):
        return None
    info = os.lstat(path)
    owners = (0, os.geteuid()) if root else (0,)
    if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid not in owners
            or info.st_mode & 0o022):
        raise ValueError('private source state is not a single root-owned regular file: ' + name)
    nonreplaceable_ancestry(path.parent, bool(root))
    return path


def oniomarchy_state_bytes(root, name, limit=1024 * 1024):
    """No-follow bytes of a safe private state file; None when absent."""
    path = oniomarchy_state_safe(root, name)
    return None if path is None else metadata_bytes(path, limit)


def oniomarchy_descriptor(root):
    """absent, approved (exactly the reviewed stanza) or conflict. Any unsafe
    private state (a redirected, replaceable or group/other-writable state
    directory, or a state path that is not a single root-owned regular file)
    is a conflict: it is preserved and never rewritten by an approval."""
    try:
        for directory in (oniomarchy_path(root, ''), oniomarchy_path(root, 'sync')):
            if os.path.lexists(directory):
                nonreplaceable_ancestry(directory, bool(root))
        for name in ONIOMARCHY_STATE_FILES:
            oniomarchy_state_safe(root, name)
        data = oniomarchy_state_bytes(root, 'oniomarchy.conf', 4096)
    except (OSError, ValueError):
        return 'conflict'
    if data is None:
        return 'absent'
    return 'approved' if data == ONIOMARCHY_DESCRIPTOR else 'conflict'


def oniomarchy_admission():
    """package -> (role, logical) from the reviewed fixed admission table."""
    table = {}
    path = Path(__file__).resolve().parent / 'packages' / 'oniomarchy.tsv'
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        fields = line.split('\t')
        if (len(fields) != 3 or not NAME.fullmatch(fields[0]) or fields[0] in table
                or fields[1] not in ('candidate', 'dependency', 'infrastructure')):
            raise ValueError('malformed oniomarchy admission table')
        table[fields[0]] = (fields[1], fields[2])
    if len(table) != ONIOMARCHY_ADMITTED:
        raise ValueError('oniomarchy admission table is not the reviewed fixed set')
    return table


def oniomarchy_records(database, keep_infrastructure=True):
    """Admitted x86_64/any records of the private signed database. Names
    outside the fixed table are never records, even when a newer signed
    database publishes them; a duplicate record makes the database unusable."""
    if not os.path.lexists(database):
        return []
    admitted = oniomarchy_admission()
    records, seen = [], set()
    for name, text in archive_members(metadata_bytes(Path(database), 64 * 1024 * 1024)):
        if not name.endswith('/desc'):
            continue
        record = field_data(text)
        package = record.get('name', '')
        if package in seen:
            raise ValueError('duplicate oniomarchy database record ' + package)
        seen.add(package)
        if package not in admitted or len(record.get('arch', [])) != 1 or record['arch'][0] not in ('x86_64', 'any'):
            continue
        if admitted[package][0] == 'infrastructure' and not keep_infrastructure:
            continue
        record['role'] = admitted[package][0]
        records.append(record)
    return records


def oniomarchy_admit(record, target=False, installed=False):
    """A planned/candidate record of the private source: a candidate only as
    the requested target (or an already-installed package, which is not a new
    selection), otherwise an admitted dependency; never the keyring outside
    its own path, never a candidate without an inventory mapping, never a
    replacement. A declared conflict is admitted: it removes nothing unless a
    conflicting package is installed, which reject_removals refuses."""
    name = record.get('name', '')
    role, logical = oniomarchy_admission().get(name, ('', ''))
    if role == 'candidate' and not (target or installed):
        raise ValueError('oniomarchy candidate is admitted only as the requested target, never as a dependency: ' + name)
    if role not in ('candidate', 'dependency') or (target and role != 'candidate'):
        raise ValueError('oniomarchy package outside the admitted role set: ' + name)
    if role == 'candidate' and logical == '-':
        raise ValueError('oniomarchy candidate without an inventory mapping is never selected or installed: ' + name)
    if record.get('replaces'):
        raise ValueError('oniomarchy package declares a replacement/conflict removal: ' + name)


def oniomarchy_consumer_ok(record, consumers):
    """A private dependency row named in dependencies.tsv serves only its
    recorded consumer (or any, for '*') and only as its recorded target;
    CONSUMERS are the logical names of the package that declares the
    dependency and of the requested target. A row whose logical is '-' has no
    dependencies.tsv entry and no recorded consumer."""
    role, logical = oniomarchy_admission().get(record.get('name', ''), ('', ''))
    if role != 'dependency' or logical == '-':
        return True
    consumer, target = vapt_tables()[3].get(logical, ('', ''))
    return target == ONIOMARCHY + '/' + record['name'] and (consumer == '*' or consumer in consumers)


def source_satisfies(source, record, dep):
    """The private source satisfies a dependency only by its exact package
    name or, for a reviewed alias (aliases.tsv), by that alias's logical name
    which the record itself provides; never through any other Provides."""
    if source != ONIOMARCHY:
        return satisfies(record, dep)
    name = re.split(r'[<>=]', dep, maxsplit=1)[0]
    if record.get('name') == name:
        return satisfies({k: v for k, v in record.items() if k != 'provides'}, dep)
    if vapt_tables()[2].get((ONIOMARCHY, record.get('name'))) != name:
        return False
    provides = [p for p in record.get('provides', []) if re.split(r'[<>=]', p, maxsplit=1)[0] == name]
    return bool(provides) and satisfies(dict(record, name='', provides=provides), dep)


_VAPT_TABLES = None


def vapt_tables():
    """identities.tsv, identity-policy.tsv, aliases.tsv and dependencies.tsv
    (logical -> (consumer, target)), as the shell validator accepted them
    (the validator refuses malformed rows first)."""
    global _VAPT_TABLES
    if _VAPT_TABLES is not None:
        return _VAPT_TABLES
    base = Path(__file__).resolve().parent / 'packages'
    def rows(name):
        return [line.split('\t') for line in (base / name).read_text().splitlines()
                if line.strip() and not line.startswith('#')]
    identities = {f[0]: (f[1], f[2], f[3]) for f in rows('identities.tsv') if len(f) == 5}
    policies = {f[0]: f[1] for f in rows('identity-policy.tsv') if len(f) == 3}
    aliases = {(f[1], f[2]): f[0] for f in rows('aliases.tsv') if len(f) == 3}
    dependencies = {f[0]: (f[1], f[2]) for f in rows('dependencies.tsv') if len(f) == 4}
    _VAPT_TABLES = identities, policies, aliases, dependencies
    return _VAPT_TABLES


def url_parts(url):
    match = re.fullmatch(r'([Hh][Tt][Tt][Pp][Ss]?)://([A-Za-z0-9.-]+)(/[A-Za-z0-9._~+/-]*)?', url or '')
    if not match:
        return None
    host, path = match[2].lower(), (match[3] or '').lower().rstrip('/')
    if host.startswith('.') or host.endswith('.') or '..' in host:
        return None
    if any(segment in ('', '.', '..') for segment in path.split('/')[1:]):
        return None
    return match[1].lower(), host, path


def closure_identity_ok(source, record):
    """The leaf resolver's identity rules for any package the closure plans
    or accepts: a package that names an inventory item (directly or through
    that repository's reviewed alias) must be that item's identity."""
    identities, policies, aliases, _ = vapt_tables()
    name = record.get('name', '')
    logical = aliases.get((source, name), name)
    if policies.get(logical) == 'blocked':
        return False
    if logical not in identities:
        return True
    kind, target, upstream = identities[logical]
    if kind == 'native':
        return False
    if target not in ('*', source + '/' + name):
        return False
    expected, actual = url_parts(upstream), url_parts(record.get('url', ''))
    if not expected or not actual or actual[1] != expected[1]:
        return False
    if actual[0] != expected[0] and actual[0] != 'https':
        return False
    return actual[2] == expected[2] or actual[2].startswith(expected[2] + '/')


def allowed_local(record, config, repos, sources=ALLOWED):
    if forbidden(record) or not record.get('version') or not record.get('url'):
        return False
    return any(p.get('name') == record['name'] and p.get('version') == record['version']
               and p.get('url', '').rstrip('/') == record['url'].rstrip('/')
               and not p.get('metadata_unknown') and not forbidden(p)
               for source in config if repository_safe(source, config) and sources.fullmatch(source)
               for p in repos.get(source, []))


def retained_private_records(root):
    """Read-only provenance for packages already installed from the private
    source when this operation did not opt in (or the source was disabled):
    the cached database whose exact bytes were verified at the last refresh,
    while the private state is not a conflict. These records only vouch for
    an installed package; they are never candidates and authorise nothing."""
    if WITH_ONIOMARCHY or oniomarchy_descriptor(root) == 'conflict' or oniomarchy_database(root)[0] != 'verified':
        return []
    try:
        return oniomarchy_records(oniomarchy_path(root, 'sync/oniomarchy.db'), keep_infrastructure=False)
    except (OSError, ValueError):
        return []


def reject_removals(incoming, local):
    """Removal scriptlets/side effects are not reviewed by an add-only plan."""
    for new in incoming:
        for old in local:
            if old['name'] == new['name']:
                continue
            if (any(satisfies(old, dep) for dep in new.get('replaces', []) + new.get('conflicts', []))
                    or any(satisfies(new, dep) for dep in old.get('conflicts', []))):
                raise ValueError('unsupported replacement/conflict removal: ' + new['name'] + ' removes ' + old['name'])


def closure(root, target, transaction=None, dbpath=None):
    config = read_config(root)
    repos = repositories(root, dbpath)
    planned, sources = [], {}
    target_repo, target_name = target.split('/', 1) if target != '-' else ('', '')
    local = installed(root)
    local_names = {p['name'] for p in local}
    # The repository set both homonym checks use (the shell's
    # vapt_oniomarchy_target too): every other configured repository with
    # safe policy/mirror and readable metadata, usable this run or not.
    def earlier_homonym(name):
        # The package name, or the logical item a reviewed alias maps it to.
        names = {name, vapt_tables()[2].get((ONIOMARCHY, name), name)}
        return any(p.get('name') in names for source in config
                   if source != ONIOMARCHY and repository_safe(source, config) for p in repos.get(source, []))
    def admit(source, record, requested=False, upgrade=False, present=False):
        # The private source never shadows a same-named package of another
        # configured source, never supplies a role outside its fixed table
        # (a candidate only as the requested target or an installed package),
        # and every source's packages keep the inventory identity rules. A
        # planned upgrade of an already-installed same-name package is not a
        # new selection: an identity mismatch there is a warning.
        if source == ONIOMARCHY:
            oniomarchy_admit(record, target=requested, installed=upgrade or present)
            if earlier_homonym(record['name']):
                raise ValueError('oniomarchy package shadows a package of an earlier source: ' + record['name'])
        if not closure_identity_ok(source, record):
            message = 'package identity does not match the reviewed inventory identity: ' + source + '/' + record['name']
            if not upgrade:
                raise ValueError(message)
            print('warning: ' + message + ' (planned upgrade of the installed package; not a new selection)', file=sys.stderr)
    def logical_of(source, name):
        return vapt_tables()[2].get((source, name), name)
    root_logical = logical_of(target_repo, target_name) if target != '-' else ''
    if transaction:
        for row in Path(transaction).read_text().splitlines():
            if not row.strip():
                continue
            source, package, version, *_ = row.split('\t')
            if not repository_safe(source, config):
                raise ValueError('forbidden transaction source')
            record = next((p for p in repos.get(source, []) if p['name'] == package and p.get('version') == version), None)
            if record is None or record.get('metadata_unknown'):
                raise ValueError('transaction differs from inspected metadata')
            requested = (source, package) == (target_repo, target_name)
            admit(source, record, requested=requested, upgrade=not requested and package in local_names)
            planned.append(record)
            sources[id(record)] = source
    selected = []
    if target != '-':
        if not repository_safe(target_repo, config):
            raise ValueError('forbidden or disabled repository')
        selected = [p for p in repos.get(target_repo, []) if p['name'] == target_name]
        if len(selected) != 1:
            raise ValueError('dependency metadata unavailable')
        admit(target_repo, selected[0], requested=True)
        sources[id(selected[0])] = target_repo
    planned_names = {p['name'] for p in planned}
    retained = [p for p in local if p['name'] not in planned_names]
    reject_removals(planned or selected, local)
    by_name = {}
    cached = retained_private_records(root)
    def same_record(record, candidates):
        return any(p.get('version') == record.get('version') and not p.get('metadata_unknown')
                   and p.get('url', '').rstrip('/') == record.get('url', '').rstrip('/')
                   for p in candidates)
    def cached_proof(record):
        # Read-only: an installed package the verified private cache vouches
        # for, when this operation did not opt into the source.
        return (bool(record.get('version')) and bool(record.get('url')) and not forbidden(record)
                and same_record(record, [p for p in cached if p.get('name') == record['name']]))
    def origin(record):
        # The earliest configured allowed source whose exact record (name,
        # version, URL) vouches for a retained package, then the verified
        # private cache; '' when none does.
        for source in config:
            if not (repository_safe(source, config) and ALLOWED.fullmatch(source)):
                continue
            if source not in by_name:
                by_name[source] = {}
                for p in repos.get(source, []):
                    by_name[source].setdefault(p.get('name'), []).append(p)
            if same_record(record, by_name[source].get(record['name'], [])):
                return source
        return ONIOMARCHY if cached_proof(record) else ''
    def earlier_satisfier(dep):
        # The offline search's order as a rule for every mode: any other
        # configured repository record satisfying DEP (by name or versioned
        # Provides) precedes a new private dependency, so a reviewed
        # transaction never admits one the dry-run would not have chosen.
        for source in config:
            if source != ONIOMARCHY and repository_safe(source, config):
                found = next((p for p in repos.get(source, []) if satisfies(p, dep)), None)
                if found is not None:
                    return source + '/' + found['name']
        return ''
    checked = set()
    def visit(record, unchanged=False):
        key = (record['name'], record.get('version', ''))
        if key in checked:
            return
        checked.add(key)
        if record.get('metadata_unknown'):
            raise ValueError('unknown dependency metadata ' + record['name'])
        if forbidden(record):
            if record['name'].startswith('omarchy'):
                raise ValueError(omarchy_refusal(record['name']) + ': package ' + record['name'])
            named = [d for d in record.get('depends', []) if 'omarchy' in d]
            raise ValueError(omarchy_refusal(*named) + ': ' + record['name'] + ' depends on ' + ', '.join(named))
        if unchanged:
            if not allowed_local(record, config, repos) and not cached_proof(record):
                raise ValueError('unresolved retained provider allowed-source identity ' + record['name'])
            # A retained provider keeps its source's admission and the
            # inventory identity rules, as a newly planned one would.
            admit(origin(record), record, present=True)
        else:
            reject_removals([record], local)
        consumers = {logical_of(origin(record) if unchanged else sources.get(id(record), ''), record['name']), root_logical}
        for dep in record.get('depends', []):
            if 'omarchy' in dep:
                raise ValueError(omarchy_refusal(dep) + ': dependency ' + dep)
            candidates = [(p, False) for p in planned if source_satisfies(sources.get(id(p), ''), p, dep)]
            candidates += [(p, True) for p in retained if source_satisfies(origin(p), p, dep)]
            if not candidates and not transaction:
                for source in config:
                    if repository_safe(source, config):
                        found = [p for p in repos.get(source, []) if source_satisfies(source, p, dep)]
                        for candidate in found:
                            admit(source, candidate)
                            sources[id(candidate)] = source
                        candidates += [(p, False) for p in found]
                        if candidates:
                            break
            if not candidates:
                raise ValueError('unresolvable dependency ' + dep)
            for candidate, retained_provider in candidates:
                source = origin(candidate) if retained_provider else sources.get(id(candidate), '')
                if source == ONIOMARCHY and not oniomarchy_consumer_ok(candidate, consumers):
                    raise ValueError('oniomarchy dependency ' + candidate['name'] + ' serves only its recorded consumer '
                                     '(dependencies.tsv), not ' + ', '.join(sorted(c for c in consumers if c)))
                if source == ONIOMARCHY and not retained_provider:
                    other = earlier_satisfier(dep)
                    if other:
                        raise ValueError('oniomarchy dependency ' + candidate['name'] + ' would win over the earlier provider '
                                         + other + ' of ' + dep + '; the private source is the last tier')
                visit(candidate, retained_provider)
    for record in selected + planned:
        visit(record)
    print('safe')


def keyring_population_script(text):
    # SHA256 of the reviewed population-only script after whitespace
    # normalization. Upstream shell source is not redistributed here.
    normalized = '\n'.join(' '.join(line.split()) for line in text.splitlines() if line.strip())
    if (len(text.encode('utf-8')) > 4096 or hashlib.sha256(normalized.encode()).hexdigest()
            != '6ac8454d6c8bb162d784d1715e34d66086d1b39cfb52bb744b17e61de4bed4c5'):
        raise ValueError('changed/unknown BlackArch keyring population scriptlet')


def audit_archives(root, filenames, keyring_population=None, plan=None, dbpath=None, reference=None, report=None,
                   sudo_plugins_path=None, base_dbpath=None, authority_facts_path=None):
    sudo_plugins = None
    config = read_config(root)
    local = {p['name']: p for p in installed(root)}
    packages, payloads, scriptlets, incoming, backups = {}, {}, [], {}, set()
    incoming_records, oldpaths, newpaths = [], set(), set()
    physical_newpaths, path_owners, dropped_dirs = set(), {}, set()
    # Explicit directory headers per member name, (package, archive entry):
    # libalpm extracts a NEW directory with exactly their owner/mode/xattrs.
    dir_entries = {}
    # Audited solver plan rows name each archive's repository. Provenance is
    # granted later only to bytes equal to that repository's reviewed digest.
    planned_sources, archive_rows, payload_package, payload_kinds = {}, {}, {}, {}
    for row in (Path(plan).read_text().splitlines() if plan else []):
        fields = row.split('\t')
        if not row.strip():
            continue
        if len(fields) < 3 or not ALLOWED.fullmatch(fields[0]) or fields[1] in {n for n, _ in planned_sources}:
            raise ValueError('malformed/duplicate transaction plan row ' + row)
        planned_sources[(fields[1], fields[2])] = fields[0]
    oniomarchy_rows = [name for (name, _), source in planned_sources.items() if source == ONIOMARCHY]
    if oniomarchy_rows:
        # The fixed admission table applies to every audited private-source
        # row; the exact records are compared below like any other source.
        admitted = oniomarchy_admission()
        if any(admitted.get(name, ('',))[0] not in ('candidate', 'dependency') for name in oniomarchy_rows):
            raise ValueError('oniomarchy plan row outside the admitted role set')
    options = config.get('options', [])
    # The package backend is pinned to C as well; Python startup locale
    # coercion and sudo policy must not change hook relevance.
    locale.setlocale(locale.LC_ALL, 'C')
    try:
        libc_fnmatch = ctypes.CDLL(None).fnmatch
    except AttributeError as error:
        raise ValueError('libc fnmatch unavailable for transaction audit') from error
    libc_fnmatch.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int)
    libc_fnmatch.restype = ctypes.c_int
    def patterns_valid(patterns):
        if any('\0' in pattern for pattern in patterns):
            raise ValueError('NUL in transaction match pattern')
    def matches_patterns(name, patterns):
        if '\0' in name:
            raise ValueError('NUL in transaction match target')
        # libalpm checks rules backwards, stripping exactly one leading
        # inversion or escape before calling fnmatch with flags=0.
        encoded = os.fsencode(name)
        for pattern in reversed(patterns):
            inverted = pattern.startswith('!')
            if inverted or pattern.startswith('\\'):
                pattern = pattern[1:]
            result = libc_fnmatch(os.fsencode(pattern), encoded, 0)
            if result == 0:
                return not inverted
            if result != 1:  # glibc FNM_NOMATCH
                raise ValueError('libc fnmatch failed for transaction match pattern')
        return False
    option_patterns = {
        key: [p for line in options if line.split('=', 1)[0].strip(' \t\r\v\f') == key and '=' in line
              for p in line.split('=', 1)[1].strip(' \t\r\v\f').split(' ') if p]
        for key in ('NoExtract', 'NoUpgrade')
    }
    for patterns in option_patterns.values():
        patterns_valid(patterns)
    def matches_option(name, key):
        return matches_patterns(name, option_patterns[key])
    archive_fields = {}
    cache = {}
    def snapshot(path):
        """One immutable byte snapshot per archive path (L5): digest, identity,
        signature, metadata, .MTREE, scripts, helpers and payload bytes all
        come from these bytes, looked up by exact member name."""
        key = ('snapshot', str(path))
        if key not in cache:
            data, signature = load_snapshot(path)
            entries, contents = read_archive(data, contents=True)
            cache[key] = (data, signature, entries, contents)
        return cache[key]
    for filename in filenames:
        _, _, kinds, contents = snapshot(filename)
        names = {}
        for name, (kind, _, _, raw, *_) in kinds.items():
            member = raw + ('/' if kind == stat.S_IFDIR and not raw.endswith('/') else '')
            if name.startswith('/') or '..' in Path(name).parts:
                raise ValueError('unsafe archive member')
            if (name.startswith(('etc/systemd/', 'usr/lib/systemd/', 'lib/systemd/', 'usr/local/lib/systemd/',
                                 'usr/share/systemd/', 'usr/local/share/systemd/', 'run/systemd/'))
                    and (any(p.endswith(('.wants', '.requires')) for p in Path(name).parts[:-1])
                         or (not member.endswith('/') and name.endswith(('.wants', '.requires'))))):
                raise ValueError('incoming enabled systemd unit link/path ' + name)
            names[name] = member
        metadata = dict(metadata_texts(kinds, contents))
        fields = {}
        for line in metadata.get('.PKGINFO', '').splitlines():
            if ' = ' in line:
                key, value = line.split(' = ', 1)
                fields.setdefault(key, []).append(value)
        if len(fields.get('pkgname', [])) != 1 or len(fields.get('pkgver', [])) != 1:
            raise ValueError('missing/ambiguous archive identity')
        package = fields['pkgname'][0]
        if package.startswith('omarchy') or package in packages:
            raise ValueError('forbidden/duplicate archive identity')
        archive_fields[package] = fields
        incoming_records.append({'name': package, 'version': fields['pkgver'][0],
                                 'provides': fields.get('provides', []),
                                 'replaces': fields.get('replaces', []), 'conflicts': fields.get('conflict', [])})
        operation = 'Upgrade' if package in local else 'Install'
        packages[package] = operation
        source = planned_sources.get((package, fields['pkgver'][0]))
        if plan and not source:
            raise ValueError('archive identity is not a reviewed plan row: ' + package + ' ' + fields['pkgver'][0])
        if source:
            archive_rows[package] = (source, fields['pkgver'][0], filename)
        newfiles = {name for name in names if name and not name.startswith('.')}
        package_paths = {name + ('/' if names[name].endswith('/') else '') for name in newfiles}
        if '.MTREE' in names and '.MTREE' not in contents:
            raise ValueError('opaque .MTREE requires manual review ' + package)
        event_paths = mtree_paths(contents['.MTREE']) if '.MTREE' in names else package_paths
        if event_paths != package_paths:
            raise ValueError('tar/.MTREE file inventory mismatch requires manual review ' + package)
        oldfiles = set()
        if operation == 'Upgrade':
            if not isinstance(local[package].get('files'), list):
                raise ValueError('installed file metadata unavailable for upgrade ' + package)
            oldfiles = set(local[package]['files'])
            if any(p.startswith('/') or '..' in Path(p).parts for p in oldfiles):
                raise ValueError('unsafe installed file metadata ' + package)
            backups.update(p.split('\t', 1)[0] for p in local[package].get('backup', []))
        backups.update(fields.get('backup', []))
        oldpaths.update(oldfiles)
        # Directories this upgrade's OLD version owned and its new one drops:
        # libalpm may unlink and another package's header recreate them.
        dropped_dirs.update(p.rstrip('/') for p in oldfiles if p.endswith('/') and p not in package_paths)
        physical_newpaths.update(package_paths)
        newpaths.update(event_paths)
        for name in newfiles | {p.rstrip('/') for p in oldfiles}:
            path_owners.setdefault(name, set()).add(package)
        for name in newfiles:
            if names[name].endswith('/'):
                if kinds.get(name, (None,))[0] != stat.S_IFDIR:
                    raise ValueError('archive member inventory disagrees with archive headers ' + name)
                dir_entries.setdefault(name, []).append((package, kinds[name]))
                continue
            if name in payloads:
                raise ValueError('ambiguous transaction file ownership ' + name)
            payloads[name] = (filename, names[name])
            payload_package[name] = package
            if name not in kinds:
                raise ValueError('archive member inventory disagrees with archive headers ' + name)
            payload_kinds[name] = kinds[name]
            if name.endswith('.hook'):
                if name not in metadata:
                    raise ValueError('incoming hook payload unavailable/opaque ' + name)
                # Executed/parsed text: exact UTF-8 of the snapshot bytes,
                # never a replacement-character rendering of other bytes.
                try:
                    incoming['/' + name] = contents[name].decode('utf-8', 'strict')
                except UnicodeDecodeError as error:
                    raise ValueError('incoming hook is not exact UTF-8 text ' + name) from error
        if '.INSTALL' in names and '.INSTALL' not in metadata:
            raise ValueError('package scriptlet payload unavailable/opaque ' + package)
        if '.INSTALL' in metadata:
            try:
                install_text = contents['.INSTALL'].decode('utf-8', 'strict')
            except UnicodeDecodeError as error:
                raise ValueError('package scriptlet is not exact UTF-8 text ' + package + '; manual review required') from error
            if keyring_population:
                # One exemption per bootstrap, for exactly its own keyring.
                if package != keyring_population:
                    raise ValueError('keyring population exemption cannot apply to another package')
                if package == 'blackarch-keyring':
                    keyring_population_script(install_text)
                elif package == 'oniomarchy-keyring':
                    oniomarchy_population_script(install_text)
                else:
                    raise ValueError('no reviewed population scriptlet policy for ' + package)
            else:
                scriptlets.append((package, install_text, operation))
    if plan:
        # The exact-artifact commit installs these archives: they must be
        # exactly the reviewed plan, carrying exactly the reviewed metadata.
        archived = {(name, fields['pkgver'][0]) for name, fields in archive_fields.items()}
        if archived != set(planned_sources):
            raise ValueError('archives and reviewed plan rows differ')
        repos = repositories(root, dbpath)
        for (name, version), source in planned_sources.items():
            record = next((p for p in repos.get(source, [])
                           if p.get('name') == name and p.get('version') == version), None)
            if record is None:
                raise ValueError('reviewed repository record unavailable ' + source + '/' + name)
            fields = archive_fields[name]
            for archive_key, record_key in (('depend', 'depends'), ('provides', 'provides'),
                                            ('conflict', 'conflicts'), ('replaces', 'replaces')):
                if sorted(fields.get(archive_key, [])) != sorted(record.get(record_key, []) or []):
                    raise ValueError('archive ' + archive_key + ' metadata differs from the reviewed record ' + name)
    reject_removals(incoming_records, list(local.values()))
    # Hook events use transaction-wide path sets. NoExtract suppresses only
    # incoming event membership; it does not filter the old package inventory
    # or prove that an old physical helper/hook disappears.
    effective_newpaths = {name for name in newpaths if not matches_option(name, 'NoExtract')}
    path_events = ([(name, 'Remove') for name in oldpaths - effective_newpaths]
                   + [(name, 'Install') for name in effective_newpaths - oldpaths]
                   + [(name, 'Upgrade') for name in effective_newpaths & oldpaths])
    # Inventory disappearance is not physical removal under NoUpgrade.
    removed = {name.rstrip('/') for name in oldpaths - physical_newpaths
               if not matches_option(name.rstrip('/'), 'NoUpgrade')} - payloads.keys()
    def future_ambiguous(name):
        return name in backups or matches_option(name, 'NoExtract') or matches_option(name, 'NoUpgrade')
    def guarded_chain(rel, view):
        """Every component REL reaches in VIEW, following retained links (and,
        in the future view, incoming links, minus removals)."""
        if view == 'PreTransaction':
            return walk_chain(rel, retained_link(root))
        def future_link(candidate):
            if candidate in payloads:
                return payload_kinds[candidate][1] if payload_kinds[candidate][0] == stat.S_IFLNK else None
            if candidate in removed:
                return None
            return retained_link(root)(candidate)
        return walk_chain(rel, future_link)
    # --- new directories (physical, future view) -----------------------------
    # A directory the transaction CREATES gets its authority from libalpm's
    # extraction: every explicit header's owner/mode/xattrs (order across
    # packages is not modelled, so all of them), or for an implicit parent a
    # root-owned 0777 & ~umask(>=022) directory; existing directories are never
    # re-permissioned. Keyed by the physical future path. A hand-over (an
    # existing directory an upgraded package drops while another package
    # ships an explicit header for it) may be removed and recreated with that
    # header's authority, so it counts as new.
    new_dirs = {}
    prefixes = set(dir_entries)
    for name in set(payloads) | set(dir_entries):
        prefixes.update(str(parent) for parent in Path(name).parents if str(parent) != '.')
    for prefix in sorted(prefixes):
        physical = guarded_chain(prefix, 'PostTransaction')[-1]
        handover = prefix in dropped_dirs and prefix in dir_entries
        if physical in payloads or (os.path.lexists(str(root) + '/' + physical) and not handover):
            continue
        new_dirs.setdefault(physical, []).extend(dir_entries.get(prefix, []))
    dir_owners = (0, os.geteuid()) if root else (0,)
    dir_groups = (0, os.getegid()) if root else (0,)
    def creation_safe(directory):
        """A new root-consumed directory is root-only: every explicit header
        (any source) root-owned, without group/other write and xattrs, and
        the nearest existing ancestor has no default ACL to inherit."""
        key = ('dir-ok', directory)
        if key in cache:
            return
        for package, entry in new_dirs.get(directory, []):
            if (entry[0] != stat.S_IFDIR or entry[5] not in dir_owners or entry[6] not in dir_groups
                    or entry[4] & 0o022 or entry[7] != 0):
                raise ValueError('new root-consumed directory /' + directory + ' from ' + package + ': owner '
                                 + str(entry[5]) + ':' + str(entry[6]) + ' mode ' + oct(entry[4]) + ' xattrs '
                                 + str(entry[7]) + ' is not root-only (manual review required)')
        ancestor = Path(directory).parent
        while str(ancestor) != '.' and not os.path.lexists(str(root) + '/' + str(ancestor)):
            ancestor = ancestor.parent
        if not parent_default_acl_free(Path(str(root) + '/' + str(ancestor)) / 'x'):
            raise ValueError('new root-consumed directory /' + directory + ' would inherit the default ACL of /'
                             + ('' if str(ancestor) == '.' else str(ancestor)) + ' (manual review required)')
        cache[key] = True
    # --- hardlink entries (libarchive write_disk) ----------------------------
    # A hardlink entry's linkname is resolved on disk under the root; the new
    # path then shares that inode, which receives the entry's permissions,
    # owner, xattrs and any body (truncating it). Only the makepkg form is
    # modelled: a zero-size link between two ordinary extracted payloads of
    # the same archive (never .PKGINFO/.INSTALL/.MTREE/... metadata, which
    # ALPM skips or stores in its database), to the EARLIER one, with the same
    # permissions/owner and no xattrs on either, both paths under plain
    # directories and actually extracted (no NoExtract/NoUpgrade/backup skip
    # that would leave the on-disk inode the retained one).
    def plain_ancestors(rel):
        for parent in list(Path(rel).parents)[:-1]:
            ancestor = str(parent)
            full = Path(str(root) + '/' + ancestor)
            if (ancestor in payloads or ancestor in removed or full.is_symlink()
                    or (os.path.lexists(full) and not full.is_dir())):
                return False
        return True
    for filename in filenames:
        entries = snapshot(filename)[2]
        order = {name: index for index, name in enumerate(entries)}
        for name, entry in entries.items():
            if entry[2] is None:
                continue
            target = str(Path(entry[2].removeprefix('./').rstrip('/'))) if entry[2].strip('./') else ''
            linked = entries.get(target) if target and not target.startswith('/') else None
            if (linked is None or '..' in Path(target).parts or order[target] >= order[name]
                    or payloads.get(name, (None,))[0] != filename or payloads.get(target, (None,))[0] != filename
                    or linked[0] != stat.S_IFREG or linked[2] is not None or entry[8] != 0
                    or entry[7] != 0 or linked[7] != 0 or entry[4:7] != linked[4:7]
                    or any(future_ambiguous(path) or not plain_ancestors(path) for path in (name, target))):
                raise ValueError('unsupported hardlink entry /' + name + ' -> ' + entry[2] + ' (only a zero-size link '
                                 'to an earlier identical-authority member is modelled; manual review required)')
    boundary = Path(root) if root else Path('/')
    # --- provenance: authenticated base-vendor artifacts (docs/vapt.md) ------
    # Base-vendor trust is never inferred from names, URLs or a package's own
    # MTREE. Incoming bytes: the audited archive equals the reviewed DB digest
    # for its plan row, its identity matches, and a base keyring signer signed
    # it. Retained bytes: equal to that owner's authenticated base reference.
    def vendor_repositories():
        if 'repos' not in cache:
            cache['repos'] = repositories(root, dbpath)
        return cache['repos']
    def base_source(package):
        key = ('source', package)
        if key not in cache:
            row = archive_rows.get(package)
            proven = False
            if row and BASE_VENDOR.fullmatch(row[0]):
                data, signature, _, _ = snapshot(row[2])
                proven = authenticate_snapshot(root, data, signature, row[0], package, row[1], vendor_repositories())
            cache[key] = proven
        return cache[key]
    def change_authenticated(name):
        """A payload's change is authenticated by its one archive; a removal
        only if EVERY transaction package that owned the path is a
        base-authenticated plan row (no hash-order dependent pick)."""
        owners = {payload_package[name]} if name in payloads else (path_owners.get(name) or {''})
        return all(owner in archive_rows and base_source(owner) for owner in owners)
    def cache_dirs():
        dirs = [p for line in options if line.split('=', 1)[0].strip(' \t\r\v\f') == 'CacheDir' and '=' in line
                for p in line.split('=', 1)[1].strip(' \t\r\v\f').split(' ') if p]
        return dirs or ['/var/cache/pacman/pkg/']
    missing_references = report if report is not None else {}
    def base_repositories():
        # The pre-refresh sync DB snapshot (BASE_DBPATH): what the installed
        # packages were published under before a full-upgrade refresh.
        if 'base-repos' not in cache:
            cache['base-repos'] = repositories(root, base_dbpath) if (root or base_dbpath) else vendor_repositories()
        return cache['base-repos']
    def references(owner):
        """Authenticated base references for OWNER, installed version first.
        Records come from the pre-refresh snapshot and the reviewed DB; the
        same (repository, name, version) must carry one digest in both. Each
        archive is authenticated against the DB its record came from."""
        key = ('references', owner)
        if key in cache:
            return cache[key]
        rows, seen = [], {}
        for db, repos in (('base', base_repositories()), ('reviewed', vendor_repositories())):
            for source in config:
                if not (BASE_VENDOR.fullmatch(source) and repository_safe(source, config)):
                    continue
                for record in repos.get(source, []):
                    if record.get('name') != owner:
                        continue
                    ident = (source, record.get('version'))
                    if ident in seen:
                        if (seen[ident].get('sha256sum') or '') != (record.get('sha256sum') or ''):
                            raise ValueError('repository record changed digest during refresh: ' + source + '/'
                                             + owner + ' ' + str(record.get('version')))
                        continue
                    seen[ident] = record
                    rows.append((db, source, record, repos))
        installed_version = local.get(owner, {}).get('version')
        rows.sort(key=lambda row: row[2].get('version') != installed_version)
        found, exact_found, exact_row = [], False, None
        for db, source, record, repos in rows:
            exact = record.get('version') == installed_version
            if exact and exact_row is None and re.fullmatch('[0-9a-f]{64}', record.get('sha256sum') or ''):
                exact_row = (db, source, record)
            artifact = record.get('filename') or ''
            if not re.fullmatch(r'[A-Za-z0-9@._+:-]+\.pkg\.tar\.(?:zst|xz|gz)', artifact):
                continue
            candidates = ([Path(f) for f in filenames if Path(f).name == artifact]
                          + [Path(str(root) + '/' + d.strip('/') + '/' + artifact) for d in cache_dirs()]
                          + ([Path(reference) / artifact] if reference else []))
            for candidate in candidates:
                try:
                    if candidate.is_symlink() or not candidate.is_file():
                        continue
                    data, signature, _, _ = snapshot(candidate)
                    if authenticate_snapshot(root, data, signature, source, owner, record.get('version', ''), repos):
                        found.append(candidate)
                        exact_found = exact_found or exact
                        break
                except (OSError, ValueError, subprocess.SubprocessError):
                    continue
        cache[('exact-record', owner)] = exact_row is not None
        if report is not None:
            if exact_row is not None and not exact_found:
                # Fetch the installed version's reference even when another
                # version's reference exists: only it can prove old bytes.
                missing_references[owner] = exact_row
            elif not found:
                first = next(((db, source, record) for db, source, record, _ in rows
                              if re.fullmatch('[0-9a-f]{64}', record.get('sha256sum') or '')), None)
                if first is not None:
                    missing_references[owner] = first
        cache[key] = found
        return found
    def reference_entry(archive, rel):
        return snapshot(archive)[2].get(rel)
    def reference_bytes(archive, rel):
        return snapshot(archive)[3].get(rel)
    def prove_current(rel, kind, value):
        # Exactly one installed owner, and its authenticated base reference
        # carries the same link target or byte-identical regular file.
        owners = [record for record in local.values()
                  if rel in record.get('files', []) or rel + '/' in record.get('files', [])]
        if len(owners) != 1:
            raise ValueError('runtime/stock path owner unproven /' + rel)
        owner = owners[0]['name']
        archives = references(owner)
        if report is not None and (not archives or owner in missing_references):
            return owner
        for archive in archives:
            entry = reference_entry(archive, rel)
            if entry and kind == 'link' and entry[0] == stat.S_IFLNK and entry[1] == value:
                return owners[0]['name']
            if (entry and kind == 'file' and entry[0] == stat.S_IFREG and not entry[2]
                    and reference_bytes(archive, rel) == value):
                return owners[0]['name']
        if not cache.get(('exact-record', owner)):
            raise ValueError('installed ' + owner + ' ' + str(owners[0].get('version')) + ' has no pre-refresh or reviewed '
                             'repository record; retained /' + rel + ' cannot be authenticated (manual review required)')
        raise ValueError('installed bytes not proven by an authenticated base reference /' + rel)
    def incoming_regular(rel):
        kind, hardlink = payload_kinds[rel][0], payload_kinds[rel][2]
        if kind != stat.S_IFREG or hardlink:
            raise ValueError('incoming stock/runtime payload is not a regular file /' + rel)
        contents = snapshot(payloads[rel][0])[3]
        if rel not in contents:
            raise ValueError('incoming payload unavailable in the audited snapshot /' + rel)
        return contents[rel]
    def proven_bytes(rel, view, attest=True):
        """Resolve REL hop by hop in VIEW; incoming hops/files must be base
        authenticated, and (ATTEST) retained ones base-proven. Returns
        (bytes, final path)."""
        parts, current, hops = rel.split('/'), [], 0
        while parts:
            part = parts.pop(0)
            if part in ('', '.'):
                continue
            if part == '..':
                current = current[:-1]
                continue
            candidate = '/'.join(current + [part])
            if view == 'PostTransaction' and candidate in removed:
                raise ValueError('runtime path removed by transaction /' + candidate)
            if view == 'PostTransaction' and candidate in payloads:
                if not base_source(payload_package[candidate]):
                    raise ValueError('runtime input from an unauthenticated (non-base) artifact /' + candidate)
                kind, target = payload_kinds[candidate][0], payload_kinds[candidate][1]
                if kind != stat.S_IFLNK:
                    if parts:
                        raise ValueError('runtime path ancestor is not a directory /' + candidate)
                    return incoming_regular(candidate), candidate
            else:
                full = Path(str(root) + '/' + candidate)
                if full.is_symlink():
                    target = os.readlink(full)
                    if attest:
                        prove_current(candidate, 'link', target)
                elif parts:
                    if not full.is_dir():
                        # A directory this transaction creates is accepted
                        # only if root-only (creation_safe).
                        if view != 'PostTransaction' or candidate not in new_dirs:
                            raise ValueError('runtime path unavailable /' + candidate)
                        creation_safe(candidate)
                    current.append(part)
                    continue
                else:
                    data = metadata_bytes(full)
                    if attest:
                        prove_current(candidate, 'file', data)
                    return data, candidate
            hops += 1
            if hops > 40:
                raise ValueError('runtime path symlink loop /' + rel)
            parts = target.split('/') + parts
            if target.startswith('/'):
                current = []
        raise ValueError('runtime path resolves to a directory /' + rel)
    def exists(rel, view):
        if view == 'PostTransaction':
            if rel in removed:
                return False
            if rel in payloads or rel in new_dirs:
                return True
        return os.path.lexists(str(root) + '/' + rel)
    # --- runtime inputs (SEC-STOCK-1) ----------------------------------------
    # Loader configuration, preload, cache, hwcaps, gconv and NSS inputs decide
    # which code a trusted program executes. Independent of hook relevance:
    # ldconfig/ldconfig.service or the next transaction would consume them.
    if os.path.lexists(str(root) + '/etc/ld.so.preload'):
        raise ValueError('retained /etc/ld.so.preload injects code into every program; manual review required')
    SUDO_PAM_TREES = ('etc/pam.d', 'usr/lib/pam.d', 'usr/lib/security', 'etc/security', 'etc/sudoers.d', 'usr/lib/sudo')
    SUDO_PAM_FILES = ('etc/pam.conf', 'etc/environment', 'etc/sudo.conf', 'etc/sudoers', 'usr/bin/sudo')
    def runtime_input(name):
        parts = Path(name).parts
        return (name in ('etc/ld.so.preload', 'etc/ld.so.cache', 'etc/nsswitch.conf') + SUDO_PAM_FILES
                or 'glibc-hwcaps' in parts
                or name.startswith(('usr/lib/gconv/', 'usr/lib32/gconv/')) or name in ('usr/lib/gconv', 'usr/lib32/gconv')
                or any(name == tree or name.startswith(tree + '/') for tree in SUDO_PAM_TREES))
    for name in sorted(set(payloads) | removed):
        if runtime_input(name) and not change_authenticated(name):
            raise ValueError('runtime loader/conversion input from an unauthenticated artifact /' + name)
    # SEC-HELPER-SELF: haseen runs this very module as root after the commit,
    # and later audits consume its policy files. Their logical paths as
    # invoked, every link hop and ancestor, and the physical targets (current
    # and future views) may not be replaced, redirected or removed by
    # unauthenticated bytes. Unchanged retained haseen code stays the trusted
    # baseline; byte/link-identical payloads and base-authenticated artifacts
    # are accepted. A module outside the sysroot cannot be touched.
    def authority_facts():
        if 'authority-facts' not in cache:
            cache['authority-facts'] = read_authority_facts(authority_facts_path, root)
        return cache['authority-facts']
    def guard_unchanged(rel, context):
        for view in ('PreTransaction', 'PostTransaction'):
            for path in guarded_chain(rel, view):
                if path in payloads:
                    if base_source(payload_package[path]):
                        continue
                    kind, target, hardlink, _, mode, uid, gid, xattrs = payload_kinds[path][:8]
                    full = Path(str(root) + '/' + path)
                    # "Unchanged" includes the write authority libalpm applies
                    # on extraction (owner, permissions, xattrs), not only the
                    # bytes. Existing directories are never re-permissioned
                    # by libalpm, so only file/link entries are compared.
                    info = os.lstat(full) if os.path.lexists(full) else None
                    authority = (info is not None and xattrs == 0
                                 and (uid, gid) == (info.st_uid, info.st_gid))
                    regular = kind == stat.S_IFREG
                    same = authority and (
                        (kind == stat.S_IFLNK and full.is_symlink() and os.readlink(full) == target)
                        or (regular and not hardlink and stat.S_ISREG(info.st_mode)
                            and mode == stat.S_IMODE(info.st_mode)
                            and metadata_bytes(full) == incoming_regular(path)))
                    if not same:
                        raise ValueError('unauthenticated change to ' + context + ' /' + path)
                    # Unlink-and-recreate drops retained ACLs, MAC labels and
                    # other system attributes, and a new regular file inherits
                    # its directory's default ACL: the retained authority must
                    # be plain, per complete root facts and as visible now.
                    entry_ok, parent_ok = authority_facts().get(path, (False, False))
                    if not (entry_ok and entry_attributes_clean(full)
                            and (not regular or (parent_ok and parent_default_acl_free(full)))):
                        raise ValueError('unauthenticated change to ' + context + ' /' + path + ': retained '
                                         'access/security attributes unverified or not preservable by package '
                                         'extraction (manual review required)')
                elif path in removed:
                    if not change_authenticated(path):
                        raise ValueError('unauthenticated removal of ' + context + ' /' + path)
                elif view == 'PostTransaction' and path in new_dirs:
                    creation_safe(path)
    for rel, context in guarded_paths(root):
        guard_unchanged(rel, context)
    module = str(Path(os.path.abspath(__file__)))
    prefix = str(boundary).rstrip('/') + '/'
    if module.startswith(prefix):
        # After an authenticated module redirect, stock_policy reads the
        # policy beside the future physical module.
        future = guarded_chain(module[len(prefix):], 'PostTransaction')[-1]
        guard_unchanged(str(Path(future).parent / 'files/stock-hooks.tsv'), 'haseen security policy')
    def selector_bytes(name, view):
        """A configuration/selector file in VIEW, read through its proven
        physical directory; symlinked or non-regular selectors fail closed."""
        parent = resolve_dir(str(Path(name).parent), view)
        if parent is None:
            return None
        name = parent + '/' + Path(name).name
        if view == 'PostTransaction' and name in payloads:
            if payload_kinds[name][0] != stat.S_IFREG:
                raise ValueError('unsupported non-regular runtime selector /' + name)
            return incoming_regular(name)
        if view == 'PostTransaction' and name in removed:
            return None
        full = Path(str(root) + '/' + name)
        if full.is_symlink() or (os.path.lexists(full) and not full.is_file()):
            raise ValueError('unsupported non-regular runtime selector /' + name)
        return metadata_bytes(full) if full.is_file() else None
    def conf_records(data, context):
        """ldconfig records: one per '\\n' line, '#' comments, C whitespace."""
        for record in data.split(b'\n'):
            record = record.split(b'#', 1)[0].strip(C_SPACE)
            if not record:
                continue
            if any(byte > 0x7f or byte == 0 for byte in record):
                raise ValueError('unsupported non-ASCII loader configuration in ' + context)
            yield record.decode('ascii')
    def conf_dir(record, context):
        if (not record.startswith('/') or any(c in record for c in ' \t\v\f\r=:,')
                or '..' in record.split('/') or not record.strip('/')):
            raise ValueError('unsupported loader configuration directive in ' + context + ': ' + record)
        return str(Path(record)).strip('/')
    CONF_DIRECTORIES = ('etc/ld.so.conf.d', 'usr/lib/ld.so.conf.d')
    def loader_dirs(view):
        """SEARCH: default dirs plus every directory named by ld.so.conf and
        its supported 'include <conf.d>/*.conf' fragments, in VIEW. Without an
        ld.so.conf both Arch fragment directories are assumed (more candidates).
        Any other directive (hwcap, other includes, dir=type) fails closed."""
        key = ('loader-dirs', view)
        if key in cache:
            return cache[key]
        dirs = {'usr/lib', 'usr/lib/systemd'}
        included = set()
        main = selector_bytes('etc/ld.so.conf', view)
        if main is None:
            included.update(CONF_DIRECTORIES)
        else:
            for record in conf_records(main, 'etc/ld.so.conf'):
                words = record.split()
                if words[0] == 'include':
                    pattern = record[len('include'):].strip()
                    directory = str(Path(pattern).parent).strip('/')
                    if len(words) != 2 or Path(pattern).name != '*.conf' or directory not in CONF_DIRECTORIES:
                        raise ValueError('unsupported loader configuration include ' + pattern)
                    included.add(directory)
                else:
                    dirs.add(conf_dir(record, 'etc/ld.so.conf'))
        names = set()
        for directory in sorted(included):
            names.update(directory + '/' + name for name in listing(directory, view) if name.endswith('.conf'))
        for name in sorted(names):
            data = selector_bytes(name, view)
            if data is not None:
                dirs.update(conf_dir(record, name) for record in conf_records(data, name))
        cache[key] = dirs
        return dirs
    def current_cache():
        if 'ld-cache' not in cache:
            path = Path(str(root) + '/etc/ld.so.cache')
            entries = {}
            if os.path.lexists(path):
                for key, value in ld_cache_entries(metadata_bytes(path)):
                    entries.setdefault(key, set()).add(value.lstrip('/'))
            cache['ld-cache'] = entries
        return cache['ld-cache']
    def search_tree(directory, view):
        """Physical DIR plus each DIR/glibc-hwcaps/<sub>; hops proven,
        non-dirs refused."""
        directory = resolve_dir(directory, view)
        if directory is None:
            return []
        trees = [directory]
        hwcaps = directory + '/glibc-hwcaps'
        subs = set()
        full = Path(str(root) + '/' + hwcaps)
        if full.is_symlink():
            prove_current(hwcaps, 'link', os.readlink(full))
            raise ValueError('unsupported runtime search: symlinked /' + hwcaps)
        if full.is_dir():
            for child in full.iterdir():
                if child.is_symlink() or not child.is_dir():
                    raise ValueError('unsupported runtime search entry /' + hwcaps + '/' + child.name)
                subs.add(child.name)
        if view == 'PostTransaction':
            subs.update(Path(n).parts[len(Path(hwcaps).parts)] for n in payloads
                        if n.startswith(hwcaps + '/') and len(Path(n).parts) > len(Path(hwcaps).parts) + 1)
        trees.extend(hwcaps + '/' + sub for sub in sorted(subs))
        return trees
    def resolve_dir(directory, view):
        """Physical directory for DIRECTORY in VIEW. Every symlink hop is
        proven (retained: one owner + equal base reference link; incoming:
        base-authenticated), so a followed selector/search directory is never
        silently treated as empty or as its unproven target."""
        parts, current, hops = directory.split('/'), [], 0
        while parts:
            part = parts.pop(0)
            if part in ('', '.'):
                continue
            if part == '..':
                current = current[:-1]
                continue
            candidate = '/'.join(current + [part])
            if view == 'PostTransaction' and candidate in removed:
                return None
            if view == 'PostTransaction' and candidate in payloads:
                kind, target = payload_kinds[candidate][0], payload_kinds[candidate][1]
                if kind != stat.S_IFLNK:
                    raise ValueError('runtime search/selector directory is not a directory /' + candidate)
                if not base_source(payload_package[candidate]):
                    raise ValueError('runtime search/selector directory link from an unauthenticated artifact /' + candidate)
            else:
                full = Path(str(root) + '/' + candidate)
                if not full.is_symlink():
                    if os.path.lexists(full) and not full.is_dir():
                        raise ValueError('runtime search/selector directory is not a directory /' + candidate)
                    if view == 'PostTransaction' and candidate in new_dirs:
                        creation_safe(candidate)
                    current.append(part)
                    continue
                target = os.readlink(full)
                prove_current(candidate, 'link', target)
            hops += 1
            if hops > 40:
                raise ValueError('runtime search/selector directory link loop /' + directory)
            parts = target.split('/') + parts
            if target.startswith('/'):
                current = []
        return '/'.join(current)
    def listing(directory, view):
        physical = resolve_dir(directory, view)
        if physical is None:
            return set()
        names = set()
        full = Path(str(root) + '/' + physical)
        if full.is_dir() and not full.is_symlink():
            names.update(child.name for child in full.iterdir())
        if view == 'PostTransaction':
            names = {n for n in names if physical + '/' + n not in removed}
            names.update(Path(n).name for n in payloads if str(Path(n).parent) == physical)
        return names
    def peek(rel, view):
        """Unproven read of REL in VIEW (links followed), only for class filtering."""
        parts, current, hops = rel.split('/'), [], 0
        while parts:
            part = parts.pop(0)
            if part in ('', '.'):
                continue
            if part == '..':
                current = current[:-1]
                continue
            candidate = '/'.join(current + [part])
            if view == 'PostTransaction' and candidate in payloads:
                kind, target = payload_kinds[candidate][0], payload_kinds[candidate][1]
                if kind != stat.S_IFLNK:
                    return incoming_regular(candidate) if not parts else None
            else:
                full = Path(str(root) + '/' + candidate)
                if not full.is_symlink():
                    if parts:
                        current.append(part)
                        continue
                    return metadata_bytes(full) if full.is_file() else None
                target = os.readlink(full)
            hops += 1
            if hops > 40:
                return None
            parts = target.split('/') + parts
            if target.startswith('/'):
                current = []
        return None
    def read_view(rel, view):
        if view == 'PostTransaction' and rel in payloads:
            return incoming_regular(rel) if payload_kinds[rel][0] == stat.S_IFREG else None
        full = Path(str(root) + '/' + rel)
        return metadata_bytes(full) if full.is_file() and not full.is_symlink() else None
    def retained_meta(rel):
        """Static ELF metadata of a retained file through a read-only mmap
        (only headers/dynamic data are touched); None when not indexable."""
        key = ('retained-meta', rel)
        if key not in cache:
            import mmap
            meta = None
            try:
                fd = metadata_fd(Path(str(root) + '/' + rel))
                try:
                    if os.fstat(fd).st_size >= 64:
                        with mmap.mmap(fd, 0, prot=mmap.PROT_READ) as mapped:
                            meta = elf_meta(mapped, rel)
                finally:
                    os.close(fd)
            except (OSError, ValueError):
                meta = None  # ldconfig likewise skips unreadable/invalid objects
            cache[key] = meta
        return cache[key]
    def soname_index(view, dirs):
        """SONAMEs ldconfig can index in VIEW: every retained and incoming
        lib*.so* / ld-* object in every search directory and hwcaps subdir."""
        key = ('sonames', view, tuple(sorted(dirs)))
        if key in cache:
            return cache[key]
        index = {}
        for directory in sorted(dirs):
            for tree in search_tree(directory, view):
                for name in listing(tree, view):
                    if not re.fullmatch(r'(?:lib|ld-).*\.so.*', name):
                        continue
                    rel = (resolve_dir(tree, view) or tree) + '/' + name
                    incoming = view == 'PostTransaction' and rel in payloads
                    if incoming and payload_kinds[rel][0] != stat.S_IFLNK:
                        data = read_view(rel, view)
                        meta = elf_meta(data, rel) if data is not None else None
                    elif incoming or Path(str(root) + '/' + rel).is_symlink():
                        # ldconfig follows library symlinks (incoming or
                        # retained) and indexes the target's SONAME under the
                        # alias path; reaching it proves every hop.
                        try:
                            data = peek(rel, view)
                            meta = elf_meta(data, rel) if data is not None else None
                        except (OSError, ValueError):
                            meta = None
                    elif Path(str(root) + '/' + rel).is_file():
                        meta = retained_meta(rel)
                    else:
                        meta = None
                    if meta and meta['soname']:
                        index.setdefault(meta['soname'], set()).add(rel)
        cache[key] = index
        return index
    def nss_names(view):
        data = selector_bytes('etc/nsswitch.conf', view)
        return nss_service_names(data) if data is not None else set()
    def gconv_targets(view):
        """Every module path the text registry or generated cache selects in
        VIEW (Post: current cache too, since iconvconfig runs later)."""
        targets = set()
        selectors = [GCONV_DIR + '/gconv-modules'] + sorted(
            GCONV_DIR + '/gconv-modules.d/' + name for name in listing(GCONV_DIR + '/gconv-modules.d', view)
            if name.endswith('.conf'))
        caches = [(GCONV_DIR + '/gconv-modules.cache', v) for v in
                  (('PreTransaction',) if view == 'PreTransaction' else ('PreTransaction', 'PostTransaction'))]
        for name, selector_view in [(name, view) for name in selectors] + caches:
            data = selector_bytes(name, selector_view)
            if data is None:
                continue
            if name.endswith('.cache'):
                targets |= gconv_cache_targets(data)
            else:
                targets |= gconv_registry_targets(data, name)
        return targets
    # Incoming shared objects in loader directories are parsed (never loaded);
    # a malformed or non-shared-object library there fails closed.
    for name in sorted(payloads):
        directory, base = str(Path(name).parent), Path(name).name
        hwcaps_parent = str(Path(name).parent.parent.parent) if Path(name).parent.parent.name == 'glibc-hwcaps' else None
        if ((directory in loader_dirs('PostTransaction') or hwcaps_parent in loader_dirs('PostTransaction'))
                and re.fullmatch(r'(?:lib|ld-).*\.so(?:\..*)?', base)
                and payload_kinds[name][0] == stat.S_IFREG and not base_source(payload_package[name])):
            meta = elf_meta(incoming_regular(name), name)
            if meta is not None and meta['type'] != 3:
                raise ValueError('non-shared-object ELF in a loader directory /' + name)
    runtime_roots = {'PreTransaction': set(), 'PostTransaction': set()}
    INTERPRETERS = ('/lib64/ld-linux-x86-64.so.2', '/usr/lib64/ld-linux-x86-64.so.2')
    def loader_candidates(name, extra, view):
        """Every object the loader could open for NAME in VIEW: each search
        directory (DIRS plus EXTRA, with glibc-hwcaps subtrees), ldconfig's
        SONAME index and the current ld.so.cache. No precedence is modelled."""
        if '/' in name or not name:
            raise ValueError('unsupported runtime dependency name ' + name)
        dirs = loader_dirs(view)
        found = set()
        for directory in sorted(dirs | extra):
            for tree in search_tree(directory, view):
                if exists(tree + '/' + name, view):
                    found.add(tree + '/' + name)
        found |= soname_index(view, dirs).get(name, set())
        found |= {path for path in current_cache().get(name, set()) if exists(path, view)}
        return found
    def runtime_closure(view, roots=None, attest=True):
        """All-candidate dynamic closure of the approved programs. No loader
        precedence is modelled: every same-class candidate must be proven.
        Without ATTEST retained objects are trusted as-is, but no
        unauthenticated incoming payload or removal may enter the closure."""
        roots = runtime_roots[view] if roots is None else roots
        if not roots:
            return
        def candidates(name, extra):
            return loader_candidates(name, extra, view)
        queue = [(rel, True) for rel in sorted(roots)]
        # Selected-at-runtime code: every gconv module any current or future
        # registry/cache selector names, then every NSS service library.
        deferred = sorted(path for path in gconv_targets(view) if exists(path, view))
        optional = sorted(nss_names(view))
        seen = set()
        root_class = None
        while queue or deferred or optional:
            if queue:
                rel, required = queue.pop()
            elif deferred:
                rel, required = deferred.pop(), False
            else:
                name = optional.pop()
                queue.extend((path, False) for path in sorted(candidates(name, set())))
                continue
            if rel in seen:
                continue
            seen.add(rel)
            if root_class is not None:
                # The loader skips objects of another class/machine; filter
                # those before proof (no 32-bit reference is required).
                peeked = peek(rel, view)
                peeked_meta = elf_meta(peeked, rel) if peeked is not None else None
                if peeked_meta is not None and (peeked_meta['class'], peeked_meta['machine']) != root_class:
                    continue
            data, final = proven_bytes(rel, view, attest)
            meta = elf_meta(data, final)
            if meta is None:
                raise ValueError('runtime object is not ELF /' + final)
            if root_class is None:
                root_class = (meta['class'], meta['machine'])
            if (meta['class'], meta['machine']) != root_class:
                raise ValueError('runtime object class/machine mismatch /' + final)
            if meta['interp'] is not None:
                if meta['interp'] not in INTERPRETERS:
                    raise ValueError('unsupported program interpreter ' + meta['interp'] + ' in /' + final)
                queue.append((meta['interp'].lstrip('/'), True))
            extra = set()
            if meta['rpath']:
                # glibc applies an ancestor's DT_RPATH to indirect dependency
                # searches; that inherited search state is not modelled.
                raise ValueError('DT_RPATH in reached runtime object /' + final + ' requires manual review')
            for entry in meta['runpath']:
                for directory in entry.split(':'):
                    if directory == '$ORIGIN':
                        # Exactly the object's own (proven) directory, as glibc
                        # iconv modules use; every candidate there is proven.
                        extra.add(str(Path(final).parent))
                        continue
                    # Any absolute literal directory is an extra search
                    # path for this object; its hops are proven via
                    # resolve_dir and every candidate there is proven.
                    normal = str(Path(directory)).strip('/')
                    if (not directory.startswith('/') or '$' in directory or '..' in Path(directory).parts
                            or not normal):
                        raise ValueError('unsupported runtime search path ' + directory + ' in /' + final)
                    extra.add(normal)
            for name in meta['needed']:
                found = candidates(name, extra)
                if not found:
                    raise ValueError('runtime dependency ' + name + ' unavailable for /' + final)
                queue.extend((path, True) for path in sorted(found))
            for name in meta['dlopen']:
                queue.extend((path, False) for path in sorted(candidates(name, extra)))
    # --- reviewed stock maintenance hooks (docs/vapt.md "stock hooks") ------
    # A relevant hook is trusted only when it is the reviewed basename in the
    # stock hook directory, its Exec equals the reviewed words, and the hook
    # file plus every bound program are proven against the owning package's
    # authenticated base artifact. Approved programs seed the runtime closure.
    policy = []
    def stock_bytes(rel, owner, view):
        trace = []
        resolved = observed_resolve(Path(str(root) + '/' + rel), root, trace)
        if any(path.is_symlink() for path in trace):
            raise ValueError('stock maintenance path is not canonical /' + rel)
        if view == 'PostTransaction':
            for path in trace[:-1]:
                name = str(path.relative_to(boundary))
                if name in payloads or name in removed:
                    raise ValueError('stock maintenance ancestor changed by transaction /' + rel)
            if rel in removed or future_ambiguous(rel):
                raise ValueError('stock maintenance payload removed/ambiguous /' + rel)
            if rel in payloads:
                if payload_package[rel] != owner or not base_source(owner):
                    raise ValueError('incoming stock maintenance payload lacks the authenticated base owner artifact /' + rel)
                return incoming_regular(rel)
        owners = [record for record in local.values() if rel in record.get('files', [])]
        if len(owners) != 1 or owners[0]['name'] != owner:
            raise ValueError('stock maintenance owner unproven /' + rel)
        data = metadata_bytes(resolved)
        prove_current(rel, 'file', data)
        return data
    def stock_native(rel, owner, view):
        data = stock_bytes(rel, owner, view)
        if elf_meta(data, rel) is None:
            raise ValueError('reviewed stock program is not native /' + rel)
        runtime_roots[view].add(rel)
    def stock_interpreter(executable, view):
        # The reviewed interpreter chain: /bin/sh or /bin/bash reaching the
        # bash package's native /usr/bin/bash; every link hop is proven.
        if executable not in ('/bin/sh', '/bin/bash', '/usr/bin/sh', '/usr/bin/bash'):
            raise ValueError('stock helper interpreter outside reviewed chain ' + executable)
        stock_native('usr/bin/bash', 'bash', view)
        _, final = proven_bytes(executable.lstrip('/'), view)
        if final != 'usr/bin/bash':
            raise ValueError('stock helper interpreter redirected ' + executable)
    def stock_binding(token, view):
        kind, _, value = token.partition(':')
        if kind == 'elf' and value.startswith('/') and '=' in value:
            path, owner = value.split('=', 1)
            stock_native(path.lstrip('/'), owner, view)
        elif kind == 'script' and value.startswith('/') and '=' in value and '@' in value:
            path, rest = value.split('=', 1)
            owner, digests = rest.split('@', 1)
            data = stock_bytes(path.lstrip('/'), owner, view)
            if hashlib.sha256(data).hexdigest() not in digests.split(','):
                raise ValueError('stock helper bytes are not a reviewed revision ' + path)
            header = re.fullmatch(rb'#![ \t]*(/\S+)(?:[ \t]+-[eu]+)?[ \t]*', data.partition(b'\n')[0])
            if not header:
                raise ValueError('stock helper interpreter line unreviewed ' + path)
            stock_interpreter(header[1].decode(), view)
        elif kind == 'path' and '=' in value:
            # Root commits run with PATH=/usr/bin only (pacman.sh).
            command, owner = value.split('=', 1)
            if not NAME.fullmatch(command):
                raise ValueError('malformed stock helper command binding')
            stock_native('usr/bin/' + command, owner, view)
        elif kind == 'shell':
            stock_interpreter(value, view)
        elif token == 'data:sysusers':
            # sysusers.d entries can only create/extend accounts and groups.
            for name in sorted(payloads):
                if view == 'PostTransaction' and re.fullmatch(r'(?:usr/lib|etc)/sysusers\.d/[^/]+\.conf', name):
                    for line in incoming_regular(name).decode('utf-8', 'strict').splitlines():
                        fields = line.split()
                        if fields and not fields[0].startswith('#') and fields[0] not in ('u', 'u!', 'g', 'm', 'r'):
                            raise ValueError('sysusers data outside reviewed account entries /' + name)
        else:
            raise ValueError('malformed stock hook policy binding ' + token)
    def stock_action(name, action, origin, view):
        if not policy:
            policy.append(stock_policy(root))
        entry = policy[0].get(name)
        rel = 'usr/share/libalpm/hooks/' + name
        if entry is None or origin[1] != rel or action['Exec'] != entry[1]:
            return False
        owner, words, bindings = entry
        label = activation_refusal(' '.join(words))
        if label:
            raise ValueError(label + ' in stock hook ' + name)
        stock_bytes(rel, owner, view if origin[0] == 'incoming' else 'PreTransaction')
        for token in bindings:
            stock_binding(token, view)
        return True
    checked = set()
    shell_checked = set()
    def shell_interpreter(executable):
        if executable in shell_checked:
            return
        trace = []
        resolved = observed_resolve(Path(str(root) + executable), root, trace)
        for path in trace:
            name = str(path.relative_to(Path(root) if root else Path('/')))
            if name in payloads or name in removed:
                raise ValueError('transaction changes shell interpreter path ' + executable)
        name = str(resolved.relative_to(Path(root) if root else Path('/')))
        if name not in ('bin/sh', 'bin/bash', 'bin/dash', 'bin/ash',
                        'usr/bin/sh', 'usr/bin/bash', 'usr/bin/dash', 'usr/bin/ash'):
            raise ValueError('redirected shell interpreter requires manual review ' + executable)
        if resolved.exists():
            # A canonical name alone cannot make an arbitrary script a trusted
            # interpreter. Read native format and allowed installed ownership.
            with os.fdopen(metadata_fd(resolved), 'rb') as stream:
                if stream.read(4) != b'\x7fELF':
                    raise ValueError('non-native shell interpreter requires manual review ' + executable)
            owners = [record for record in local.values()
                      if record['name'] in ('bash', 'dash')
                      and name in record.get('files', [])]
            if len(owners) != 1:
                raise ValueError('shell interpreter source ownership unavailable ' + executable)
            prove_current(name, 'file', metadata_bytes(resolved))
            runtime_roots['PreTransaction'].add(name)
            runtime_roots['PostTransaction'].add(name)
        # A missing, unchanged interpreter cannot execute anything. This also
        # lets incomplete read-only sysroot fixtures inspect the supplied script.
        shell_checked.add(executable)
    def helper(executable, when):
        if not executable.startswith('/'):
            raise ValueError('unresolved delegated helper ' + executable)
        if 'omarchy' in executable.lower():
            raise ValueError(omarchy_refusal(executable) + ': delegated helper ' + executable)
        name = executable.lstrip('/')
        if isinstance(when, tuple):
            package, phase = when
            affected = set(path_owners.get(name, ()))
            for parent in Path(name).parents:
                ancestor = str(parent)
                if ancestor in payloads or ancestor in removed:
                    affected.update(path_owners.get(ancestor, ()))
            # Package scriptlets run between commits. Without guessing libalpm's
            # sort, inspect both possible snapshots of another changed package.
            views = ('PreTransaction', 'PostTransaction') if affected - {package} else (phase,)
        else:
            views = (when,)
        for view in views:
            key = (executable, when, view)
            if key in checked:
                continue
            checked.add(key)
            archive = payloads.get(name) if view == 'PostTransaction' else None
            if view == 'PostTransaction' and (future_ambiguous(name) or name in removed):
                raise ValueError('effective helper payload ambiguous/removed ' + executable)
            if view == 'PostTransaction' and any(str(p) in payloads for p in Path(name).parents if str(p) != '.'):
                raise ValueError('incoming helper ancestor is not a directory ' + executable)
            if view == 'PostTransaction' and any(str(p) in removed for p in Path(name).parents if str(p) != '.'):
                raise ValueError('effective helper ancestor removed ' + executable)
            if archive:
                # Exactly the member bash would execute, from the audited
                # snapshot: never a pattern lookup that could match another.
                text = snapshot(archive[0])[3].get(name)
                if text is None:
                    raise ValueError('opaque helper payload requires manual review ' + executable)
            else:
                # Raw bytes as bash reads them (no universal-newline rewrite).
                text = metadata_bytes(Path(str(root) + executable), 4 * 1024 * 1024)
            if len(text) > 4 * 1024 * 1024 or not text.startswith(b'#!') or b'\0' in text:
                raise ValueError('opaque helper payload requires manual review ' + executable)
            header = text.partition(b'\n')[0].decode('utf-8', 'strict')
            # Only body-preserving shell flags are modeled. In particular -c
            # executes the filename as commands, and -s reads a different input.
            if not re.fullmatch(r'#![ \t]*/(?:usr/)?bin/(?:ba|da|a)?sh(?:[ \t]+-[eu]+)?[ \t]*', header):
                raise ValueError('opaque helper interpreter requires manual review ' + executable)
            shell_interpreter(header[2:].strip().split()[0])
            script(text.decode('utf-8', 'strict'), executable, when)
    def command(text, context, when, direct=False):
        # shlex's comment mode truncates even midword '#', unlike Bash.
        # Whole-line comments are skipped by script(); keep other hashes literal.
        words = text if direct else shlex.split(text, comments=False)
        if not words:
            return
        if direct:
            # Hook Exec is execv from /: no PATH lookup and no shell builtins.
            words = ['/' + words[0].lstrip('/'), *words[1:]]
            text = ' '.join(words)
        elif words[0] in ('echo', 'printf') and not re.search(r'[$`<>]|[;&|]', text):
            return
        label = activation_refusal(text)
        if label:
            raise ValueError(label + ' in ' + context)
        if re.search(r'[$`<>;&|\\]', text):
            raise ValueError('opaque dynamic command requires manual review ' + context)
        if not direct:
            # bash brace/glob/tilde expansion would run (or pass) a word other
            # than the audited literal: refuse unquoted expansion characters.
            flags = unquoted_expansions(text)
            if len(flags) != len(words) or any(flags):
                raise ValueError('unquoted shell expansion requires manual review ' + context)
        if not direct and words[0] in (':', 'true', 'false', 'return', 'exit'):
            return
        if words[0] in ('/bin/sh', '/bin/bash', '/usr/bin/sh', '/usr/bin/bash'):
            if len(words) < 2 or words[1].startswith('-'):
                raise ValueError('opaque interpreter invocation ' + context)
            shell_interpreter(words[0])
            helper(words[1], when)
        elif words[0].startswith('/'):
            helper(words[0], when)
        else:
            raise ValueError('opaque delegated command requires manual review ' + context + ': ' + words[0])
    def script(text, context, when, phases=None):
        function = None
        # bash ends a line only at LF, and only space/tab are blanks. Any other
        # control or whitespace character (VT, FF, CR, FS, NEL, U+2028, ...)
        # would make this split/strip differ from what bash runs: refuse.
        if any((ch < ' ' and ch not in '\t\n') or ch == '\x7f' or (ch.isspace() and ch not in ' \t\n')
               for ch in text):
            raise ValueError('unsupported control/non-shell whitespace in ' + context + '; manual review required')
        for raw in text.split('\n'):
            line = raw.strip(' \t')
            if not line or line.startswith('#'):
                continue
            definition = re.fullmatch(r'([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\)\s*\{', line)
            if definition and function is None:
                if definition[1] in ('echo', 'printf', 'true', 'false', 'return', 'exit'):
                    raise ValueError('shell builtin function override requires manual review ' + context)
                function = definition[1]
                continue
            if line == '}' and function is not None:
                function = None
                continue
            if phases is not None and function is not None and function not in phases:
                shlex.split(line, comments=False)
                # Only unquoted braces/redirections can change the function
                # structure bash parses; quoted text is literal.
                if '\\' in line or any(c in unquoted_text(line) for c in '{}<>'):
                    raise ValueError('opaque inactive scriptlet structure ' + context)
                continue
            command(line, context, when)
        if function is not None:
            raise ValueError('opaque/unclosed scriptlet function ' + context)
    for package, text, operation in scriptlets:
        phase = 'install' if operation == 'Install' else 'upgrade'
        for when, prefix in (('PreTransaction', 'pre_'), ('PostTransaction', 'post_')):
            script(text, 'package scriptlet ' + package, (package, when), {prefix + phase})
    explicit = [p for line in options if line.split('=', 1)[0].strip(' \t\r\v\f') == 'HookDir' and '=' in line
                for p in line.split('=', 1)[1].strip(' \t\r\v\f').split(' ') if p]
    hookdirs = ['/usr/share/libalpm/hooks'] + (explicit or ['/etc/pacman.d/hooks'])
    boundary = Path(root) if root else Path('/')
    def future_paths_safe(paths, context):
        for path in paths:
            name = str(path.relative_to(boundary))
            if name in payloads or name in removed:
                raise ValueError('effective hook path redirected/removed by transaction ' + context)
    def hook_directory(directory, when):
        path = Path(directory)
        if not path.is_absolute() or '..' in path.parts:
            raise ValueError('forbidden hook directory')
        if 'omarchy' in directory.lower():
            raise ValueError(omarchy_refusal(directory) + ': hook directory')
        path = Path('/' + directory.lstrip('/'))
        # Path normalizes trailing/repeated slashes and dot components;
        # observed_resolve keeps both absolute and relative aliases fixture-rooted.
        trace = []
        observed = observed_resolve(Path(str(root) + str(path)), root, trace)
        if any(not p.is_symlink() and p.exists() and not p.is_dir() for p in trace):
            raise ValueError('non-directory effective hook path ' + directory)
        if when == 'PostTransaction':
            future_paths_safe(trace, directory)
        return observed
    removed_hooks = {observed_resolve(Path(str(root) + '/' + name).parent, root) / Path(name).name
                     for name in removed if name.endswith('.hook')}
    def hook_view(when):
        hooks = {}
        # libalpm registers highest-priority basenames only after validation.
        # A malformed file is not an inert mask, even when it cannot match.
        for directory in reversed(hookdirs):
            observed = hook_directory(directory, when)
            overlay = {}
            if when == 'PostTransaction':
                for name, text in incoming.items():
                    parent = hook_directory(str(Path(name).parent), when)
                    if parent == observed:
                        if future_ambiguous(name.lstrip('/')):
                            raise ValueError('effective hook payload ambiguous ' + name)
                        basename = Path(name).name
                        if basename in overlay:
                            raise ValueError('ambiguous aliased incoming hook ' + name)
                        overlay[basename] = (text, name.lstrip('/'))
            for hook in observed.glob('*.hook'):
                if hook.name in hooks:
                    continue
                if when == 'PostTransaction' and (hook in removed_hooks or hook.name in overlay):
                    continue
                trace = []
                resolved = observed_resolve(hook, root, trace)
                if when == 'PostTransaction':
                    future_paths_safe(trace, str(hook))
                if hook.is_symlink() and os.readlink(hook) == '/dev/null':
                    text = ''
                elif resolved.is_dir():
                    continue  # libalpm ignores hook-named directories
                else:
                    text = resolved.read_bytes().decode('utf-8')
                canonical = not any(path.is_symlink() for path in trace)
                origin = ('installed', str(resolved.relative_to(boundary)) if canonical else None)
                hooks[hook.name] = parse_hook(text, str(hook)) + (origin,)
            for basename, (text, name) in overlay.items():
                if basename not in hooks:
                    hooks[basename] = parse_hook(text, directory + '/' + basename) + (('incoming', name),)
        return hooks
    for view in ('PreTransaction', 'PostTransaction'):
        for name, (triggers, action, origin) in hook_view(view).items():
            relevant = False
            for trigger in triggers:
                candidates = packages.items() if trigger['Type'] == 'Package' else path_events
                targets, operations = trigger['Target'], trigger['Operation']
                patterns_valid(targets)
                if any(op in operations and matches_patterns(item, targets) for item, op in candidates):
                    relevant = True
            if relevant and action['When'] == view and not stock_action(name, action, origin, view):
                command(action['Exec'], 'relevant hook ' + name, view, direct=True)
    # SEC-L1: libalpm runs every defined pre_/post_ install/upgrade function
    # through /bin/sh -c. That shell, its link hops and its native closure are
    # base-proven in both snapshots, whatever the function body contains.
    # Any non-exempt .INSTALL may run (libalpm greps its text for the phase).
    if scriptlets:
        for view in ('PreTransaction', 'PostTransaction'):
            if not (exists('bin/sh', view) or exists('usr/bin/sh', view) or exists('usr/bin/bash', view)):
                raise ValueError('package scriptlet needs a base-proven /bin/sh in the ' + view + ' snapshot')
            stock_interpreter('/bin/sh', view)
    # --- the root interpreter's startup layout (CPython 3.14 getpath) -------
    # haseen runs its root steps as /usr/bin/python3 -I -S. Those flags do not
    # disable getpath's layout selectors: <executable>._pth / <libpython>._pth
    # (replace sys.path and may re-enable site), pyvenv.cfg beside or above
    # the executable (home= moves the stdlib search), pybuilddir.txt (build
    # tree) and the versioned prefix landmarks searched upward from the
    # libpython and executable directories. Only the stock layout is
    # supported: any such selector in the current or future view refuses,
    # whoever supplies it (retained, base-authenticated or not), because the
    # import roots it would select are not modelled.
    def unsupported_layout(path):
        return ValueError('unsupported root Python startup layout /' + path + ': CPython would read it as a '
                          'startup selector or prefix landmark (manual review required)')
    def interpreter_layout(view):
        exe_chain = guarded_chain('usr/bin/python3', view)
        real = exe_chain[-1]
        if not exists(real, view):
            return set(), set(), None
        full = Path(str(root) + '/' + real)
        data = (incoming_regular(real) if view == 'PostTransaction' and real in payloads
                else metadata_bytes(full) if full.is_file() and not full.is_symlink() else None)
        meta = elf_meta(data, real) if data is not None else None
        if meta is None:
            raise ValueError('unmodelled root interpreter /' + real + ' (manual review required)')
        if meta['rpath'] or meta['runpath']:
            raise ValueError('unmodelled root interpreter library search path /' + real + ' (manual review required)')
        # The executable as invoked, every link hop, and the real file.
        executables = [path for path in exe_chain if re.fullmatch(r'python3[0-9.t]*', Path(path).name)]
        version = re.fullmatch(r'python(3)\.(\d+)(t?)', Path(real).name)
        libraries = set()
        for needed in meta['needed']:
            if not needed.startswith('libpython'):
                continue
            version = version or re.match(r'libpython(3)\.(\d+)(t?)\.so', needed)
            found = loader_candidates(needed, set(), view)
            if not found:
                raise ValueError('unmodelled root interpreter: no ' + needed + ' candidate (manual review required)')
            found |= {directory + '/' + needed for directory in loader_dirs(view)}
            for path in found:
                # getpath's library is the path the loader opened (dladdr).
                libraries |= {path, guarded_chain(path, view)[-1]}
        if version is None:
            raise ValueError('unmodelled root interpreter version /' + real + ' (manual review required)')
        major, minor, thread = version.groups()
        selectors = {path + '._pth' for path in executables + sorted(libraries)}
        for path in executables:
            directory = str(Path(path).parent)
            selectors |= {directory + '/pyvenv.cfg', str(Path(directory).parent) + '/pyvenv.cfg',
                          directory + '/pybuilddir.txt'}
        versioned = 'lib/python' + major + '.' + minor + thread
        names = ('lib/python' + major + minor + thread + '.zip', versioned + '/os.py', versioned + '/os.pyc',
                 versioned + '/lib-dynload')
        landmarks = set()
        for start in {str(Path(path).parent) for path in executables + sorted(libraries)}:
            directory = start
            while directory not in ('', '.'):
                if directory != 'usr':  # the real prefix: the SEC-L2 stdlib guard
                    landmarks |= {directory + '/' + name for name in names}
                directory = str(Path(directory).parent)
        if not usrmerge_lib(view):
            landmarks |= set(names)  # getpath's upward search ends at '/'
        return selectors, landmarks, (major, minor, thread)
    def usrmerge_lib(view):
        """The root /lib is exactly the usrmerge alias of usr/lib (guarded)."""
        if view == 'PostTransaction' and ('lib' in payloads or 'lib' in removed):
            return False
        full = Path(str(root) + '/lib')
        return full.is_symlink() and os.path.normpath(os.readlink(full)).lstrip('/') == 'usr/lib'
    def layout_present(path, view):
        if exists(path, view):
            return True
        return view == 'PostTransaction' and (path + '/' in physical_newpaths
                                              or any(name.startswith(path + '/') for name in payloads))
    # The stock stdlib is physical: SEC-L2 guards it by its canonical names,
    # so a link anywhere on the import roots would let other bytes stand in.
    # The prefix directories and lib-dynload must be real directories, the
    # stdlib zip (if any) a regular file, and every link inside the imported
    # stdlib must resolve within it, never outside or into site-packages
    # (which -I -S does not import, and which SEC-L2 does not guard). Links
    # that start under site-packages are not import roots and are not scanned.
    def unsupported_stdlib(path, why):
        return ValueError('unsupported root Python stdlib layout /' + path + ': ' + why + ' (manual review required)')
    retained_stdlib_links = {}
    def stdlib_links(stdlib):
        """Symlinks under the retained STDLIB (no-follow), outside site-packages."""
        if stdlib not in retained_stdlib_links:
            links, base = [], Path(str(root) + '/' + stdlib)
            if base.is_dir() and not base.is_symlink():
                for directory, dirnames, filenames in os.walk(base, followlinks=False):
                    relative = str(Path(directory).relative_to(boundary))
                    if relative == stdlib + '/site-packages':
                        dirnames[:] = []
                        continue
                    for entry in dirnames + filenames:
                        link = relative + '/' + entry
                        if link != stdlib + '/site-packages' and os.path.islink(os.path.join(directory, entry)):
                            links.append(link)
            retained_stdlib_links[stdlib] = links
        return retained_stdlib_links[stdlib]
    def stdlib_shape(version, view):
        major, minor, thread = version
        stdlib = 'usr/lib/python' + major + '.' + minor + thread
        site = stdlib + '/site-packages'
        for component in ('usr', 'usr/lib', stdlib, stdlib + '/lib-dynload'):
            full = Path(str(root) + '/' + component)
            # A dropped directory entry does not remove a non-empty directory;
            # a non-directory payload there would replace it.
            if view == 'PostTransaction' and component in payloads:
                raise unsupported_stdlib(component, 'the stdlib prefix must stay a real directory')
            if full.is_symlink() or (os.path.lexists(full) and not full.is_dir()):
                raise unsupported_stdlib(component, 'the stdlib prefix must be a real directory')
        archive = 'usr/lib/python' + major + minor + thread + '.zip'
        full = Path(str(root) + '/' + archive)
        if view == 'PostTransaction' and archive in payloads:
            if payload_kinds[archive][0] != stat.S_IFREG or payload_kinds[archive][2] is not None:
                raise unsupported_stdlib(archive, 'the stdlib zip must be a regular file')
        elif full.is_symlink() or (os.path.lexists(full) and not full.is_file()):
            if not (view == 'PostTransaction' and archive in removed):
                raise unsupported_stdlib(archive, 'the stdlib zip must be a regular file')
        links = [link for link in stdlib_links(stdlib)
                 if not (view == 'PostTransaction' and (link in removed or link in payloads))]
        if view == 'PostTransaction':
            links += [name for name in payloads if name.startswith(stdlib + '/') and name != site
                      and not name.startswith(site + '/')
                      and payload_kinds[name][0] == stat.S_IFLNK]
        for link in sorted(links):
            target = guarded_chain(link, view)[-1]
            inside = target == stdlib or target.startswith(stdlib + '/')
            if not inside or target == site or target.startswith(site + '/'):
                raise unsupported_stdlib(link, 'a stdlib link must resolve inside the imported stdlib (not to /'
                                         + target + ')')
    layouts = {view: interpreter_layout(view) for view in ('PreTransaction', 'PostTransaction')}
    # haseen's post-commit root steps run /usr/bin/python3: losing it would
    # only surface after the commit, so refuse up front.
    if layouts['PreTransaction'][2] is not None and layouts['PostTransaction'][2] is None:
        raise ValueError('transaction removes the root interpreter /usr/bin/python3 that post-commit steps run '
                         '(manual review required)')
    for view in ('PreTransaction', 'PostTransaction'):
        selectors, landmarks, version = layouts[view]
        if version is None:
            continue
        for path in sorted(selectors | landmarks):
            if layout_present(path, view):
                raise unsupported_layout(path)
        stdlib_shape(version, view)
        # A non-directory payload at an ancestor would redirect a selector.
        for path in sorted(selectors):
            for parent in Path(path).parents:
                if str(parent) in payloads:
                    raise unsupported_layout(str(parent))
    for view in ('PreTransaction', 'PostTransaction'):
        runtime_closure(view)
    # Haseen's own privileged steps after the commit (install-reason
    # bookkeeping, recovery-record clearing, cleanup) execute these programs.
    # Retained copies are the documented trust boundary (the pre-audit root
    # download already ran them); the transaction may not replace or redirect
    # them, their link hops or their libraries with unauthenticated bytes.
    # SEC-L2: root metadata runs `/usr/bin/python3 -I -S`; with the stock
    # startup layout (enforced above) its import path is exactly the stdlib
    # zip, usr/lib/python3.X and its lib-dynload (no
    # site-packages). Unauthenticated additions, replacements or removals
    # there are refused; native extension modules join the guarded closure.
    stdlib = {str(Path(p).relative_to(boundary)) for p in boundary.glob('usr/lib/python3.*') if p.is_dir()}
    stdlib |= {'/'.join(Path(n).parts[:3]) for n in payloads if re.match(r'usr/lib/python3\.\d+t?/', n)}
    # A directory-only new version tree is still a stdlib a later interpreter
    # switch would import: its new directories join the namespace.
    stdlib |= {'/'.join(Path(d).parts[:3]) for d in new_dirs if re.fullmatch(r'usr/lib/python3\.\d+t?(?:/.*)?', d)}
    extensions = set()
    def in_stdlib(name):
        directory = '/'.join(Path(name).parts[:3])
        # Only the exact site-packages component (and below) is outside the
        # -I -S import path; siblings such as site-packages-compat are stdlib.
        site = directory + '/site-packages'
        return bool((directory in stdlib and name != site and not name.startswith(site + '/'))
                    or re.fullmatch(r'usr/lib/python3\d+t?\.zip', name))
    for name in sorted(set(payloads) | removed):
        if in_stdlib(name) and not change_authenticated(name):
            raise ValueError('privileged Python import path changed by an unauthenticated artifact /' + name)
    # New directories root consumes are root-only, whoever creates them: the
    # imported stdlib, the runtime loader/conversion/PAM-sudo inputs, the hook
    # directories, each configured future loader search directory (resolved,
    # links included), and every new ancestor of those.
    # Hook directories are matched physically: every component of each hook
    # directory's future chain (retained or incoming links included).
    hook_roots = {component for directory in hookdirs
                  for component in guarded_chain(directory.strip('/'), 'PostTransaction')}
    # gconv and PAM/sudo trees are matched physically too: each root resolved
    # once through its future chain (links included); a new directory at or
    # below the physical root, or on the chain to it, is root-consumed. This
    # does not depend on payloads, present objects or runtime roots.
    runtime_chains = [guarded_chain(tree, 'PostTransaction')
                      for tree in ('usr/lib/gconv', 'usr/lib32/gconv') + SUDO_PAM_TREES]
    runtime_components = {component for chain in runtime_chains for component in chain}
    runtime_physical = {chain[-1] for chain in runtime_chains}
    def runtime_namespace(directory):
        return (runtime_input(directory) or directory in runtime_components
                or any(directory.startswith(physical + '/') for physical in runtime_physical))
    for directory in sorted(new_dirs):
        if in_stdlib(directory) or runtime_namespace(directory) or directory in hook_roots:
            for path in [directory] + [str(parent) for parent in Path(directory).parents if str(parent) in new_dirs]:
                creation_safe(path)
    if new_dirs:
        for directory in sorted(loader_dirs('PostTransaction')):
            if any(component in new_dirs for component in guarded_chain(directory.strip('/'), 'PostTransaction')):
                resolve_dir(directory, 'PostTransaction')
    for directory in sorted(stdlib):
        dynload = directory + '/lib-dynload'
        extensions |= {dynload + '/' + name for name in listing(dynload, 'PostTransaction') if name.endswith('.so')}
    # SEC-PAM1 (A3): the post-commit sudo loads PAM modules (sudo/other
    # services and their includes), sudo.conf plugins and sudoers
    # group_plugin modules, and PAM may run helper executables. The retained
    # initial configuration is the documented boundary; the transaction may
    # not change it (prefilter above) nor replace/redirect anything it
    # reaches. Unsupported or non-literal syntax fails closed.
    def pam_tokens(data, context):
        if b'\0' in data:
            raise ValueError('NUL in PAM/sudo configuration ' + context)
        text = data.decode('utf-8', 'strict').replace('\\\n', ' ')
        for line in text.split('\n'):
            line = line.split('#', 1)[0]
            tokens, index = [], 0
            while index < len(line):
                if line[index] in ' \t\v\f\r':
                    index += 1
                elif line[index] == '[':
                    stop = line.find(']', index)
                    if stop < 0:
                        raise ValueError('unterminated PAM control in ' + context)
                    tokens.append(line[index:stop + 1])
                    index = stop + 1
                else:
                    start = index
                    while index < len(line) and line[index] not in ' \t\v\f\r[':
                        index += 1
                    tokens.append(line[start:index])
            if tokens:
                yield tokens
    def literal_path(value, context, default_dir=None):
        if '$' in value or '..' in value.split('/') or not value or '\0' in value:
            raise ValueError('unsupported non-literal path ' + value + ' in ' + context)
        if value.startswith('/'):
            return value.lstrip('/')
        if default_dir is None:
            raise ValueError('unsupported relative path ' + value + ' in ' + context)
        return default_dir + '/' + value
    PAM_ENV = re.compile(rb'\b(?:LD_[A-Z_]+|GCONV_PATH|LOCPATH)\b')
    def env_file(rel, view):
        data = selector_bytes(rel, view)
        if data is not None and PAM_ENV.search(data):
            raise ValueError('PAM environment file sets loader/conversion variables /' + rel)
    def sudo_pam_graph(view):
        """(modules, guarded) reachable from the post-commit sudo in VIEW."""
        modules, guarded = set(), set()
        if selector_bytes('etc/pam.conf', view) is not None:
            raise ValueError('/etc/pam.conf PAM configuration is unsupported; manual review required')
        services, seen = ['sudo', 'other'], set()
        depth = 0
        while services:
            service = services.pop()
            if service in seen:
                continue
            seen.add(service)
            depth += 1
            if depth > 256 or not re.fullmatch(r'[A-Za-z0-9_.+-]+', service):
                raise ValueError('unsupported PAM service graph ' + service)
            # Approved all-candidate policy: every present selector file for
            # SERVICE (/etc/pam.d and vendor) is guarded; no precedence is
            # modelled, so a shadowed vendor file cannot hide a later change.
            contexts = [directory + '/' + service for directory in ('etc/pam.d', 'usr/lib/pam.d')
                        if selector_bytes(directory + '/' + service, view) is not None]
            for context, tokens in ((context, tokens) for context in contexts
                                    for tokens in pam_tokens(selector_bytes(context, view), context)):
                if tokens[0] == '@include' and len(tokens) == 2:
                    services.append(tokens[1])
                    continue
                kind = tokens[0].lstrip('-')
                if kind not in ('auth', 'account', 'password', 'session') or len(tokens) < 3:
                    raise ValueError('unsupported PAM rule in ' + context)
                if tokens[1] in ('include', 'substack'):
                    if len(tokens) != 3:
                        raise ValueError('unsupported PAM include in ' + context)
                    services.append(tokens[2])
                    continue
                if not (tokens[1] in ('required', 'requisite', 'sufficient', 'optional')
                        or tokens[1].startswith('[')):
                    raise ValueError('unsupported PAM control in ' + context)
                module = literal_path(tokens[2], context, 'usr/lib/security')
                modules.add(module)
                command = Path(module).name != 'pam_exec.so'
                for argument in tokens[3:]:
                    value = argument.split('=', 1)[1] if '=' in argument else argument
                    if value.startswith('/'):
                        guarded.add(literal_path(value, context))
                        if Path(module).name == 'pam_env.so' and argument.startswith(('conffile=', 'envfile=')):
                            env_file(literal_path(value, context), view)
                    elif not command and argument not in (
                            'debug', 'expose_authtok', 'seteuid', 'quiet', 'quiet_log', 'stdout') and not (
                            argument.startswith(('log=', 'type='))):
                        # pam_exec runs its first non-option word; only a
                        # literal absolute command is supported.
                        raise ValueError('unsupported relative pam_exec command ' + argument + ' in ' + context)
                    if not command and argument.startswith('/'):
                        command = True
        for rel in ('etc/environment', 'etc/security/pam_env.conf'):
            env_file(rel, view)
        # Helpers Linux-PAM modules execute (not DT_NEEDED).
        modules |= {rel for rel in ('usr/bin/unix_chkpwd', 'usr/bin/unix_update', 'usr/bin/pam_timestamp_check')
                    if exists(rel, view)}
        return modules, guarded
    def sudo_selectors(view):
        modules, guarded = set(), set()
        plugins = []
        data = selector_bytes('etc/sudo.conf', view)
        for tokens in (pam_tokens(data, 'etc/sudo.conf') if data is not None else ()):
            if tokens[0] == 'Plugin':
                # Plugin arguments select policy sources (sudoers_file=,
                # ldap_conf=, ...) the producer does not follow: unsupported.
                if len(tokens) != 3:
                    raise ValueError('sudo.conf Plugin arguments are unsupported; manual review required')
                plugins.append(tokens[2])
            elif tokens[0] == 'Path' and len(tokens) == 3:
                if tokens[1] == 'plugin_dir':
                    raise ValueError('sudo.conf plugin_dir override is unsupported; manual review required')
                else:
                    for value in tokens[2].split(':'):
                        rel = literal_path(value, 'etc/sudo.conf')
                        (modules if tokens[1] in ('noexec', 'intercept') else guarded).add(rel)
            elif tokens[0] in ('Set', 'Debug'):
                continue
            else:
                raise ValueError('unsupported sudo.conf directive ' + tokens[0])
        for plugin in plugins or ['sudoers.so']:
            modules.add(literal_path(plugin, 'etc/sudo.conf', 'usr/lib/sudo'))
        modules |= sudo_plugins
        return modules, guarded
    def guarded_roots(paths, view):
        """Guarded paths: no unauthenticated payload, removal or hop; ELF ones
        become roots, '#!' ones guard and root their interpreter."""
        found = set()
        for rel in sorted(paths):
            parts = rel.split('/')
            for index in range(1, len(parts) + 1):
                prefix = '/'.join(parts[:index])
                if prefix in removed:
                    if not change_authenticated(prefix):
                        raise ValueError('PAM/sudo selected path removed by an unauthenticated artifact /' + prefix)
            if not exists(rel, view):
                continue
            new_directory = view == 'PostTransaction' and rel in new_dirs
            if new_directory or (not (view == 'PostTransaction' and rel in payloads)
                                 and os.path.isdir(str(root) + '/' + rel) and not os.path.islink(str(root) + '/' + rel)):
                # Directories carry only authority, never bytes: a new one
                # must be root-only (any source), an existing one is never
                # re-permissioned; its hops are proven by resolve_dir.
                if new_directory:
                    creation_safe(rel)
                resolve_dir(rel, view)
                continue
            data, final = proven_bytes(rel, view, attest=False)
            if elf_meta(data, final) is not None:
                found.add(final)
            elif data.startswith(b'#!'):
                interpreter = data.partition(b'\n')[0][2:].strip().split(b' ')[0].decode('ascii', 'strict')
                found |= guarded_roots({literal_path(interpreter, '/' + final)}, view)
        return found
    if payloads or removed:
        sudo_roots = set()
        if exists('usr/bin/sudo', 'PostTransaction'):
            sudo_plugins = read_sudo_plugins(sudo_plugins_path, root)
            for view in ('PreTransaction', 'PostTransaction'):
                pam_modules, pam_guarded = sudo_pam_graph(view)
                sudo_modules, sudo_guarded = sudo_selectors(view)
                # Selected modules: no unauthenticated payload, removal or hop,
                # checked before absence filtering. A module missing in both
                # snapshots (optional, never installed) is simply not loaded.
                sudo_roots |= guarded_roots(pam_guarded | sudo_guarded | pam_modules | sudo_modules, 'PostTransaction')
        runtime_closure('PostTransaction', attest=False, roots={
            rel for rel in ('usr/bin/env', 'usr/bin/pacman', 'usr/bin/rm', 'usr/bin/python3', 'usr/bin/tee', 'usr/bin/sudo',
                            *sorted(extensions), *sorted(sudo_roots))
            if exists(rel, 'PostTransaction')})
    if report is None:
        print('safe')

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


def stock_policy_path():
    """The stock hook policy the audit consumes: beside the physical module."""
    return Path(__file__).resolve().parent / 'files' / 'stock-hooks.tsv'


def stock_policy(root):
    """Reviewed stock maintenance hooks; fixture sysroots may restate digests."""
    path = stock_policy_path()
    if root:
        fixture = observed_resolve(Path(str(root) + '/var/lib/haseen/vapt/stock-hooks.tsv'), root)
        if fixture.is_file():
            path = fixture
    policy = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        fields = line.split('\t')
        if len(fields) != 4 or fields[0] in policy or not NAME.fullmatch(fields[1]):
            raise ValueError('malformed stock hook policy')
        policy[fields[0]] = (fields[1], hook_words(fields[2], 'stock hook policy'), fields[3].split(' '))
    return policy


def system_python(root, compatible=False):
    records = [p for p in installed(root) if p['name'] == 'python']
    if len(records) != 1 or not allowed_local(records[0], read_config(root), repositories(root)):
        raise ValueError('system Python allowed-source version metadata unavailable')
    version = records[0].get('version', '').split(':')[-1].split('-')[0]
    match = re.match(r'^3\.(\d+)(?:\.|$)', version)
    if not match or (compatible and not 10 <= int(match[1]) < 15):
        raise ValueError('system Python outside supported version')
    interpreter = observed_resolve(Path(str(root) + '/usr/bin/python'), root)
    if interpreter != Path(str(root) + '/usr/bin/python3.' + match[1]):
        raise ValueError('system Python redirected outside package interpreter path')
    metadata_check(interpreter)
    if not os.access(interpreter, os.X_OK):
        raise ValueError('system Python interpreter unavailable')
    return interpreter, version




def metadata_fd(path, directory=False):
    """Open each component without following links, including fixture parents."""
    path = Path(path)
    if not path.is_absolute() or '..' in path.parts:
        raise ValueError('unsafe metadata path')
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for index, part in enumerate(path.parts[1:]):
            isdir = index < len(path.parts) - 2 or directory
            flags = os.O_RDONLY | os.O_NOFOLLOW | (os.O_DIRECTORY if isdir else os.O_NONBLOCK)
            child = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = child
        if not directory and not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError('nonregular metadata file')
        result, fd = fd, None
        return result
    finally:
        if fd is not None:
            os.close(fd)


def metadata_check(path, directory=False):
    os.close(metadata_fd(path, directory))


def metadata_read(path):
    with os.fdopen(metadata_fd(path), 'r', encoding='utf-8') as stream:
        text = stream.read(4 * 1024 * 1024 + 1)
        if len(text) > 4 * 1024 * 1024:
            raise ValueError('oversized metadata file ' + str(path))
        return text


def metadata_bytes(path, limit=64 * 1024 * 1024):
    with os.fdopen(metadata_fd(path), 'rb') as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError('oversized metadata file ' + str(path))
    return data


_BASE_SIGNERS = {}
_FIXTURE_NOTE = []
REJECTED_STATUS = {'BADSIG', 'ERRSIG', 'EXPSIG', 'EXPKEYSIG', 'REVKEYSIG', 'KEYREVOKED', 'KEYEXPIRED',
                   'SIGEXPIRED', 'NO_PUBKEY', 'FAILURE'}


def base_signers(root):
    """Primary fingerprints of the base vendor keyrings (archlinux, cachyos),
    minus their *-revoked lists. Fixture sysroots declare theirs explicitly."""
    if str(root) in _BASE_SIGNERS:
        return _BASE_SIGNERS[str(root)]
    signers = set()
    if root:
        path = observed_resolve(Path(str(root) + '/var/lib/haseen/vapt/fixture-base-signers'), root)
        if path.is_file():
            signers = {line.strip() for line in path.read_text().splitlines() if re.fullmatch('[A-F0-9]{40}', line.strip())}
    else:
        for name in ('archlinux', 'cachyos'):
            keyring = Path('/usr/share/pacman/keyrings/' + name + '.gpg')
            if not keyring.is_file():
                continue
            revoked = Path('/usr/share/pacman/keyrings/' + name + '-revoked')
            excluded = ({line.split()[0] for line in revoked.read_text().splitlines() if line.strip()}
                        if revoked.is_file() else set())
            with tempfile.TemporaryDirectory(prefix='haseen-vapt-gpg.') as home:
                output = subprocess.run(['gpg', '--homedir', home, '--batch', '--with-colons',
                                         '--import-options', 'show-only', '--import', str(keyring)],
                                        capture_output=True, text=True, check=True).stdout
            primary = False
            for line in output.splitlines():
                fields = line.split(':')
                if fields[0] == 'pub':
                    primary = True
                elif fields[0] == 'fpr' and primary:
                    if fields[9] not in excluded:
                        signers.add(fields[9])
                    primary = False
                elif fields[0] in ('sub', 'uid'):
                    primary = False
    _BASE_SIGNERS[str(root)] = signers
    return signers


def artifact_signer(root, data, digest, signature):
    """Primary fingerprint whose detached SIGNATURE (bytes) signs DATA (bytes),
    or ''. Both are in-memory snapshots: nothing is reopened by path."""
    if root:
        # Fixture protocol: explicit sha256->signer rows, no cryptography.
        if not _FIXTURE_NOTE:
            _FIXTURE_NOTE.append(True)
            print('conditional trust: fixture signature protocol, no cryptographic verification', file=sys.stderr)
        table = observed_resolve(Path(str(root) + '/var/lib/haseen/vapt/fixture-signatures.tsv'), root)
        rows = [line.split('\t') for line in (table.read_text().splitlines() if table.is_file() else [])]
        signers = {fields[1] for fields in rows if len(fields) == 2 and fields[0] == digest}
        return signers.pop() if len(signers) == 1 else ''
    if signature is None:
        return ''
    with tempfile.TemporaryDirectory(prefix='haseen-vapt-gpg.') as home:
        for name in ('archlinux', 'cachyos'):
            keyring = Path('/usr/share/pacman/keyrings/' + name + '.gpg')
            if keyring.is_file():
                subprocess.run(['gpg', '--homedir', home, '--batch', '--quiet', '--import', str(keyring)],
                               capture_output=True, check=True)
        detached = Path(home) / 'artifact.sig'
        detached.write_bytes(signature)
        status = subprocess.run(['gpg', '--homedir', home, '--batch', '--status-fd', '1',
                                 '--verify', str(detached), '-'],
                                input=data, capture_output=True).stdout.decode('utf-8', 'replace')
    primaries = []
    for line in status.splitlines():
        fields = line.split()
        if len(fields) < 2 or fields[0] != '[GNUPG:]':
            continue
        if fields[1] in REJECTED_STATUS:
            return ''
        if fields[1] == 'VALIDSIG' and len(fields) > 11:
            primaries.append(fields[11])
    return primaries[0] if len(primaries) == 1 else ''


def load_snapshot(path, limit=512 * 1024 * 1024):
    """(archive bytes, detached signature bytes or None), each read once
    through no-follow descriptors. All later checks use only these bytes."""
    data = metadata_bytes(Path(path), limit)
    signature = Path(str(path) + '.sig')
    sig = metadata_bytes(signature, 64 * 1024) if os.path.lexists(signature) else None
    return data, sig


def authenticate_snapshot(root, data, signature, repo, name, version, repos):
    """DATA is exactly the reviewed artifact of REPO/NAME=VERSION: DB digest,
    archive identity, and (base vendor) a base keyring signature over DATA."""
    record = next((p for p in repos.get(repo, []) if p.get('name') == name and p.get('version') == version), None)
    expected = (record or {}).get('sha256sum') or ''
    if not re.fullmatch('[0-9a-f]{64}', expected):
        return False
    digest = hashlib.sha256(data).hexdigest()
    if digest != expected or snapshot_identity(data)[0] != (name, version):
        return False
    return not BASE_VENDOR.fullmatch(repo) or artifact_signer(root, data, digest, signature) in base_signers(root)


def elf_meta(data, context):
    """Static ELF metadata (never loaded): class, machine, type, PT_INTERP,
    DT_NEEDED/SONAME/RPATH/RUNPATH and FDO dlopen notes. None for non-ELF;
    ValueError for anything truncated, out of bounds or ambiguous."""
    import struct
    if data is None or data[:4] != b'\x7fELF':
        return None
    def malformed(reason):
        return ValueError('malformed ELF (' + reason + ') /' + context)
    if len(data) < 16 or data[4] not in (1, 2) or data[5] not in (1, 2):
        raise malformed('ident')
    end = '<' if data[5] == 1 else '>'
    wide = data[4] == 2
    header = end + ('HHIQQQIHHHHHH' if wide else 'HHIIIIIHHHHHH')
    if len(data) < 16 + struct.calcsize(header):
        raise malformed('header')
    fields = struct.unpack_from(header, data, 16)
    e_type, machine, phoff, phentsize, phnum = fields[0], fields[1], fields[4], fields[8], fields[9]
    program = end + ('IIQQQQQQ' if wide else 'IIIIIIII')
    if phentsize != struct.calcsize(program) or phnum > 64 or phoff + phnum * phentsize > len(data):
        raise malformed('program headers')
    loads, dynamic, interp, notes = [], None, None, []
    for index in range(phnum):
        values = struct.unpack_from(program, data, phoff + index * phentsize)
        if wide:
            p_type, _, offset, vaddr, _, filesz = values[:6]
        else:
            p_type, offset, vaddr, _, filesz = values[:5]
        if offset + filesz > len(data):
            raise malformed('segment bounds')
        if p_type == 1:
            loads.append((vaddr, offset, filesz))
        elif p_type == 2:
            if dynamic is not None:
                raise malformed('duplicate PT_DYNAMIC')
            dynamic = (offset, filesz)
        elif p_type == 3:
            if interp is not None:
                raise malformed('duplicate PT_INTERP')
            raw = data[offset:offset + filesz]
            if not raw.endswith(b'\0') or b'\0' in raw[:-1]:
                raise malformed('PT_INTERP')
            interp = raw[:-1].decode('utf-8', 'strict')
        elif p_type == 4:
            notes.append((offset, filesz))
    def mapped(address):
        for vaddr, offset, filesz in loads:
            if vaddr <= address < vaddr + filesz:
                return offset + address - vaddr
        raise malformed('unmapped dynamic address')
    needed, soname, rpath, runpath, strtab, strsz = [], None, [], [], None, None
    tagged = []
    if dynamic is not None:
        entry = end + ('qQ' if wide else 'iI')
        size = struct.calcsize(entry)
        terminated = False
        for position in range(dynamic[0], dynamic[0] + dynamic[1] - size + 1, size):
            tag, value = struct.unpack_from(entry, data, position)
            if tag == 0:
                terminated = True
                break
            if tag == 5:
                strtab = value
            elif tag == 10:
                strsz = value
            elif tag in (1, 14, 15, 29):
                tagged.append((tag, value))
        if not terminated:
            raise malformed('unterminated dynamic section')
    if tagged:
        if strtab is None or strsz is None:
            raise malformed('dynamic strings unavailable')
        base = mapped(strtab)
        if base + strsz > len(data):
            raise malformed('string table bounds')
        table = data[base:base + strsz]
        for tag, offset in tagged:
            stop = table.find(b'\0', offset)
            if offset >= strsz or stop < 0:
                raise malformed('dynamic string bounds')
            text = table[offset:stop].decode('utf-8', 'strict')
            if tag == 1:
                needed.append(text)
            elif tag == 14:
                if soname is not None:
                    raise malformed('duplicate DT_SONAME')
                soname = text
            elif tag == 15:
                rpath.append(text)
            else:
                runpath.append(text)
    dlopen = []
    for offset, size in notes:
        position, limit = offset, offset + size
        while position + 12 <= limit:
            namesz, descsz, kind = struct.unpack_from(end + 'III', data, position)
            name_start = position + 12
            desc_start = name_start + namesz + (-namesz % 4)
            position = desc_start + descsz + (-descsz % 4)
            if position > limit:
                raise malformed('note bounds')
            if data[name_start:name_start + namesz] == b'FDO\0' and kind == 0x407c0c0a:
                try:
                    entries = json.loads(data[desc_start:desc_start + descsz].rstrip(b'\0').decode('utf-8'))
                except (ValueError, UnicodeDecodeError) as error:
                    raise malformed('dlopen note') from error
                if not isinstance(entries, list):
                    raise malformed('dlopen note')
                for item in entries:
                    names = item.get('soname') if isinstance(item, dict) else None
                    if not isinstance(names, list) or not all(isinstance(n, str) for n in names):
                        raise malformed('dlopen note')
                    dlopen.extend(names)
    return {'class': data[4], 'machine': machine, 'type': e_type, 'interp': interp, 'needed': needed,
            'soname': soname, 'rpath': rpath, 'runpath': runpath, 'dlopen': dlopen}


def ld_cache_entries(data):
    """(key, path) pairs of 64-bit x86-64 libc6 entries in a glibc-ld.so.cache1.1
    file (layout: sysdeps/generic/dl-cache.h). Any other variant fails closed."""
    import struct
    magic = b'glibc-ld.so.cache1.1'
    if not data.startswith(magic) or len(data) < 48:
        raise ValueError('unsupported /etc/ld.so.cache format; manual review required')
    nlibs, len_strings, flags = struct.unpack_from('<IIB', data, 20)
    if flags & 3 not in (0, 2) or 48 + 24 * nlibs > len(data):
        raise ValueError('unsupported/corrupt /etc/ld.so.cache')
    def string(offset):
        stop = data.find(b'\0', offset)
        if offset >= len(data) or stop < 0:
            raise ValueError('corrupt /etc/ld.so.cache string')
        return data[offset:stop].decode('utf-8', 'strict')
    entries = []
    for index in range(nlibs):
        entry_flags, key, value, _, _ = struct.unpack_from('<iIIIQ', data, 48 + 24 * index)
        if entry_flags & 0xff == 3 and entry_flags & 0xff00 == 0x0300:  # ELF libc6, x86-64
            entries.append((string(key), string(value)))
    return entries


def nonreplaceable_ancestry(path, allow_caller=False):
    """Every directory from / to PATH is a real directory owned by root (and,
    only for a fixture sysroot, by the caller) and not group/other-writable,
    except a root-owned sticky directory (/tmp): no other account can rename,
    replace or retarget a component of PATH."""
    owners = (0, os.geteuid()) if allow_caller else (0,)
    current = Path('/')
    for part in ('/',) + Path(path).parts[1:]:
        current = current / part if part != '/' else current
        info = os.lstat(current)
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise ValueError('sealed path component is not a real directory ' + str(current))
        if info.st_uid not in owners:
            raise ValueError('sealed path component owned by another account ' + str(current))
        if info.st_mode & 0o022 and not (info.st_mode & stat.S_ISVTX and info.st_uid == 0):
            raise ValueError('sealed path component replaceable by others ' + str(current))


def seal(source, destination, expected, allow_caller=False):
    """Copy SOURCE (and its .sig) into a root-only sealed directory through
    no-follow descriptors, hashing exactly the copied bytes."""
    if not re.fullmatch('[0-9a-f]{64}', expected):
        raise ValueError('reviewed artifact digest unavailable')
    destination = Path(destination)
    if not re.fullmatch(r'[A-Za-z0-9@._+:-]+\.pkg\.tar\.(?:zst|xz|gz)', destination.name):
        raise ValueError('invalid sealed artifact name')
    parent = metadata_fd(destination.parent, directory=True)
    try:
        if os.fstat(parent).st_mode & 0o022:
            raise ValueError('sealed directory writable by group/others')
        nonreplaceable_ancestry(destination.parent, allow_caller)
        def copy(source_path, name, digest):
            reader = metadata_fd(Path(source_path))
            writer, hasher = None, hashlib.sha256()
            try:
                writer = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644, dir_fd=parent)
                os.fchmod(writer, 0o644)
                while chunk := os.read(reader, 1 << 20):
                    hasher.update(chunk)
                    view = memoryview(chunk)
                    while view:
                        view = view[os.write(writer, view):]
                os.fsync(writer)
            except BaseException:
                if writer is not None:
                    os.unlink(name, dir_fd=parent)
                raise
            finally:
                os.close(reader)
                if writer is not None:
                    os.close(writer)
            if digest and hasher.hexdigest() != digest:
                os.unlink(name, dir_fd=parent)
                raise ValueError('downloaded artifact differs from the reviewed repository digest ' + name)
        copy(source, destination.name, expected)
        if os.path.lexists(str(source) + '.sig'):
            copy(str(source) + '.sig', destination.name + '.sig', None)
        os.fsync(parent)
    finally:
        os.close(parent)


GCONV_DIR = 'usr/lib/gconv'


C_SPACE = b' \t\n\v\f\r'


def c_words(record):
    """C-locale isspace tokenization of one byte record."""
    words, start = [], None
    for index, byte in enumerate(record):
        if byte in C_SPACE:
            if start is not None:
                words.append(record[start:index])
                start = None
        elif start is None:
            start = index
    if start is not None:
        words.append(record[start:])
    return words


def gconv_registry_targets(data, context):
    """Module paths a gconv text registry selects (iconv/gconv_parseconfdir.h
    and gconv_conf.c): records end at '\\n', '#' starts a comment anywhere,
    words are C-whitespace separated, keywords 'alias'/'module' are exact.
    A relative FILE joins the gconv directory and gains '.so' unless it ends
    in exactly '.so'. Absolute FILEs (whose generated-cache spelling differs),
    non-ASCII, '..' and unknown records fail closed."""
    targets = set()
    for record in data.split(b'\n'):
        record = record.split(b'#', 1)[0]
        if any(byte > 0x7f or byte == 0 for byte in record):
            raise ValueError('unsupported non-ASCII gconv registry record in ' + context)
        words = c_words(record)
        if not words:
            continue
        if words[0] == b'alias' and len(words) == 3:
            continue
        if words[0] == b'module' and len(words) in (4, 5):
            module = words[3].decode('ascii')
            if module.startswith('/') or '..' in module.split('/') or not module.strip('/'):
                raise ValueError('unsupported gconv module path in ' + context)
            if not module.endswith('.so'):
                module += '.so'
            targets.add(GCONV_DIR + '/' + module)
            continue
        raise ValueError('unsupported gconv registry record in ' + context)
    return targets


def gconv_cache_targets(data):
    """Module paths a gconv-modules.cache selects (iconv/iconvconfig.h,
    gconv_cache.c): 16-byte header (u32 magic 0x20010324, u16 string, hash,
    hash size, module, otherconv offsets); hash entries {string, module index};
    6×u16 module entries; extra lists at otherconv + extra_offset - 1 of
    {cnt, cnt×(outname index, dir, name)} ended by cnt 0. A module is the
    literal dir + name concatenation (no suffix); an empty dir is builtin.
    Every section, index and string is bounds-checked; else fail closed."""
    import struct
    if len(data) < 16:
        raise ValueError('unsupported gconv cache')
    magic, strings, hashes, hash_size, modules, other = struct.unpack_from('<IHHHHH', data, 0)
    if (magic != 0x20010324 or not 16 <= strings <= hashes <= modules <= other <= len(data)
            or hashes + 4 * hash_size > modules or (other - modules) % 12):
        raise ValueError('unsupported gconv cache')
    count = (other - modules) // 12
    def string(offset):
        start = strings + offset
        stop = data.find(b'\0', start, hashes)
        if start >= hashes or stop < 0:
            raise ValueError('unsupported gconv cache string')
        raw = data[start:stop]
        if any(byte > 0x7f for byte in raw):
            raise ValueError('unsupported non-ASCII gconv cache string')
        return raw.decode('ascii')
    for index in range(hash_size):
        name, module = struct.unpack_from('<HH', data, hashes + 4 * index)
        if name:
            string(name)
            if module >= count:
                raise ValueError('gconv cache hash entry outside the module table')
    targets = set()
    def add(directory, name):
        directory, name = string(directory), string(name)
        if directory:
            path = directory + name
            if not path.startswith('/') or '..' in path.split('/'):
                raise ValueError('unsupported gconv cache module path ' + path)
            targets.add(path.lstrip('/'))
    for index in range(count):
        canon, fromdir, fromname, todir, toname, extra = struct.unpack_from('<6H', data, modules + 12 * index)
        string(canon)
        add(fromdir, fromname)
        add(todir, toname)
        if extra:
            position = other + extra - 1
            for _ in range(65536):
                if position + 2 > len(data):
                    raise ValueError('unsupported gconv cache extra list')
                (entries,) = struct.unpack_from('<H', data, position)
                if entries == 0:
                    break
                if position + 2 + 6 * entries > len(data):
                    raise ValueError('unsupported gconv cache extra list')
                for item in range(entries):
                    outname, directory, name = struct.unpack_from('<3H', data, position + 2 + 6 * item)
                    if outname >= count:
                        raise ValueError('gconv cache extra entry outside the module table')
                    add(directory, name)
                position += 2 + 6 * entries
            else:
                raise ValueError('unsupported gconv cache extra list')
    return targets


def nss_service_names(data):
    """libnss_<service>.so.2 names nsswitch.conf can load (nss/nss_action_parse.c:
    a source runs until C whitespace or '['; [...] holds actions). 'files'
    and 'dns' are built into libc. Unsupported characters fail closed."""
    names = set()
    for record in data.split(b'\n'):
        record = record.split(b'#', 1)[0]
        if b':' not in record:
            if c_words(record):
                raise ValueError('unsupported nsswitch.conf record')
            continue
        if any(byte > 0x7f or byte == 0 for byte in record):
            raise ValueError('unsupported non-ASCII nsswitch.conf record')
        rest = record.split(b':', 1)[1]
        index = 0
        while index < len(rest):
            if rest[index] in C_SPACE:
                index += 1
                continue
            if rest[index:index + 1] == b'[':
                stop = rest.find(b']', index)
                if stop < 0:
                    raise ValueError('unterminated nsswitch.conf action')
                index = stop + 1
                continue
            start = index
            while index < len(rest) and rest[index] not in C_SPACE and rest[index:index + 1] != b'[':
                index += 1
            service = rest[start:index].decode('ascii')
            if not re.fullmatch(r'[A-Za-z0-9_-]+', service):
                raise ValueError('unsupported nsswitch.conf service ' + service)
            if service not in ('files', 'dns'):
                names.add('libnss_' + service + '.so.2')
    return names


def recovery_record(path):
    """The exact recovery protocol; anything else fails closed. The private
    oniomarchy source never joins a full upgrade, so no record names it."""
    records = {b'reviewed-full-upgrade-commit-pending\n': 'generic',
               b'reviewed-full-upgrade-commit-pending\tblackarch-staged\n': 'blackarch-staged'}
    data = metadata_bytes(Path(path), 4096)
    if data not in records:
        raise ValueError('unrecognised full-upgrade recovery record; manual review required')
    return records[data]


SUDO_INCLUDE = re.compile(r'[@#](include|includedir)\s+([^\s"\\]+)')
SUDO_INCLUDE_DIRECTIVE = re.compile(r'[@#]include(?:dir)?(?:\s|$)')
SUDO_GROUP_PLUGIN = re.compile(r'Defaults\s+group_plugin\s*=\s*"?([^"\s]+)(?:\s[^"]*)?"?\s*')
SUDO_PAM_SERVICE = re.compile(r'\bpam_(?:login_|askpass_)?service\b')


def sudo_group_plugins(root):
    """Literal group_plugin modules named by the retained sudoers (and its
    includes, depth 8), as absolute paths. Policy selection this does not
    model fails closed: sudo.conf Plugin arguments (sudoers_file=, ldap_*)
    or plugin_dir, an nsswitch sudoers source other than files, PAM service
    overrides, and include spellings other than one unquoted literal path."""
    conf = Path(str(root) + '/etc/sudo.conf')
    if conf.is_file():
        for line in metadata_bytes(conf).decode('utf-8', 'strict').splitlines():
            fields = line.split('#', 1)[0].split()
            if fields[:1] == ['Plugin'] and len(fields) != 3:
                raise ValueError('sudo.conf Plugin arguments are unsupported; manual review required')
            if fields[:2] == ['Path', 'plugin_dir']:
                raise ValueError('sudo.conf plugin_dir override is unsupported; manual review required')
    nsswitch = Path(str(root) + '/etc/nsswitch.conf')
    if nsswitch.is_file():
        for line in metadata_bytes(nsswitch).decode('utf-8', 'strict').splitlines():
            fields = line.split('#', 1)[0].split()
            if fields[:1] == ['sudoers:'] and fields[1:] != ['files']:
                raise ValueError('nsswitch sudoers source other than files is unsupported; manual review required')
    found, seen = set(), set()
    def visit(path, depth):
        if depth > 8 or '%' in path or '$' in path or '..' in path.split('/') or not path.startswith('/'):
            raise ValueError('unsupported sudoers include ' + path)
        if path in seen:
            return
        seen.add(path)
        full = Path(str(root) + path)
        if full.is_symlink() or not full.is_file():
            if path == '/etc/sudoers':
                return
            raise ValueError('unsupported sudoers include target ' + path)
        text = metadata_bytes(full).decode('utf-8', 'strict').replace('\\\n', ' ')
        for line in text.splitlines():
            stripped = line.strip()
            if SUDO_INCLUDE_DIRECTIVE.match(stripped):
                include = SUDO_INCLUDE.fullmatch(stripped)
                if not include:
                    raise ValueError('unsupported sudoers include spelling in ' + path + '; manual review required')
                target = include.group(2)
                if not target.startswith('/'):
                    target = str(Path(path).parent / target)
                if include.group(1) == 'include':
                    visit(target, depth + 1)
                else:
                    directory = Path(str(root) + target)
                    if directory.is_symlink():
                        raise ValueError('unsupported sudoers includedir ' + target)
                    if directory.is_dir():
                        for child in sorted(os.listdir(directory)):
                            # sudo skips names ending in '~' or containing '.'.
                            if '.' not in child and not child.endswith('~'):
                                visit(target.rstrip('/') + '/' + child, depth + 1)
                continue
            content = '' if stripped.startswith('#') else stripped
            if SUDO_PAM_SERVICE.search(content):
                raise ValueError('sudoers PAM service override is unsupported in ' + path + '; manual review required')
            if 'group_plugin' not in content:
                continue
            plugin = SUDO_GROUP_PLUGIN.fullmatch(stripped)
            if not plugin:
                raise ValueError('unsupported sudoers group_plugin form in ' + path)
            module = plugin.group(1)
            if '$' in module or '%' in module or '..' in module.split('/'):
                raise ValueError('unsupported sudoers group_plugin path ' + module)
            found.add(module if module.startswith('/') else '/usr/lib/sudo/' + module)
    visit('/etc/sudoers', 0)
    return found


def write_root_facts(root, out, name, data, context):
    """Root producer output: DATA as a 0644 file NAME in the existing root
    transaction stage <root>/var/cache/haseen-vapt.<id>/ only. The stage is
    never created or chmodded here; any other destination is refused."""
    expected = re.escape(str(root).rstrip('/')) + r'/var/cache/haseen-vapt\.[A-Za-z0-9]+/' + re.escape(name)
    if not out or not re.fullmatch(expected, out):
        raise ValueError(context + ' destination outside the root transaction stage')
    directory = Path(out).parent
    info = os.lstat(directory)
    owners = (0, os.geteuid()) if root else (0,)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid not in owners or info.st_mode & 0o022:
        raise ValueError('root transaction stage is not a safe directory')
    nonreplaceable_ancestry(str(directory), bool(root))
    temporary = Path(str(out) + '.new')
    if os.path.lexists(temporary):
        os.unlink(temporary)
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        os.fchmod(descriptor, 0o644)
        os.write(descriptor, data)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.replace(temporary, out)


def read_root_facts(path, root, context):
    """Text of a root-produced facts file; absent or replaceable facts refuse
    (owned by root, or by the caller only in a fixture sysroot)."""
    fixture = bool(root)
    if not path:
        raise ValueError(context + ' unavailable; manual review required')
    nonreplaceable_ancestry(str(Path(path).parent), fixture)
    info = os.lstat(path)
    owners = (0, os.geteuid()) if fixture else (0,)
    if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid not in owners
            or info.st_mode & 0o022):
        raise ValueError(context + ' are replaceable; manual review required')
    return metadata_bytes(Path(path)).decode('utf-8', 'strict')


def write_sudo_plugins(root, out):
    data = ''.join(sorted(path + '\n' for path in sudo_group_plugins(root))).encode()
    write_root_facts(root, out, 'sudo-plugins', data, 'sudoers facts')


def read_sudo_plugins(path, root):
    """Consume the root-produced group_plugin facts; absent, replaceable or
    malformed facts refuse the audit (fixture or not)."""
    plugins = set()
    for line in read_root_facts(path, root, 'sudoers group_plugin facts').splitlines():
        if (not line.startswith('/') or '$' in line or '\0' in line or '%' in line
                or '..' in line.split('/')):
            raise ValueError('invalid sudoers group_plugin fact ' + line)
        plugins.add(line.lstrip('/'))
    return plugins


def walk_chain(rel, link_of):
    """Every component path REL reaches, following link hops (LINK_OF gives a
    component's link target or None) like the kernel: '..' after a hop is
    resolved against the hop's target directory."""
    parts, current, hops, chain = rel.split('/'), [], 0, []
    while parts:
        part = parts.pop(0)
        if part in ('', '.'):
            continue
        if part == '..':
            current = current[:-1]
            continue
        candidate = '/'.join(current + [part])
        chain.append(candidate)
        target = link_of(candidate)
        if target is None:
            current.append(part)
            continue
        hops += 1
        if hops > 40:
            raise ValueError('privileged program path symlink loop /' + rel)
        parts = target.split('/') + parts
        if target.startswith('/'):
            current = []
    return chain


def retained_link(root):
    def link_of(candidate):
        full = Path(str(root) + '/' + candidate)
        return os.readlink(full) if full.is_symlink() else None
    return link_of


VENDOR_ANCHORS = tuple('usr/share/pacman/keyrings/' + name
                       for name in ('archlinux.gpg', 'archlinux-revoked', 'cachyos.gpg', 'cachyos-revoked'))


def guarded_paths(root):
    """(path, context) haseen trusts as unchanged baseline: the module it runs
    as root (as invoked, when inside the sysroot), its security policy where
    each consumer reads it (signers via the logical layer directory, stock
    hooks beside the physical module), and the base-vendor trust anchors."""
    paths = []
    boundary = Path(root) if root else Path('/')
    module = str(Path(os.path.abspath(__file__)))
    prefix = str(boundary).rstrip('/') + '/'
    if module.startswith(prefix):
        module_rel = module[len(prefix):]
        paths.append((module_rel, 'the privileged haseen program'))
        physical = walk_chain(module_rel, retained_link(root))[-1]
        for policy in sorted({str(Path(module_rel).parent / 'files/blackarch-signers.txt'),
                              str(Path(module_rel).parent / 'files/stock-hooks.tsv'),
                              str(Path(physical).parent / 'files/stock-hooks.tsv')}):
            paths.append((policy, 'haseen security policy'))
    paths.extend((anchor, 'a base-vendor trust anchor') for anchor in VENDOR_ANCHORS)
    return paths


def entry_attributes_clean(full):
    """Only ordinary user.* attributes on the entry itself (no-follow): an
    access ACL, MAC label, capability or trusted.* attribute is retained
    authority that unlink-and-recreate extraction cannot preserve."""
    try:
        names = os.listxattr(full, follow_symlinks=False)
    except OSError as error:
        return error.errno == errno.EOPNOTSUPP
    return all(name.startswith('user.') for name in names)


def parent_default_acl_free(full):
    """No default ACL a newly created regular file in FULL's directory would
    inherit (symlinks inherit none)."""
    try:
        names = os.listxattr(full.parent)
    except OSError as error:
        return error.errno == errno.EOPNOTSUPP
    return 'system.posix_acl_default' not in names


def root_sees_all_attributes():
    """euid 0 with effective CAP_SYS_ADMIN: trusted.* names are only listed to
    such a process (xattr(7)); without it the facts are incomplete."""
    if os.geteuid() != 0:
        return False
    for line in Path('/proc/self/status').read_text().splitlines():
        if line.startswith('CapEff:'):
            return bool(int(line.split()[1], 16) >> 21 & 1)
    return False


def write_authority_facts(root, out):
    """Root producer: per guarded chain element of the retained filesystem,
    whether its attributes and its directory's default ACL let an identical
    reinstall preserve the retained write authority. A fixture sysroot is the
    caller's explicit model ('fixture'), never a production substitute."""
    visibility = 'fixture' if root else ('full' if root_sees_all_attributes() else 'limited')
    rows = {}
    for rel, _ in guarded_paths(root):
        for path in walk_chain(rel, retained_link(root)):
            full = Path(str(root) + '/' + path)
            rows[path] = (entry_attributes_clean(full), parent_default_acl_free(full))
    data = '# visibility ' + visibility + '\n' + ''.join(
        path + '\t' + str(int(entry)) + '\t' + str(int(parent)) + '\n' for path, (entry, parent) in sorted(rows.items()))
    write_root_facts(root, out, 'authority-facts', data.encode(), 'authority facts')


def read_authority_facts(path, root):
    """{path: (entry-ok, parent-ok)} from complete root facts: production needs
    'full' visibility, a fixture sysroot its explicit 'fixture' model."""
    lines = read_root_facts(path, root, 'retained authority facts').splitlines()
    if not lines or lines[0] != '# visibility ' + ('fixture' if root else 'full'):
        raise ValueError('retained attributes not fully visible to root here (no CAP_SYS_ADMIN); manual review required')
    rows = {}
    for line in lines[1:]:
        fields = line.split('\t')
        if len(fields) != 3 or fields[1] not in ('0', '1') or fields[2] not in ('0', '1') or fields[0] in rows:
            raise ValueError('invalid retained authority fact ' + line)
        rows[fields[0]] = (fields[1] == '1', fields[2] == '1')
    return rows


def activate_blackarch(path):
    """Append the reviewed [blackarch] stanza to PATH (pacman.conf) atomically:
    a complete new file is written beside it and renamed over it, keeping its
    owner and mode. A failure leaves the previous file byte-identical; an
    existing [blackarch] section is never rewritten."""
    target = Path(path)
    parent = metadata_fd(target.parent, directory=True)
    temporary = None
    try:
        source = os.open(target.name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent)
        try:
            info = os.fstat(source)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                raise ValueError('pacman configuration is not a single regular file')
            old = b''
            while chunk := os.read(source, 1 << 16):
                old += chunk
        finally:
            os.close(source)
        if re.search(rb'(?m)^[ \t]*\[blackarch\][ \t]*$', old):
            return
        stanza = ('\n# haseen VAPT: signed packages, retained on layer removal\n[blackarch]\n'
                  + '\n'.join(BLACKARCH_STANZA) + '\n').encode()
        data = old + (b'' if old.endswith(b'\n') or not old else b'\n') + stanza
        temporary = '.' + target.name + '.haseen-' + os.urandom(8).hex()
        out = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=parent)
        try:
            view = memoryview(data)
            while view:
                view = view[os.write(out, view):]
            if os.geteuid() == 0:
                os.fchown(out, info.st_uid, info.st_gid)
            os.fchmod(out, stat.S_IMODE(info.st_mode))
            os.fsync(out)
        finally:
            os.close(out)
        os.replace(temporary, target.name, src_dir_fd=parent, dst_dir_fd=parent)
        temporary = None
        os.fsync(parent)
    finally:
        if temporary:
            os.unlink(temporary, dir_fd=parent)
        os.close(parent)


def metadata_children(path):
    fd = metadata_fd(path, directory=True)
    try:
        return [Path(path) / name for name in os.listdir(fd)]
    finally:
        os.close(fd)


def distribution_metadata(venv):
    matches = []
    try:
        versions = metadata_children(Path(venv) / 'lib')
    except FileNotFoundError:
        return matches
    for version in versions:
        if not re.fullmatch(r'python3\.\d+', version.name):
            continue
        metadata_check(version, directory=True)
        site = version / 'site-packages'
        try:
            infos = metadata_children(site)
        except FileNotFoundError:
            continue
        for info in infos:
            if info.name.endswith('.dist-info'):
                metadata_check(info, directory=True)
                matches.append((info, email.message_from_string(metadata_read(info / 'METADATA'))))
    return matches


def dist_state(venv, pin):
    name, wanted = pin.split('==', 1)
    try:
        matches = [msg.get('Version', '') for _, msg in distribution_metadata(venv)
                   if norm(msg.get('Name', '')) == norm(name)]
        if not matches:
            print('missing')
        elif len(matches) != 1:
            print('ambiguous')
        else:
            version = matches[0]
            print(('exact' if version == wanted or version.startswith(wanted + '+') else 'drifted') + ' ' + version)
    except (OSError, ValueError):
        print('ambiguous')


def venv_config(venv):
    return dict((k.strip(), v.strip()) for line in metadata_read(Path(venv) / 'pyvenv.cfg').splitlines()
                if '=' in line for k, v in [line.split('=', 1)])


def coae_interpreter_observe(venv, uvroot, root=''):
    """Inspect a managed interpreter chain without granting ownership."""
    venv, uvroot = Path(venv), Path(uvroot)
    metadata_check(venv, directory=True)
    metadata_check(venv / 'bin', directory=True)
    cfg = venv_config(venv)
    if not re.fullmatch(r'3\.12(?:\.\d+)?', cfg.get('version_info', cfg.get('version', ''))):
        raise ValueError('COAE requires Python 3.12 metadata')
    interpreter = observed_resolve(venv / 'bin' / 'python', root)
    relative = interpreter.relative_to(uvroot)
    if (len(relative.parts) != 3 or not re.fullmatch(r'cpython-3\.12\.\d+-linux-[a-z0-9_]+-(?:gnu|musl)', relative.parts[0])
            or relative.parts[1:] != ('bin', 'python3.12')):
        raise ValueError('COAE interpreter outside intended uv-managed Python 3.12 chain')
    metadata_check(interpreter)
    if not os.access(interpreter, os.X_OK):
        raise ValueError('managed COAE interpreter unavailable')
    if not cfg.get('home') or observed_resolve(Path(str(root) + cfg['home']), root) != interpreter.parent:
        raise ValueError('COAE base home disagrees with managed interpreter')
    for key in ('base-executable', 'executable'):
        if key in cfg and observed_resolve(Path(str(root) + cfg[key]), root) != interpreter:
            raise ValueError('COAE base executable disagrees with managed interpreter')
    return interpreter


def coae_interpreter(venv, record, uvroot, root=''):
    logical = '/' + str(Path(venv).relative_to(Path(root) if root else Path('/')))
    if metadata_read(record).strip() not in ('v1\tpending\t' + logical, 'v1\tcreated\t' + logical):
        raise ValueError('COAE interpreter lacks owned environment authority')
    return coae_interpreter_observe(venv, uvroot, root)


def native_interpreter(home, logical, spec, state_directory='', root=''):
    distribution = 'netexec' if spec.startswith('git+') else spec.split('==')[0]
    venv = Path(home) / 'venvs' / norm(distribution)
    metadata_check(venv / 'bin', directory=True)
    interpreter = observed_resolve(venv / 'bin' / 'python', root)
    cfg = venv_config(venv)
    try:
        intended, version = system_python(root, compatible=logical == 'pyrit')
    except (OSError, ValueError):
        intended, version = None, ''
    if interpreter != intended:
        if logical != 'pyrit':
            raise ValueError('native interpreter outside intended allowed-source system Python')
        data = Path(home).parent.parent.parent
        state = Path(state_directory) if state_directory else Path(str(root) + os.environ.get(
            'HASEEN_USER_STATE', str(Path(os.environ['HOME']) / '.local/state/haseen')))
        intended = coae_interpreter(data / 'htb-coae', state / 'vapt/coae.tsv', data / 'uv/python', root)
        version = '3.12'
        if interpreter != intended:
            raise ValueError('native interpreter outside owned COAE chain')
    if not cfg.get('version_info', cfg.get('version', '')).startswith('.'.join(version.split('.')[:2]) + '.'):
        raise ValueError('native interpreter version metadata disagrees with intended base')
    metadata_check(interpreter)



def native_state(home, logical, spec, probe, state_directory='', root=''):
    distribution = 'netexec' if spec.startswith('git+') else spec.split('==')[0]
    venv = Path(home) / 'venvs' / norm(distribution)
    if venv.is_symlink() or any(parent.is_symlink() for parent in venv.parents):
        print('unknown'); return
    if not venv.exists():
        print('missing'); return
    try:
        metadata = json.loads(metadata_read(venv / 'pipx_metadata.json'))
        package = metadata['main_package']
        if norm(package['package']) != norm(distribution) or package.get('package_or_url') != spec:
            print('drifted'); return
        matches = [(info, msg) for info, msg in distribution_metadata(venv)
                   if norm(msg.get('Name', '')) == norm(distribution)]
        if len(matches) != 1:
            print('unknown'); return
        info, msg = matches[0]
        if spec.startswith('git+'):
            direct = json.loads(metadata_read(info / 'direct_url.json'))
            url, commit = spec[4:].rsplit('@', 1)
            if direct.get('url', '').removesuffix('.git') != url.removesuffix('.git') or direct.get('vcs_info', {}).get('commit_id') != commit:
                print('drifted'); return
        elif msg.get('Version') != spec.split('==')[1]:
            print('drifted'); return
        executable = Path(home) / 'bin' / probe
        expected = venv / 'bin' / probe
        owner = Path(home) / 'owned' / logical
        if (not owner.is_file() or owner.is_symlink() or any(p.is_symlink() for p in owner.parents)
                or metadata_read(owner).strip() != spec):
            print('unknown'); return
        for directory in (venv / 'bin', Path(home) / 'bin'):
            if directory.is_symlink() or any(p.is_symlink() for p in directory.parents):
                print('drifted'); return
        native_interpreter(home, logical, spec, state_directory, root)
        resolved_expected = observed_resolve(expected, root)
        resolved_executable = observed_resolve(executable, root)
        if not resolved_expected.exists() or not resolved_executable.exists():
            print('missing'); return
        if (not resolved_expected.is_relative_to(venv / 'bin')
                or resolved_executable != resolved_expected or not os.access(resolved_expected, os.X_OK)):
            print('drifted'); return
        print('exact')
    except (OSError, ValueError, KeyError, TypeError):
        print('unknown')


def verify_status(status, pins):
    approved = {line.strip() for line in Path(pins).read_text().splitlines() if re.fullmatch('[A-F0-9]{40}', line.strip())}
    valid = []
    rejected = {'BADSIG', 'ERRSIG', 'EXPSIG', 'EXPKEYSIG', 'REVKEYSIG', 'KEYREVOKED', 'KEYEXPIRED', 'SIGEXPIRED', 'NO_PUBKEY', 'FAILURE'}
    for line in Path(status).read_text().splitlines():
        fields = line.split()
        if len(fields) < 2 or fields[0] != '[GNUPG:]':
            continue
        if fields[1] in rejected:
            raise ValueError('invalid signing status ' + fields[1])
        if fields[1] == 'VALIDSIG':
            if len(fields) < 11:
                raise ValueError('malformed VALIDSIG')
            primary = fields[11] if len(fields) > 11 else fields[2]
            if primary not in approved:
                raise ValueError('unapproved primary signer')
            valid.append(primary)
    if len(valid) != 1:
        raise ValueError('signature must have exactly one approved primary')
    print(valid[0])


def repair_state_dirs(paths, fixture):
    """The haseen state directories exist as real 0755 directories owned by
    root (by the caller only in a fixture sysroot) before any user-side state,
    lock or marker check: missing components are created and an existing
    directory made 0700 under a 077 umask is repaired, all through no-follow
    descriptors from /. A symlinked component, another owner or a replaceable
    ancestor is refused."""
    owners = (0, os.geteuid()) if fixture else (0,)
    for path in paths:
        parts = Path(path).parts
        if not Path(path).is_absolute() or '..' in parts or len(parts) < 2:
            raise ValueError('unsafe state directory path')
        fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
        try:
            for part in parts[1:]:
                try:
                    child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                except FileNotFoundError:
                    os.mkdir(part, 0o700, dir_fd=fd)
                    child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                    os.fchmod(child, 0o755)
                    os.fsync(fd)
                os.close(fd)
                fd = child
            info = os.fstat(fd)
            if info.st_uid not in owners:
                raise ValueError('haseen state directory owned by another account ' + path)
            if stat.S_IMODE(info.st_mode) != 0o755:
                os.fchmod(fd, 0o755)
        finally:
            os.close(fd)
        nonreplaceable_ancestry(path, fixture)


def state_path(path, operation):
    """No-follow directory descriptors keep authority writes inside their tree."""
    parts = Path(path).parts
    if not Path(path).is_absolute() or '..' in parts or len(parts) < 2:
        raise ValueError('unsafe state path')
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    temporary = None
    try:
        for part in parts[1:-1]:
            try:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except FileNotFoundError:
                if operation not in ('state-write', 'lock-prepare', 'shared-lock-prepare'):
                    return
                os.mkdir(part, 0o700, dir_fd=fd)
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                # Explicit mode, independent of sudo's inherited umask: root
                # state stays traversable for every haseen user's lock open.
                os.fchmod(child, 0o755 if os.geteuid() == 0 else 0o700)
                os.fsync(fd)
                os.close(fd)
                fd = child
                continue
            os.close(fd)
            fd = child
        name = parts[-1]
        try:
            dest = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if not stat.S_ISREG(dest.st_mode) or dest.st_nlink != 1:
                raise ValueError('state destination symlink/nonregular/hardlink conflict')
        except FileNotFoundError:
            pass
        if operation in ('lock-prepare', 'shared-lock-prepare'):
            # The shared lock is root-owned and world-readable so every haseen
            # user can flock it; nobody else can replace or write it.
            mode = 0o644 if operation == 'shared-lock-prepare' else 0o600
            lock = os.open(name, os.O_RDONLY | os.O_CREAT | os.O_NOFOLLOW, mode, dir_fd=fd)
            os.fchmod(lock, mode)
            try:
                authority = os.fstat(lock)
                if (not stat.S_ISREG(authority.st_mode) or authority.st_nlink != 1
                        or authority.st_uid != os.geteuid()):
                    raise ValueError('unsafe lifecycle lock ownership')
                os.fsync(lock)
                os.fsync(fd)
            finally:
                os.close(lock)
        if operation == 'state-clear':
            try:
                os.unlink(name, dir_fd=fd)
                os.fsync(fd)
            except FileNotFoundError:
                pass
        elif operation == 'state-write':
            temporary = '.vapt-' + os.urandom(16).hex()
            out = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                          0o644 if os.geteuid() == 0 else 0o600, dir_fd=fd)
            os.fchmod(out, 0o644 if os.geteuid() == 0 else 0o600)
            with os.fdopen(out, 'wb') as stream:
                while data := sys.stdin.buffer.read(65536):
                    stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            # Atomic replacement never follows an intervening destination link.
            try:
                dest = os.stat(name, dir_fd=fd, follow_symlinks=False)
                if not stat.S_ISREG(dest.st_mode) or dest.st_nlink != 1:
                    raise ValueError('state destination changed to a conflict')
            except FileNotFoundError:
                pass
            os.replace(temporary, name, src_dir_fd=fd, dst_dir_fd=fd)
            temporary = None
            os.fsync(fd)
    finally:
        if temporary:
            os.unlink(temporary, dir_fd=fd)
        os.close(fd)

def lock_fd(path, number, kind='user', root=''):
    fd = int(number)
    authority = metadata_fd(path)
    # The shared privileged-transaction lock belongs to root (to the sysroot
    # owner in fixtures); the per-user lifecycle lock to the caller.
    owner = (os.stat(root).st_uid if root else 0) if kind == 'shared' else os.geteuid()
    try:
        expected, actual = os.fstat(authority), os.fstat(fd)
        if ((expected.st_dev, expected.st_ino) != (actual.st_dev, actual.st_ino)
                or actual.st_nlink != 1 or actual.st_uid != owner
                or (kind == 'shared' and actual.st_mode & 0o022)):
            raise ValueError('lifecycle lock changed/redirected')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('VAPT lifecycle busy; apply/remove not performed')
        # Parent shell retains this same open-file description until its
        # lifecycle subshell exits. Never unlink/rewrite the lock inode.
    finally:
        os.close(authority)


def report_requires(path, group):
    try:
        text = metadata_read(path)
    except FileNotFoundError:
        return False
    return any(len(fields) == 8 and not fields[0].startswith('#') and group in fields[1].split(',')
               for line in text.splitlines() for fields in [line.split('\t')])


RETAINED_NOTE = re.compile(r'; source (?:not selected|[a-z-]+) this run \(oniomarchy:[a-z-]+\); installed package retained$')


def retained_private_row(old, new):
    """A later run that could not use the private source (not selected,
    declined, unavailable, unsupported architecture) keeps the earlier row of
    an item installed from it, annotated, instead of overwriting the record
    with "unavailable": the installed package is retained. A homonym that
    appeared in an earlier source (identity-rejected) or any other resolution
    replaces the row as usual."""
    if old is None or old[2] != ONIOMARCHY or old[5] not in ('installed', 'already-exact'):
        return None
    tiers = new[7].split(',')
    state = tiers[-1].split(':', 1)[1] if tiers[-1].startswith(ONIOMARCHY + ':') else ''
    if new[4] == 'resolved' or state not in ('not-selected', 'declined', 'unavailable', 'unsupported-architecture'):
        return None
    reason = RETAINED_NOTE.sub('', old[6])
    why = 'not selected' if state == 'not-selected' else state
    return old[:6] + [reason + '; source ' + why + ' this run (oniomarchy:' + state + '); installed package retained', old[7]]


def merge_report(path):
    old = metadata_read(path) if Path(path).exists() else ''
    new = sys.stdin.read()
    rows, annotations = {}, {}
    header = '# haseen-vapt-report-v1\nlogical\tselected_groups\tselected_source\ttarget\tresolution_state\tapply_state\treason\tattempted_tiers'
    for text in (old, new):
        for line in text.splitlines():
            fields = line.split('\t')
            if not fields or fields[0] == 'logical' or fields[0] == '# haseen-vapt-report-v1':
                continue
            if fields[0].startswith('#'):
                key = tuple(fields[:2]) if fields[0] in ('# infrastructure', '# dependency') else (fields[0],)
                annotations[key] = line
            elif len(fields) == 8:
                previous = rows.get(fields[0])
                if previous is not None:
                    fields[1] = ','.join(dict.fromkeys(previous[1].split(',') + fields[1].split(',')))
                    kept = retained_private_row(previous, fields)
                    if kept is not None:
                        kept[1] = fields[1]
                        fields = kept
                rows[fields[0]] = fields
            else:
                raise ValueError('malformed retained provisioning report')
    print(header)
    for fields in rows.values():
        print(*fields, sep='\t')
    for line in annotations.values():
        print(line)


# --- private oniomarchy source: trust anchor, keyring authority, canary ------
AUTHORITY_HEADER = 'haseen-vapt-oniomarchy-authority-v1'
DATABASE_HEADER = 'haseen-vapt-oniomarchy-database-v1'
FINGERPRINT = re.compile('[A-F0-9]{40}')


def pinned_signers():
    """The reviewed initial trust anchor (files/oniomarchy-signers.txt)."""
    path = Path(__file__).resolve().parent / 'files' / 'oniomarchy-signers.txt'
    pins = [line.strip() for line in path.read_text().splitlines() if line.strip() and not line.startswith('#')]
    if len(pins) != 1 or not FINGERPRINT.fullmatch(pins[0]):
        raise ValueError('oniomarchy signer pin file must hold exactly one primary fingerprint')
    return pins[0]


def oniomarchy_population_script(text):
    """Only the literal keyring population operation is accepted (it is then
    performed explicitly, never by running the scriptlet)."""
    allowed = {'post_install() {', 'post_upgrade() {', 'post_install()', 'post_upgrade()', '{', '}',
               'pacman-key --populate oniomarchy', '/usr/bin/pacman-key --populate oniomarchy'}
    lines = [' '.join(line.split()) for line in text.splitlines()]
    if len(text.encode('utf-8')) > 4096 or any(line and not line.startswith('#') and line not in allowed for line in lines):
        raise ValueError('changed/unknown oniomarchy keyring scriptlet; manual review required')


def key_primary(text):
    """The one primary of a fetched public key (gpg --with-colons show-only
    listing): exactly one primary, the reviewed pin, not revoked, expired,
    disabled or invalid. A second primary is refused, not ignored."""
    import time
    primaries, pending = [], None
    for line in text.splitlines():
        fields = line.split(':')
        if fields[0] == 'pub':
            pending = {'validity': fields[1] if len(fields) > 1 else '', 'expires': fields[6] if len(fields) > 6 else ''}
            primaries.append(pending)
        elif fields[0] == 'fpr' and pending is not None:
            pending['fpr'] = fields[9] if len(fields) > 9 else ''
            pending = None
        elif fields[0] in ('sub', 'ssb', 'sec'):
            pending = None
    if len(primaries) != 1:
        raise ValueError('fetched key must contain exactly one primary key')
    primary = primaries[0]
    if primary.get('fpr') != pinned_signers():
        raise ValueError('fetched key primary differs from the reviewed fingerprint')
    if primary['validity'] in ('r', 'e', 'i', 'd', 'n'):
        raise ValueError('fetched key is revoked, expired, disabled or invalid')
    if primary['expires'] and (not primary['expires'].isdigit() or int(primary['expires']) <= time.time()):
        raise ValueError('fetched key is expired')
    return primary['fpr']


def parse_keyring_lists(trusted, revoked):
    """Accepted and revoked primaries declared by keyring payload files."""
    def fingerprints(text, suffix):
        found = set()
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            match = re.fullmatch('([A-F0-9]{40})' + suffix, line)
            if not match:
                raise ValueError('malformed oniomarchy keyring list line')
            found.add(match[1])
        return found
    return fingerprints(trusted, '(?::[0-9]+:)?'), fingerprints(revoked, '')


def parse_authority(text):
    lines = text.split('\n')
    if lines[-1] != '':
        raise ValueError('malformed keyring authority record')
    lines = lines[:-1]
    keys = ('package', 'version', 'sha256', 'signer', 'accepted', 'revoked', 'observed')
    if len(lines) != 1 + len(keys) + len(ONIOMARCHY_KEYRING_FILES) or lines[0] != AUTHORITY_HEADER:
        raise ValueError('malformed keyring authority record')
    record = {}
    for key, line in zip(keys, lines[1:]):
        fields = line.split('\t')
        if len(fields) != 2 or fields[0] != key:
            raise ValueError('malformed keyring authority record')
        record[key] = fields[1]
    record['files'] = {}
    for path, line in zip(ONIOMARCHY_KEYRING_FILES, lines[1 + len(keys):]):
        fields = line.split('\t')
        if len(fields) != 3 or fields[:2] != ['file', path] or not re.fullmatch('[0-9a-f]{64}', fields[2]):
            raise ValueError('malformed keyring authority record')
        record['files'][path] = fields[2]
    accepted = set(record['accepted'].split(','))
    revoked = set() if record['revoked'] == '-' else set(record['revoked'].split(','))
    observed = set(record['observed'].split(','))
    if (record['package'] != 'oniomarchy-keyring' or not re.fullmatch('[0-9a-f]{64}', record['sha256'])
            or not FINGERPRINT.fullmatch(record['signer']) or not accepted
            or not all(FINGERPRINT.fullmatch(f) for f in accepted | revoked | observed) or accepted & revoked
            or pinned_signers() not in observed or record['signer'] not in observed
            or not re.fullmatch(r'[A-Za-z0-9.+:_~-]+', record['version'])):
        raise ValueError('malformed keyring authority record')
    record['accepted'], record['revoked'], record['observed'] = accepted, revoked, observed
    return record


def render_authority(record):
    lines = [AUTHORITY_HEADER, 'package\toniomarchy-keyring', 'version\t' + record['version'], 'sha256\t' + record['sha256'],
             'signer\t' + record['signer'], 'accepted\t' + ','.join(sorted(record['accepted'])),
             'revoked\t' + (','.join(sorted(record['revoked'])) or '-'),
             'observed\t' + ','.join(sorted(record['observed']))]
    lines += ['file\t' + path + '\t' + record['files'][path] for path in ONIOMARCHY_KEYRING_FILES]
    return '\n'.join(lines) + '\n'


def oniomarchy_authority(root):
    """(absent|ok|mismatch, record, reason): the retained root authority
    record must match the installed keyring package version and the bytes
    of its retained keyring files; anything else is missing proof."""
    try:
        data = oniomarchy_state_bytes(root, 'oniomarchy.authority', 64 * 1024)
    except (OSError, ValueError) as error:
        return 'mismatch', None, str(error)
    if data is None:
        return 'absent', None, 'no keyring authority recorded'
    try:
        record = parse_authority(data.decode('utf-8', 'strict'))
    except (UnicodeDecodeError, ValueError) as error:
        return 'mismatch', None, str(error)
    local = [p for p in installed(root) if p.get('name') == 'oniomarchy-keyring']
    if len(local) != 1 or local[0].get('version') != record['version']:
        return 'mismatch', None, 'installed oniomarchy-keyring differs from the recorded authority'
    contents = {}
    for path, digest in record['files'].items():
        try:
            contents[path] = metadata_bytes(Path(str(root) + '/' + path), 16 * 1024 * 1024)
        except (OSError, ValueError):
            return 'mismatch', None, 'retained keyring file unreadable or redirected: /' + path
        if hashlib.sha256(contents[path]).hexdigest() != digest:
            return 'mismatch', None, 'retained keyring file changed: /' + path
    # The record is authority only for the sets those files declare: an
    # accepted/revoked set they never declared is not proof.
    try:
        trusted, revoked = parse_keyring_lists(contents[ONIOMARCHY_KEYRING_FILES[1]].decode('ascii'),
                                               contents[ONIOMARCHY_KEYRING_FILES[2]].decode('ascii'))
    except (UnicodeDecodeError, ValueError):
        return 'mismatch', None, 'retained keyring lists malformed'
    if record['accepted'] != trusted - revoked or record['revoked'] != revoked:
        return 'mismatch', None, 'recorded accepted/revoked primaries differ from the retained keyring lists'
    return 'ok', record, 'installed keyring matches the recorded authority'


def oniomarchy_signers(root):
    """Accepted primaries for database/package verification: the authority
    record when one exists, else the reviewed pin. Missing proof refuses."""
    state, record, reason = oniomarchy_authority(root)
    if state == 'ok':
        return sorted(record['accepted'] - record['revoked'])
    if state == 'absent':
        return [pinned_signers()]
    raise ValueError('keyring authority unverified: ' + reason)


def oniomarchy_database(root):
    """(absent|verified|unverified, keyring record present): the cached
    private database and detached signature against the root record of the
    exact bytes verified at the last refresh, signed by an accepted primary."""
    try:
        db = oniomarchy_state_bytes(root, 'sync/oniomarchy.db', 64 * 1024 * 1024)
        sig = oniomarchy_state_bytes(root, 'sync/oniomarchy.db.sig', 64 * 1024)
        note = oniomarchy_state_bytes(root, 'oniomarchy.database', 4096)
    except (OSError, ValueError):
        return 'unverified', False
    if db is None:
        return 'absent', False
    if sig is None or note is None:
        return 'unverified', False
    expected = (DATABASE_HEADER + '\ndb\t' + hashlib.sha256(db).hexdigest() + '\nsig\t'
                + hashlib.sha256(sig).hexdigest() + '\nsigner\t')
    text = note.decode('utf-8', 'replace')
    try:
        accepted = oniomarchy_signers(root)
    except (OSError, ValueError):
        return 'unverified', False
    if not text.startswith(expected) or text[len(expected):].rstrip('\n') not in accepted or not text.endswith('\n'):
        return 'unverified', False
    try:
        keyring = any(r['name'] == 'oniomarchy-keyring' for r in oniomarchy_records(oniomarchy_path(root, 'sync/oniomarchy.db')))
    except (OSError, ValueError):
        return 'unverified', False
    return 'verified', keyring


def host_architecture(root):
    if root:
        path = Path(str(root) + '/var/lib/haseen/vapt/fixture-architecture')
        return path.read_text().strip() if path.is_file() else 'unknown'
    return os.uname().machine


def oniomarchy_canary(root):
    """Offline readiness of the private source from recorded evidence only:
    no network, refresh, lock or key operation. An operation that opts in
    re-verifies the live database before using it."""
    read_config(root)
    row = {'name': ONIOMARCHY, 'selected': False, 'architecture': host_architecture(root),
           'hostStanza': 'declared' if HOST_STANZAS.get(str(root)) is not None else 'absent',
           'descriptor': oniomarchy_descriptor(root)}
    row['descriptorPolicy'] = 'Required DatabaseRequired' if row['descriptor'] == 'approved' else row['descriptor']
    authority, _, authority_reason = oniomarchy_authority(root)
    row['keyringAuthorityState'] = authority
    database, keyring = oniomarchy_database(root)
    row['databaseSignatureState'] = database
    if not re.fullmatch(r'[A-Za-z0-9_.-]{1,64}', row['architecture']):
        # Never emitted raw (rows, JSON or a terminal): refused with a reason.
        row['architecture'] = 'unreadable'
        state, reason = 'unsupported-architecture', 'host architecture unreadable (tab, newline or control character); refused'
    elif row['architecture'] != 'x86_64':
        state, reason = 'unsupported-architecture', 'oniomarchy publishes x86_64 only; host is ' + row['architecture']
    elif row['hostStanza'] == 'declared':
        state, reason = 'broken', '/etc/pacman.conf declares [oniomarchy]; preserved, not adopted; the private source is refused while a global declaration exists'
    elif row['descriptor'] == 'conflict':
        state, reason = 'broken', 'private descriptor or source state changed or unsafe; preserved, not repaired'
    elif row['descriptor'] == 'absent':
        state, reason = 'absent', 'not approved (haseen vapt repo-enable oniomarchy)'
    elif authority != 'ok':
        state, reason = 'unverified', 'keyring authority ' + authority + ': ' + authority_reason
    elif database != 'verified':
        state, reason = 'unverified', 'cached database signature ' + database
    elif not keyring:
        state, reason = 'unverified', 'authenticated database has no oniomarchy-keyring record'
    else:
        state, reason = 'usable', 'cached evidence verified at the last refresh; an opted-in operation re-verifies'
    row['state'], row['reason'] = state, reason
    return row


def oniomarchy_keyring_audit(root, archive, database, signer, sudo_plugins_path, authority_facts_path, database_signer=None):
    """Audit the sealed keyring archive before any trust operation and print
    the authority record it establishes. Rotation is accepted only from a
    package signed by a currently accepted, non-revoked primary; revocations
    never roll back and a package never authorizes its own signer."""
    records = [r for r in oniomarchy_records(database) if r['name'] == 'oniomarchy-keyring']
    if len(records) != 1:
        raise ValueError('authenticated database has no single oniomarchy-keyring record')
    record = records[0]
    data = metadata_bytes(Path(archive), 64 * 1024 * 1024)
    digest = hashlib.sha256(data).hexdigest()
    if digest != record.get('sha256sum'):
        raise ValueError('keyring archive differs from the authenticated database digest')
    entries, contents = read_archive(data, contents=True)
    (name, version), fields = snapshot_identity(data)
    if (name, version) != ('oniomarchy-keyring', record.get('version')):
        raise ValueError('keyring archive identity differs from the authenticated database record')
    if fields.get('arch', []) != record.get('arch', []) or sorted(fields.get('depend', [])) != sorted(record.get('depends', [])):
        raise ValueError('keyring archive architecture/dependency metadata differs from the database')
    if fields.get('provides') or fields.get('conflict') or fields.get('replaces') or fields.get('backup'):
        raise ValueError('keyring archive declares provides/conflicts/replaces/backup; manual review required')
    directories = {'usr', 'usr/share', 'usr/share/pacman', 'usr/share/pacman/keyrings'}
    metadata = {'.PKGINFO', '.MTREE', '.BUILDINFO', '.INSTALL'}
    for member, (kind, symlink, hardlink, *_rest) in entries.items():
        if member in metadata and kind == stat.S_IFREG and hardlink is None:
            continue
        if member in directories and kind == stat.S_IFDIR:
            continue
        if member in ONIOMARCHY_KEYRING_FILES and kind == stat.S_IFREG and hardlink is None and symlink is None:
            continue
        raise ValueError('unknown oniomarchy keyring layout member ' + member + '; manual review required')
    if any(path not in contents for path in ONIOMARCHY_KEYRING_FILES):
        raise ValueError('oniomarchy keyring layout incomplete; manual review required')
    try:
        trusted, revoked = parse_keyring_lists(contents[ONIOMARCHY_KEYRING_FILES[1]].decode('ascii'),
                                               contents[ONIOMARCHY_KEYRING_FILES[2]].decode('ascii'))
    except UnicodeDecodeError as error:
        raise ValueError('malformed oniomarchy keyring list') from error
    state, previous, reason = oniomarchy_authority(root)
    if state == 'mismatch':
        raise ValueError('existing keyring authority unverified (' + reason + '); manual review required')
    pin = pinned_signers()
    previous_accepted = previous['accepted'] - previous['revoked'] if previous else {pin}
    previous_revoked = previous['revoked'] if previous else set()
    if signer not in previous_accepted:
        raise ValueError('keyring package is not signed by a currently accepted primary')
    if database_signer is not None and (not FINGERPRINT.fullmatch(database_signer) or database_signer not in previous_accepted):
        raise ValueError('database signer is not a currently accepted primary')
    if not previous_revoked <= revoked:
        raise ValueError('keyring package withdraws a recorded revocation')
    # `pacman-key --populate oniomarchy` applies the revoked list to the
    # shared keyring, so the package may revoke only keys this source has
    # actually used: the pin, earlier revocations, and observed signers (the
    # primaries whose VALIDSIG verified this source's database or keyring
    # archive, recorded across approvals). A fingerprint merely listed in a
    # trusted list, now or in any earlier archive, is never revocable: else
    # trusted={PIN,ARCH} then revoked={ARCH} would disable an unrelated key.
    observed = (previous['observed'] if previous else set()) | {pin, signer}
    if database_signer:
        observed.add(database_signer)
    recorded = oniomarchy_recorded_database_signer(root)
    if recorded:
        observed.add(recorded)
    authority = previous_revoked | observed
    foreign = revoked - authority
    if foreign:
        raise ValueError('keyring package revokes primaries this source never used (' + ','.join(sorted(foreign))
                         + '); a revocation may name only the pin, an earlier revocation or a primary that has signed '
                         + "this source's database or keyring; manual review required")
    accepted = trusted - revoked
    if not accepted:
        raise ValueError('keyring package leaves no accepted primary')
    if previous is None and pin not in accepted:
        raise ValueError('initial keyring package does not trust the reviewed primary')
    if previous is not None:
        compare = subprocess.run(['vercmp', version, previous['version']], capture_output=True, text=True, check=True)
        if int(compare.stdout.strip()) < 0:
            raise ValueError('keyring package version older than the recorded authority')
    local, seen = installed(root), set()
    config, repos = read_config(root), repositories(root)
    def check_dependency(dep):
        candidates = [r for r in local if satisfies(r, dep)]
        if not candidates:
            raise ValueError('keyring dependency not already available ' + dep)
        for candidate in candidates:
            if candidate['name'] in seen:
                continue
            seen.add(candidate['name'])
            if not allowed_local(candidate, config, repos):
                raise ValueError('unresolved retained keyring dependency source/identity ' + candidate['name'])
            for required in candidate.get('depends', []):
                check_dependency(required)
    for dep in fields.get('depend', []):
        check_dependency(dep)
    import contextlib
    import io
    with contextlib.redirect_stdout(io.StringIO()):  # its "safe" is not part of the record
        audit_archives(root, [archive], keyring_population='oniomarchy-keyring', sudo_plugins_path=sudo_plugins_path,
                       authority_facts_path=authority_facts_path)
    files = {path: hashlib.sha256(contents[path]).hexdigest() for path in ONIOMARCHY_KEYRING_FILES}
    return render_authority({'version': version, 'sha256': digest, 'signer': signer, 'accepted': accepted,
                             'revoked': revoked, 'observed': observed, 'files': files})


def oniomarchy_recorded_database_signer(root):
    """The primary recorded for the cached database when that record still
    verifies (oniomarchy_database); '' otherwise."""
    if oniomarchy_database(root)[0] != 'verified':
        return ''
    try:
        note = oniomarchy_state_bytes(root, 'oniomarchy.database', 4096).decode('ascii')
    except (OSError, ValueError, UnicodeDecodeError, AttributeError):
        return ''
    signer = note.rstrip('\n').rsplit('\nsigner\t', 1)[-1]
    return signer if FINGERPRINT.fullmatch(signer) else ''


def oniomarchy_status(root, as_json):
    row = oniomarchy_canary(root)
    if as_json:
        keys = ('name', 'selected', 'state', 'architecture', 'descriptorPolicy', 'databaseSignatureState',
                'keyringAuthorityState', 'reason')
        print(json.dumps({'schemaVersion': 1, 'repositories': [{key: row[key] for key in keys}]}, sort_keys=False))
        return
    for key in ('state', 'architecture', 'hostStanza', 'descriptor', 'descriptorPolicy', 'databaseSignatureState',
                'keyringAuthorityState', 'reason'):
        print(key, row[key], sep='\t')



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['snapshot', 'config', 'closure', 'native', 'native-interpreter', 'native-link', 'interpreter', 'coae-interpreter', 'coae-interpreter-observe', 'dist-state', 'includes', 'verify', 'discover', 'keyring', 'audit', 'reference-missing', 'artifact-digest', 'seal', 'sealed-safe', 'activate-blackarch', 'activation-preflight', 'sudo-plugins', 'authority-facts', 'state-repair', 'recovery-record', 'installed', 'absent', 'blackarch-stanza', 'state-read', 'state-safe', 'state-write', 'state-clear', 'lock-prepare', 'shared-lock-prepare', 'lock-fd', 'report-requires', 'report-merge', 'cache-permissions',
                                             'oniomarchy-status', 'oniomarchy-signers', 'oniomarchy-keyring', 'oniomarchy-approve', 'oniomarchy-withdraw', 'key-primary', 'file-digest', 'install-reason'])
    parser.add_argument('args', nargs='*')
    parser.add_argument('--root', default='')
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--dbpath')
    parser.add_argument('--frozen')
    parser.add_argument('--local', action='store_true')
    parser.add_argument('--plan')
    parser.add_argument('--with-blackarch', action='store_true')
    parser.add_argument('--reference')
    parser.add_argument('--sudo-plugins')
    parser.add_argument('--authority-facts')
    parser.add_argument('--base-dbpath')
    parser.add_argument('--out')
    parser.add_argument('--with-oniomarchy', action='store_true')
    parser.add_argument('--db')
    parser.add_argument('--signer')
    parser.add_argument('--db-signer')
    parser.add_argument('--json', action='store_true')
    options = parser.parse_args()
    args = options.args
    global WITH_BLACKARCH, WITH_ONIOMARCHY
    WITH_BLACKARCH = options.with_blackarch
    WITH_ONIOMARCHY = options.with_oniomarchy
    try:
        if options.operation == 'snapshot': emit_snapshot(options.root, options.offline)
        elif options.operation == 'oniomarchy-status': oniomarchy_status(options.root, options.json)
        elif options.operation == 'oniomarchy-signers': print('\n'.join(oniomarchy_signers(options.root)))
        elif options.operation == 'key-primary': print(key_primary(metadata_bytes(Path(args[0]), 1024 * 1024).decode('utf-8', 'replace')))
        elif options.operation == 'file-digest': print(hashlib.sha256(metadata_bytes(Path(args[0]), 512 * 1024 * 1024)).hexdigest())
        elif options.operation == 'install-reason':
            match = [r for r in installed(options.root) if r.get('name') == args[0]]
            reason = (match[0].get('reason') if match else None)
            # libalpm desc: %REASON% 1 marks a dependency; fixtures name it.
            print('absent' if not match else 'depend' if reason in ('depend', ['1']) else 'explicit')
        elif options.operation == 'oniomarchy-keyring':
            print(oniomarchy_keyring_audit(options.root, args[0], options.db, options.signer, options.sudo_plugins,
                                           options.authority_facts, database_signer=options.db_signer), end='')
        elif options.operation in ('oniomarchy-approve', 'oniomarchy-withdraw'):
            # Root-only: exactly the canonical private descriptor (fixture: under --root).
            canonical = options.root.rstrip('/') + ONIOMARCHY_STATE + '/oniomarchy.conf'
            if args != [canonical]:
                raise ValueError('private descriptor path is not the canonical ' + ONIOMARCHY_STATE + '/oniomarchy.conf')
            current = oniomarchy_descriptor(options.root)
            if options.operation == 'oniomarchy-approve':
                if current == 'conflict':
                    raise ValueError('existing private descriptor differs; preserved, not replaced')
                if current == 'absent':
                    import io
                    # The descriptor bytes come from this module, never stdin.
                    sys.stdin = io.TextIOWrapper(io.BytesIO(ONIOMARCHY_DESCRIPTOR))
                    state_path(canonical, 'state-write')
            else:
                if current == 'conflict':
                    raise ValueError('private descriptor changed or foreign; preserved, not removed')
                if current == 'approved':
                    state_path(canonical, 'state-clear')
        elif options.operation == 'config':
            if options.frozen and not re.fullmatch(r'/var/cache/haseen-vapt\.[A-Za-z0-9]+/reviewed', options.frozen):
                raise ValueError('unexpected reviewed mirror path')
            if options.frozen and options.local:
                raise ValueError('frozen and local commit configurations are exclusive')
            render_config(options.root, options.frozen, options.local)
        elif options.operation == 'blackarch-stanza':
            print('\n# haseen VAPT: signed packages, retained on layer removal\n[blackarch]\n' + '\n'.join(BLACKARCH_STANZA))
        elif options.operation == 'state-read':
            # No-follow, regular-file read of a durable recovery record.
            print(metadata_read(Path(args[0])), end='')
        elif options.operation == 'closure': closure(options.root, *args, dbpath=options.dbpath)
        elif options.operation == 'native': native_state(*args, root=options.root)
        elif options.operation == 'native-interpreter': native_interpreter(*args, root=options.root)
        elif options.operation == 'native-link':
            expected = Path(args[1])
            resolved = observed_resolve(expected, options.root)
            if (not resolved.is_relative_to(expected.parent) or not resolved.is_file()
                    or observed_resolve(Path(args[0]), options.root) != resolved):
                raise ValueError('redirected native executable')
        elif options.operation == 'includes':
            path = observed_resolve(Path(str(options.root) + args[0]), options.root)
            if not path.is_file() or not any(include in path.read_text() for include in args[1:]):
                return 1
        elif options.operation == 'interpreter': print(system_python(options.root, compatible=args != ['any'])[1])
        elif options.operation == 'coae-interpreter': coae_interpreter(*args, root=options.root)
        elif options.operation == 'coae-interpreter-observe': coae_interpreter_observe(*args, root=options.root)
        elif options.operation == 'dist-state': dist_state(*args)
        elif options.operation == 'lock-fd': lock_fd(*args, root=options.root)
        elif options.operation == 'shared-lock-prepare':
            # Root-only: exactly the canonical shared lock (fixture: under --root).
            if args != [options.root.rstrip('/') + '/var/lib/haseen/vapt/transaction.lock']:
                raise ValueError('shared lock path is not the canonical /var/lib/haseen/vapt/transaction.lock')
            state_path(args[0], options.operation)
        elif options.operation == 'lock-prepare': state_path(args[0], options.operation)
        elif options.operation == 'seal': seal(*args, allow_caller=bool(options.root))
        elif options.operation == 'recovery-record': print(recovery_record(args[0]))
        elif options.operation == 'sealed-safe':
            # Sealed artifacts are reopened by name (audit, root -U/-Syu):
            # every component must stay non-replaceable up to that moment.
            for path in args:
                nonreplaceable_ancestry(path, bool(options.root))
        elif options.operation == 'activate-blackarch': activate_blackarch(args[0])
        elif options.operation == 'activation-preflight':
            info = os.lstat(args[0])
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                raise ValueError('/etc/pacman.conf is not a single regular file; BlackArch activation unsupported')
            if not options.root:
                nonreplaceable_ancestry(Path(args[0]).parent, False)
        elif options.operation == 'artifact-digest':
            repo, name, version, filename = args
            record = next((p for p in repositories(options.root, options.dbpath).get(repo, [])
                           if p.get('name') == name and p.get('version') == version), None)
            digest = (record or {}).get('sha256sum') or ''
            if not ALLOWED.fullmatch(repo) or not re.fullmatch('[0-9a-f]{64}', digest):
                raise ValueError('reviewed repository digest unavailable ' + repo + '/' + name)
            if (record or {}).get('filename') != filename:
                raise ValueError('planned artifact name differs from the reviewed repository record ' + filename)
            print(digest)
        elif options.operation == 'report-requires': print('1' if report_requires(*args) else '0')
        elif options.operation == 'verify': verify_status(*args)
        # Directory-only repair, never a file state destination: dispatched
        # before the generic state-* file operations.
        elif options.operation == 'state-repair':
            # Root-only: exactly the canonical state directories.
            prefix = options.root.rstrip('/')
            if args != [prefix + '/var/lib/haseen', prefix + '/var/lib/haseen/vapt']:
                raise ValueError('state-repair is limited to /var/lib/haseen and /var/lib/haseen/vapt')
            repair_state_dirs(args, bool(options.root))
        elif options.operation.startswith('state-'): state_path(args[0], options.operation)
        elif options.operation == 'report-merge': merge_report(args[0])
        elif options.operation == 'cache-permissions': cache_permissions(options.root, args[0])
        elif options.operation == 'discover':
            # discover DB [KEYRING]: the one keyring record of a database the
            # caller has already authenticated (oniomarchy: by its pinned
            # detached signature) or, for BlackArch, its bootstrap database.
            keyring = args[1] if len(args) > 1 else 'blackarch-keyring'
            if keyring not in ('blackarch-keyring', 'oniomarchy-keyring'):
                raise ValueError('unknown keyring package')
            if keyring == 'oniomarchy-keyring':
                records = [r for r in oniomarchy_records(args[0]) if r['name'] == keyring]
            else:
                records = [field_data(text) for name, text in archive_members(args[0])
                           if name.endswith('/desc') and field_data(text).get('name') == keyring]
            if (len(records) != 1
                    or not re.fullmatch(re.escape(keyring) + r'-[A-Za-z0-9.+_-]+\.pkg\.tar\.(?:xz|zst|gz)', records[0].get('filename', ''))
                    or not re.fullmatch('[0-9a-f]{64}', records[0].get('sha256sum', ''))):
                raise ValueError('invalid/ambiguous keyring artifact or digest')
            # The bootstrap seals exactly these bytes before verify/audit/install.
            print(records[0]['filename'], records[0]['sha256sum'], sep='\t')
        elif options.operation == 'keyring':
            metadata = [text for name, text in archive_members(args[0]) if name == '.PKGINFO']
            if len(metadata) != 1:
                raise ValueError('keyring package identity metadata missing')
            fields = {}
            for line in metadata[0].splitlines():
                if ' = ' in line:
                    key, value = line.split(' = ', 1)
                    fields.setdefault(key, []).append(value)
            if fields.get('pkgname') != ['blackarch-keyring']:
                raise ValueError('signed archive is not blackarch-keyring')
            local, seen = installed(options.root), set()
            config, repos = read_config(options.root), repositories(options.root)
            def check_dependency(dep):
                candidates = [record for record in local if satisfies(record, dep)]
                if not candidates:
                    raise ValueError('keyring bootstrap dependency not already available ' + dep)
                for record in candidates:
                    name = record['name']
                    if name in seen:
                        continue
                    seen.add(name)
                    if not allowed_local(record, config, repos):
                        raise ValueError('unresolved retained keyring dependency source/identity ' + name)
                    for required in record.get('depends', []):
                        check_dependency(required)
            for dep in fields.get('depend', []):
                check_dependency(dep)
            audit_archives(options.root, args, keyring_population='blackarch-keyring', sudo_plugins_path=options.sudo_plugins,
                           authority_facts_path=options.authority_facts)
        elif options.operation == 'audit':
            audit_archives(options.root, args, plan=options.plan, dbpath=options.dbpath, reference=options.reference,
                           sudo_plugins_path=options.sudo_plugins, base_dbpath=options.base_dbpath,
                           authority_facts_path=options.authority_facts)
        elif options.operation == 'sudo-plugins':
            write_sudo_plugins(options.root, options.out)
        elif options.operation == 'authority-facts':
            write_authority_facts(options.root, options.out)
        elif options.operation == 'reference-missing':
            # Owners whose authenticated base reference the audit would need
            # but cannot find locally. A policy refusal ends the walk early;
            # the real audit then reports it.
            missing = {}
            try:
                audit_archives(options.root, args, plan=options.plan, dbpath=options.dbpath,
                               reference=options.reference, report=missing, sudo_plugins_path=options.sudo_plugins,
                               base_dbpath=options.base_dbpath, authority_facts_path=options.authority_facts)
            except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
                pass
            # db (base: the pre-refresh snapshot; reviewed) source owner version filename sha256
            for owner, (db, source, record) in sorted(missing.items()):
                row = (db, source, owner, record['version'], record['filename'], record['sha256sum'])
                if not emit_safe(*row):
                    raise ValueError('base reference metadata has a tab, newline or control character; refused')
                print(*row, sep='\t')
        elif options.operation == 'absent':
            present = {record['name'] for record in installed(options.root)}
            print('\n'.join(name for name in args if name not in present))
        elif options.operation == 'installed':
            repo, name, version, expected_url = args
            match = [r for r in installed(options.root) if r['name'] == name and r.get('version') == version
                     and not forbidden(r) and expected_url not in ('', '-') and r.get('url', '').rstrip('/') == expected_url.rstrip('/')]
            print('exact' if len(match) == 1 and version not in ('', '-') else 'unknown')
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
