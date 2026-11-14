#!/usr/bin/env python3
"""A tiny ImagePolicyWebhook back end for the CKS practice cluster.

The API server POSTs an ImageReview for every new pod. This server allows the pod
only if every image comes from an allowed registry prefix and has a tag other than
"latest" (or a digest). It listens on https://localhost:8443 on cks-cp.

Allowed prefixes come from /etc/image-policy/allowed-registries, one per line.
"""
import json
import ssl
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

CONF = "/etc/image-policy"


def allowed_prefixes():
    with open(f"{CONF}/allowed-registries") as f:
        return [l.strip() for l in f if l.strip() and not l.startswith("#")]


def normalize(img):
    """Expand short names the way container runtimes do: busybox:1.36 -> docker.io/library/busybox:1.36."""
    first = img.split("/", 1)[0]
    if "/" not in img:
        return "docker.io/library/" + img
    if "." not in first and ":" not in first and first != "localhost":
        return "docker.io/" + img
    return img


def verdict(images):
    prefixes = allowed_prefixes()
    for img in map(normalize, images):
        if not any(img.startswith(p) for p in prefixes):
            return False, f"image {img} is not from an allowed registry"
        if "@sha256:" not in img:
            name = img.rsplit("/", 1)[-1]
            if ":" not in name or name.endswith(":latest"):
                return False, f"image {img} has no tag or uses latest"
    return True, ""


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        images = [c.get("image", "") for c in body.get("spec", {}).get("containers", [])]
        ok, reason = verdict(images)
        body["status"] = {"allowed": ok}
        if reason:
            body["status"]["reason"] = reason
        print(f"{'ALLOW' if ok else 'DENY '} {images} {reason}", flush=True)
        out = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8443
    httpd = HTTPServer(("127.0.0.1", port), Handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(f"{CONF}/server.crt", f"{CONF}/server.key")
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    httpd.serve_forever()
