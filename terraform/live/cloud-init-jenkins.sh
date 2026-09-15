#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

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

cat >/usr/local/bin/go-micro-check-tools <<'EOF'
#!/bin/bash
set -e
echo "docker: $(docker --version)"
echo "compose: $(docker compose version)"
echo "git: $(git --version)"
EOF
chmod +x /usr/local/bin/go-micro-check-tools

cat >/etc/motd <<'EOF'
go-micro Jenkins host (CI). Kind/Argo is a separate EC2.

  git clone https://github.com/minhtri1612/go-micro-infra.git ~/go-micro-infra
  cd ~/go-micro-infra/jenkins
  cp .env.example .env
  docker compose up -d --build
  follow README.md
EOF
