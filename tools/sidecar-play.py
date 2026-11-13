#!/usr/bin/env python3
"""tools/sidecar-play.py SOCKET BASE SCRIPT - play a script to haseen-sidecar.

tests/test-sidecar.sh compares what the daemon prints for each script with what
the Go daemon printed (core/sidecar/tests/golden/, plan 167). SCRIPT has one JSON object
per line:

  {"send": "<a request line>"}           write it to the socket
  {"wait": "reply"|"event", "n": 1}      read until n frames of that type came
  {"write": ["<path under BASE>", "<text>"]}   rewrite a fixture file
  {"sleep": <ms>}

Frames are printed one per line. The frames read between two waits are sorted,
because Go answered a subscribe and sent its first sample from two goroutines,
in either order. The hello's pid and version, and values divided by wall time
(the network rates, a process's cpu, the gpu of a chosen rc6 card) are masked; the disks'
sizes are masked too, since they come from the live filesystem under BASE.
"""

import json
import os
import re
import socket
import sys
import time

SENTINEL = '{"id":987654,"method":"capabilities"}'


def mask(frame: str) -> str:
    frame = re.sub(r'"pid":\d+', '"pid":0', frame, count=1) if '"type":"hello"' in frame else frame
    frame = re.sub(r'("type":"hello","protocol":1,"version":)"[^"]*"', r'\1"V"', frame)
    # A rate over wall time: only its sign is the same in two runs.
    frame = re.sub(r'"(rxBps|txBps)":(?!-1[,}])[0-9.e+-]+', r'"\1":"N"', frame)
    frame = re.sub(r'("pid":\d+,"user":"[^"]*","cpu":)(?!-1[,}])[0-9.e+-]+', r'\1"N"', frame)
    if re.search(r'"gpuInfo":\{[^}]*"method":"rc6"', frame):
        frame = re.sub(r'("data":\{"cpu":[^,]*,"mem":(?:null|\{[^}]*\}),"gpu":)(?!-1[,}])[0-9.e+-]+', r'\1"N"', frame)
    start = frame.find('"disks":[')
    if start >= 0:
        end = frame.index("]", start)
        disks = re.sub(r'"(totalKiB|usedKiB|availKiB|percent)":[0-9.e+-]+', r'"\1":"N"', frame[start:end])
        frame = frame[:start] + disks + frame[end:]
    return frame


class Player:
    def __init__(self, path: str):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(5)
        self.sock.connect(path)
        self.buf = b""
        self.held: list[str] = []

    def frame(self, timeout: float) -> str | None:
        deadline = time.monotonic() + timeout
        while b"\n" not in self.buf:
            left = deadline - time.monotonic()
            if left <= 0:
                return None
            self.sock.settimeout(left)
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                return None
            if not chunk:
                return None
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return line.decode("utf-8", "replace")

    def flush(self) -> None:
        for f in sorted(self.held):
            print(f)
        self.held = []

    def wait(self, kind: str, n: int, timeout: float = 5.0) -> None:
        seen = 0
        while seen < n:
            f = self.frame(timeout)
            if f is None:
                self.held.append(f"TIMEOUT waiting for {kind} {n}")
                break
            self.held.append(mask(f))
            if f'"type":"{kind}"' in f:
                seen += 1
        self.flush()


def main() -> int:
    path, base, script = sys.argv[1:4]
    p = Player(path)
    hello = p.frame(5)
    print(mask(hello) if hello is not None else "NO HELLO")
    with open(script, encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            step = json.loads(raw)
            if "send" in step:
                p.sock.sendall(step["send"].encode() + b"\n")
            elif "wait" in step:
                p.wait(step["wait"], step.get("n", 1))
            elif "write" in step:
                rel, text = step["write"]
                target = os.path.join(base, rel)
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with open(target, "w", encoding="utf-8") as out:
                    out.write(text)
            elif "sleep" in step:
                time.sleep(step["sleep"] / 1000)
    # Whatever is still on its way: everything up to the sentinel's answer,
    # then a moment for a late event.
    p.sock.sendall(SENTINEL.encode() + b"\n")
    while True:
        f = p.frame(5)
        if f is None:
            p.held.append("TIMEOUT waiting for the sentinel")
            break
        if '"id":987654' in f:
            break
        p.held.append(mask(f))
    while (f := p.frame(0.3)) is not None:
        p.held.append(mask(f))
    p.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
