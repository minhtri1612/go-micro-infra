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

# IMDSv2 only (http_tokens = required on this instance).
IMDS_TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

mkdir -p /etc/rancher/rke2
cat >/etc/rancher/rke2/config.yaml <<EOT
token: ${rke2_token}
write-kubeconfig-mode: "0644"
# Canal is the RKE2 default CNI; Traefik comes from Argo CD, so the bundled
# ingress-nginx must stay off or it fights for the same NodePorts.
disable:
  - rke2-ingress-nginx
tls-san:
  - "${api_dns_name}"
  - "$PRIVATE_IP"
# Server is control-plane only. Workloads (Argo CD, Traefik, apps) land on agents.
node-taint:
  - "node-role.kubernetes.io/control-plane:NoSchedule"
EOT

curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=server INSTALL_RKE2_VERSION="${rke2_version}" sh -
systemctl enable --now rke2-server

# Shell access to this node is SSM only; there is no port 22 in any SG.
snap list amazon-ssm-agent >/dev/null 2>&1 || snap install amazon-ssm-agent --classic
snap start amazon-ssm-agent || true

cat >/etc/profile.d/rke2.sh <<'PROFILE'
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
PROFILE
chmod +x /etc/profile.d/rke2.sh
ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
ln -sf /var/lib/rancher/rke2/bin/crictl /usr/local/bin/crictl

timeout 600 bash -c 'until /var/lib/rancher/rke2/bin/kubectl \
  --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes >/dev/null 2>&1; do sleep 10; done' || true
