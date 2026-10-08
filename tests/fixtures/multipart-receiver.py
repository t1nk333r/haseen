#!/usr/bin/env python3
"""Fixture-only HTTP receiver for tests/test-capture-upload.sh.

Binds 127.0.0.1 on an ephemeral port (written to PORT_FILE), parses every
multipart POST with the standard library and appends one JSON line per
request to LOG_FILE: the path and each leaf part's field name, filename,
sha256 and (for parts without a filename) its text value. It answers in the
shape each uploader backend reads, so the real curl, not a stub, decides what
is sent. Nothing leaves the loopback interface.
"""
import email.parser
import email.policy
import hashlib
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT_FILE, LOG_FILE = sys.argv[1], sys.argv[2]
LINK = 'https://share.example.com/r/fixture.png'


class Handler(BaseHTTPRequestHandler):
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
        self.send_response(200)
        self.send_header('X-Token', 'fixture-management-token')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
# Publish the port only once it is bound (rename is atomic).
with open(PORT_FILE + '.new', 'w', encoding='ascii') as stream:
    stream.write(str(server.server_address[1]))
os.replace(PORT_FILE + '.new', PORT_FILE)
server.serve_forever()
