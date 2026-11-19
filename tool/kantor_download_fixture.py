"""Local-only slow/404 Android download fixture; no real Kantor data."""
import hashlib
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CHUNK = bytes(range(256)) * 256
SIZE = 8 * 1024 * 1024


class Fixture(BaseHTTPRequestHandler):
    retry_requests = 0

    def do_GET(self):
        attachment = self.path.startswith('/api/attachments/fixture-') and self.path.endswith('/raw')
        if attachment:
            if self.headers.get('Authorization') != 'Bearer fixture-only':
                self.send_error(401)
                return
            if self.path == '/api/attachments/fixture-retry/raw':
                Fixture.retry_requests += 1
                if Fixture.retry_requests == 1:
                    self.send_error(404)
                    return
        if self.path.endswith('/missing-test.bin'):
            self.send_error(404)
            return
        if not attachment and not self.path.startswith('/pv/fixture/key/'):
            self.send_error(404)
            return
        size = 262144 if self.path == '/api/attachments/fixture-retry/raw' else SIZE
        start = 0
        if self.headers.get('Range'):
            start = int(self.headers['Range'].split('=')[1].split('-')[0])
        self.send_response(206 if start else 200)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(size - start))
        self.send_header('Accept-Ranges', 'bytes')
        if start:
            self.send_header('Content-Range', f'bytes {start}-{size - 1}/{size}')
        self.end_headers()
        try:
            for offset in range(start, size, len(CHUNK)):
                self.wfile.write(CHUNK[: min(len(CHUNK), size - offset)])
                self.wfile.flush()
                time.sleep(.25)
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == '__main__':
    print('Fixture size:', SIZE, 'SHA256:', hashlib.sha256(CHUNK * (SIZE // len(CHUNK))).hexdigest(), flush=True)
    ThreadingHTTPServer(('127.0.0.1', 18376), Fixture).serve_forever()
