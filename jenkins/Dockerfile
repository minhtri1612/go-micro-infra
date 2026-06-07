# Jenkins controller có plugin đóng gói sẵn — cluster không cần init tải plugin mỗi lần pod lên.
# Build & push Hub (chạy từ ROOT repo go-micro):
#   docker build -t minhtri1612/jenkins-custom:2.504.1-lts-jdk17-pkg1 -f jenkins/Dockerfile jenkins
# Hoặc đã cd vào thư mục jenkins/:
#   docker build -t minhtri1612/jenkins-custom:2.504.1-lts-jdk17-pkg1 -f Dockerfile .
#   docker push minhtri1612/jenkins-custom:2.504.1-lts-jdk17-pkg1
# Kind (không qua Hub): kind load docker-image minhtri1612/jenkins-custom:2.504.1-lts-jdk17-pkg1 --name management
# Core LTS ≥ 2.504.1 (configuration-as-code + kubernetes plugin trên Update Center hiện tại).
FROM jenkins/jenkins:2.504.1-lts-jdk17

USER root

# Provide kubectl in controller for pipelines that spawn test pods in kind-dev.
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates \
  && curl -fsSL "https://dl.k8s.io/release/v1.28.15/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
  && curl -fsSL "https://github.com/argoproj/argo-rollouts/releases/download/v1.8.3/kubectl-argo-rollouts-linux-amd64" -o /usr/local/bin/kubectl-argo-rollouts \
  && curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-27.5.1.tgz" -o /tmp/docker.tgz \
  && tar -xzf /tmp/docker.tgz -C /tmp && mv /tmp/docker/docker /usr/local/bin/docker \
  && chmod +x /usr/local/bin/docker /usr/local/bin/kubectl /usr/local/bin/kubectl-argo-rollouts \
  && rm -rf /tmp/docker.tgz /tmp/docker \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# DinD sidecar trong jenkins-values (DOCKER_HOST → daemon trong cùng pod).
ENV DOCKER_HOST=tcp://127.0.0.1:2375

USER jenkins

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt

# Cài vào ref — entrypoint copy vào JENKINS_HOME khi PVC trống / thiếu plugin (theo README jenkinsci/docker).
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt
