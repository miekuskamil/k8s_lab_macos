# CKS 03: System hardening (10%)

> New to a term here, like attack surface or NodeRestriction? The [glossary](../../course/glossary.md#cks-exam-track) explains every term this track uses.

**Before this domain:** the [practice cluster](../README.md#the-practice-cluster) running. No course module covers node hardening, so this domain starts from the basics.

Kubernetes runs on ordinary Linux machines. An attacker who escapes a container lands on that machine, with whatever services, users and credentials it holds. This domain makes the node itself a poor place to land. It has three tasks and takes about 25 minutes.

The curriculum lists AppArmor and seccomp under domain 06, so they live in [06, tasks 4 and 5](06-monitoring-logging-runtime-security.md#task-4-a-seccomp-profile).

## Theory: less on the node, fewer rights for everyone on it

### Attack surface

The **attack surface** is everything an attacker might use to get in or move on: listening ports, installed packages, running services, user accounts. Every item is a door. A node needs very few doors: the kubelet, the container runtime, SSH for the admins, and the CNI agent. Everything else is risk without benefit.

Shrinking the surface follows the same steps every time:

1. List what listens: `ss -tlnp` shows TCP sockets with the owning process.
2. Find which package owns the program: `dpkg -S /usr/sbin/vsftpd`.
3. Stop and disable the service: `systemctl disable --now vsftpd`.
4. Remove the package: `apt-get purge vsftpd`, so a later reboot or upgrade doesn't bring it back.

Step 4 matters. A disabled service is still on disk, and the next `apt-get upgrade` or a careless `systemctl start` revives it.

### Least privilege for people on the node

**Least privilege** means each user and each program gets the rights its job needs and nothing more. On a Linux node, the big right is `sudo`. Two places grant it on Ubuntu: membership in the `sudo` group, and files under `/etc/sudoers.d/`. A user who needs no root keeps the account but loses both. A user who left keeps the files for the audit trail, but the account gets locked with `passwd -l`.

### Least privilege for the kubelet

Every kubelet holds a client certificate for `system:node:<name>`, and every node stores it in `/var/lib/kubelet/pki/`. Anybody root on one node owns that identity. Two layers limit what it does:

1. The **Node authorizer** lets a kubelet read only the objects its own pods need, and in 1.37 only its own Node object.
2. The **NodeRestriction** admission plugin limits writes: a kubelet changes only its own Node and the pods bound to it, and never sets labels with the `node-restriction.kubernetes.io/` prefix.

That prefix exists for a reason. Admins use labels under it to steer sensitive workloads to trusted nodes. If a kubelet set such a label on itself, a compromised node would attract the very workloads meant to avoid it.

The test run measured both layers. With NodeRestriction off, the kubelet of `cks-w1` still failed to touch `cks-cp`, because the Node authorizer refused the read first: `node 'cks-w1' cannot read 'cks-cp', only its own Node object`. But it set `node-restriction.kubernetes.io/cks=1` on itself without complaint. With NodeRestriction back, the same label failed: `is not allowed to modify labels: node-restriction.kubernetes.io/cks`.

## Task 1: Remove a service nobody needs

**Time budget:** 4 minutes. **Host:** `cks-w1`.

```bash
./certs/cks/task.sh setup 3.1
```

> Something on `cks-w1` listens on TCP port 21. Find the program and the package it comes from, stop it for good, and remove the package.

<details>
<summary>Solution</summary>

```bash
ss -tlnp | grep ':21 '
dpkg -S /usr/sbin/vsftpd
systemctl disable --now vsftpd
apt-get purge -y vsftpd
ss -tlnp | grep ':21 '        # prints nothing now
```

In the test run, `ss` showed `users:(("vsftpd",pid=41498,fd=3))` on `*:21`, and `dpkg -S` answered `vsftpd: /usr/sbin/vsftpd`. vsftpd is an FTP server. FTP sends passwords in clear text, so it has no place on a Kubernetes node.

</details>

```bash
./certs/cks/task.sh check 3.1
```

```
  PASS  nothing listens on TCP port 21
  PASS  the package vsftpd is removed
```

## Task 2: A user with too much power

**Time budget:** 4 minutes. **Host:** `cks-w1`.

```bash
./certs/cks/task.sh setup 3.2
```

> On `cks-w1`, user `cks-dev` must keep the account but lose every root right. User `old-admin` left the team: lock the account's password without deleting the user.

<details>
<summary>Solution</summary>

```bash
id cks-dev
gpasswd -d cks-dev sudo
grep -rl cks-dev /etc/sudoers /etc/sudoers.d/
rm /etc/sudoers.d/cks-dev
passwd -l old-admin
sudo -l -U cks-dev
passwd -S old-admin
```

The `grep` finds the second grant, a `NOPASSWD:ALL` line in `/etc/sudoers.d/cks-dev`. Removing only the group membership leaves that file working. In the test run, `sudo -l -U cks-dev` ended with `User cks-dev is not allowed to run sudo on cks-w1.`, and `passwd -S old-admin` showed `L` in the second column.

</details>

```bash
./certs/cks/task.sh check 3.2
```

```
  PASS  cks-dev is no longer in the sudo group
  PASS  sudo grants cks-dev nothing
  PASS  cks-dev still exists
  PASS  old-admin's password is locked
```

## Task 3: Limit what a kubelet may change

**Time budget:** 6 minutes. **Hosts:** `cks-cp`, and `cks-w1` to test.

```bash
./certs/cks/task.sh setup 3.3
```

> Someone changed the API server's admission plugins. Restore them so that a kubelet may change only its own Node object and may not set `node-restriction.kubernetes.io/` labels. Remove any plugin that admits everything.

Test with the kubelet's own credentials on `cks-w1`:

```bash
kubectl --kubeconfig /etc/kubernetes/kubelet.conf label node cks-w1 node-restriction.kubernetes.io/cks=1
kubectl --kubeconfig /etc/kubernetes/kubelet.conf label node cks-w1 node-restriction.kubernetes.io/cks-
```

<details>
<summary>Solution</summary>

On `cks-cp`:

```bash
grep admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

Change the line to:

```yaml
    - --enable-admission-plugins=NodeRestriction
```

`AlwaysAdmit` admits every request, and Kubernetes deprecated it years ago. The default plugins, such as `ServiceAccount` and `LimitRanger`, stay on without being listed. Wait for the API server, then repeat the test on `cks-w1`. The label command now fails with `is not allowed to modify labels: node-restriction.kubernetes.io/cks`.

</details>

```bash
./certs/cks/task.sh check 3.3
```

In the test run, the third check passed even before the fix, for the reason the theory gives. After the fix:

```
  PASS  the API server enables NodeRestriction
  PASS  the API server no longer enables AlwaysAdmit
  PASS  cks-w1's kubelet may not label node cks-cp (the Node authorizer already blocks this)
  PASS  cks-w1's kubelet may not set a node-restriction label on itself
```

## Clean up

Task 3 restarts the API server twice, once in the setup and once in your fix. Nothing else needs undoing. `./certs/cks/cluster/reset.sh` wipes the users and packages too.
