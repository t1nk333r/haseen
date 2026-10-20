#!/usr/bin/env python3
# Adapted from typist_worker.py in sanjuanjor/typist (MIT, Copyright (c) 2026
# sanjuanjor), via the owner's fork t1nk33r.typist 1.1.0; see LICENSE and
# UPSTREAM.md beside this file.
#
# haseen changes: keys go to the command given as --keys (bin/haseen-typist
# passes haseen's `ydotool key` shim, share/haseen/shell/Compat/bin/ydotool,
# which turns them into Hyprland send_key_state dispatches, so no ydotoold and
# no /dev/uinput); a failure is reported through --notify (haseen notification
# send) instead of omarchy-notification-send; and a character is typed only
# when the layout reaches it with no modifier or with Shift alone. The shim
# carries Shift, Ctrl, Alt and Super as Hyprland mod names, and AltGr
# (LevelThree, Mod5) has no such name: sent as ALT it would type a different
# character, so those characters are skipped and counted instead.
#
# The text is read from stdin and never passed to another process: the keymap
# is built from the layout alone, and only key codes reach --keys.
import argparse
import ctypes
import ctypes.util
import json
import re
import signal
import subprocess
import sys
import time

PUNCTUATION = set(".,;:!?¿¡()[]{}<>\"'`-_=+*^%$#@/\\|~")
STOP_REQUESTED = False

# The only modifier a typed character may need (Linux input code). See the
# header: the haseen shim has no name for LevelThree/Mod5.
SHIFT_CODE = 42


class TypingFailed(Exception):
    """Raised when the key injection command refuses to run."""


def handle_sigterm(signum, frame):
    global STOP_REQUESTED
    STOP_REQUESTED = True


def detect_layout():
    try:
        out = subprocess.run(["hyprctl", "devices", "-j"], check=False, capture_output=True, text=True).stdout
        data = json.loads(out)
        keyboards = data.get("keyboards", [])
        main_kb = next((k for k in keyboards if k.get("main")), keyboards[0] if keyboards else None)
        if main_kb and main_kb.get("layout"):
            return str(main_kb["layout"]).split(",")[0]
    except Exception:
        pass

    try:
        out = subprocess.run(["setxkbmap", "-query"], check=False, capture_output=True, text=True).stdout
        m = re.search(r"^layout:\s*(\S+)", out, re.MULTILINE)
        if m:
            return m.group(1).split(",")[0]
    except Exception:
        pass

    return "us"


def key_sequence_for_char(ch, keymap):
    # Linux input key codes (KEY_ENTER=28, KEY_SPACE=57), not XKB key codes,
    # which are offset by 8; the shim adds the 8 back for Hyprland.
    if ch == "\n":
        return ["28:1", "28:0"]
    if ch == " ":
        return ["57:1", "57:0"]
    return keymap.get(ch)


class _RuleNames(ctypes.Structure):
    _fields_ = [
        ("rules", ctypes.c_char_p),
        ("model", ctypes.c_char_p),
        ("layout", ctypes.c_char_p),
        ("variant", ctypes.c_char_p),
        ("options", ctypes.c_char_p),
    ]


def _load_xkb():
    path = ctypes.util.find_library("xkbcommon") or "libxkbcommon.so.0"
    lib = ctypes.CDLL(path)

    lib.xkb_context_new.argtypes = [ctypes.c_int]
    lib.xkb_context_new.restype = ctypes.c_void_p
    lib.xkb_keymap_new_from_names.argtypes = [
        ctypes.c_void_p, ctypes.POINTER(_RuleNames), ctypes.c_int]
    lib.xkb_keymap_new_from_names.restype = ctypes.c_void_p
    for name in ("xkb_keymap_min_keycode", "xkb_keymap_max_keycode", "xkb_keymap_num_mods"):
        func = getattr(lib, name)
        func.argtypes = [ctypes.c_void_p]
        func.restype = ctypes.c_uint32
    lib.xkb_keymap_num_levels_for_key.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32]
    lib.xkb_keymap_num_levels_for_key.restype = ctypes.c_uint32
    lib.xkb_keymap_key_get_syms_by_level.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32,
        ctypes.POINTER(ctypes.POINTER(ctypes.c_uint32))]
    lib.xkb_keymap_key_get_syms_by_level.restype = ctypes.c_int
    lib.xkb_keymap_key_get_mods_for_level.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_uint32), ctypes.c_size_t]
    lib.xkb_keymap_key_get_mods_for_level.restype = ctypes.c_size_t
    lib.xkb_keymap_mod_get_name.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    lib.xkb_keymap_mod_get_name.restype = ctypes.c_char_p
    lib.xkb_keysym_to_utf32.argtypes = [ctypes.c_uint32]
    lib.xkb_keysym_to_utf32.restype = ctypes.c_uint32
    lib.xkb_keymap_unref.argtypes = [ctypes.c_void_p]
    lib.xkb_keymap_unref.restype = None
    lib.xkb_context_unref.argtypes = [ctypes.c_void_p]
    lib.xkb_context_unref.restype = None
    return lib


def mask_codes(mask, mod_names):
    """The Shift code a modifier mask needs, [] for none, None when it needs
    anything else (LevelThree, Mod5, Control, Lock …)."""
    names = [name for index, name in enumerate(mod_names) if mask & (1 << index)]
    if not names:
        return []
    if names == ["Shift"]:
        return [SHIFT_CODE]
    return None


def build_keymap(layout):
    """Map every printable character the layout reaches with no modifier or
    Shift alone to key actions.

    The whole map is built up front from the layout alone, so no clipboard
    character is ever passed to another process as an argument, where it would
    be readable in /proc/<pid>/cmdline.
    """
    lib = _load_xkb()
    context = lib.xkb_context_new(0)
    if not context:
        raise RuntimeError("could not create an xkb context")

    keymap_ptr = None
    try:
        names = _RuleNames(b"evdev", b"pc105", layout.encode("utf-8"), None, None)
        keymap_ptr = lib.xkb_keymap_new_from_names(context, ctypes.byref(names), 0)
        if not keymap_ptr:
            raise RuntimeError("could not compile keymap for layout " + layout)

        mod_names = [
            lib.xkb_keymap_mod_get_name(keymap_ptr, i).decode("utf-8", "replace")
            for i in range(lib.xkb_keymap_num_mods(keymap_ptr))
        ]

        table = {}
        masks = (ctypes.c_uint32 * 8)()
        for keycode in range(lib.xkb_keymap_min_keycode(keymap_ptr),
                             lib.xkb_keymap_max_keycode(keymap_ptr) + 1):
            linux_keycode = keycode - 8
            if linux_keycode <= 0:
                continue

            for level in range(lib.xkb_keymap_num_levels_for_key(keymap_ptr, keycode, 0)):
                syms = ctypes.POINTER(ctypes.c_uint32)()
                if lib.xkb_keymap_key_get_syms_by_level(
                        keymap_ptr, keycode, 0, level, ctypes.byref(syms)) < 1:
                    continue

                codepoint = lib.xkb_keysym_to_utf32(syms[0])
                # Control characters are excluded on purpose: Return, Tab and
                # friends map to real keys, and pressing them would turn a
                # CRLF clipboard into doubled line breaks.
                if codepoint < 0x20 or codepoint == 0x7F:
                    continue

                char = chr(codepoint)
                # The first key that produces a character wins, matching the
                # order the keymap lists them in.
                if char in table:
                    continue

                # A level can be reached by several masks (Shift or Lock for
                # a capital); the first one haseen can send wins.
                count = lib.xkb_keymap_key_get_mods_for_level(
                    keymap_ptr, keycode, 0, level, masks, len(masks))
                codes = None
                if count == 0:
                    codes = []
                for i in range(count):
                    codes = mask_codes(masks[i], mod_names)
                    if codes is not None:
                        break
                if codes is None:
                    continue

                actions = [f"{code}:1" for code in codes]
                actions.extend([f"{linux_keycode}:1", f"{linux_keycode}:0"])
                actions.extend(f"{code}:0" for code in reversed(codes))
                table[char] = actions

        return table
    finally:
        if keymap_ptr:
            lib.xkb_keymap_unref(keymap_ptr)
        lib.xkb_context_unref(context)


def type_text(text, keys, delay, newline_delay, punctuation_delay, layout=None):
    """Types TEXT; returns (completed, skipped)."""
    layout = layout or detect_layout()
    keymap = build_keymap(layout)
    skipped = 0

    for ch in text:
        if STOP_REQUESTED:
            return False, skipped

        if ch == "\n":
            current_delay = newline_delay
        elif ch in PUNCTUATION:
            current_delay = punctuation_delay
        else:
            current_delay = delay
        current_delay = max(current_delay, 5)

        seq = key_sequence_for_char(ch, keymap)
        if seq is None:
            # Not reachable on this layout without AltGr, or not at all.
            # Passing the character itself to another program would expose it
            # in /proc/<pid>/cmdline, so it is skipped and counted.
            skipped += 1
            continue

        cmd = [keys, "key", "-d", str(current_delay)]
        cmd.extend(seq)
        result = subprocess.run(
            cmd, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if result.returncode != 0:
            # Typing every remaining character would repeat the same failure
            # in silence.
            detail = result.stderr.decode("utf-8", "replace").strip().splitlines()
            raise TypingFailed(detail[0] if detail else "key injection failed")

        time.sleep(max(current_delay / 1000.0, 0.01))

    return True, skipped


def read_text_from_stdin(max_bytes):
    data = sys.stdin.buffer.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise ValueError("clipboard_too_large")
    return data.decode("utf-8", errors="replace")


def report(notify, summary, detail=""):
    """Surface an outcome to the user, not just to the journal.

    The worker runs detached under systemd, so stderr alone would be
    invisible. Only fixed text is passed on; typed content never leaves the
    process.
    """
    message = f"{summary} {detail}".strip() if detail else summary
    sys.stderr.write(message + "\n")
    if not notify:
        return
    try:
        subprocess.run(
            [notify, "--app-name", "haseen typist", "Typist", summary],
            check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        # The journal message above is the fallback when no notifier exists.
        pass


def startup_wait(startup_delay_ms):
    if startup_delay_ms <= 0:
        return
    remaining = startup_delay_ms / 1000.0
    step = 0.02
    while remaining > 0 and not STOP_REQUESTED:
        sleep_for = step if remaining > step else remaining
        time.sleep(sleep_for)
        remaining -= sleep_for


def main():
    parser = argparse.ArgumentParser(description="Type text from stdin once, with per-character timing.")
    parser.add_argument("--max-bytes", type=int, default=65536)
    parser.add_argument("--startup-delay", type=int, default=250)
    parser.add_argument("--delay", type=int, default=35)
    parser.add_argument("--newline-delay", type=int, default=90)
    parser.add_argument("--punctuation-delay", type=int, default=60)
    parser.add_argument("--keys", default="ydotool",
                        help="a command taking `key [-d MS] CODE:STATE …` (ydotool's syntax)")
    parser.add_argument("--notify", default="",
                        help="a command taking `--app-name NAME HEADLINE BODY`")
    parser.add_argument("--layout", default="",
                        help="XKB layout; default: Hyprland's main keyboard")
    args = parser.parse_args()

    if args.max_bytes < 1:
        raise SystemExit("--max-bytes must be >= 1")
    if args.startup_delay < 0:
        raise SystemExit("--startup-delay must be >= 0")

    try:
        text = read_text_from_stdin(args.max_bytes)
    except ValueError:
        report(args.notify, "Nothing typed: the text is over the size limit.")
        return 1

    if text == "":
        report(args.notify, "Nothing typed: there is no text to type.")
        return 1

    signal.signal(signal.SIGTERM, handle_sigterm)

    startup_wait(args.startup_delay)
    if STOP_REQUESTED:
        return 0
    try:
        _, skipped = type_text(text, args.keys, args.delay, args.newline_delay,
                               args.punctuation_delay, args.layout or None)
    except TypingFailed as exc:
        report(args.notify, "Typing failed.", str(exc))
        return 1
    except FileNotFoundError:
        report(args.notify, "Typing failed: the key command is missing.")
        return 1
    except (OSError, RuntimeError) as exc:
        # Failing loudly matters here: a silent no-op looks exactly like a
        # successful run from the outside.
        report(args.notify, "Could not read the keyboard layout.", str(exc))
        return 1
    if skipped:
        report(args.notify, f"Typed, but skipped {skipped} character(s) this layout needs AltGr for.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
