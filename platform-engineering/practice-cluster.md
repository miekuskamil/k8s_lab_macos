# The practice cluster

> New to a term here, like kubeadm or static pod? The [glossary](glossary.md#the-practice-cluster-and-the-security-modules) explains every term the practice cluster and the security modules use.

Modules 33 to 44 and the six timed practice exams run on a second cluster, the practice cluster, instead of the k3d lab. The k3d lab is built for watching a platform work, so it runs the shop, Istio and every UI on one k3s node that you drive from your Mac. The application and security modules train a different skill, fixing a given problem on a live cluster from a terminal inside its time budget, and that skill needs a cluster that looks like the ones teams build by hand.

| | k3d lab (modules 0 to 32) | Practice cluster (modules 33 to 44) |
|---|---|---|
| Cluster | k3d on your Mac, one k3s node, Istio and the shop | kubeadm on two OrbStack Linux machines, no mesh |
| You work | from your Mac, with `kubectl` and the UIs | inside a node, with `kubectl`, `vim`, `systemctl` and `journalctl` |
| A module is | 30 to 60 minutes that explain one idea in depth | course-style theory, concepts and diagrams, then timed tasks of 3 to 10 minutes each |
| You finish when | you understand why the platform behaves as it does | you solve each task inside its time budget without opening the solution |

The practice cluster comes from kubeadm, the official tool that turns plain Linux machines into a Kubernetes cluster. kubeadm runs the control plane as **static pods**, which are pods that the kubelet starts from YAML files in `/etc/kubernetes/manifests` with no API server involved. Many security tasks edit those files, while the k3s cluster of the lab keeps its control plane inside one binary, so those tasks have nothing to edit there. The [timed tasks page](timed-tasks.md) explains how a task works, and the [VM page](kernel-and-host/README.md) explains the third machine that the kernel tasks of module 44 need.

## The two machines

![The practice clusters: two OrbStack machines, cks-cp and cks-w1, with the tools each one runs, and the Lima VM cks-lima with Cilium, AppArmor and WireGuard](../docs/diagrams/chapters/cks-practice-cluster.svg)

The cluster has two nodes, each an OrbStack Linux machine with Ubuntu 24.04 on arm64:

1. `cks-cp` runs the control plane: API server, etcd, scheduler and controller manager, all as static pods. It also holds `etcdctl`, `trivy`, `kube-bench`, `kubesec`, `bom` and a small image policy service for the supply chain tasks.
2. `cks-w1` runs the workloads. It holds gVisor, a second container runtime for sandboxed pods, and Falco, which watches system calls.

Both nodes run containerd 2.2.10 and Kubernetes 1.37.1. That is one patch release below the newest 1.37, so the upgrade task has somewhere to go. Calico 3.32.3 connects the pods and enforces NetworkPolicy. ingress-nginx 1.15.1 serves Ingress objects on NodePorts 30080 and 30443.

### Create, stop, reset, destroy

```bash
./platform-engineering/practice/cluster/create.sh          # builds both machines; safe to run again
orb -m cks-cp                          # a shell on the control plane, like "ssh cks-cp" on a real cluster
orb -m cks-w1                          # a shell on the worker; "sudo -i" for root
orb stop cks-cp cks-w1                 # frees the memory; "orb start cks-cp cks-w1" brings the cluster back
./platform-engineering/practice/cluster/reset.sh           # back to a fresh cluster at 1.37.1, machines and downloads kept
./platform-engineering/practice/cluster/destroy.sh --yes   # deletes both machines
```

In the test run, `create.sh` took 3 minutes 45 seconds from nothing, and 47 seconds when run again on a finished cluster. `reset.sh` took 2 minutes 30 seconds. With the cluster idle, `cks-cp` used 1.1 GB of memory and `cks-w1` 0.7 GB, page cache included.

The machines keep their IP addresses across `orb stop` and `orb start`, which matters because the API server's certificate names the control plane's IP. After a start, the pods take about a minute to come back.

### What the OrbStack kernel changes

OrbStack machines are not full virtual machines. They share one Linux kernel with each other and with OrbStack's Docker engine. Four consequences matter for the security modules:

- The kernel has no AppArmor. The kubelet accepts AppArmor fields in a pod but refuses to start the pod: `Cannot enforce AppArmor: AppArmor is not enabled on the host`. So the AppArmor tasks run on the [Lima VM](kernel-and-host/README.md#the-lima-vm-on-a-mac), which has a kernel of its own.
- The kernel has no WireGuard module, so Calico and Cilium node-to-node encryption don't run here. Pod-to-pod encryption points to Istio, which the course already runs, or to the Lima VM.
- Cilium would load its eBPF programs into the kernel that every OrbStack machine and the Docker engine share. The Cilium tasks run on the Lima VM for that reason, and the OrbStack cluster keeps Calico.
- Falco sees every system call on the shared kernel, including the ones from other OrbStack machines and Docker containers. Filter its output by `k8s.ns.name` or container name to see only your cluster.

Two settings in `platform-engineering/practice/cluster/kubeadm-config.yaml` exist only because of OrbStack. kube-proxy doesn't set the kernel's connection tracking table size (`conntrack.maxPerCore: 0`), because a machine may not change a value the whole kernel shares. And the kubelet tolerates swap (`failSwapOn: false`), because OrbStack gives every machine the host's swap.

## The application extras

![The application extras on the practice cluster: the two machines cks-cp and cks-w1, with helm, podman and the local registry added on cks-cp and metrics-server in the cluster](../docs/diagrams/chapters/ckad-practice-cluster.svg)

The application modules 33 to 37 run on the same two machines as the security modules, but building and shipping an app needs a few tools that hardening a cluster doesn't. So a small script adds them on top:

1. On `cks-cp`: helm 4.3.1 to install charts, podman to build and push images, `kubectl-convert` for API version changes, and a local image registry at `registry.ckad:5000`, which runs as the systemd service `ckad-registry` outside Kubernetes.
2. On both nodes: the name `registry.ckad`, and a containerd setting that lets the kubelet pull images from that registry over plain HTTP.
3. In the cluster: metrics-server 0.9.1, so that `kubectl top` works.

```bash
./platform-engineering/practice/cluster/create.sh     # the cluster, if it doesn't exist yet; safe to run again
./platform-engineering/practice/app-extras/extras.sh  # the application extras; safe to run again
orb -m cks-cp                                         # a shell on the control plane, then sudo -i
./platform-engineering/practice/app-extras/reset.sh   # removes everything the application tasks and exams created
orb stop cks-cp cks-w1                                # frees the memory; "orb start cks-cp cks-w1" brings the cluster back
```

In the test run, `extras.sh` took 51 seconds the first time and 31 seconds when run again. The extras follow the cluster scripts' platform setting, so with `CKS_PLATFORM=vms` they install on [your own VMs](#the-practice-cluster-on-your-own-vms-proxmox-or-any-ssh-reachable-ubuntu) the same way, and every download picks the node's CPU type from `dpkg --print-architecture`.

The application and security modules share one cluster, so each keeps out of the other's way. Every namespace an application task creates carries the label `ckad=task`, and every practice exam namespace `ckad=mock`, so `reset.sh` finds and deletes them all. Cluster-wide objects that the tasks create start with `ckad-`, and Custom Resource Definitions sit in the `ckad.io` group, so the reset finds those too. The reset also removes metrics-server, which the security modules don't use, and the tasks that need it install it again. It does that last, after the namespaces are gone, because a namespace only finishes deleting while every API group answers, and the metrics API stops answering when metrics-server goes. In one test run the opposite order held the namespaces in `Terminating` for about a minute. The tools on `cks-cp` stay, because nothing in Kubernetes sees them, and in the test run the reset took between 43 and 56 seconds, with 16 to 55 namespaces to delete.

`./platform-engineering/practice/cluster/reset.sh` rebuilds the cluster from scratch, which also rewrites containerd's settings, so run `extras.sh` again after it.

The test run checked that the two groups of modules leave each other alone. After all application tasks, the three application practice exams and an application reset, the security tasks 38.1, 38.4, 39.1, 41.1, 41.3 and 41.4 each failed their check after setup and passed after their solution, gVisor included, although `extras.sh` had restarted containerd on `cks-w1`. After a full cluster reset, `extras.sh` and two application tasks ran again without changes.

## The practice cluster on your own VMs (Proxmox or any SSH-reachable Ubuntu)

The same two-node cluster also runs on two virtual machines that you reach over SSH, for example on a Proxmox server at home. The scripts then send every node command through `ssh` and `sudo` instead of `orb`, so the tasks, the checks and the practice exams stay the same. A VM brings a kernel of its own, and that kernel has AppArmor, so the AppArmor and kernel module tasks move from the Lima VM to `cks-w1`.

### What you need

You need two VMs with Ubuntu 24.04 on amd64 or arm64. Give `cks-cp` 2 CPUs, 3 GB of memory and 30 GB of disk, and give `cks-w1` 2 CPUs, 2.5 GB and 30 GB. Both VMs need internet access, and one user that logs in with an SSH key and runs `sudo` without a password. Their network must stay clear of the pod network `10.244.0.0/16` and the service network `10.96.0.0/12`. The pod network avoids Calico's default `192.168.0.0/16` on purpose, because that range overlaps most home networks.

On Proxmox, `proxmox/create-vms.sh` builds both VMs from the Ubuntu cloud image. You run it as root on the Proxmox host, and it creates VM 221 `cks-cp` at 192.168.1.221 and VM 222 `cks-w1` at 192.168.1.222, with the user `ubuntu` and your public key. Any other hypervisor or cloud works the same way once the two VMs answer on SSH. The VMs need no particular hostname, because `create.sh` renames them to `cks-cp` and `cks-w1`, the node names that kubeadm and the tasks expect.

### Settings and commands

Five environment variables tell the scripts where the VMs are. Every script reads them, `task.sh` and `practice-exam.sh` included, so export them once in your shell:

```bash
export CKS_PLATFORM=vms                  # without it, the scripts use OrbStack
export CKS_CP_HOST=192.168.1.221         # the address of cks-cp (this is the default)
export CKS_W1_HOST=192.168.1.222         # the address of cks-w1 (this is the default)
export CKS_SSH_USER=ubuntu               # the login user on both VMs (the default)
export CKS_SSH_KEY=~/.ssh/cks_proxmox    # the private key for that user (the default)

./platform-engineering/practice/cluster/create.sh            # builds the cluster on both VMs; safe to run again
ssh -i ~/.ssh/cks_proxmox ubuntu@192.168.1.221   # a shell on cks-cp; "sudo -i" for root
./platform-engineering/practice/cluster/reset.sh             # back to a fresh cluster at 1.37.1
./platform-engineering/practice/cluster/destroy.sh --yes     # wipes the cluster with kubeadm reset and keeps both VMs
```

`destroy.sh` never deletes a VM here, because the VMs belong to you and to your hypervisor. It runs `kubeadm reset` and undoes the task changes, and `create.sh` builds the cluster again on the same VMs. A sixth variable, `CKS_SSH_OPTS`, passes extra options to `ssh`, such as a separate known hosts file.

### What the test run measured

The test ran on a Proxmox host with an Intel i7-12700T and 15 GB of memory, so the nodes ran on amd64. On two new VMs, `create.sh` built the cluster in 3 minutes 26 seconds, after it had waited for cloud-init to finish the first-boot package upgrade. A rebuild after `destroy.sh` took 2 minutes 28 seconds, and `reset.sh` took between 2 minutes 35 seconds and 4 minutes 33 seconds. With the cluster idle, `cks-cp` used 1.0 GB of memory and `cks-w1` 0.6 GB, page cache left out. The host kept 2.8 GB free through every task and mock exam, next to another VM of 7 GB, and never swapped.

All 65 security tasks and the three security practice exams passed in this setup. Two things differed from OrbStack, and neither changed a task. The node scripts pick the downloads for the VM's CPU, amd64 here and arm64 on a Mac. And the first boot stalled, because the VMs reached Ubuntu's package mirrors over HTTPS only and plain HTTP downloads hung. If `apt` hangs on your VMs, change `http://` to `https://` in `/etc/apt/sources.list.d/ubuntu.sources`.

### Where the kernel tasks run

A VM brings a kernel of its own, so on your own VMs the AppArmor and kernel module tasks of module 44 run on `cks-w1`, while the Cilium tasks still need the Lima VM. The [VM page](kernel-and-host/README.md#where-each-task-runs) lists each task and its host.
