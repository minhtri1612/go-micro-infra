#!/bin/bash
set -euxo pipefail

swapoff -a || true
sed -i 's@^\([^#].*swap.*\)$@# \1@' /etc/fstab || true
modprobe overlay || true
modprobe br_netfilter || true
cat >/etc/sysctl.d/99-rke2.conf <<'SYSCTL'
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward                = 1
SYSCTL
sysctl --system || true

mkdir -p /etc/rancher/rke2
cat >/etc/rancher/rke2/config.yaml <<EOT
server: https://${master_ip}:9345
token: ${rke2_token}
EOT

curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=agent INSTALL_RKE2_VERSION="${rke2_version}" sh -
systemctl enable --now rke2-agent

snap list amazon-ssm-agent >/dev/null 2>&1 || snap install amazon-ssm-agent --classic
snap start amazon-ssm-agent || true

cat >/etc/profile.d/rke2.sh <<'PROFILE'
export PATH=$PATH:/var/lib/rancher/rke2/bin
PROFILE
chmod +x /etc/profile.d/rke2.sh
