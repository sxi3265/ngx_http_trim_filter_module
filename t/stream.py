"""Exercise the nginx filter with chunked producers and a slow consumer."""
import hashlib
import http.client
import http.server
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import tempfile
import threading
import time


def unused_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


cases = [
    ('<p  >hello   world</p><!--remove-->', '<p>hello   world</p>'),
    ('<title>a <!--keep--> b</title>', '<title>a <!--keep--> b</title>'),
    ('<script>const x = `a // b`;</script>', '<script>const x = `a // b`;</script>'),
    ('<script>var/**/x = 1;</script>', '<script>var/**/x = 1;</script>'),
    ('<style>.x { --pair: a/**/b; }</style>', '<style>.x { --pair: a/**/b; }</style>'),
    ('<p>x</p><', '<p>x</p><'),
    ('<p>x</p><!-', '<p>x</p><!-'),
    ('<!--remove-->', ''),
    ('<p  title="' + 'x' * 5000 + '">a  b<!--keep--></p>',
     '<p  title="' + 'x' * 5000 + '">a  b<!--keep--></p>'),
]
piece = b'<p  id = "x">hello   world</p><!--drop-->'
trimmed_piece = b'<p id="x">hello   world</p>'
repetitions = 160000


class Backend(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def do_GET(self):
        if self.path == '/large':
            data = piece * repetitions
            step, delay = 4096, 0
        elif self.path == '/slow':
            data = b'<p>first</p><p>second</p>'
            step, delay = 11, 0.3
        else:
            data = cases[int(self.path[1:])][0].encode()
            step, delay = (1, 0.001) if len(data) < 100 else (137, 0)
        self.connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Transfer-Encoding', 'chunked')
        self.end_headers()
        for off in range(0, len(data), step):
            if off and delay:
                time.sleep(delay)
            chunk = data[off:off + step]
            self.wfile.write(f'{len(chunk):x}\r\n'.encode() + chunk + b'\r\n')
            self.wfile.flush()
        self.wfile.write(b'0\r\n\r\n')
        self.wfile.flush()

    def log_message(self, *args):
        pass


backend = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Backend)
threading.Thread(target=backend.serve_forever, daemon=True).start()
port = unused_port()
binary = os.environ['TEST_NGINX_BINARY']
modules = ''.join(f'load_module {p};\n' for p in
                  shlex.split(os.environ.get('TEST_NGINX_LOAD_MODULES', '')))

with tempfile.TemporaryDirectory(prefix='trim-stream-') as directory:
    root = Path(directory)
    (root / 'logs').mkdir()
    user = 'user root;' if os.geteuid() == 0 else ''
    config = modules + f'''
{user}
daemon off;
master_process off;
error_log {root}/error.log notice;
pid {root}/nginx.pid;
events {{}}
http {{
    access_log off;
    server {{
        listen 127.0.0.1:{port};
        trim on;
        trim_js on;
        trim_css on;
        location / {{
            proxy_buffering off;
            proxy_pass http://127.0.0.1:{backend.server_port};
        }}
    }}
}}
'''
    (root / 'nginx.conf').write_text(config)
    process = subprocess.Popen([binary, '-p', directory + '/', '-c', str(root / 'nginx.conf')])
    try:
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError((root / 'error.log').read_text())
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=1):
                    break
            except ConnectionRefusedError:
                time.sleep(0.05)
        for i, (_, expected) in enumerate(cases):
            connection = http.client.HTTPConnection('127.0.0.1', port, timeout=10)
            connection.request('GET', f'/{i}')
            response = connection.getresponse()
            body = response.read().decode()
            assert response.status == 200 and body == expected, (i, body, expected)
            connection.close()
        connection = http.client.HTTPConnection('127.0.0.1', port, timeout=10)
        start = time.monotonic()
        connection.request('GET', '/slow')
        response = connection.getresponse()
        first = response.read(1)
        first_at = time.monotonic() - start
        assert first_at < 0.45, first_at
        assert first + response.read() == b'<p>first</p><p>second</p>'
        connection.close()

        connection = http.client.HTTPConnection('127.0.0.1', port, timeout=20)
        connection.connect()
        connection.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 32768)
        connection.request('GET', '/large')
        response = connection.getresponse()
        digest = hashlib.sha256()
        length = 0
        while True:
            chunk = response.read(4096)
            if not chunk:
                break
            digest.update(chunk)
            length += len(chunk)
            time.sleep(0.001)
        expected = trimmed_piece * repetitions
        assert length == len(expected), (length, len(expected))
        assert digest.digest() == hashlib.sha256(expected).digest()
        connection.close()
        log = (root / 'error.log').read_text()
        assert '[alert]' not in log and '[crit]' not in log, log
        print(json.dumps({'chunked_cases': len(cases), 'first_body_ms': round(first_at * 1000, 2),
                          'backpressure_input_bytes': len(piece) * repetitions,
                          'backpressure_output_bytes': length}))
    finally:
        process.terminate()
        process.wait(timeout=10)
        backend.shutdown()
