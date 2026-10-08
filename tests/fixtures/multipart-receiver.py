#!/usr/bin/env python3
"""Fixture-only HTTP receiver for tests/test-capture-upload.sh.

Usage: multipart-receiver.py PORT_FILE LOG_FILE [--redirect URL] [--tls CERT KEY]

Binds 127.0.0.1 on an ephemeral port (written to PORT_FILE), parses every
multipart POST with the standard library and appends one JSON line per
request to LOG_FILE: the path and each leaf part's field name, filename,
sha256 and (for parts without a filename) its text value. It answers in the
shape each uploader backend reads, so the real curl, not a stub, decides what
is sent. With --redirect every POST is answered 307 to URL instead (a client
that follows replays its body there); with --tls it speaks HTTPS with that
certificate. A request through it as a proxy logs the absolute URL as its
path. Nothing leaves the loopback interface. Every wait is bounded: a
connection idle for CONN_TIMEOUT seconds is dropped (the TLS handshake
included, so one stalled client cannot block the accept loop) and the
process exits on its own after LIFETIME seconds, so a test that aborts
before it kills the receiver cannot leave it running.
"""
import email.parser
import email.policy
import hashlib
import json
import os
import ssl
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT_FILE, LOG_FILE = sys.argv[1], sys.argv[2]
REDIRECT = sys.argv[sys.argv.index('--redirect') + 1] if '--redirect' in sys.argv else None
TLS = sys.argv[sys.argv.index('--tls') + 1:sys.argv.index('--tls') + 3] if '--tls' in sys.argv else None
LINK = 'https://share.example.com/r/fixture.png'
CONN_TIMEOUT = 10
LIFETIME = 300


class Handler(BaseHTTPRequestHandler):
    timeout = CONN_TIMEOUT

    def log_message(self, *args):
        pass

    def do_GET(self):
        # The XBackBone api probe: a tagged release has no such route.
        self.send_response(404)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        message = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
            b'Content-Type: ' + self.headers.get('Content-Type', '').encode() + b'\r\n\r\n' + body)
        parts = []
        for part in message.walk():
            if part.is_multipart():
                continue
            payload = part.get_payload(decode=True) or b''
            row = {'name': part.get_param('name', header='content-disposition'),
                   'filename': part.get_filename(),
                   'sha256': hashlib.sha256(payload).hexdigest()}
            if row['filename'] is None:
                row['value'] = payload.decode('utf-8', 'replace')
            parts.append(row)
        with open(LOG_FILE, 'a', encoding='utf-8') as log:
            log.write(json.dumps({'path': self.path, 'parts': parts}) + '\n')
        if self.path.startswith('/api/v1/upload'):
            answer = json.dumps({'data': {'raw_url': LINK}})
        elif self.path.startswith('/3/image'):
            answer = json.dumps({'data': {'link': LINK, 'deletehash': 'fixture-deletehash'}})
        else:
            answer = LINK
        data = answer.encode()
        if REDIRECT:
            self.send_response(307)
            self.send_header('Location', REDIRECT)
        else:
            self.send_response(200)
        self.send_header('X-Token', 'fixture-management-token')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
server.daemon_threads = True
if TLS:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(TLS[0], TLS[1])
    # The handshake runs on the first read in the handler thread, under its
    # timeout, not inside accept() on the serving thread.
    server.socket = context.wrap_socket(server.socket, server_side=True,
                                        do_handshake_on_connect=False)
watchdog = threading.Timer(LIFETIME, os._exit, args=(3,))
watchdog.daemon = True
watchdog.start()
# Publish the port only once it is bound (rename is atomic).
with open(PORT_FILE + '.new', 'w', encoding='ascii') as stream:
    stream.write(str(server.server_address[1]))
os.replace(PORT_FILE + '.new', PORT_FILE)
server.serve_forever()
