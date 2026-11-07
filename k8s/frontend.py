"""Frontend: for every request calls the backend through its Service and shows which pods/nodes answered."""
import json
import os
import signal
import sys
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BACKEND_URL = os.environ.get("BACKEND_URL", "http://backend:8000")  # Service name -> cluster DNS -> one backend pod


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            text = "ok"
        else:
            try:
                with urllib.request.urlopen(BACKEND_URL, timeout=2) as r:
                    b = json.load(r)
                text = (f"frontend {os.environ['HOSTNAME']} on {os.environ.get('NODE_NAME', '?')}\n"
                        f"  -> backend {b['pod']} on {b['node']} (v{b['version']}): {b['message']}\n")
            except OSError as e:  # backend down - say so instead of crashing
                text = f"frontend {os.environ['HOSTNAME']}: backend unavailable ({e})\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(text.encode())


# PID 1 ignores SIGTERM by default -> Kubernetes would wait 30 s (grace period) before killing an old pod
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
ThreadingHTTPServer(("", 8080), Handler).serve_forever()
