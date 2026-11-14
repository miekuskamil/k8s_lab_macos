# CKS 03: System hardening (10%)

> New to a term here, like attack surface or NodeRestriction? The [glossary](../../platform-engineering/glossary.md#cks-exam-track) explains every term this track uses.

**Before this domain:** the [practice cluster](../README.md#the-practice-cluster) running, and the [Lima VM](../README.md#the-lima-vm-for-apparmor-and-cilium) for task 7. No course module covers node hardening, so this domain starts from the basics.

Kubernetes runs on ordinary Linux machines. An attacker who escapes a container lands on that machine, with whatever services, users and credentials it holds. This domain makes the node itself a poor place to land. It has seven tasks and takes about an hour.

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

A service doesn't need a package to exist. An attacker who got root once often leaves a backdoor: a copied binary with an innocent name, started by a systemd unit so it survives a reboot. `ss -tlnp` names the process and its PID, and `/proc/<pid>/exe` points to the file that really runs, whatever the process calls itself. `systemctl status <pid>` names the unit that started it. Task 4 follows that trail.

### Kernel modules

The kernel loads modules on demand. A program that opens a socket for an unusual protocol, such as DCCP or TIPC, makes the kernel load that protocol's module, with all its code and its bugs. Several kernel exploits started exactly so. The CIS benchmark for Linux lists modules a server never needs and asks you to block them.

A file in `/etc/modprobe.d/` does it with two kinds of lines:

| Line | Effect |
|---|---|
| `blacklist dccp` | stops loading by alias, for example when hardware or a socket asks for it. A direct `modprobe dccp` still works |
| `install dccp /bin/false` | replaces the load command with one that fails. Every load fails, direct ones too |

Use both. The file stops future loads only, so also unload a module that's already in: `modprobe -r dccp`. A module that something uses refuses to unload, and `lsmod` shows its users count in the third column. `modprobe -n -v dccp` shows what a load would do without doing it.

OrbStack machines share one kernel and may not load modules, so task 7 runs on the Lima VM.

### Remote logins

An exam node usually runs `sshd`, the SSH server. Two of its settings matter most. `PermitRootLogin no` stops direct root logins, so every admin logs in as themselves and the logs show who did what. `PasswordAuthentication no` leaves only keys, so guessing a password gets an attacker nowhere.

Ubuntu's `/etc/ssh/sshd_config` starts with `Include /etc/ssh/sshd_config.d/*.conf`, and for most settings sshd keeps the first value it reads. So a line in a drop-in file beats the same setting further down the main file. An edit to the main file that seems right changes nothing. `sshd -T` prints the configuration sshd really uses, and settles the question.

### Least privilege for people on the node

**Least privilege** means each user and each program gets the rights its job needs and nothing more. On a Linux node, the big right is `sudo`. Two places grant it on Ubuntu: membership in the `sudo` group, and files under `/etc/sudoers.d/`. A user who needs no root keeps the account but loses both. A user who left keeps the files for the audit trail, but the account gets locked with `passwd -l`.

A kubeconfig file is also a key. `/etc/kubernetes/admin.conf` holds a client certificate for a cluster administrator, and Kubernetes has no revocation list, so nothing stops a client certificate before it expires. A copy in somebody's home folder or a backup folder stays a full admin key for up to a year. Delete every copy you find, and keep the node's own kubeconfig files readable by root only. In a real incident, you'd also rotate the certificate authority, which is beyond the exam.

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

## Task 4: A listener that hides

**Time budget:** 5 minutes. **Host:** `cks-w1`.

```bash
./certs/cks/task.sh setup 3.4
```

> Something on `cks-w1` listens on TCP port 4444. No package owns it. Stop it for good: the process, whatever starts it at boot, and its binary. Leave the system's packages alone.

<details>
<summary>Solution</summary>

```bash
ss -tlnp | grep ':4444 '
ls -l /proc/<pid>/exe
systemctl status <pid> | head -1
```

In the test run, `ss` showed `users:(("sysmond",pid=33256,fd=5))`, the link pointed to `/usr/local/lib/.sysmon/sysmond`, and `systemctl status` named `sysmon.service`. The unit file shows what it does: `sysmond TCP-LISTEN:4444,fork,reuseaddr EXEC:/bin/sh`. That's a copy of `socat` handing a root shell to anybody who connects. `dpkg -S /usr/local/lib/.sysmon/sysmond` finds no package, which is the giveaway.

```bash
systemctl disable --now sysmon
rm /etc/systemd/system/sysmon.service
systemctl daemon-reload
rm -rf /usr/local/lib/.sysmon
```

Kill only the process, and `Restart=always` starts it again a moment later. Delete only the binary, and the next boot fails to start it but the unit stays as a clue for the next attacker. Remove all three.

</details>

```bash
./certs/cks/task.sh check 3.4
```

```
  PASS  nothing listens on TCP port 4444
  PASS  systemd knows no sysmon unit any more
  PASS  the binary behind it is gone
  PASS  the socat package stays installed
```

## Task 5: Harden sshd

**Time budget:** 4 minutes. **Host:** `cks-w1`.

```bash
./certs/cks/task.sh setup 3.5
```

> On `cks-w1`, sshd must refuse root logins and password logins. It must keep running.

<details>
<summary>Solution</summary>

Ask sshd what it uses before you edit anything, then find where each value comes from:

```bash
sshd -T | grep -E '^(permitrootlogin|passwordauthentication) '
grep -rnE '^(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
```

In the test run, both lines came from `/etc/ssh/sshd_config.d/10-legacy.conf`. Change them there to `PermitRootLogin no` and `PasswordAuthentication no`, then test the syntax and restart:

```bash
sshd -t && systemctl restart ssh
sshd -T | grep -E '^(permitrootlogin|passwordauthentication) '
```

`sshd -t` checks the files first, so a typo doesn't leave the node without SSH. On Ubuntu 24.04 the service's name is `ssh`, not `sshd`.

</details>

```bash
./certs/cks/task.sh check 3.5
```

```
  PASS  sshd's effective config says permitrootlogin no
  PASS  sshd's effective config says passwordauthentication no
  PASS  sshd runs, with the new config loaded
```

## Task 6: Admin credentials lying around

**Time budget:** 4 minutes. **Host:** `cks-w1`.

```bash
./certs/cks/task.sh setup 3.6
```

The setup shows what the leak gives away. In the test run: `kubectl auth can-i "*" "*" as cks-ops on cks-w1: yes`.

> Somebody copied the cluster's admin kubeconfig onto the worker `cks-w1`. Remove every copy from the node. Keep user `cks-ops`. Also make `/etc/kubernetes/kubelet.conf` readable by root only.

<details>
<summary>Solution</summary>

An admin kubeconfig embeds its certificate as `client-certificate-data`. The kubelet's own file points to a certificate file instead, so a search for the embedded form finds the copies:

```bash
grep -rlsE 'client-certificate-data' /home /root /var/backups /tmp /etc
rm /home/cks-ops/.kube/config /var/backups/k8s/admin.conf.bak
chmod 600 /etc/kubernetes/kubelet.conf && chown root:root /etc/kubernetes/kubelet.conf
```

In the test run, the search found `/home/cks-ops/.kube/config` and `/var/backups/k8s/admin.conf.bak`. The theory explains why deleting the files is only the first half of a real response: the certificate inside stays valid until it expires.

</details>

```bash
./certs/cks/task.sh check 3.6
```

```
  PASS  no file on cks-w1 holds the admin client certificate any more
  PASS  user cks-ops still exists
  PASS  /etc/kubernetes/kubelet.conf is 600 and owned by root
```

## Task 7: Keep a kernel module out

**Time budget:** 4 minutes. **Host:** `cks-lima`.

```bash
./certs/cks/cluster/lima.sh start      # once, when the VM is off
./certs/cks/task.sh setup 3.7
```

> On `cks-lima`, the kernel holds the modules `dccp` and `tipc`. Unload them, and make sure no later request loads them again. Put the rules in a file under `/etc/modprobe.d/`.

<details>
<summary>Solution</summary>

```bash
cat > /etc/modprobe.d/cks-blacklist.conf <<EOF
install dccp /bin/false
blacklist dccp
install tipc /bin/false
blacklist tipc
EOF
modprobe -r dccp tipc
lsmod | grep -E '^(dccp|tipc) '       # prints nothing
modprobe -n -v tipc                    # install /bin/false
```

In the test run, a direct `modprobe tipc` afterwards failed with `Error running install command '/bin/false' for module tipc: retcode 1`. The `sctp` module sat in the kernel too, with 8 users, and refused to unload. That's why the task picks two modules nobody uses.

</details>

```bash
./certs/cks/task.sh check 3.7
```

```
  PASS  tipc is not loaded
  PASS  modprobe refuses to load tipc
  PASS  dccp is not loaded, and modprobe refuses it
  PASS  the rule lives in a file under /etc/modprobe.d
```

## Clean up

Task 3 restarts the API server twice, once in the setup and once in your fix. `./certs/cks/cluster/reset.sh` wipes the users, units and packages of tasks 1 to 6 too, and `./certs/cks/cluster/lima.sh reset` removes task 7's file.
