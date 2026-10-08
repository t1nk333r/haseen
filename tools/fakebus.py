"""The private-bus guard of tools/fake-mpris.py and tools/fake-upower.py.

Both claim well-known names (an MPRIS player, UPower) that must never appear
on the owner's real session or system bus. A D-Bus address is a list of
`transport:key=value,...` entries separated by `;`, and its values may be
percent-escaped (D-Bus specification, "Server Addresses"): comparing the raw
string misses `unix:path=/run/user/1000/%62us`. So every entry is parsed and
unescaped, only `unix:path=` (what the tests' dbus-daemon --address gives) is
accepted, and its socket is compared with the real buses' sockets by identity
(device and inode, after symlinks) and by resolved path. Any other transport
(abstract sockets, tcp, unixexec, autolaunch, `runtime=yes`, `dir=`) is
refused: none is how the tests start a bus, and some reach the real one.
"""

import os
from urllib.parse import unquote_to_bytes


def parse(address):
    """[(transport, {key: value})] with the values unescaped; ValueError if malformed."""
    entries = []
    for entry in address.split(";"):
        if entry == "":
            continue
        transport, colon, rest = entry.partition(":")
        if not colon or not transport:
            raise ValueError("no transport in %r" % entry)
        params = {}
        for pair in rest.split(",") if rest else []:
            key, eq, value = pair.partition("=")
            if not eq or not key or key in params:
                raise ValueError("bad parameter %r" % pair)
            params[key] = os.fsdecode(unquote_to_bytes(value))
        entries.append((transport, params))
    if not entries:
        raise ValueError("empty address")
    return entries


def real_sockets():
    """The real session and system bus sockets of this user."""
    runtime = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    return [os.path.join(runtime, "bus"), "/run/user/%d/bus" % os.getuid(),
            "/run/dbus/system_bus_socket", "/var/run/dbus/system_bus_socket"]


def _identity(path):
    try:
        st = os.stat(path)
    except OSError:
        return None
    return (st.st_dev, st.st_ino)


def refusal(address, real=None):
    """Why `address` is not a private test bus, or None when it is."""
    if not address:
        return "no address"
    try:
        entries = parse(address)
    except ValueError as err:
        return "not a D-Bus address (%s)" % err
    real = real_sockets() if real is None else real
    real_ids = {i for i in map(_identity, real) if i is not None}
    real_paths = {os.path.realpath(p) for p in real}
    for transport, params in entries:
        if transport != "unix" or "path" not in params or set(params) - {"path", "guid"}:
            return "only unix:path= addresses of a private bus are allowed"
        path = params["path"]
        if not os.path.isabs(path):
            return "the socket path must be absolute"
        if os.path.realpath(path) in real_paths or _identity(path) in real_ids:
            return "%s is a real bus" % path
    return None
