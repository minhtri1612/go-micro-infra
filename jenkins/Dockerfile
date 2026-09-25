# LTS hiện tại: plugin latest (git, github, CASC…) đòi core >= 2.504.3.
FROM jenkins/jenkins:lts-jdk17

USER root

ARG TF_VERSION=1.16.4

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates git unzip jq \
  && arch="$(uname -m)" \
  && case "${arch}" in x86_64) dockerarch=x86_64; tfarch=amd64 ;; aarch64) dockerarch=aarch64; tfarch=arm64 ;; *) echo "unsupported arch ${arch}"; exit 1 ;; esac \
  && curl -fsSL "https://download.docker.com/linux/static/stable/${dockerarch}/docker-27.5.1.tgz" -o /tmp/docker.tgz \
  && tar -xzf /tmp/docker.tgz -C /tmp && mv /tmp/docker/docker /usr/local/bin/docker \
  && chmod +x /usr/local/bin/docker \
  && curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${tfarch}.zip" -o /tmp/tf.zip \
  && unzip -o /tmp/tf.zip -d /usr/local/bin \
  && chmod +x /usr/local/bin/terraform \
  && rm -rf /tmp/docker.tgz /tmp/docker /tmp/tf.zip \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt

USER jenkins
