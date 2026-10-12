#!/usr/bin/env python3
"""Bound the abuse suite's FIFO barrier and own every race subprocess.

The FIFOs are opened read/write and nonblocking before starting the partner:
Bash's `read -t ... <fifo` does not bound the preceding blocking open. All
children use private process groups and file-backed stdio, never the suite's
output-capture pipe. Cleanup kills descendants even if their leader exited.
"""
import argparse
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time


def interrupted(signum, _frame):
    raise RuntimeError(f'race supervisor interrupted by signal {signum}')


def race(args):
    sandbox = Path(args.sandbox)
    processes, descriptors, fifos = [], [], []

    def start(operation, label):
        with (sandbox / f'{label}.out').open('wb') as output:
            process = subprocess.Popen(
                ['bash', args.runner, operation, '--yes'],
                stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        processes.append(process)
        return process

    def finish(process, label):
        try:
            status = process.wait(timeout=args.process_timeout)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f'{label} timed out after {args.process_timeout:g}s') from error
        (sandbox / f'{label}.status').write_text(f'{status}\n')
        return status

    try:
        for name in ('ready', 'release'):
            fifo = sandbox / name
            os.mkfifo(fifo)
            fifos.append(fifo)
            descriptors.append(os.open(fifo, os.O_RDWR | os.O_NONBLOCK))
        ready, release = descriptors
        first = start('repo-enable', 'first')
        deadline = time.monotonic() + args.handshake_timeout
        with selectors.DefaultSelector() as selector:
            selector.register(ready, selectors.EVENT_READ)
            message = b''
            while b'\n' not in message:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise RuntimeError(f'approval readiness handshake timed out after {args.handshake_timeout:g}s')
                if selector.select(min(remaining, 0.05)):
                    message += os.read(ready, 4096)
                elif first.poll() is not None:
                    raise RuntimeError(f'approval partner exited before readiness handshake (exit {first.returncode})')
            if message != b'ready\n':
                raise RuntimeError(f'invalid approval readiness handshake: {message!r}')
        challenger = start(args.operation, 'challenger')
        finish(challenger, 'challenger')
        if first.poll() is not None:
            raise RuntimeError(f'approval partner exited before release handshake (exit {first.returncode})')
        # One tiny nonblocking write: neither opening nor writing can stall.
        if os.write(release, b'release\n') != len(b'release\n'):
            raise RuntimeError('incomplete approval release handshake')
        finish(first, 'first')
    finally:
        for process in processes:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        for process in processes:
            process.wait(timeout=2)
        for descriptor in descriptors:
            os.close(descriptor)
        for fifo in fifos:
            fifo.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sandbox')
    parser.add_argument('runner')
    parser.add_argument('operation', choices=('repo-disable', 'repo-enable'))
    parser.add_argument('--handshake-timeout', type=float, default=20)
    parser.add_argument('--process-timeout', type=float, default=60)
    args = parser.parse_args()
    if args.handshake_timeout <= 0 or args.process_timeout <= 0:
        parser.error('timeouts must be positive')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        race(args)
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'FAIL abuse race: {error}', file=sys.stderr)
        first_output = Path(args.sandbox) / 'first.out'
        if first_output.exists():
            print(first_output.read_text(errors='replace')[:4000], file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
