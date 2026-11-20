# The practice cluster

> New to a term here, like kubeadm, kind or static pod? The [glossary](glossary.md#the-practice-cluster-and-the-security-modules) explains every term the practice cluster and the security modules use.

Modules 33 to 43 and the six timed practice exams run on a second cluster, the practice cluster, instead of the k3d lab. The k3d lab is built for watching a platform work, so it runs the shop, Istio and every UI on one k3s node that you drive from your Mac. The application and security modules train a different skill, fixing a given problem on a live cluster from a terminal inside its time budget, and that skill needs a cluster that looks like the ones teams build by hand.

| | k3d lab (modules 0 to 32) | Practice cluster (modules 33 to 43) |
|---|---|---|
| Cluster | k3d on your Mac, one k3s node, Istio and the shop | kubeadm on two kind nodes in Docker, no mesh |
| You work | from your Mac, with `kubectl` and the UIs | inside a node, with `kubectl`, `vim`, `systemctl` and `journalctl` |
| A module is | 30 to 60 minutes that explain one idea in depth | course-style theory, concepts and diagrams, then timed tasks of 3 to 10 minutes each |
| You finish when | you understand why the platform behaves as it does | you solve each task inside its time budget without opening the solution |

The practice cluster comes from kubeadm, the official tool that turns plain Linux machines into a Kubernetes cluster. kubeadm runs the control plane as **static pods**, which are pods that the kubelet starts from YAML files in `/etc/kubernetes/manifests` with no API server involved. Many security tasks edit those files, while the k3s cluster of the lab keeps its control plane inside one binary, so those tasks have nothing to edit there. The [timed tasks page](timed-tasks.md) explains how a task works, and the [VM page](kernel-and-host/README.md) explains the third machine that the kernel tasks of module 44 need.

## Two nodes in Docker

The cluster needs two Linux machines, because many tasks change a node: they edit a static pod, restart the kubelet, add a systemd unit or read the journal. Two virtual machines would give you that, but they cost memory, take minutes to install, and tie the course to one hypervisor. **kind** gets the same result inside the Docker engine that the k3d lab already uses. kind starts each node as a privileged container that runs systemd, containerd and the kubelet, so from the inside a node behaves like a small Linux machine, and kubeadm builds the cluster on top exactly as it would on two servers. The only things you need on your Mac are Docker and this repo.

![The practice cluster: two kind nodes, practice-control-plane and practice-worker, as containers in the Docker engine with the tools each one runs, and the Lima VM cks-lima with Cilium, AppArmor and WireGuard](../docs/diagrams/chapters/cks-practice-cluster.svg)

The picture shows the two nodes inside the Docker engine on your Mac:

1. `practice-control-plane` runs the control plane: API server, etcd, scheduler and controller manager, all as static pods. It also holds `etcdctl`, `trivy`, `kube-bench`, `kubesec`, `bom` and a small image policy service for the supply chain tasks.
2. `practice-worker` runs the workloads. It holds gVisor, a second container runtime for sandboxed pods, and Falco, which watches system calls.

Both nodes run Kubernetes 1.37.1. That is one patch release below the newest 1.37, so the upgrade task has somewhere to go. Calico 3.32.3 connects the pods and enforces NetworkPolicy, and ingress-nginx 1.15.1 serves Ingress objects on NodePorts 30080 and 30443, which also answer on your Mac at `localhost:30080` and `localhost:30443`.

Every tool comes from one **node image**. kind publishes a node image per Kubernetes version, and its newest, for 1.37.0, is the base. A Dockerfile in `platform-engineering/practice/cluster/kind/` adds the kubeadm, kubelet and kubectl packages at 1.37.1 from the Kubernetes package repository, so `apt` upgrades them in module 39 the way it does on any kubeadm node, and then every scanner, runtime and helper that the tasks use. The first `./lab.sh practice up` builds that image once. After that Docker keeps it, so a new cluster downloads nothing but the Kubernetes images, and you carry the whole toolbox with you wherever Docker runs.

### Create, open, reset, delete

```bash
./lab.sh practice up              # builds the node image once, then the cluster; safe to run again
./lab.sh practice shell           # a root shell on the control plane, with the k alias set
./lab.sh practice shell worker    # a root shell on the worker
./lab.sh practice reset           # deletes both nodes and builds a fresh cluster at 1.37.1
./lab.sh practice down --yes      # deletes the cluster and the registry; the node image stays cached
```

In the test run on a Mac with 24 GB of memory and OrbStack, `./lab.sh practice up` took __CREATE_NOTHING__ from nothing, which includes __BUILD__ for the node image. A second `up` on a finished cluster took __CREATE_AGAIN__, and `./lab.sh practice reset` took between __RESET_MIN__ and __RESET_MAX__. A reset deletes the two node containers and starts new ones from the cached image, which is faster and cleaner than undoing every task by hand.

The cluster fits next to the running k3d lab. With the cluster idle, `practice-control-plane` used __MEM_CP__ of memory and `practice-worker` __MEM_W1__, while the k3d lab used __MEM_K3D__, all inside OrbStack's Docker engine with its limit of 11.7 GB. During the tasks the two nodes peaked at __MEM_PEAK__ together.

kind writes the cluster's kubeconfig to `~/.kube/practice-kind.yaml` instead of your main kubeconfig, so the current context of your `kubectl` stays on the k3d lab. You rarely need it, because the tasks run inside a node, but `KUBECONFIG=~/.kube/practice-kind.yaml kubectl get nodes` works from your Mac.

### What a shared kernel changes

A kind node is a container, so both nodes share one Linux kernel with each other, with the k3d lab and with every other container on your Mac. Most security controls live above the kernel and work the same as on a server. Four consequences matter for the security modules:

- The kernel has no AppArmor. The kubelet accepts AppArmor fields in a pod but refuses to start the pod: `Cannot enforce AppArmor: AppArmor is not enabled on the host`. So the AppArmor tasks run on the [Lima VM](kernel-and-host/README.md#the-lima-vm-on-a-mac), which has a kernel of its own.
- The kernel has no WireGuard module, so Calico and Cilium node-to-node encryption don't run here. Pod-to-pod encryption points to Istio, which the course already runs, or to the Lima VM.
- Cilium would load its eBPF programs into the kernel that every container shares. The Cilium tasks run on the Lima VM for that reason, and the practice cluster keeps Calico.
- Falco sees every system call on the shared kernel, including the ones from the k3d lab and other containers. Filter its output by `k8s.ns.name` or container name to see only your cluster.

gVisor and Falco still run on the worker. gVisor brings its own user-space kernel inside the sandbox, and Falco's eBPF probe only watches system calls, so neither needs a kernel to itself, and both passed every task in the test run. The [kernel and host page](kernel-and-host/README.md) collects the tasks that do need one.

Two kubeadm settings in `platform-engineering/practice/cluster/kind/cluster.yaml` exist because of the shared kernel. kube-proxy doesn't set the kernel's connection tracking table size (`conntrack.maxPerCore: 0`), because a container may not change a value the whole kernel shares. And the kubelet tolerates swap (`failSwapOn: false`), because the Docker engine's VM may have swap that every container sees.

## The application extras

![The application extras on the practice cluster: the two kind nodes with helm, podman and kubectl-convert in the node image, the local registry container, and metrics-server in the cluster](../docs/diagrams/chapters/ckad-practice-cluster.svg)

The application modules 33 to 37 run on the same two nodes as the security modules, but building and shipping an app needs a few tools that hardening a cluster doesn't:

1. On `practice-control-plane`: helm 4.3.1 to install charts, podman to build and push images, and `kubectl-convert` for API version changes. All three sit in the node image.
2. Next to the nodes: a local image registry at `registry.practice:5000`, which runs as the container `practice-registry` on kind's Docker network. Both nodes and every pod reach it by that name, and containerd on both nodes pulls from it over plain HTTP.
3. In the cluster: metrics-server 0.9.1, so that `kubectl top` works.

`./lab.sh practice up` starts the registry with the cluster, so only metrics-server is left for the extras script:

```bash
./lab.sh practice up                                  # the cluster and the registry; safe to run again
./platform-engineering/practice/app-extras/extras.sh  # checks the tools and adds metrics-server; safe to run again
./lab.sh practice shell                               # a root shell on the control plane
./platform-engineering/practice/app-extras/reset.sh   # removes everything the application tasks and exams created
```

In the test run, `extras.sh` took __EXTRAS__.

The application and security modules share one cluster, so each keeps out of the other's way. Every namespace an application task creates carries the label `practice=task`, and every practice exam namespace `practice=mock`, so `reset.sh` finds and deletes them all. Cluster-wide objects that the tasks create start with `ckad-`, and Custom Resource Definitions sit in the `ckad.io` group, so the reset finds those too. The reset also empties the registry and removes metrics-server, which the security modules don't use, and the tasks that need it install it again. It does that last, after the namespaces are gone, because a namespace only finishes deleting while every API group answers, and the metrics API stops answering when metrics-server goes. In the test run the reset took __APPRESET__.

`./lab.sh practice reset` builds the cluster from scratch, so run `extras.sh` again after it.

## Other platforms: OrbStack machines and your own VMs

The scripts keep two other homes for the same cluster. Both build two Ubuntu 24.04 machines called `cks-cp` and `cks-w1`, install containerd and kubeadm on them, and then run the same tasks and practice exams. One environment variable picks the platform, and every script reads it, `./lab.sh`, `task.sh` and `practice-exam.sh` included:

| `PRACTICE_PLATFORM` | The nodes | Reached with |
|---|---|---|
| `kind`, the default | two containers, `practice-control-plane` and `practice-worker` | `docker exec` |
| `orbstack` | two OrbStack Linux machines, `cks-cp` and `cks-w1` | `orb -m <node> -u root` |
| `vms` | two VMs you reach over SSH, `cks-cp` and `cks-w1` | `ssh` and `sudo` |

The older names `CKS_PLATFORM`, `CKS_CP_HOST` and so on still work when the new `PRACTICE_*` name is unset. Inside the task scripts, the node names come from two variables, `CP` and `W1`, which every node shell receives, so one script serves all three platforms.

### OrbStack machines

An OrbStack machine is a lightweight Ubuntu system that shares OrbStack's kernel, so it brings the same kernel limits as kind, but each node is a full Ubuntu install that keeps its state across `orb stop` and `orb start`:

```bash
export PRACTICE_PLATFORM=orbstack
./lab.sh practice up              # creates cks-cp and cks-w1 and builds the cluster, about 4 minutes
./lab.sh practice shell           # the same as: orb -m cks-cp -u root
orb stop cks-cp cks-w1            # frees the memory; "orb start cks-cp cks-w1" brings the cluster back
./lab.sh practice reset           # kubeadm reset and a rebuild, machines and downloads kept
./lab.sh practice down --yes      # deletes both machines
```

In the earlier test runs, `create.sh` took 3 minutes 45 seconds from nothing and `reset.sh` 2 minutes 30 seconds, and the machines used 1.1 GB and 0.7 GB of memory. The application extras install helm, podman and kubectl-convert on `cks-cp` there, with the registry as the systemd service `practice-registry` on port 5000. After this course moved to kind, a sample of __ORB_SAMPLE__ tasks still passed on the OrbStack machines.

## The practice cluster on your own VMs (Proxmox or any SSH-reachable Ubuntu)

The same two-node cluster also runs on two virtual machines that you reach over SSH, for example on a Proxmox server at home. The scripts then send every node command through `ssh` and `sudo`, so the tasks, the checks and the practice exams stay the same. A VM brings a kernel of its own, and that kernel has AppArmor, so the AppArmor and kernel module tasks move from the Lima VM to `cks-w1`.

### What you need

You need two VMs with Ubuntu 24.04 on amd64 or arm64. Give `cks-cp` 2 CPUs, 3 GB of memory and 30 GB of disk, and give `cks-w1` 2 CPUs, 2.5 GB and 30 GB. Both VMs need internet access, and one user that logs in with an SSH key and runs `sudo` without a password. Their network must stay clear of the pod network `10.244.0.0/16` and the service network `10.96.0.0/12`. The pod network avoids Calico's default `192.168.0.0/16` on purpose, because that range overlaps most home networks.

On Proxmox, `proxmox/create-vms.sh` builds both VMs from the Ubuntu cloud image. You run it as root on the Proxmox host, and it creates VM 221 `cks-cp` at 192.168.1.221 and VM 222 `cks-w1` at 192.168.1.222, with the user `ubuntu` and your public key. Any other hypervisor or cloud works the same way once the two VMs answer on SSH. The VMs need no particular hostname, because `create.sh` renames them to `cks-cp` and `cks-w1`, the node names that kubeadm and the tasks expect.

### Settings and commands

Five environment variables tell the scripts where the VMs are. Export them once in your shell:

```bash
export PRACTICE_PLATFORM=vms                  # without it, the scripts use kind
export PRACTICE_CP_HOST=192.168.1.221         # the address of cks-cp (this is the default)
export PRACTICE_W1_HOST=192.168.1.222         # the address of cks-w1 (this is the default)
export PRACTICE_SSH_USER=ubuntu               # the login user on both VMs (the default)
export PRACTICE_SSH_KEY=~/.ssh/cks_proxmox    # the private key for that user (the default)

./lab.sh practice up             # builds the cluster on both VMs; safe to run again
./lab.sh practice shell          # ssh to cks-cp and sudo -i
./lab.sh practice reset          # back to a fresh cluster at 1.37.1
./lab.sh practice down --yes     # wipes the cluster with kubeadm reset and keeps both VMs
```

`down` never deletes a VM here, because the VMs belong to you and to your hypervisor. It runs `kubeadm reset` and undoes the task changes, and `up` builds the cluster again on the same VMs. A sixth variable, `PRACTICE_SSH_OPTS`, passes extra options to `ssh`, such as a separate known hosts file.

### What the test run measured

The test ran on a Proxmox host with an Intel i7-12700T and 15 GB of memory, so the nodes ran on amd64. On two new VMs, `create.sh` built the cluster in 3 minutes 26 seconds, after it had waited for cloud-init to finish the first-boot package upgrade. A rebuild after `destroy.sh` took 2 minutes 28 seconds, and `reset.sh` took between 2 minutes 35 seconds and 4 minutes 33 seconds. With the cluster idle, `cks-cp` used 1.0 GB of memory and `cks-w1` 0.6 GB, page cache left out. The host kept 2.8 GB free through every task and mock exam, next to another VM of 7 GB, and never swapped.

All 65 security tasks and the three security practice exams passed in this setup. The node scripts pick the downloads for the VM's CPU, amd64 here and arm64 on a Mac. The first boot stalled, because the VMs reached Ubuntu's package mirrors over HTTPS only and plain HTTP downloads hung. If `apt` hangs on your VMs, change `http://` to `https://` in `/etc/apt/sources.list.d/ubuntu.sources`.

### Where the kernel tasks run

A VM brings a kernel of its own, so on your own VMs the AppArmor and kernel module tasks of module 44 run on `cks-w1`, while the Cilium tasks still need the Lima VM. The [VM page](kernel-and-host/README.md#where-each-task-runs) lists each task and its host.
