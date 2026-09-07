import http.server
import time

DATA = bytes(range(64))

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path.startswith('/failed'):
            self.send_error(503)
            return
        if self.path.startswith('/slow'):
            time.sleep(2)
        start, end = map(int, self.headers['Range'].removeprefix('bytes=').split('-'))
        if self.path.startswith('/pause') and start >= 16:
            time.sleep(2)
        body = DATA[start:end + 1]
        if self.path.startswith('/corrupt'):
            body = bytes([255] * len(body))
        reported_start = 0 if self.path.startswith('/wrong-range') else start
        self.send_response(206)
        self.send_header('Content-Range', f'bytes {reported_start}-{end}/{len(DATA)}')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
