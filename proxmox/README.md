# The lab on Proxmox

`create-vms.sh` creates the lab's Ubuntu 24.04 VMs on a Proxmox VE host from the official cloud image, with cloud-init setting the user, the SSH key and a fixed address. You run it as root in the Proxmox shell, so it needs no API token and nothing installed on your laptop.

| Set | VMID | Name | Address | CPU | Memory | Disk |
|---|---|---|---|---|---|---|
| cks | 221 | cks-cp | 192.168.1.221 | 2 | 3 GB | 30 GB |
| cks | 222 | cks-w1 | 192.168.1.222 | 2 | 2.5 GB | 30 GB |
| course | 231 | pe-lab | 192.168.1.231 | 4 | 8 GB | 60 GB |

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

## Platform Engineering course

The course runs on one VM, pe-lab, which holds the whole lab: Docker Engine, the k3d cluster, Istio and every tool the modules use. Two scripts set it up. `install-lab.sh` runs on the VM, installs everything that the [Linux section of the guide](../README.md#linux) describes, and then runs `./scripts/provision.sh`. `pe-lab.sh` runs on your Mac, copies the installer to the VM over SSH, and later opens the lab's web UIs on your Mac.

### 1. Create the VM

Copy the script and your public key to the Proxmox host as in [Create the VMs](#create-the-vms), then run this in the Proxmox shell:

```bash
qm stop 221 222                                   # free the memory the CKS VMs hold
SSH_KEY_FILE=/root/cks_proxmox.pub ./create-vms.sh course
```

The script creates VM 231 with 4 cores, 8 GB of memory and a 60 GB disk at 192.168.1.231. After about a minute, `ssh -i ~/.ssh/cks_proxmox ubuntu@192.168.1.231` logs you in.

### 2. Install the lab

From the repository on your Mac:

```bash
./proxmox/pe-lab.sh install                 # the course without the AI modules
./proxmox/pe-lab.sh install --with-ollama   # also Ollama and its two models, for modules 17, 18, 19 and 27
```

The installer downloads each tool at the version that the [Linux section of the guide](../README.md#linux) lists and compares it with the checksum its project publishes, so a broken or tampered download stops the run before it installs anything. It then adds `ubuntu` to the docker group, raises the inotify limits for good, clones the repository into `~/k8s_lab_macos` and runs `provision.sh`. A second run skips every step it already finished, and on an existing clone it pulls the latest commits first.

Without the wrapper, the same thing takes two commands:

```bash
scp -i ~/.ssh/cks_proxmox proxmox/install-lab.sh ubuntu@192.168.1.231:
ssh -i ~/.ssh/cks_proxmox ubuntu@192.168.1.231 ./install-lab.sh
```

To try a branch that is not on GitHub yet, `./proxmox/pe-lab.sh install --from-checkout` ships your current branch to the VM as a Git bundle and runs the installer from that checkout. ArgoCD still deploys from `main` on GitHub, so only the scripts and the course text come from your branch.

### 3. Open the UIs

```bash
./proxmox/pe-lab.sh ui
```

The command opens one SSH session that runs `scripts/port-forward.sh` on the VM and forwards each port to the same port on your Mac, so http://localhost:8080 shows the shop and http://localhost:3000 shows Grafana, exactly as the course text says. The [main README](../README.md#logins-and-addresses) lists every address and password, and Ctrl-C closes them all. The Mac's own lab uses the same ports, and the wrapper refuses to start while a port is busy, so either stop the local lab with `k3d cluster stop k8s-lab` or run `PE_LAB_PORT_OFFSET=10000 ./proxmox/pe-lab.sh ui` to move the VM's UIs to http://localhost:18080, http://localhost:13000 and so on. The plain SSH form is:

```bash
ssh -i ~/.ssh/cks_proxmox -L 8080:localhost:8080 -L 8443:localhost:8443 -L 8081:localhost:8081 \
  -L 3000:localhost:3000 -L 9090:localhost:9090 -L 9093:localhost:9093 -L 16686:localhost:16686 \
  -L 20001:localhost:20001 -L 4466:localhost:4466 ubuntu@192.168.1.231 k8s_lab_macos/scripts/port-forward.sh
```

The forwards keep the UIs off your home network. Kiali and Headlamp have no login and Headlamp acts as `cluster-admin`, so publishing the cluster's ports on the VM's LAN address would hand the whole cluster to anyone on the network.

Everything else in the course runs in a shell on the VM: `./proxmox/pe-lab.sh ssh`, then `cd k8s_lab_macos`.

### Test results

On the real pe-lab VM (amd64, 8 GB) on 16 November 2026, `pe-lab.sh install` finished in 219 seconds, 206 of them in `provision.sh`, and all 12 ArgoCD applications came up Synced and Healthy. Cloud-init's first-boot upgrade stalled before that, because plain-HTTP apt downloads hang on this network while HTTPS works, so `pe-lab.sh` now passes `LAB_APT_MIRROR=https://gb.archive.ubuntu.com/ubuntu` and the installer waits for cloud-init before it touches apt. On a new VM where cloud-init stalls the same way, point `/etc/apt/sources.list.d/ubuntu.sources` at that HTTPS mirror, stop the stuck `apt-get`, and run `sudo dpkg --configure -a`. The run of `verify.sh` on the VM still waits, because the host ran short of memory during the install, as the Memory section explains.


The first test ran on 16 November 2026 in a stand-in for pe-lab: a fresh OrbStack machine on a Mac with Ubuntu 24.04, 4 CPUs and a 10 GB memory limit, on arm64 instead of the VM's amd64, which the installer handles by picking each tool's arm64 build. From an empty machine, `pe-lab.sh install` finished in 216 seconds, 198 of them in `provision.sh`, and every health check passed. A second run with `--with-ollama` skipped every finished step, pulled the two models, and a pod reached Ollama at `host.docker.internal` 148 seconds later.

`./platform-engineering/verify.sh` then passed 286 of its 292 checks in 44 minutes. All 6 failures sit in module 31, because that module uses `istioctl proxy-status -o json` and the analyzer code `IST0173`, which arrived in istioctl releases newer than 1.24.2. The installer now puts the 1.32.0 client on the VM, the version Homebrew installs on the Mac, while the control plane stays at 1.24.2.

With Ollama installed, `verify.sh 17` passed 6 of 10 checks: the mesh policies and the ServiceEntry all worked, but the 4 checks that wait for a model answer failed, because Ollama took more than 4 minutes to load `qwen2.5:3b` next to the running lab in the stand-in, while the Mac itself ran short of memory. The AI modules therefore still need a run on pe-lab itself, which gives Ollama 4 dedicated cores.

## Memory

The CKS set uses 5.5 GB and the course VM 8 GB. On a host with 16 GB that already runs other VMs, start one set at a time: `qm stop 221 222` before `qm start 231`.

Inside pe-lab, the idle lab uses about 3.7 GB, but the VM soon holds nearly all of its 8 GB in host memory, because the guest keeps its page cache. With VM 103 running beside it, the 15 GB host had only 0.3 GB available at the peak of the install, so run pe-lab with VM 103 stopped, or give the host more memory, before a long `verify.sh` run. The AI modules need about 2.5 GB more than 8 GB while a model answers, so they need a larger VM. Stop the VM when you finish a session with `qm stop 231`, and after `qm start 231` run `./scripts/start.sh` on the VM to bring the lab back.

With `--with-ollama`, Ollama listens on every interface of the VM, because pods reach it through the k3d network's gateway. Other machines on your network reach it too, so stop it after the AI modules with `sudo systemctl stop ollama`.
