"""Tiny demo web app for the ECS Fargate project. Standard library only,
so the container image stays small and has nothing to patch."""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", "8080"))

# Which region is serving. Set by the ECS task definition, so after a failover
# the response shows that the DR region is answering.
REGION = os.environ.get("APP_REGION", "unknown")

# ECS injects this from Secrets Manager. We report only WHETHER it was loaded,
# never its value, so the secret can never leak through the app.
SECRET_LOADED = bool(os.environ.get("APP_SECRET"))


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            # Used by the load balancer and the container health check.
            self._send(200, {"status": "ok"})
        elif self.path == "/":
            self._send(200, {"service": "demo-app", "region": REGION, "secret_loaded": SECRET_LOADED})
        else:
            self._send(404, {"error": "not found"})


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
