#!/usr/bin/env bash
# Remove everything provision.sh created. Asks for confirmation unless you pass --yes.
set -euo pipefail

if [[ "${1:-}" != "--yes" ]]; then
  if [[ ! -t 0 ]]; then
    echo "No terminal to ask for confirmation. Run ./scripts/teardown.sh --yes to delete without asking." >&2
    exit 1
  fi
  read -r -p "Delete the k3d cluster ${CLUSTER_NAME:-k8s-lab} and everything in it? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

k3d cluster delete "${CLUSTER_NAME:-k8s-lab}"
echo "Done. The Docker images k8s-lab/backend and k8s-lab/frontend stay in your local Docker store."
