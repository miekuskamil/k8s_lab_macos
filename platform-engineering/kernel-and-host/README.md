# Kernel and host security (runs on a VM)

> New to a term here, like Lima or AppArmor? The [glossary](../glossary.md#the-practice-cluster-and-the-security-modules) explains every term the security modules use.

This domain sits outside the four levels, because its tasks need something the rest of the course never asks for: a Linux kernel that belongs to one machine. The practice cluster runs on two kind nodes, which are containers that share one kernel with each other and with every other container in the Docker engine. That kernel has no AppArmor and no WireGuard module, it refuses to load kernel modules from a container, and Cilium would rewire the network of every container at once if it loaded its programs there. So the seven tasks that change the kernel run on a virtual machine with a kernel of its own, and they sit together in one module.

| Module | You learn | Tools you use |
|---|---|---|
| [44. Kernel and host security](44-kernel-and-host-security.md) | Cilium policies at layers 3, 4 and 7, keeping kernel modules out, WireGuard between pods, AppArmor profiles for a pod and a Deployment | `cilium`, `modprobe`, `apparmor_parser`, `aa-status` |

Take module 44 after the module each task comes from: the Cilium tasks after [module 38](../2-intermediate/38-setting-up-a-secure-cluster.md), the kernel module task after [module 40](../3-advanced/40-hardening-nodes.md), the WireGuard task after [module 41](../3-advanced/41-hardening-workloads.md), and the AppArmor tasks after [module 43](../3-advanced/43-runtime-security-and-auditing.md). Practice exams 5 and 6 each hold one Cilium task and one AppArmor or kernel module task, so they need the VM as well.

gVisor and Falco stay on the practice cluster. gVisor runs its own user-space kernel inside the sandbox, and Falco only watches system calls, so neither needs a kernel to itself, and both passed their test runs on kind.

## The VM you need

The VM depends on the machine you work on:

| Your machine | The VM | How to build it |
|---|---|---|
| Mac | the Lima VM `cks-lima`, one node with Cilium and AppArmor | `./platform-engineering/practice/cluster/lima.sh create`, as the next section shows |
| Proxmox server | `cks-w1` of the practice cluster takes the AppArmor and kernel module tasks, and the Cilium tasks still need the Lima VM on a Mac | [the practice cluster on your own VMs](../practice-cluster.md#the-practice-cluster-on-your-own-vms-proxmox-or-any-ssh-reachable-ubuntu) and [the Proxmox page](../../proxmox/README.md#create-the-vms) |
| Windows | two Ubuntu 24.04 VMs in Hyper-V or Multipass, set up like the Proxmox VMs | the same [own-VMs setup](../practice-cluster.md#what-you-need), run from a Linux shell that reaches the VMs over SSH |

The test runs covered the Mac and Proxmox setups. Nobody has run the Windows setup yet, so treat it as a starting point and check each step.

## The Lima VM on a Mac

**Lima** is a tool for macOS that runs Linux virtual machines on Apple's virtualization framework, each with its own kernel. The VM `cks-lima` runs Ubuntu 24.04 with AppArmor on, and a one-node kubeadm cluster at Kubernetes 1.37.1 with Cilium 1.20.4 as its CNI.

```bash
brew install lima                                           # once
./platform-engineering/practice/cluster/lima.sh create      # builds the VM and the cluster; safe to run again
./platform-engineering/practice/cluster/lima.sh shell       # a root shell on the node, like "ssh cks-lima"
./platform-engineering/practice/cluster/lima.sh stop        # frees the memory; "start" brings it back
./platform-engineering/practice/cluster/lima.sh reset       # back to a fresh cluster, VM kept
./platform-engineering/practice/cluster/lima.sh destroy     # deletes the VM
```

In the test run, `create` took 2 minutes 5 seconds from nothing, and `reset` took 2 minutes 15 seconds. The VM gets 2 CPUs and 3 GiB. With the cluster idle, the guest used 1.25 GB and the VM process on the Mac 1.5 GB. Lima's memory comes from the Mac directly, not from OrbStack's share, so it doesn't compete with the OrbStack machines or the k3d lab.

Lima shows your Mac home folder inside the VM at the same path, read-only. The node has `kubectl` with the `k` alias, `crictl`, `apparmor_parser`, `aa-status` and the `cilium` command line tool. Module 44 marks each task that runs here with **Host:** `cks-lima`.

## Where each task runs

On a Mac every task of module 44 runs on the Lima VM. On your own VMs, the kernel of `cks-w1` has AppArmor and loads modules, so three tasks of module 44 and two practice exam tasks move there:

| Task | On a Mac | On your own VMs |
|---|---|---|
| 44.1 to 44.3, Cilium policies | `cks-lima` | `cks-lima` |
| 44.4, a kernel module | `cks-lima` | `cks-w1` |
| 44.5, WireGuard with Cilium | `cks-lima` | `cks-lima` |
| 44.6 and 44.7, AppArmor | `cks-lima` | `cks-w1` |
| Practice exam 5 task 9, AppArmor | `cks-lima` | `cks-w1` |
| Practice exam 6 task 10, a kernel module | `cks-lima` | `cks-w1` |
| Practice exams 5 and 6, task 3, Cilium | `cks-lima` | `cks-lima` |

The task text says `cks-lima`, so on your own VMs read it as `cks-w1` for the AppArmor and kernel module tasks: load the profile or write the modprobe rule on `cks-w1`, and run `kubectl` on `cks-cp`. The pods land on `cks-w1` anyway, because the control plane keeps its taint, and AppArmor confines a container only on the node that loaded the profile.

The Cilium tasks stay on the Lima VM, because Cilium replaces the cluster's network plugin and so needs a cluster of its own. A third VM for it needs another 3 GB, which the test host lacked while `cks-cp` and `cks-w1` ran, so keep `cks-lima` on your Mac for those tasks. Without it, they stop with a message, and every other task still works.
