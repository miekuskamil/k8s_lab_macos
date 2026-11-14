# Domain 03, system hardening. Functions for task.sh: setup_3_N, check_3_N, solve_3_N.

# ---- Task 1: remove a service nobody needs -------------------------------------------
setup_3_1() {
  onw1 <<'EOF'
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq vsftpd >/dev/null
systemctl enable --now vsftpd >/dev/null 2>&1
ss -tlnp | grep ':21 ' || echo "vsftpd not listening"
EOF
}
check_3_1() {
  check_w1 "nothing listens on TCP port 21" "! ss -tln | grep -q ':21 '"
  check_w1 "the package vsftpd is removed" "! dpkg -l vsftpd 2>/dev/null | grep -q '^ii'"
}
solve_3_1() {
  onw1 <<'EOF'
ss -tlnp | grep ':21 '
dpkg -S "$(command -v vsftpd || echo /usr/sbin/vsftpd)"
systemctl disable --now vsftpd
apt-get purge -y -qq vsftpd >/dev/null
EOF
}

# ---- Task 2: a user with too much power ----------------------------------------------
setup_3_2() {
  onw1 <<'EOF'
id cks-dev >/dev/null 2>&1 || useradd -m -s /bin/bash cks-dev
usermod -aG sudo cks-dev
echo 'cks-dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/cks-dev && chmod 440 /etc/sudoers.d/cks-dev
id old-admin >/dev/null 2>&1 || useradd -m -s /bin/bash old-admin
echo 'old-admin:0ld-admin' | chpasswd
usermod -U old-admin 2>/dev/null; true
EOF
}
check_3_2() {
  check_w1 "cks-dev is no longer in the sudo group" "! id -nG cks-dev | tr ' ' '\n' | grep -qx sudo"
  check_w1 "sudo grants cks-dev nothing" "sudo -l -U cks-dev | grep -q 'not allowed to run sudo'"
  check_w1 "cks-dev still exists" "id cks-dev"
  check_w1 "old-admin's password is locked" "passwd -S old-admin | awk '{print \$2}' | grep -qx L"
}
solve_3_2() {
  onw1 <<'EOF'
gpasswd -d cks-dev sudo
grep -rl cks-dev /etc/sudoers /etc/sudoers.d/
rm -f /etc/sudoers.d/cks-dev
passwd -l old-admin
sudo -l -U cks-dev
EOF
}

# ---- Task 3: limit what a kubelet may change -----------------------------------------
setup_3_3() {
  oncp <<'EOF'
f=/etc/kubernetes/manifests/kube-apiserver.yaml
cp $f /root/kube-apiserver.yaml.before-3.3
sed -i 's/--enable-admission-plugins=NodeRestriction$/--enable-admission-plugins=AlwaysAdmit/' $f
grep -- --enable-admission-plugins $f
EOF
  sleep 5; wait_api
}
check_3_3() {
  check_cp "the API server enables NodeRestriction" \
    "grep -- '--enable-admission-plugins=' /etc/kubernetes/manifests/kube-apiserver.yaml | grep -q NodeRestriction"
  check_cp "the API server no longer enables AlwaysAdmit" \
    "! grep -- '--enable-admission-plugins=' /etc/kubernetes/manifests/kube-apiserver.yaml | grep -q AlwaysAdmit"
  check "cks-w1's kubelet may not label node cks-cp (the Node authorizer already blocks this)" bash -c "! orb -m $CKS_W1 -u root kubectl --kubeconfig /etc/kubernetes/kubelet.conf label node cks-cp cks-test=1 --overwrite"
  check "cks-w1's kubelet may not set a node-restriction label on itself" \
    bash -c "! orb -m $CKS_W1 -u root kubectl --kubeconfig /etc/kubernetes/kubelet.conf label node cks-w1 node-restriction.kubernetes.io/cks=1 --overwrite"
  k label node cks-cp cks-test- >/dev/null 2>&1
  k label node cks-w1 node-restriction.kubernetes.io/cks- >/dev/null 2>&1
}
solve_3_3() {
  cp_sh "sed -i 's/--enable-admission-plugins=AlwaysAdmit\$/--enable-admission-plugins=NodeRestriction/' /etc/kubernetes/manifests/kube-apiserver.yaml"
  sleep 5; wait_api
}

# ---- Task 4: a listener that hides --------------------------------------------------------
setup_3_4() {
  onw1 <<'EOF'
mkdir -p /usr/local/lib/.sysmon
cp /usr/bin/socat /usr/local/lib/.sysmon/sysmond
cat > /etc/systemd/system/sysmon.service <<'UNIT'
[Unit]
Description=System monitor agent
After=network-online.target

[Service]
ExecStart=/usr/local/lib/.sysmon/sysmond TCP-LISTEN:4444,fork,reuseaddr EXEC:/bin/sh
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now sysmon >/dev/null 2>&1
sleep 1
ss -tlnp | grep ':4444 ' || echo "  nothing on 4444"
EOF
}
check_3_4() {
  check_w1 "nothing listens on TCP port 4444" "! ss -tln | grep -q ':4444 '"
  check_w1 "systemd knows no sysmon unit any more" "! systemctl cat sysmon >/dev/null 2>&1"
  check_w1 "the binary behind it is gone" "test ! -e /usr/local/lib/.sysmon/sysmond"
  check_w1 "the socat package stays installed" "dpkg -l socat | grep -q '^ii'"
}
solve_3_4() {
  onw1 <<'EOF'
ss -tlnp | grep ':4444 '
pid=$(ss -tlnp | grep ':4444 ' | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)
ls -l /proc/$pid/exe
systemctl status $pid --no-pager | head -1
systemctl disable --now sysmon
rm -f /etc/systemd/system/sysmon.service
systemctl daemon-reload
rm -rf /usr/local/lib/.sysmon
EOF
}

# ---- Task 5: harden sshd ------------------------------------------------------------------
setup_3_5() {
  onw1 <<'EOF'
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server >/dev/null
mkdir -p /etc/ssh/sshd_config.d
printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/10-legacy.conf
systemctl enable ssh >/dev/null 2>&1; systemctl restart ssh
sshd -T | grep -E '^(permitrootlogin|passwordauthentication) '
EOF
}
check_3_5() {
  check_w1 "sshd's effective config says permitrootlogin no" "sshd -T | grep -qx 'permitrootlogin no'"
  check_w1 "sshd's effective config says passwordauthentication no" "sshd -T | grep -qx 'passwordauthentication no'"
  check_w1 "sshd runs, with the new config loaded" \
    "systemctl is-active -q ssh && [ \$(systemctl show ssh -p ActiveEnterTimestampMonotonic --value) -gt 0 ] && ss -tln | grep -q ':22 '"
}
solve_3_5() {
  onw1 <<'EOF'
sshd -T | grep -E '^(permitrootlogin|passwordauthentication) '
grep -rnE '^(PermitRootLogin|PasswordAuthentication)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
sed -i -e 's/^PermitRootLogin .*/PermitRootLogin no/' -e 's/^PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config.d/10-legacy.conf
sshd -t && systemctl restart ssh
sshd -T | grep -E '^(permitrootlogin|passwordauthentication) '
EOF
}

# ---- Task 6: admin credentials lying around ------------------------------------------------
setup_3_6() {
  cp_sh 'cat /etc/kubernetes/admin.conf' | w1_sh '
id cks-ops >/dev/null 2>&1 || useradd -m -s /bin/bash cks-ops
mkdir -p /home/cks-ops/.kube /var/backups/k8s
cat > /home/cks-ops/.kube/config
cp /home/cks-ops/.kube/config /var/backups/k8s/admin.conf.bak
chown -R cks-ops:cks-ops /home/cks-ops/.kube
chmod 644 /home/cks-ops/.kube/config /var/backups/k8s/admin.conf.bak /etc/kubernetes/kubelet.conf
echo "  kubectl auth can-i \"*\" \"*\" as cks-ops on cks-w1: $(sudo -u cks-ops kubectl auth can-i "*" "*" 2>&1)"'
}
# The first 60 characters of the admin client certificate identify every copy of admin.conf.
admin_fp() { cp_sh "grep client-certificate-data /etc/kubernetes/admin.conf | awk '{print \$2}' | cut -c1-60"; }
check_3_6() {
  local fp; fp="$(admin_fp)"
  check_w1 "no file on cks-w1 holds the admin client certificate any more" \
    "! grep -rlsF '$fp' /home /root /var/backups /tmp /etc 2>/dev/null | grep -q ."
  check_w1 "user cks-ops still exists" "id cks-ops"
  check_w1 "/etc/kubernetes/kubelet.conf is 600 and owned by root" "stat -c '%a %U' /etc/kubernetes/kubelet.conf | grep -qx '600 root'"
}
solve_3_6() {
  onw1 <<'EOF'
grep -rlsE 'client-certificate-data' /home /root /var/backups /tmp 2>/dev/null
rm -f /home/cks-ops/.kube/config /var/backups/k8s/admin.conf.bak
chmod 600 /etc/kubernetes/kubelet.conf
chown root:root /etc/kubernetes/kubelet.conf
EOF
}

# ---- Task 7: keep a kernel module out (Lima) -----------------------------------------------
setup_3_7() {
  need_lima || return 1
  onlima <<'EOF'
rm -f /etc/modprobe.d/cks-*.conf
modprobe tipc 2>/dev/null; modprobe dccp 2>/dev/null
lsmod | grep -E '^(tipc|dccp) ' || echo "  neither module loads on this kernel"
EOF
}
check_3_7() {
  check_lima "tipc is not loaded" "! lsmod | grep -q '^tipc '"
  check_lima "modprobe refuses to load tipc" "modprobe -n -v tipc 2>&1 | grep -q 'install /bin/false'"
  check_lima "dccp is not loaded, and modprobe refuses it" "! lsmod | grep -q '^dccp ' && modprobe -n -v dccp 2>&1 | grep -q 'install /bin/false'"
  check_lima "the rule lives in a file under /etc/modprobe.d" "grep -rqsE '^install +tipc +/bin/false' /etc/modprobe.d/"
}
solve_3_7() {
  need_lima || return 1
  onlima <<'EOF'
printf 'install tipc /bin/false\nblacklist tipc\ninstall dccp /bin/false\nblacklist dccp\n' > /etc/modprobe.d/cks-blacklist.conf
modprobe -r tipc 2>/dev/null; modprobe -r dccp 2>/dev/null
lsmod | grep -E '^(tipc|dccp) ' || echo "neither module loaded"
modprobe -n -v tipc
EOF
}
