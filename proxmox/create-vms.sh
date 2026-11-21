#!/usr/bin/env bash
# Creates the lab's Ubuntu 24.04 VMs on a Proxmox VE host. Run it as root in the
# Proxmox shell (Datacenter > node > Shell, or ssh root@<proxmox>):
#
#   ./create-vms.sh cks              the practice VMs: cks-cp, cks-w1 and the Cilium VM practice-cilium
#   ./create-vms.sh course           the Platform Engineering lab VM: pe-lab
#   ./create-vms.sh all              both sets
#   ./create-vms.sh list             what this script manages, and its state
#   ./create-vms.sh snapshot <set>   a snapshot named clean-<date> of every VM in the set
#   ./create-vms.sh backup <set>     a vzdump backup of every VM in the set to BACKUP_STORAGE
#   ./create-vms.sh destroy <set>    stops and deletes the VMs of the set (asks first)
#
# Safe to run again: a VM that already exists with the expected name is left alone,
# and the script refuses to touch a VMID that belongs to a VM with another name.
# Settings come from the environment; the defaults match the author's homelab:
#   SSH_KEY_FILE=/root/lab_key.pub   public key the VMs accept for user "ubuntu" (required)
#   NET_PREFIX=192.168.1  GATEWAY=192.168.1.1  DNS=1.1.1.1  BRIDGE=vmbr0
#   STORAGE=local-lvm  IMAGE_STORAGE_DIR=/var/lib/vz/import  BACKUP_STORAGE=local
#   DRY_RUN=1   prints the qm commands instead of running them
set -euo pipefail

SSH_KEY_FILE="${SSH_KEY_FILE:-/root/lab_key.pub}"
NET_PREFIX="${NET_PREFIX:-192.168.1}"
GATEWAY="${GATEWAY:-192.168.1.1}"
DNS="${DNS:-1.1.1.1}"
BRIDGE="${BRIDGE:-vmbr0}"
STORAGE="${STORAGE:-local-lvm}"
IMAGE_STORAGE_DIR="${IMAGE_STORAGE_DIR:-/var/lib/vz/import}"
BACKUP_STORAGE="${BACKUP_STORAGE:-local}"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE="$IMAGE_STORAGE_DIR/noble-server-cloudimg-amd64.qcow2"

# One line per VM: set, VMID, name, last octet of the IP, cores, memory in MB, disk size.
VMS="
cks    221 cks-cp 221 2 3072  30G
cks    222 cks-w1 222 2 2560  30G
cks    223 practice-cilium 223 2 3072  30G
course 231 pe-lab 231 4 8192  80G
"

run() { if [ "${DRY_RUN:-0}" = 1 ]; then echo "+ $*"; else "$@"; fi; }
say() { printf '\n=== %s\n' "$*"; }
rows() { echo "$VMS" | awk -v s="$1" 'NF && (s=="all" || $1==s)'; }
vm_name() { { qm config "$1" 2>/dev/null || true; } | awk '/^name:/{print $2}'; }

need_set() {
  case "${1:-}" in cks|course|all) ;; *) echo "name a set: cks, course or all"; exit 1 ;; esac
}

image() {
  if [ ! -s "$IMAGE" ]; then
    say "downloading the Ubuntu 24.04 cloud image"
    run mkdir -p "$IMAGE_STORAGE_DIR"
    run wget -q --show-progress -O "$IMAGE.part" "$IMAGE_URL"
    run mv "$IMAGE.part" "$IMAGE"
  fi
}

create() {
  need_set "$1"
  command -v qm >/dev/null || { echo "qm not found: run this on the Proxmox host as root"; exit 1; }
  [ -s "$SSH_KEY_FILE" ] || { echo "no public key at $SSH_KEY_FILE (set SSH_KEY_FILE)"; exit 1; }
  image
  rows "$1" | while read -r _ id name octet cores mem disk; do
    have="$(vm_name "$id")"
    if [ "$have" = "$name" ]; then
      echo "$id $name exists, leaving it alone"
      continue
    elif [ -n "$have" ]; then
      echo "VMID $id belongs to '$have', not $name: refusing to touch it" >&2
      exit 1
    fi
    if ping -c1 -W1 "$NET_PREFIX.$octet" >/dev/null 2>&1; then
      echo "$NET_PREFIX.$octet already answers on the network: pick another address" >&2
      exit 1
    fi
    say "$id $name: $cores cores, $mem MB, $disk, $NET_PREFIX.$octet"
    run qm create "$id" --name "$name" --ostype l26 --cpu host --cores "$cores" --memory "$mem" \
      --scsihw virtio-scsi-single --net0 "virtio,bridge=$BRIDGE" \
      --serial0 socket --vga serial0 --agent enabled=1 --onboot 0
    run qm set "$id" --scsi0 "$STORAGE:0,import-from=$IMAGE,discard=on,iothread=1"
    run qm resize "$id" scsi0 "$disk"
    run qm set "$id" --ide2 "$STORAGE:cloudinit" --boot order=scsi0 \
      --ciuser ubuntu --sshkeys "$SSH_KEY_FILE" \
      --ipconfig0 "ip=$NET_PREFIX.$octet/24,gw=$GATEWAY" --nameserver "$DNS"
    run qm start "$id"
  done
  say "done"
  echo "The VMs take about a minute to boot. Then: ssh ubuntu@<address>"
}

list() {
  printf '%-6s %-5s %-16s %-16s %s\n' SET VMID NAME ADDRESS STATE
  rows all | while read -r set id name octet _; do
    state="$(qm status "$id" 2>/dev/null | awk '{print $2}')"
    have="$(vm_name "$id")"
    [ -n "$have" ] && [ "$have" != "$name" ] && state="VMID used by $have"
    printf '%-6s %-5s %-16s %-16s %s\n' "$set" "$id" "$name" "$NET_PREFIX.$octet" "${state:-absent}"
  done
}

snapshot() {
  need_set "$1"
  snap="clean-$(date +%Y-%m-%d)"
  rows "$1" | while read -r _ id name _; do
    [ "$(vm_name "$id")" = "$name" ] || continue
    run qm snapshot "$id" "$snap" --description "$name: clean baseline, $(date '+%d %B %Y')"
    echo "$id $name: snapshot $snap"
  done
}

backup() {
  need_set "$1"
  rows "$1" | while read -r _ id name _; do
    [ "$(vm_name "$id")" = "$name" ] || continue
    run vzdump "$id" --storage "$BACKUP_STORAGE" --mode snapshot --compress zstd \
      --notes-template "$name: lab VM backup, $(date '+%d %B %Y')"
  done
}

destroy() {
  need_set "$1"
  ids="$(rows "$1" | while read -r _ id name _; do [ "$(vm_name "$id")" = "$name" ] && echo "$id"; done | xargs)"
  [ -n "$ids" ] || { echo "nothing to delete"; return; }
  read -r -p "Delete VMs $ids and their disks? Type yes: " ok
  [ "$ok" = yes ] || { echo "kept"; return; }
  for id in $ids; do
    run qm stop "$id" >/dev/null 2>&1 || true
    run qm destroy "$id" --purge
  done
}

case "${1:-}" in
  cks|course|all) create "$1" ;;
  list) list ;;
  snapshot|backup|destroy) "$1" "${2:-}" ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
