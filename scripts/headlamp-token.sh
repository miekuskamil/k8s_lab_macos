#!/usr/bin/env bash
# Print the Headlamp login token and copy it to the clipboard when possible.
# Always reads from the lab cluster, even if OrbStack switched kubectl to its own context.
set -euo pipefail

CONTEXT="k3d-${CLUSTER_NAME:-k8s-lab}"
token="$(kubectl --context "$CONTEXT" -n headlamp get secret headlamp-admin -o jsonpath='{.data.token}' | base64 -d)"
if [[ -z "$token" ]]; then
  echo "No token yet. Check: kubectl --context $CONTEXT -n headlamp get secret headlamp-admin" >&2
  exit 1
fi

printf '%s\n' "$token"
if command -v pbcopy >/dev/null; then
  printf '%s' "$token" | pbcopy && echo "(copied to the clipboard)" >&2
elif command -v wl-copy >/dev/null; then
  printf '%s' "$token" | wl-copy && echo "(copied to the clipboard)" >&2
elif command -v xclip >/dev/null; then
  printf '%s' "$token" | xclip -selection clipboard && echo "(copied to the clipboard)" >&2
fi
