#!/usr/bin/env bash
# Runs as root when the toolbox container starts, then hands over to its command (sleep).
# 1. Creates the user "lab" with your uid and gid, so files it writes in the repo stay yours.
# 2. Lets that user talk to the Docker socket, whatever group owns the socket on this host.
# 3. Forwards a few localhost ports to the host, because the scripts expect the shop on
#    localhost:8080 and Ollama on localhost:11434, as they are on the host itself.
# 4. Writes kubeconfig entries for the clusters that already exist (kube-sync.sh).
set -euo pipefail
rm -f /run/lab-ready

uid="${HOST_UID:-1000}" gid="${HOST_GID:-1000}"
group="$(getent group "$gid" | cut -d: -f1 || true)"
if [[ -z "$group" ]]; then groupadd -g "$gid" lab; group=lab; fi
if ! id lab >/dev/null 2>&1; then
  useradd -o -u "$uid" -g "$gid" -d /home/lab -s /bin/bash lab 2>/dev/null
fi
sock=/var/run/docker.sock
if [[ -S "$sock" ]]; then
  sgid="$(stat -c %g "$sock")"
  sgroup="$(getent group "$sgid" | cut -d: -f1 || true)"
  if [[ -z "$sgroup" ]]; then groupadd -g "$sgid" docker-host; sgroup=docker-host; fi
  usermod -aG "$sgroup" lab
fi
mkdir -p /home/lab/.kube
chown "$uid:$gid" /home/lab /home/lab/.kube

forward() {   # forward <local port> <target host:port>
  socat "TCP-LISTEN:$1,bind=127.0.0.1,fork,reuseaddr" "TCP:$2" 2>/dev/null &
}
forward 8080 host.docker.internal:8080                     # the shop, through the k3d load balancer
forward 8443 host.docker.internal:8443                     # the shop over HTTPS (module 3.10)
forward 11434 host.docker.internal:11434                   # Ollama on the host, or the ollama service
forward 30080 "${PRACTICE_KIND_NAME:-practice}-control-plane:30080"   # the practice cluster's ingress
forward 30443 "${PRACTICE_KIND_NAME:-practice}-control-plane:30443"
forward 5555 course-registry:5000                          # the Docker track's registry (module 0.2)

su lab -c /usr/local/lib/lab/kube-sync.sh || echo "kube-sync failed; run it again with: kube-sync" >&2
touch /run/lab-ready     # lab.sh waits for this file before it runs commands here
exec "$@"
