"""Local-only slow/404 Android download fixture; no real Kantor data."""
import hashlib
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CHUNK = bytes(range(256)) * 256
SIZE = 8 * 1024 * 1024


class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.endswith('/missing-test.bin'):
            self.send_error(404)
            return
        if not self.path.startswith('/pv/fixture/key/'):
            self.send_error(404)
            return
        start = 0
        if self.headers.get('Range'):
            start = int(self.headers['Range'].split('=')[1].split('-')[0])
        self.send_response(206 if start else 200)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(SIZE - start))
        self.send_header('Accept-Ranges', 'bytes')
        if start:
            self.send_header('Content-Range', f'bytes {start}-{SIZE - 1}/{SIZE}')
        self.end_headers()
        try:
            for offset in range(start, SIZE, len(CHUNK)):
                self.wfile.write(CHUNK[: min(len(CHUNK), SIZE - offset)])
                self.wfile.flush()
                time.sleep(.25)
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == '__main__':
    print('Fixture size:', SIZE, 'SHA256:', hashlib.sha256(CHUNK * (SIZE // len(CHUNK))).hexdigest(), flush=True)
    ThreadingHTTPServer(('127.0.0.1', 18376), Fixture).serve_forever()
