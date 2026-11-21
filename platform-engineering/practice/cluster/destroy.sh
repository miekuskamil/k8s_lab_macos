#!/usr/bin/env bash
# kind (the default): deletes the two node containers and the registry container. The node image
# stays in Docker's cache, so the next ./lab.sh practice up skips the build. ./lab.sh practice down runs this.
# OrbStack: deletes the two practice machines and everything in them. Nothing else on OrbStack changes.
# VMs (PRACTICE_PLATFORM=vms): wipes the cluster from both VMs with kubeadm reset and keeps the VMs,
# because they belong to you and their hypervisor. Delete them there when you want them gone.
# Usage: ./platform-engineering/practice/cluster/destroy.sh            (asks first)
#        ./platform-engineering/practice/cluster/destroy.sh --yes
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/platform.sh"

if [ "$PRACTICE_PLATFORM" = kind ]; then
  if [ "${1:-}" != "--yes" ]; then
    read -r -p "Delete the kind cluster $PRACTICE_KIND_NAME ($CP, $W1) and the registry container? [y/N] " a
    [ "$a" = y ] || [ "$a" = Y ] || { echo "nothing deleted"; exit 0; }
  fi
  exec "$HERE/kind/kind.sh" destroy
fi

if [ "$PRACTICE_PLATFORM" = vms ]; then
  if [ "${1:-}" != "--yes" ]; then
    read -r -p "Wipe the cluster from the VMs $PRACTICE_CP_HOST and $PRACTICE_W1_HOST (the VMs stay)? [y/N] " a
    [ "$a" = y ] || [ "$a" = Y ] || { echo "nothing changed"; exit 0; }
  fi
  "$HERE/reset.sh" --wipe-only
  echo "the cluster is gone; the VMs still run, and create.sh builds it again"
  exit 0
fi

if [ "${1:-}" != "--yes" ]; then
  read -r -p "Delete the OrbStack machines $CP and $W1? [y/N] " a
  [ "$a" = y ] || [ "$a" = Y ] || { echo "nothing deleted"; exit 0; }
fi
for m in "$W1" "$CP"; do
  if orb list | awk '{print $1}' | grep -qx "$m"; then
    orb delete -f "$m"
    echo "deleted $m"
  else
    echo "$m does not exist"
  fi
done
