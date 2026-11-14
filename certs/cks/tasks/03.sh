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
