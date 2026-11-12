#!/usr/bin/env bash
# Make the lab's JWT signing key, its public JWKS and four test tokens for module 13.
# The repository already contains the output. Run this only to make new ones.
# Needs openssl and python3 (standard library only).
set -euo pipefail
cd "$(dirname "$0")"

openssl genrsa -out signing-key.pem 2048 2>/dev/null       # the lab "identity provider" key
openssl genrsa -out wrong-key.pem 2048 2>/dev/null         # a key nobody trusts

python3 -I - <<'PY'
import base64, json, subprocess, time

def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

def modulus(path: str) -> bytes:
    hexmod = subprocess.check_output(["openssl", "rsa", "-in", path, "-noout", "-modulus"]).decode().strip().split("=")[1]
    return bytes.fromhex(hexmod)

jwks = {"keys": [{"kty": "RSA", "alg": "RS256", "use": "sig", "kid": "k8s-lab-1",
                  "n": b64(modulus("signing-key.pem")), "e": b64((65537).to_bytes(3, "big"))}]}
open("jwks.json", "w").write(json.dumps(jwks, indent=2) + "\n")

def token(claims: dict, key: str) -> str:
    header = {"alg": "RS256", "typ": "JWT", "kid": "k8s-lab-1"}
    signing_input = b64(json.dumps(header, separators=(",", ":")).encode()) + "." + b64(json.dumps(claims, separators=(",", ":")).encode())
    sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key], input=signing_input.encode(), capture_output=True, check=True).stdout
    return signing_input + "." + b64(sig)

now = int(time.time())
ten_years = now + 10 * 365 * 24 * 3600
base = {"iss": "https://idp.k8s-lab.local", "aud": "shop"}
tokens = {
    "alice.jwt":   token({**base, "sub": "alice", "groups": ["customers"], "iat": now, "exp": ten_years}, "signing-key.pem"),
    "admin.jwt":   token({**base, "sub": "bob", "groups": ["customers", "admin"], "iat": now, "exp": ten_years}, "signing-key.pem"),
    "expired.jwt": token({**base, "sub": "alice", "groups": ["customers"], "iat": now - 7200, "exp": now - 3600}, "signing-key.pem"),
    "forged.jwt":  token({**base, "sub": "mallory", "groups": ["admin"], "iat": now, "exp": ten_years}, "wrong-key.pem"),
}
for name, value in tokens.items():
    open(name, "w").write(value + "\n")
PY
rm -f wrong-key.pem
echo "wrote jwks.json, alice.jwt, admin.jwt, expired.jwt, forged.jwt"
