# Jenkins controller chạy trên EC2 riêng — không deploy vào Kind.
FROM jenkins/jenkins:2.492.3-lts-jdk17

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates git \
  && curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-27.5.1.tgz" -o /tmp/docker.tgz \
  && tar -xzf /tmp/docker.tgz -C /tmp && mv /tmp/docker/docker /usr/local/bin/docker \
  && chmod +x /usr/local/bin/docker \
  && rm -rf /tmp/docker.tgz /tmp/docker \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt

USER jenkins
