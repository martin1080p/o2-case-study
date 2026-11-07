"""Backend: answers with a greeting and where it runs (pod, node, version). Stdlib only."""
import json
import os
import signal
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":  # readinessProbe: the Service sends traffic only to ready pods
            body = b"ok"
        else:
            body = json.dumps({
                "message": "Hello from the backend",
                "version": os.environ["VERSION"],  # baked into the image - changes with a rolling update
                "pod": os.environ["HOSTNAME"],  # Kubernetes sets HOSTNAME to the pod name
                "node": os.environ.get("NODE_NAME", "?"),  # from the Deployment (downward API)
            }).encode()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)


# PID 1 ignores SIGTERM by default -> Kubernetes would wait 30 s (grace period) before killing an old pod
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
ThreadingHTTPServer(("", 8000), Handler).serve_forever()
