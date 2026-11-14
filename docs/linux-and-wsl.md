# Running the lab on Linux and WSL2

The lab and the course were written on macOS. This page covers what changes on Ubuntu 24.04, either on a Linux machine or inside WSL2 on Windows. The short version: the cluster, the mesh and every course check behave the same. Only the setup steps and a few commands differ.

## What was tested

| | |
|---|---|
| OS | Ubuntu 24.04, arm64, in an OrbStack Linux machine |
| Container engine | Docker Engine 29.1.3 from Ubuntu's packages |
| Tools | k3d 5.9.0, kubectl 1.31.5, helm 4.3.1, istioctl 1.24.2 |
| Result | `./scripts/provision.sh` from nothing in 163 seconds, then `./platform-engineering/verify.sh`: 230 of 232 checks passed in 40 minutes. The 2 failures were an `istioctl` command form in module 7, now fixed. A re-run of modules 7 and 22 passed 31 of 31. |

WSL2 itself wasn't tested. WSL2 runs a real Linux kernel with a normal Ubuntu on top, so the Ubuntu results carry over. The WSL-specific parts below (memory, systemd, file location) come from Microsoft's and Docker's documentation, not from a test run.

## Set up WSL2

Skip this section on a plain Linux machine.

1. In PowerShell as administrator, install Ubuntu 24.04:

   ```powershell
   wsl --install -d Ubuntu-24.04
   ```

2. Give WSL2 enough memory. By default WSL2 takes half of the Windows machine's memory. The lab needs about 8 GB, and the AI modules add about 2.5 GB while a model answers. Create `C:\Users\<you>\.wslconfig`:

   ```ini
   [wsl2]
   memory=12GB
   swap=4GB
   ```

   Then restart WSL so the setting applies: `wsl --shutdown`, and open Ubuntu again.

3. Pick a container engine. There are two choices, and the next section explains each.

4. Clone the repository inside the Linux file system, for example `~/k8s_lab_macos`, not under `/mnt/c/...`. Files under `/mnt/c` live on Windows, and every read crosses from Linux to Windows. Image builds and Git get many times slower there, and file permissions come out wrong.

## Choose a container engine

The lab runs its cluster in Docker containers with k3d, so it needs a Docker engine.

**Docker Engine inside Ubuntu.** This matches the tested setup. WSL2 needs systemd to run the Docker service. Turn it on in `/etc/wsl.conf`:

```ini
[boot]
systemd=true
```

Run `wsl --shutdown` in PowerShell, open Ubuntu again, then install Docker:

```bash
sudo apt-get update && sudo apt-get install -y docker.io
sudo usermod -aG docker $USER     # log out and back in for the group to apply
docker run --rm hello-world
```

**Docker Desktop with the WSL2 backend.** Docker Desktop runs the engine for you. In its settings, open Resources, then WSL integration, and switch it on for Ubuntu-24.04. The `docker` command inside Ubuntu then talks to Docker Desktop. Docker Desktop sets its own memory limit under Resources, on top of `.wslconfig`.

## Install the tools

Homebrew is the macOS route. On Ubuntu, download each tool at the version the lab was tested with. `dpkg --print-architecture` prints `amd64` on most Windows PCs and `arm64` on ARM machines.

```bash
ARCH=$(dpkg --print-architecture)
sudo apt-get install -y git curl python3

curl -fsSLO "https://dl.k8s.io/release/v1.31.5/bin/linux/$ARCH/kubectl"
sudo install kubectl /usr/local/bin/ && rm kubectl

curl -fsSL "https://get.helm.sh/helm-v4.3.1-linux-$ARCH.tar.gz" | tar xz
sudo install "linux-$ARCH/helm" /usr/local/bin/ && rm -r "linux-$ARCH"

curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.9.0 bash

curl -fsSL "https://github.com/istio/istio/releases/download/1.24.2/istioctl-1.24.2-linux-$ARCH.tar.gz" | tar xz
sudo install istioctl /usr/local/bin/ && rm istioctl
```

Linux limits how many files one user may watch for changes. The lab's many pods go past the default limit, and pods then fail with "too many open files". Raise the limit now and after every reboot:

```bash
echo -e "fs.inotify.max_user_instances=512\nfs.inotify.max_user_watches=524288" | sudo tee /etc/sysctl.d/99-k8s-lab.conf
sudo sysctl --system
```

Then run `./scripts/provision.sh` as the main README describes.

## Commands that differ from the course text

| The course says | On Linux and WSL |
|---|---|
| `brew install ...` | Use the install commands above. |
| open http://localhost:8080 in a browser | Same address. In WSL2, Windows forwards `localhost` to WSL, so the Windows browser opens it. |
| `open http://...` | `xdg-open http://...` on a Linux desktop. In WSL2, paste the address into the Windows browser. |

Every other command in the course runs unchanged. Two commands used to break on Linux and now use a form that works on both systems: module 22 edits files with `sed -i.bak`, and module 7 names the pod as `POD.NAMESPACE` in `istioctl x describe pod`.

## The AI modules (17, 18, 19 and 27)

These modules call [Ollama](https://ollama.com), a program that runs language models on your own machine. Pods reach it under the name `host.docker.internal`, which means "the machine that runs Docker". On macOS, OrbStack and Docker Desktop answer that name for you. Plain Docker Engine on Linux doesn't, so the setup needs two extra steps.

**With Docker Desktop on WSL2,** `host.docker.internal` already points at Windows. Install Ollama for Windows, pull the models, and the modules work as written. This path wasn't tested. The course's test script looks for Ollama at `http://localhost:11434` by default. When Ollama runs somewhere else, tell the script where: `LAB_OLLAMA_URL=http://<windows-host>:11434 ./platform-engineering/verify.sh 17`.

**With Docker Engine inside Ubuntu:**

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
