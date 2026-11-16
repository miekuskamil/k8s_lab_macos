#!/usr/bin/env bash
# OrbStack: deletes the two practice machines and everything in them. Nothing else on OrbStack changes.
# VMs (CKS_PLATFORM=vms): wipes the cluster from both VMs with kubeadm reset and keeps the VMs,
# because they belong to you and their hypervisor. Delete them there when you want them gone.
# Usage: ./certs/cks/cluster/destroy.sh            (asks first)
#        ./certs/cks/cluster/destroy.sh --yes
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/platform.sh"

if [ "$CKS_PLATFORM" = vms ]; then
  if [ "${1:-}" != "--yes" ]; then
    read -r -p "Wipe the cluster from the VMs $CKS_CP_HOST and $CKS_W1_HOST (the VMs stay)? [y/N] " a
    [ "$a" = y ] || [ "$a" = Y ] || { echo "nothing changed"; exit 0; }
  fi
  "$HERE/reset.sh" --wipe-only
  echo "the cluster is gone; the VMs still run, and create.sh builds it again"
  exit 0
fi

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
