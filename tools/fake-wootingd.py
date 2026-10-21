#!/usr/bin/env python3
"""A stand-in for wootingd: same unix socket, same line protocol, no hardware.

From the owner's t1nk333r/haseen-wooting tests/fakedaemon.py at 184f6fa (MIT,
Copyright (c) 2026 t1nk33r); plan 099. haseen added two things the real
daemon does (core/wootingd/src/main.rs): a `profile set` is broadcast to every
`subscribe`d connection as a {"event":"change",...} snapshot, and SIGTERM
removes the socket before exiting, which is how the bar learns the daemon
went away.

Every reply shape here was captured from a live daemon run against the real
Wooting 60HE+ (compare daemon/src/main.rs, Snapshot::json, Core::set_profile
and handle_client), down to the compact separators, the raw UTF-8 em dash in
the error text and the empty strings in the absent snapshot -- so the tests
exercise the shell surface against production bytes, including the error
shapes.

The default fixture is the reference keyboard as it actually is: 4 addressable
slots, of which only slot 0 holds a stored profile ("1 Typing Profile"), so
`count` is 1 and `profile set 1..3` is refused with the daemon's
"holds no stored profile" line while `profile set 4+` is "out of range".

usage: fake-wootingd.py SOCKET [options]

  --absent      behave as if no keyboard is connected
  --profiles N  model N stored profiles (1..4, default 1); slots past 0 are
                stored but nameless, so they get the daemon's synthesised
                "Profile N" label with named:false
  --active N    start with slot N active (default 0)
  --garbage     answer every verb with a line that is not JSON
  --silent      accept the connection, read the verb, and never answer --
                the connection is held open so the client's timeout is what
                ends the round trip
  --error MSG   answer every verb with {"ok":false,"error":"MSG"}
  --analog-keys JSON
                keys under travel for `analog get`/`analog subscribe`, e.g.
                '[{"row":2,"col":2,"code":26,"value":0.62,"actuated":true}]'
  --fn-map JSON the learned Fn layer for `fn get`, e.g. '{"3,3":73}'
"""

import json
import os
import signal
import socket
import sys
import threading
import time

# Slot 0 is the only slot with a stored profile on the reference device; the
# other addressable slots are empty. `--profiles N` pretends N of them are
# stored (nameless past slot 0), for the name-resolution and cycling tests.
NAMES = ["1 Typing Profile", None, None, None]
RANGE = 4  # addressable slots (GetMappingProfile answers 0x88 for 0..=3)
SERIAL = "A00B0000W00T00000S00H00000"
NODE = "/dev/hidraw5"
FIRMWARE = "2.14.0"


def dump(obj):
    """Compact separators and raw UTF-8, exactly like the daemon's esc()."""
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=False)


def label(slot):
    return NAMES[slot] if NAMES[slot] else "Profile %d" % (slot + 1)


def stored(state):
    """The slots the daemon would publish: every stored slot, plus the active
    one even if its read reported no data (Core::refresh keeps it)."""
    slots = list(range(state["profiles"]))
    if state["active"] not in slots:
        slots.append(state["active"])
    return slots


# Wooting 60HE+ identity as the daemon publishes it (proto::model_for_pid).
PID = 0x1320
MODEL = "Wooting 60HE+"
COLUMNS = 14
FUNCTION_ROW = False
LAYOUT = "ansi"
ANALOG_NODE = "/dev/hidraw7"


def snapshot(state, tag, tag_value):
    """The daemon's snapshot object, key order included."""
    out = {tag: tag_value}
    if state["absent"]:
        # Snapshot::absent(): empty strings and "standard" framing, not nulls.
        out.update(
            {
                "present": False,
                "firmware": None,
                "serial": "",
                "node": "",
                "framing": "standard",
                "pid": 0,
                "model": None,
                "columns": 0,
                "functionRow": False,
                "layout": "unknown",
                "count": 0,
                "active": 0,
                "profiles": [],
            }
        )
        return out
    active = state["active"]
    slots = stored(state)
    out.update(
        {
            "present": True,
            "firmware": FIRMWARE,
            "serial": SERIAL,
            "node": NODE,
            "framing": "arm",
            "pid": PID,
            "model": MODEL,
            "columns": COLUMNS,
            "functionRow": FUNCTION_ROW,
            "layout": LAYOUT,
            "count": len(slots),
            "active": active,
            "profiles": [
                {
                    "slot": slot,
                    "name": label(slot),
                    "named": NAMES[slot] is not None,
                    "active": slot == active,
                }
                for slot in slots
            ],
        }
    )
    return out


def analog_snapshot(state, tag, tag_value):
    """AnalogState::json. `--analog-keys` seeds the keys under travel; the
    real daemon sends this exact shape on `analog get` and as every event."""
    out = {tag: tag_value}
    if state["absent"]:
        out.update({"present": False, "node": "", "keys": []})
        return out
    out.update({"present": True, "node": ANALOG_NODE, "keys": state["analog_keys"]})
    return out


def set_error(slot, state):
    """Core::set_profile's two refusals, verbatim."""
    selectable = ", ".join(str(s) for s in stored(state))
    if slot < RANGE:
        return (
            "slot %d holds no stored profile \u2014 create it in Wootility first "
            "(selectable: %s)" % (slot, selectable)
        )
    return "slot %d out of range (device has %d addressable slots; selectable: %s)" % (
        slot,
        RANGE,
        selectable,
    )


SUBSCRIBERS = []
SUBSCRIBERS_LOCK = threading.Lock()


def broadcast(state):
    line = (dump(snapshot(state, "event", "change")) + "\n").encode("utf-8")
    with SUBSCRIBERS_LOCK:
        for stream in list(SUBSCRIBERS):
            try:
                stream.write(line)
                stream.flush()
            except (OSError, ValueError):
                SUBSCRIBERS.remove(stream)


def reply_for(verb, state):
    if state["garbage"]:
        return "this is not JSON"
    if state["error"]:
        return dump({"ok": False, "error": state["error"]})
    if verb == "ping":
        return dump({"ok": True, "pong": True})
    if verb in ("status", "profile list"):
        return dump(snapshot(state, "ok", True))
    if verb == "profile get":
        if state["absent"]:
            return dump({"ok": False, "error": "no keyboard present"})
        return dump({"ok": True, "active": state["active"]})
    if verb == "subscribe":
        return dump(snapshot(state, "event", "status"))
    if verb == "analog get":
        return dump(analog_snapshot(state, "ok", True))
    if verb == "analog subscribe":
        return dump(analog_snapshot(state, "event", "analog"))
    if verb == "fn get":
        # The daemon's learned Fn map: position -> the code this board reports
        # under Fn. `--fn-map` seeds it; empty is the honest default, because a
        # keyboard nobody has pressed Fn on has taught the daemon nothing.
        return dump({"ok": True, "count": len(state["fn_map"]), "keys": state["fn_map"]})
    if verb.startswith("profile set "):
        arg = verb[len("profile set ") :].strip()
        try:
            slot = int(arg)
            if slot < 0 or slot > 255:  # the daemon parses a u8
                raise ValueError(arg)
        except ValueError:
            return dump(
                {"ok": False, "error": "profile set: %s is not a slot number" % arg}
            )
        if state["absent"]:
            return dump({"ok": False, "error": "no keyboard present"})
        if slot not in stored(state):
            return dump({"ok": False, "error": set_error(slot, state)})
        state["active"] = slot
        return dump({"ok": True, "active": slot})
    return dump({"ok": False, "error": "unknown verb: %s" % verb})


def serve(conn, state):
    """One client: read verb lines, answer exactly one line each."""
    with conn, conn.makefile("rwb") as stream:
        for raw in stream:
            verb = raw.decode("utf-8", "replace").strip()
            if not verb:
                continue
            if state["silent"]:
                # A wedged daemon keeps the socket open and says nothing; the
                # client's own timeout has to end the exchange. Closing here
                # would hand the client an EOF instead, which is a different
                # (and much faster) failure path.
                time.sleep(60)
                return
            before = state["active"]
            with SUBSCRIBERS_LOCK:
                stream.write((reply_for(verb, state) + "\n").encode("utf-8"))
                stream.flush()
                if verb == "subscribe" and stream not in SUBSCRIBERS:
                    SUBSCRIBERS.append(stream)
            if verb.startswith("profile set ") and state["active"] != before:
                broadcast(state)
    with SUBSCRIBERS_LOCK:
        if stream in SUBSCRIBERS:
            SUBSCRIBERS.remove(stream)


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    path = args[0]
    profiles = int(args[args.index("--profiles") + 1]) if "--profiles" in args else 1
    if not 1 <= profiles <= len(NAMES):
        sys.exit("fakedaemon: --profiles must be 1..%d" % len(NAMES))
    state = {
        "absent": "--absent" in args,
        "garbage": "--garbage" in args,
        "silent": "--silent" in args,
        "error": args[args.index("--error") + 1] if "--error" in args else None,
        "active": int(args[args.index("--active") + 1]) if "--active" in args else 0,
        "profiles": profiles,
        "analog_keys": json.loads(args[args.index("--analog-keys") + 1])
        if "--analog-keys" in args
        else [],
        "fn_map": json.loads(args[args.index("--fn-map") + 1])
        if "--fn-map" in args
        else {},
    }

    if os.path.exists(path):
        os.unlink(path)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(path)
    srv.listen(8)

    def terminate(_sig, _frame):
        try:
            os.unlink(path)
        except OSError:
            pass
        os._exit(0)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=serve, args=(conn, state), daemon=True).start()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
