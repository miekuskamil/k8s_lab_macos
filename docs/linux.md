# Running the lab on Linux

The lab and the course were written on macOS. This page covers what changes on Ubuntu 24.04, on a Linux machine or a Linux VM. The short version: the cluster, the mesh and every course check behave the same. Only the setup steps and a few commands differ.

## What was tested

| | |
|---|---|
| OS | Ubuntu 24.04, arm64, in an OrbStack Linux machine |
| Container engine | Docker Engine 29.1.3 from Ubuntu's packages |
| Tools | k3d 5.9.0, kubectl 1.31.5, helm 4.3.1, istioctl 1.32.0 (client; the control plane runs 1.24.2) |
| Result | `./scripts/provision.sh` from nothing in 163 seconds, then `./platform-engineering/verify.sh`: 230 of 232 checks passed in 40 minutes. The 2 failures were an `istioctl` command form in module 7, now fixed. A re-run of modules 7 and 22 passed 31 of 31. |

## Before you start

Give the machine at least 12 GB of memory: the lab needs about 8 GB, and the AI modules add about 2.5 GB while a model answers. Clone the repository on the machine's own disk, for example `~/k8s_lab_macos`.

## Install Docker

The lab runs its cluster in Docker containers with k3d, so it needs a Docker engine.

Install Docker Engine from Ubuntu's packages, which matches the tested setup:

```bash
sudo apt-get update && sudo apt-get install -y docker.io
sudo usermod -aG docker $USER     # log out and back in for the group to apply
docker run --rm hello-world
```

## Install the tools

The toolbox makes this section optional. `./lab.sh shell` builds a container with every tool below at the same versions and opens a shell in it, so the machine needs only Docker and git. Skip to the inotify limit at the end of this section, which the toolbox doesn't change, because the clusters share the host's kernel.

Homebrew is the macOS route. On Ubuntu, download each tool at the version the lab was tested with. `dpkg --print-architecture` prints `amd64` on Intel and AMD machines and `arm64` on ARM machines.

```bash
ARCH=$(dpkg --print-architecture)
sudo apt-get install -y git curl python3

curl -fsSLO "https://dl.k8s.io/release/v1.31.5/bin/linux/$ARCH/kubectl"
sudo install kubectl /usr/local/bin/ && rm kubectl

curl -fsSL "https://get.helm.sh/helm-v4.3.1-linux-$ARCH.tar.gz" | tar xz
sudo install "linux-$ARCH/helm" /usr/local/bin/ && rm -r "linux-$ARCH"

curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.9.0 bash

curl -fsSL "https://github.com/istio/istio/releases/download/1.32.0/istioctl-1.32.0-linux-$ARCH.tar.gz" | tar xz
sudo install istioctl /usr/local/bin/ && rm istioctl
```

Linux limits how many files one user may watch for changes. The lab's many pods go past the default limit, and pods then fail with "too many open files". Raise the limit now and after every reboot:

```bash
echo -e "fs.inotify.max_user_instances=512\nfs.inotify.max_user_watches=524288" | sudo tee /etc/sysctl.d/99-k8s-lab.conf
sudo sysctl --system
```

Then run `./scripts/provision.sh` as the main README describes.

## Commands that differ from the course text

| The course says | On Linux |
|---|---|
| `brew install ...` | Use the install commands above. |
| open http://localhost:8080 in a browser | Same address on a Linux desktop. On a remote VM, forward the port over SSH: `ssh -L 8080:localhost:8080 <vm>`. |
| `open http://...` | `xdg-open http://...` on a Linux desktop, or the forwarded address in your own browser. |

Every other command in the course runs unchanged. Two commands used to break on Linux and now use a form that works on both systems: module 22 edits files with `sed -i.bak`, and module 7 names the pod as `POD.NAMESPACE` in `istioctl x describe pod`.

## The AI modules (17, 18, 19 and 27)

These modules call [Ollama](https://ollama.com), a program that runs language models on your own machine. Pods reach it under the name `host.docker.internal`, which means "the machine that runs Docker". On macOS, OrbStack and Docker Desktop answer that name for you. Plain Docker Engine on Linux doesn't, so the setup needs two extra steps.

1. Install Ollama in Ubuntu and make it listen on every network interface, not only on `127.0.0.1`. The cluster's containers sit on their own Docker network, and they reach Ubuntu through that network's gateway address, not through Ubuntu's loopback.

   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   sudo mkdir -p /etc/systemd/system/ollama.service.d
   printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0"\n' | sudo tee /etc/systemd/system/ollama.service.d/listen.conf
   sudo systemctl daemon-reload && sudo systemctl restart ollama
   ollama pull qwen2.5:3b && ollama pull nomic-embed-text
   ```

2. Tell the cluster's DNS server, CoreDNS, that `host.docker.internal` means the gateway of the k3d network. k3s reads extra CoreDNS zones from a ConfigMap named `coredns-custom`:

   ```bash
   GW=$(docker network inspect k3d-k8s-lab -f '{{(index .IPAM.Config 0).Gateway}}')
   kubectl -n kube-system create configmap coredns-custom \
     --from-literal=hostdocker.server="host.docker.internal:53 {
       hosts {
         $GW host.docker.internal
       }
     }" --dry-run=client -o yaml | kubectl apply -f -
   kubectl -n kube-system rollout restart deploy/coredns
   ```

   Check the result from inside the cluster. The command should print Ollama's model list:

   ```bash
   kubectl run ollama-check --rm -i --restart=Never --image=curlimages/curl:8.11.1 -- \
     curl -s http://host.docker.internal:11434/api/tags
   ```

In the test run, a stand-in server on port 11434 replaced Ollama to save memory. A pod resolved `host.docker.internal` to the gateway `172.18.0.1`, and with module 17's ServiceEntry applied, the request went through the shop waypoint. The models themselves behave the same on every platform.

Ollama now listens on every interface, so other machines on your network reach it too. On a laptop on a shared network, block port 11434 with a firewall, or stop Ollama after the AI modules: `sudo systemctl stop ollama`.
