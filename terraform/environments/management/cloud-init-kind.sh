#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

KUBECTL_VERSION=v1.28.15
KIND_VERSION=v0.30.0
HELM_VERSION=v3.16.4
ARGOCD_VERSION=v2.14.15

apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  unzip \
  apt-transport-https

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

snap install amazon-ssm-agent --classic
systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service

cat >/etc/sysctl.d/99-go-micro-kind.conf <<'EOF'
fs.inotify.max_user_watches=1048576
fs.inotify.max_user_instances=8192
fs.file-max=2097152
EOF
sysctl --system

curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tgz
tar -xzf /tmp/helm.tgz -C /tmp
install -m 755 /tmp/linux-amd64/helm /usr/local/bin/helm
rm -rf /tmp/helm.tgz /tmp/linux-amd64

curl -Lo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
chmod +x /usr/local/bin/kind

curl -sSL -o /tmp/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
install -m 555 /tmp/argocd /usr/local/bin/argocd
rm -f /tmp/argocd

cat >/usr/local/bin/go-micro-check-tools <<'EOF'
#!/bin/bash
set -e
echo "docker: $(docker --version)"
echo "kind: $(kind version)"
echo "kubectl: $(kubectl version --client --output=yaml | grep gitVersion | head -1)"
echo "helm: $(helm version --short)"
echo "argocd: $(argocd version --client --short | head -1)"
EOF
chmod +x /usr/local/bin/go-micro-check-tools

cat >/etc/motd <<'EOF'
go-micro Kind host (cluster + Argo CD). Jenkins is a separate EC2.

  git clone https://github.com/minhtri1612/go-micro-infra.git ~/go-micro-infra
  git clone https://github.com/minhtri1612/go-micro-gitops.git ~/go-micro-gitops
  go-micro-check-tools
  follow ~/go-micro-infra/kind/README.md
EOF
