# The lab on Proxmox

`create-vms.sh` creates the lab's Ubuntu 24.04 VMs on a Proxmox VE host from the official cloud image, with cloud-init setting the user, the SSH key and a fixed address. You run it as root in the Proxmox shell, so it needs no API token and nothing installed on your laptop.

| Set | VMID | Name | Address | CPU | Memory | Disk |
|---|---|---|---|---|---|---|
| cks | 221 | cks-cp | 192.168.1.221 | 2 | 3 GB | 30 GB |
| cks | 222 | cks-w1 | 192.168.1.222 | 2 | 2.5 GB | 30 GB |
| course | 231 | pe-lab | 192.168.1.231 | 4 | 10 GB | 60 GB |

## Create the VMs

1. On your laptop, make a key pair for the lab if you have none: `ssh-keygen -t ed25519 -f ~/.ssh/cks_proxmox`.
2. Copy the script and the public key to the Proxmox host:

   ```bash
   scp proxmox/create-vms.sh ~/.ssh/cks_proxmox.pub root@192.168.1.250:/root/
   ```

3. In the Proxmox shell, as root:

   ```bash
   SSH_KEY_FILE=/root/cks_proxmox.pub ./create-vms.sh cks
   ./create-vms.sh list
   ```

4. After about a minute, log in from your laptop: `ssh -i ~/.ssh/cks_proxmox ubuntu@192.168.1.221`.

The addresses, the bridge and the storage match one homelab. Set `NET_PREFIX`, `GATEWAY`, `BRIDGE` and `STORAGE` for yours, and run with `DRY_RUN=1` first to see every `qm` command before it runs. Before it creates a VM, the script checks that the address is free on the network. It never touches a VMID that belongs to a VM with another name, so the VMs you already run stay safe.

## Snapshots and backups

```bash
./create-vms.sh snapshot cks     # instant rollback point named clean-<date>
./create-vms.sh backup cks       # vzdump to the "local" storage, compressed with zstd
./create-vms.sh destroy cks      # asks before it deletes anything
```

## Memory

The CKS set uses 5.5 GB and the course VM 10 GB. On a host with 16 GB that already runs other VMs, start one set at a time: `qm stop 221 222` before `qm start 231`.
