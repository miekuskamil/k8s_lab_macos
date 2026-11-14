#!/usr/bin/env bash
# Deletes the two practice machines and everything in them. Nothing else on OrbStack changes.
# Usage: ./certs/cks/cluster/destroy.sh            (asks first)
#        ./certs/cks/cluster/destroy.sh --yes
set -euo pipefail

if [ "${1:-}" != "--yes" ]; then
  read -r -p "Delete the OrbStack machines cks-cp and cks-w1? [y/N] " a
  [ "$a" = y ] || [ "$a" = Y ] || { echo "nothing deleted"; exit 0; }
fi
for m in cks-w1 cks-cp; do
  if orb list | awk '{print $1}' | grep -qx "$m"; then
    orb delete -f "$m"
    echo "deleted $m"
  else
    echo "$m does not exist"
  fi
done
