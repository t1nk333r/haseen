#!/usr/bin/env python3
"""A fake MPRIS media player for tests and nested proofs (plan 078).

It serves org.mpris.MediaPlayer2.NAME on the session bus at
$DBUS_SESSION_BUS_ADDRESS, which must be a private bus (a dbus-daemon or
dbus-run-session of the test's own), never the login session's bus: the
owner's real players live there.

usage: fake-mpris.py NAME [KEY=VALUE ...] < commands
  NAME        bus name suffix; the Identity unless Identity= is given
  KEY=VALUE   initial state:
    PlaybackStatus=Playing|Paused|Stopped  LoopStatus=None|Track|Playlist
    Shuffle=true  Volume=0.5  Position=SECONDS  Rate=1
    CanControl CanPlay CanPause CanSeek CanGoNext CanGoPrevious CanRaise=BOOL
    Identity=TEXT
    title= artist= album= art=URL length=SECONDS   (track metadata)
    omit=Shuffle,LoopStatus,Volume   properties the player does not have
Each stdin line is a set of KEY=VALUE pairs applied at once (one
PropertiesChanged); `sleep=SECONDS` pauses before the rest of the line. At
EOF the fake keeps serving until it is killed. Every method call and
property write from a client is printed as `fake-mpris: call NAME ARGS` or
`fake-mpris: set KEY=VALUE`, and takes effect as a player would apply it.
"""

import os
import sys
import time

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

ROOT = "org.mpris.MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"
PROPS = "org.freedesktop.DBus.Properties"
PATH = "/org/mpris/MediaPlayer2"
TRACK = dbus.ObjectPath("/org/haseen/fake/track/1")

BOOLS = ("CanControl", "CanPlay", "CanPause", "CanSeek", "CanGoNext", "CanGoPrevious",
         "CanRaise", "CanQuit", "Shuffle", "HasTrackList")
DOUBLES = ("Volume", "Rate", "MinimumRate", "MaximumRate")
META = {"title": "xesam:title", "album": "xesam:album", "artist": "xesam:artist",
        "art": "mpris:artUrl", "length": "mpris:length"}


def log(text):
    print("fake-mpris: " + text, flush=True)


def boolean(value):
    return dbus.Boolean(str(value).lower() in ("1", "true", "yes"))


class Player(dbus.service.Object):
    def __init__(self, bus, name, initial):
        super().__init__(bus, PATH)
        self.omit = set()
        self.root = {
            "Identity": dbus.String(name), "DesktopEntry": dbus.String(""),
            "CanRaise": dbus.Boolean(False), "CanQuit": dbus.Boolean(False),
            "HasTrackList": dbus.Boolean(False),
            "SupportedUriSchemes": dbus.Array([], signature="s"),
            "SupportedMimeTypes": dbus.Array([], signature="s"),
        }
        self.meta = {"mpris:trackid": TRACK}
        self.player = {
            "PlaybackStatus": dbus.String("Playing"), "LoopStatus": dbus.String("None"),
            "Shuffle": dbus.Boolean(False), "Volume": dbus.Double(1.0),
            "Rate": dbus.Double(1.0), "MinimumRate": dbus.Double(1.0), "MaximumRate": dbus.Double(1.0),
            "CanControl": dbus.Boolean(True), "CanPlay": dbus.Boolean(True),
            "CanPause": dbus.Boolean(True), "CanSeek": dbus.Boolean(True),
            "CanGoNext": dbus.Boolean(True), "CanGoPrevious": dbus.Boolean(True),
        }
        # Position in microseconds at `since` (monotonic seconds); it runs
        # while Playing, as a real player's would.
        self.base = 0
        self.since = time.monotonic()
        self.apply(initial, announce=False)

    # --- state -------------------------------------------------------------

    def position(self):
        pos = self.base
        if self.player.get("PlaybackStatus") == "Playing":
            pos += int((time.monotonic() - self.since) * 1e6)
        length = int(self.meta.get("mpris:length", 0))
        return max(0, min(pos, length) if length > 0 else pos)

    def set_position(self, us):
        self.base = int(us)
        self.since = time.monotonic()

    def apply(self, pairs, announce=True):
        root, player = {}, {}
        meta_changed = False
        for key, value in pairs:
            if key == "omit":
                self.omit.update(v for v in value.split(",") if v)
            elif key in META:
                field = META[key]
                if key == "length":
                    self.meta[field] = dbus.Int64(int(float(value) * 1e6))
                elif key == "artist":
                    self.meta[field] = dbus.Array([value], signature="s")
                else:
                    self.meta[field] = dbus.String(value)
                meta_changed = True
            elif key == "Position":
                self.set_position(float(value) * 1e6)
                if announce:
                    self.Seeked(dbus.Int64(self.position()))
            elif key in ("Identity", "DesktopEntry"):
                root[key] = dbus.String(value)
            elif key in ("CanRaise", "CanQuit"):
                root[key] = boolean(value)
            elif key in BOOLS:
                player[key] = boolean(value)
            elif key in DOUBLES:
                player[key] = dbus.Double(float(value))
            else:
                if key == "PlaybackStatus":
                    self.set_position(self.position())
                player[key] = dbus.String(value)
        if meta_changed:
            player["Metadata"] = self.metadata()
        self.root.update(root)
        self.player.update({k: v for k, v in player.items() if k != "Metadata"})
        if announce:
            self.changed(ROOT, root)
            self.changed(PLAYER, player)

    def metadata(self):
        return dbus.Dictionary(self.meta, signature="sv")

    def props(self, iface):
        if iface == ROOT:
            out = dict(self.root)
        elif iface == PLAYER:
            out = dict(self.player, Metadata=self.metadata(), Position=dbus.Int64(self.position()))
        else:
            out = {}
        return {k: v for k, v in out.items() if k not in self.omit}

    def changed(self, iface, props):
        props = {k: v for k, v in props.items() if k not in self.omit}
        if props:
            self.PropertiesChanged(iface, dbus.Dictionary(props, signature="sv"), dbus.Array([], signature="s"))

    # --- org.freedesktop.DBus.Properties -------------------------------------

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, iface, name):
        props = self.props(iface)
        if name not in props:
            raise dbus.exceptions.DBusException("no property " + name, name="org.freedesktop.DBus.Error.InvalidArgs")
        return props[name]

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return dbus.Dictionary(self.props(iface), signature="sv")

    @dbus.service.method(PROPS, in_signature="ssv")
    def Set(self, iface, name, value):
        if name in self.omit or name not in ("Volume", "Shuffle", "LoopStatus", "Rate"):
            raise dbus.exceptions.DBusException("read-only " + name, name="org.freedesktop.DBus.Error.PropertyReadOnly")
        shown = str(bool(value)).lower() if name == "Shuffle" else str(value)
        log("set %s=%s" % (name, shown))
        self.apply([(name, shown)])

    @dbus.service.signal(PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, invalidated):
        pass

    # --- org.mpris.MediaPlayer2 ----------------------------------------------

    @dbus.service.method(ROOT)
    def Raise(self):
        log("call Raise")

    @dbus.service.method(ROOT)
    def Quit(self):
        log("call Quit")

    # --- org.mpris.MediaPlayer2.Player ---------------------------------------

    def status(self, value):
        self.apply([("PlaybackStatus", value)])

    @dbus.service.method(PLAYER)
    def Next(self):
        log("call Next")

    @dbus.service.method(PLAYER)
    def Previous(self):
        log("call Previous")

    @dbus.service.method(PLAYER)
    def Play(self):
        log("call Play")
        self.status("Playing")

    @dbus.service.method(PLAYER)
    def Pause(self):
        log("call Pause")
        self.status("Paused")

    @dbus.service.method(PLAYER)
    def PlayPause(self):
        log("call PlayPause")
        self.status("Paused" if self.player["PlaybackStatus"] == "Playing" else "Playing")

    @dbus.service.method(PLAYER)
    def Stop(self):
        log("call Stop")
        self.status("Stopped")

    @dbus.service.method(PLAYER, in_signature="x")
    def Seek(self, offset):
        log("call Seek %d" % offset)
        self.set_position(self.position() + offset)
        self.Seeked(dbus.Int64(self.position()))

    @dbus.service.method(PLAYER, in_signature="ox")
    def SetPosition(self, track, position):
        log("call SetPosition %s %d" % (track, position))
        if track == TRACK:
            self.set_position(position)
            self.Seeked(dbus.Int64(self.position()))

    @dbus.service.method(PLAYER, in_signature="s")
    def OpenUri(self, uri):
        log("call OpenUri " + uri)

    @dbus.service.signal(PLAYER, signature="x")
    def Seeked(self, position):
        pass


def parse(words):
    return [tuple(w.partition("=")[::2]) for w in words if "=" in w]


def main():
    if len(sys.argv) < 2 or sys.argv[1].startswith("-") or "=" in sys.argv[1]:
        sys.exit(__doc__)
    address = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
    runtime = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    if not address or ("unix:path=%s/bus" % runtime) in address or ("unix:path=/run/user/%d/bus" % os.getuid()) in address:
        sys.exit("fake-mpris: set DBUS_SESSION_BUS_ADDRESS to a private bus, never the login session's")
    name = sys.argv[1]
    DBusGMainLoop(set_as_default=True)
    bus = dbus.bus.BusConnection(address)
    player = Player(bus, name, parse(sys.argv[2:]))
    # Held for the process lifetime: a collected BusName releases the name.
    bus_name = dbus.service.BusName(ROOT + "." + name, bus, do_not_queue=True)
    log("ready " + bus_name.get_name())

    pending = []
    sleeping = [False]

    def drain():
        sleeping[0] = False
        while pending:
            words = pending.pop(0).split()
            if words and words[0].startswith("sleep="):
                if words[1:]:
                    pending.insert(0, " ".join(words[1:]))
                sleeping[0] = True
                GLib.timeout_add(int(float(words[0][6:]) * 1000), drain)
                return False
            if words:
                player.apply(parse(words))
                log("applied " + " ".join(words))
        return False

    def on_input(fd, condition):
        line = sys.stdin.readline()
        if not line:
            return False
        pending.append(line.strip())
        if not sleeping[0]:
            drain()
        return True

    GLib.io_add_watch(sys.stdin, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, on_input)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
