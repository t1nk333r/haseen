#!/usr/bin/env python3
"""A fake UPower (and power-profiles-daemon) for tests and nested proofs.

It serves org.freedesktop.UPower with one laptop battery, the display device
that mirrors it, and org.freedesktop.UPower.PowerProfiles (also as
net.hadess.PowerProfiles), on the bus at $DBUS_SYSTEM_BUS_ADDRESS. Point it
at a private dbus-daemon, never at the real system bus, and give the shell
under test the same DBUS_SYSTEM_BUS_ADDRESS (plan 075).

usage: fake-upower.py [KEY=VALUE ...] < commands
  KEY=VALUE   initial battery properties, e.g. Percentage=50 State=2
Each stdin line is a set of KEY=VALUE pairs applied at once; the change goes
out as one PropertiesChanged per object. `OnBattery=true` sets the daemon's
property, `ActiveProfile=balanced` the power profile, `sleep=SECONDS`
pauses before the rest of the line, and a line `client` holds the rest of
the script until a client has read the display device (GetAll), so a script
times its changes from when the shell under test is up, not from when the
fake started. At EOF the fake keeps serving until it is killed. State:
1 charging, 2 discharging, 4 fully charged, 5 pending charge (plugged in,
not charging).
"""

import os
import sys
import time

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

import fakebus

UPOWER = "org.freedesktop.UPower"
DEVICE = "org.freedesktop.UPower.Device"
PROFILES = "org.freedesktop.UPower.PowerProfiles"
PROPS = "org.freedesktop.DBus.Properties"

# D-Bus type per property (UPower's introspection).
TYPES = {
    "Type": dbus.UInt32, "State": dbus.UInt32, "Technology": dbus.UInt32,
    "WarningLevel": dbus.UInt32, "BatteryLevel": dbus.UInt32,
    "Percentage": dbus.Double, "Energy": dbus.Double, "EnergyFull": dbus.Double,
    "EnergyFullDesign": dbus.Double, "EnergyEmpty": dbus.Double,
    "EnergyRate": dbus.Double, "Voltage": dbus.Double, "Capacity": dbus.Double,
    "Temperature": dbus.Double, "Luminosity": dbus.Double,
    "TimeToEmpty": dbus.Int64, "TimeToFull": dbus.Int64, "UpdateTime": dbus.UInt64,
    "ChargeCycles": dbus.Int32,
    "PowerSupply": dbus.Boolean, "IsPresent": dbus.Boolean, "IsRechargeable": dbus.Boolean,
    "Online": dbus.Boolean, "HasHistory": dbus.Boolean, "HasStatistics": dbus.Boolean,
    "NativePath": dbus.String, "Model": dbus.String, "Vendor": dbus.String,
    "Serial": dbus.String, "IconName": dbus.String,
}


def convert(key, value):
    kind = TYPES.get(key, dbus.String)
    if kind is dbus.Boolean:
        return dbus.Boolean(value.lower() in ("1", "true", "yes"))
    if kind in (dbus.UInt32, dbus.Int32, dbus.Int64, dbus.UInt64):
        return kind(int(float(value)))
    if kind is dbus.Double:
        return dbus.Double(float(value))
    return dbus.String(value)


class PropertyObject(dbus.service.Object):
    """An object with one interface's properties behind org.freedesktop.DBus.Properties."""

    def __init__(self, bus, path, iface, props):
        super().__init__(bus, path)
        self.iface = iface
        self.props = props
        # Called after each GetAll (the display device's `client` gate).
        self.on_read = None

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, iface, name):
        return self.props[name]

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        if self.on_read:
            # After the reply is on the wire: the reader has the values the
            # script then changes.
            GLib.idle_add(self.on_read)
        return dbus.Dictionary(self.props if iface == self.iface else {}, signature="sv")

    @dbus.service.method(PROPS, in_signature="ssv")
    def Set(self, iface, name, value):
        self.update({name: value})

    @dbus.service.signal(PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, invalidated):
        pass

    def update(self, changed):
        if not changed:
            return
        self.props.update(changed)
        self.PropertiesChanged(self.iface, dbus.Dictionary(changed, signature="sv"), dbus.Array([], signature="s"))


class Daemon(PropertyObject):
    def __init__(self, bus, devices):
        super().__init__(bus, "/org/freedesktop/UPower", UPOWER, {
            "DaemonVersion": dbus.String("1.91.3"),
            "OnBattery": dbus.Boolean(True),
            "LidIsClosed": dbus.Boolean(False),
            "LidIsPresent": dbus.Boolean(True),
        })
        self.devices = devices

    @dbus.service.method(UPOWER, out_signature="ao")
    def EnumerateDevices(self):
        return dbus.Array([dbus.ObjectPath("/org/freedesktop/UPower/devices/battery_BAT0")], signature="o")

    @dbus.service.method(UPOWER, out_signature="o")
    def GetDisplayDevice(self):
        return dbus.ObjectPath("/org/freedesktop/UPower/devices/DisplayDevice")

    @dbus.service.method(UPOWER, out_signature="s")
    def GetCriticalAction(self):
        return "PowerOff"

    @dbus.service.signal(UPOWER, signature="o")
    def DeviceAdded(self, path):
        pass

    @dbus.service.signal(UPOWER, signature="o")
    def DeviceRemoved(self, path):
        pass


class Device(PropertyObject):
    def __init__(self, bus, path, props):
        super().__init__(bus, path, DEVICE, props)

    @dbus.service.method(DEVICE)
    def Refresh(self):
        pass


class Profiles(PropertyObject):
    def __init__(self, bus, path):
        super().__init__(bus, path, PROFILES, {
            "ActiveProfile": dbus.String("balanced"),
            "PerformanceDegraded": dbus.String(""),
            "PerformanceInhibited": dbus.String(""),
            "Profiles": dbus.Array([
                dbus.Dictionary({"Profile": dbus.String(p), "Driver": dbus.String("fake")}, signature="sv")
                for p in ("power-saver", "balanced", "performance")
            ], signature="a{sv}"),
            "Actions": dbus.Array([], signature="s"),
            "ActiveProfileHolds": dbus.Array([], signature="a{sv}"),
            "Version": dbus.String("0.30"),
        })

    @dbus.service.method(PROFILES, in_signature="sss", out_signature="u")
    def HoldProfile(self, profile, reason, app):
        return dbus.UInt32(1)

    @dbus.service.method(PROFILES, in_signature="u")
    def ReleaseProfile(self, cookie):
        pass


def battery_props():
    return {
        "NativePath": dbus.String("BAT0"), "Vendor": dbus.String("haseen"),
        "Model": dbus.String("Fake battery"), "Serial": dbus.String("0"),
        "UpdateTime": dbus.UInt64(int(time.time())),
        "Type": dbus.UInt32(2), "PowerSupply": dbus.Boolean(True),
        "Online": dbus.Boolean(False), "HasHistory": dbus.Boolean(False),
        "HasStatistics": dbus.Boolean(False), "IsPresent": dbus.Boolean(True),
        "IsRechargeable": dbus.Boolean(True), "State": dbus.UInt32(2),
        "Percentage": dbus.Double(50), "Energy": dbus.Double(25),
        "EnergyEmpty": dbus.Double(0), "EnergyFull": dbus.Double(50),
        "EnergyFullDesign": dbus.Double(57), "EnergyRate": dbus.Double(8.4),
        "Voltage": dbus.Double(12), "TimeToEmpty": dbus.Int64(10800),
        "TimeToFull": dbus.Int64(0), "Capacity": dbus.Double(88),
        "Technology": dbus.UInt32(1), "Temperature": dbus.Double(0),
        "Luminosity": dbus.Double(0), "WarningLevel": dbus.UInt32(1),
        "BatteryLevel": dbus.UInt32(1), "IconName": dbus.String("battery-good-symbolic"),
        "ChargeCycles": dbus.Int32(120),
    }


def main():
    address = os.environ.get("DBUS_SYSTEM_BUS_ADDRESS", "")
    why = fakebus.refusal(address)
    if why:
        sys.exit("fake-upower: set DBUS_SYSTEM_BUS_ADDRESS to a private bus, never the real system bus (%s)" % why)
    DBusGMainLoop(set_as_default=True)
    bus = dbus.bus.BusConnection(address)

    initial = battery_props()
    for arg in sys.argv[1:]:
        key, _, value = arg.partition("=")
        initial[key] = convert(key, value)
    battery = Device(bus, "/org/freedesktop/UPower/devices/battery_BAT0", dict(initial))
    display = Device(bus, "/org/freedesktop/UPower/devices/DisplayDevice", dict(initial, NativePath=dbus.String("")))
    daemon = Daemon(bus, [battery])
    profiles = [Profiles(bus, "/org/freedesktop/UPower/PowerProfiles"), Profiles(bus, "/net/hadess/PowerProfiles")]
    # Held for the process lifetime: a collected BusName releases the name.
    names = [dbus.service.BusName(n, bus, do_not_queue=True) for n in (UPOWER, PROFILES, "net.hadess.PowerProfiles")]
    print("fake-upower: ready", flush=True)

    pending = []
    sleeping = [False]
    # The display device has been read / a `client` line is waiting for it.
    read = [False]
    gated = [False]

    def on_read():
        read[0] = True
        if gated[0]:
            gated[0] = False
            drain()
        return False

    display.on_read = on_read

    def apply(line):
        device, root, profile = {}, {}, {}
        for pair in line.split():
            key, _, value = pair.partition("=")
            if key == "OnBattery":
                root[key] = convert("PowerSupply", value)
            elif key == "ActiveProfile":
                profile[key] = dbus.String(value)
            else:
                device[key] = convert(key, value)
        if device:
            device["UpdateTime"] = dbus.UInt64(int(time.time()))
        battery.update(dict(device))
        display.update(dict(device))
        daemon.update(root)
        for p in profiles:
            p.update(dict(profile))
        print("fake-upower: applied " + line, flush=True)

    def drain():
        sleeping[0] = False
        while pending:
            line = pending.pop(0)
            words = line.split()
            if words == ["client"]:
                if not read[0]:
                    gated[0] = True
                    print("fake-upower: waiting for a client", flush=True)
                    return False
                continue
            if words and words[0].startswith("sleep="):
                rest = " ".join(words[1:])
                if rest:
                    pending.insert(0, rest)
                sleeping[0] = True
                GLib.timeout_add(int(float(words[0][6:]) * 1000), drain)
                return False
            if words:
                apply(line)
        return False

    def on_input(fd, condition):
        line = sys.stdin.readline()
        if not line:
            return False
        pending.append(line.strip())
        if not sleeping[0] and not gated[0]:
            drain()
        return True

    GLib.io_add_watch(sys.stdin, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, on_input)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
