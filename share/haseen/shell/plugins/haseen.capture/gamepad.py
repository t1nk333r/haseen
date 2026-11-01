#!/usr/bin/env python3
"""haseen.capture's controller listener (plan 150).

Prints one line per controller event for the toolbar's Process to read:

    connected N     the number of controllers it reads (printed at start and
                    whenever a controller comes or goes)
    press BUTTON    a, b, x, y, lb, rb, lt, rt, select, start, guide, up,
                    down, left or right
    error TEXT      a controller it may not open

It reads the kernel's evdev nodes with the standard library only and never
grabs them, so a game keeps getting every press. The button codes are the
kernel's gamepad layout (Documentation/input/gamepad.rst): BTN_SOUTH is A,
the D-pad is BTN_DPAD_* or the ABS_HAT0 axes, the left stick is ABS_X/ABS_Y.
The shell starts it only while the toolbar is open or a recording runs, and
it sleeps in select(): a press or an inotify event on /dev/input wakes it,
nothing else (no polling, architecture 6).

--sysfs and --dev point it at other trees for tests/test-capture-toolbar.sh.
"""

import argparse
import ctypes
import ctypes.util
import errno
import fcntl
import os
import select
import struct
import sys

EV_KEY = 0x01
EV_ABS = 0x03

KEYS = {
    0x130: "a",  # BTN_SOUTH
    0x131: "b",  # BTN_EAST
    0x133: "x",  # BTN_NORTH (BTN_X)
    0x134: "y",  # BTN_WEST (BTN_Y)
    0x136: "lb",  # BTN_TL
    0x137: "rb",  # BTN_TR
    0x138: "lt",  # BTN_TL2
    0x139: "rt",  # BTN_TR2
    0x13A: "select",
    0x13B: "start",
    0x13C: "guide",  # BTN_MODE
    0x220: "up",  # BTN_DPAD_UP
    0x221: "down",
    0x222: "left",
    0x223: "right",
}
BTN_SOUTH = 0x130
BTN_TL2 = 0x138

ABS_X, ABS_Y, ABS_Z, ABS_RX, ABS_RZ = 0x00, 0x01, 0x02, 0x03, 0x05
ABS_GAS, ABS_BRAKE = 0x09, 0x0A
ABS_HAT0X, ABS_HAT0Y = 0x10, 0x11

# struct input_event on a 64-bit kernel: a timeval, then type, code, value.
EVENT = struct.Struct("llHHi")
# struct input_absinfo: value, minimum, maximum, fuzz, flat, resolution.
ABSINFO = struct.Struct("6i")

# An axis past PRESS of its travel presses; it must come back under RELEASE
# before it can press again, so a resting stick never repeats.
PRESS = 0.6
RELEASE = 0.3

IN_ATTRIB = 0x004
IN_MOVED_TO = 0x080
IN_CREATE = 0x100
IN_DELETE = 0x200


def say(line):
    try:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        # The shell closed the pipe: the toolbar no longer listens.
        os._exit(0)


def bits(path):
    """The capability bitmap in a sysfs file: hex words, highest first."""
    try:
        with open(path, encoding="ascii") as f:
            words = f.read().split()
    except OSError:
        return 0
    value = 0
    width = struct.calcsize("l") * 8
    for word in words:
        try:
            value = (value << width) | int(word, 16)
        except ValueError:
            return 0
    return value


def has(bitmap, bit):
    return (bitmap >> bit) & 1 == 1


def eviocgabs(code):
    # _IOR('E', 0x40 + code, struct input_absinfo)
    return (2 << 30) | (ABSINFO.size << 16) | (ord("E") << 8) | (0x40 + code)


class Pad:
    def __init__(self, path, fd, keys, axes):
        self.path = path
        self.fd = fd
        self.buffer = b""
        # The digital trigger buttons win: a pad with both reports each pull
        # twice otherwise. ABS_Z and ABS_RZ are triggers only beside a right
        # stick on ABS_RX; on a plain HID pad they are the right stick.
        self.triggers = {}
        if not has(keys, BTN_TL2):
            if has(axes, ABS_RX):
                self.triggers.update({ABS_Z: "lt", ABS_RZ: "rt"})
            self.triggers.update({ABS_BRAKE: "lt", ABS_GAS: "rt"})
        self.ranges = {}
        for code in (ABS_X, ABS_Y, ABS_Z, ABS_RZ, ABS_GAS, ABS_BRAKE):
            self.ranges[code] = self.range(code)
        self.held = {}

    def range(self, code):
        stick = code in (ABS_X, ABS_Y)
        fallback = (-32768, 32767) if stick else (0, 255)
        try:
            raw = fcntl.ioctl(self.fd, eviocgabs(code), bytes(ABSINFO.size))
            _, low, high, _, _, _ = ABSINFO.unpack(raw)
        except OSError:
            return fallback
        return (low, high) if high > low else fallback

    def axis(self, code, value):
        """The button an axis move presses, or None."""
        if code in (ABS_HAT0X, ABS_HAT0Y):
            names = ("left", "right") if code == ABS_HAT0X else ("up", "down")
            was = self.held.get(code)
            now = names[0] if value < 0 else names[1] if value > 0 else None
            self.held[code] = now
            return now if now and now != was else None
        if code in (ABS_X, ABS_Y):
            low, high = self.ranges[code]
            half = (high - low) / 2
            level = (value - (low + high) / 2) / half if half else 0
            names = ("left", "right") if code == ABS_X else ("up", "down")
            return self.edge(code, names[0] if level < 0 else names[1], abs(level))
        if code in self.triggers:
            low, high = self.ranges[code]
            level = (value - low) / (high - low) if high > low else 0
            return self.edge(code, self.triggers[code], level)
        return None

    def edge(self, code, name, level):
        was = self.held.get(code)
        if was is None and level >= PRESS:
            self.held[code] = name
            return name
        if was is not None and level <= RELEASE:
            self.held[code] = None
        return None

    def read(self):
        """The buttons pressed since the last read; None once it is gone."""
        try:
            data = os.read(self.fd, EVENT.size * 64)
        except BlockingIOError:
            return []
        except OSError:
            return None
        if not data:
            return None
        self.buffer += data
        pressed = []
        while len(self.buffer) >= EVENT.size:
            _, _, kind, code, value = EVENT.unpack_from(self.buffer)
            self.buffer = self.buffer[EVENT.size:]
            if kind == EV_KEY and value == 1 and code in KEYS:
                pressed.append(KEYS[code])
            elif kind == EV_ABS:
                name = self.axis(code, value)
                if name:
                    pressed.append(name)
        return pressed


class Listener:
    def __init__(self, sysfs, dev):
        self.sysfs = sysfs
        self.dev = dev
        self.pads = {}
        self.refused = set()
        self.reported = None
        self.inotify = self.watch()

    def watch(self):
        try:
            libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6", use_errno=True)
            fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
            if fd < 0:
                return None
            # IN_ATTRIB: udev sets the node's access after creating it.
            mask = IN_CREATE | IN_DELETE | IN_ATTRIB | IN_MOVED_TO
            if libc.inotify_add_watch(fd, os.fsencode(self.dev), mask) < 0:
                os.close(fd)
                return None
            return fd
        except (OSError, AttributeError):
            return None

    def candidates(self):
        try:
            names = os.listdir(self.sysfs)
        except OSError:
            return []
        out = []
        for name in sorted(names):
            if not name.startswith("event"):
                continue
            caps = os.path.join(self.sysfs, name, "device", "capabilities")
            keys = bits(os.path.join(caps, "key"))
            if has(keys, BTN_SOUTH):
                out.append((os.path.join(self.dev, name), keys, bits(os.path.join(caps, "abs"))))
        return out

    def scan(self):
        seen = set()
        for path, keys, axes in self.candidates():
            seen.add(path)
            if path in self.pads:
                continue
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
            except OSError as e:
                if e.errno in (errno.EACCES, errno.EPERM) and path not in self.refused:
                    self.refused.add(path)
                    say("error cannot read " + os.path.basename(path) + ": " + e.strerror)
                continue
            self.refused.discard(path)
            self.pads[path] = Pad(path, fd, keys, axes)
        for path in list(self.pads):
            if path not in seen:
                self.drop(path)
        self.report()

    def drop(self, path):
        pad = self.pads.pop(path, None)
        if pad:
            try:
                os.close(pad.fd)
            except OSError:
                pass

    def report(self):
        if self.reported != len(self.pads):
            self.reported = len(self.pads)
            say("connected %d" % self.reported)

    def run(self):
        self.scan()
        while True:
            fds = [p.fd for p in self.pads.values()]
            if self.inotify is not None:
                fds.append(self.inotify)
            if not fds:
                # Nothing to read and no way to hear a new controller: wait
                # for the shell to stop this process.
                select.select([sys.stdin], [], [])
                return
            ready, _, _ = select.select(fds, [], [])
            if self.inotify in ready:
                try:
                    os.read(self.inotify, 65536)
                except OSError:
                    pass
                self.scan()
            for path, pad in list(self.pads.items()):
                if pad.fd not in ready:
                    continue
                pressed = pad.read()
                if pressed is None:
                    self.drop(path)
                    self.report()
                    continue
                for name in pressed:
                    say("press " + name)


def main():
    parser = argparse.ArgumentParser(description="Print controller presses for haseen.capture.")
    parser.add_argument("--sysfs", default="/sys/class/input")
    parser.add_argument("--dev", default="/dev/input")
    args = parser.parse_args()
    try:
        Listener(args.sysfs, args.dev).run()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
