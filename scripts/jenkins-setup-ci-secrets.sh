#!/bin/bash
# Tạo Secret jenkins-ci-env trên cụm management → Jenkins JCasC đọc thành
# dockerhub-credentials + github-go-micro-pat (KHÔNG cần tạo tay trên UI).
#
# KHÔNG dùng AWS key ESO (access-key-id / secret-access-key trong external-secrets).
#   - ESO  → IAM đọc AWS Secrets Manager (DB, Stripe, …)
#   - Docker Hub → token tại https://hub.docker.com → Account Settings → Security
#   - GitHub     → PAT (repo scope) để push env/dev.yaml
#
# Usage — lần đầu:
#   cp scripts/jenkins-ci.env.example scripts/jenkins-ci.env  # CHỈ MỘT LẦN
#   # sửa DOCKERHUB_TOKEN + GITHUB_PAT trong jenkins-ci.env
#   bash scripts/jenkins-apply-ci-secrets.sh
#
# Sau reboot / Kind cluster lên lại (giữ nguyên jenkins-ci.env, KHÔNG cp example):
#   bash scripts/jenkins-apply-ci-secrets.sh
#   kubectl -n jenkins delete pod jenkins-management-0
set -euo pipefail

CTX="${JENKINS_KUBE_CONTEXT:-kind-management}"
NS="${JENKINS_NAMESPACE:-jenkins}"
SECRET_NAME="${JENKINS_CI_SECRET_NAME:-jenkins-ci-env}"

: "${DOCKERHUB_USER:?Set DOCKERHUB_USER (Hub username)}"
: "${DOCKERHUB_TOKEN:?Set DOCKERHUB_TOKEN (Hub Access Token — KHÔNG phải AWS secret ESO)}"
: "${GITHUB_PAT:?Set GITHUB_PAT (GitHub PAT để git push)}"
GITHUB_USER="${GITHUB_USER:-$DOCKERHUB_USER}"

kubectl --context "$CTX" create namespace "$NS" --dry-run=client -o yaml | kubectl --context "$CTX" apply -f -

kubectl --context "$CTX" -n "$NS" create secret generic "$SECRET_NAME" \
  --from-literal=DOCKERHUB_USER="$DOCKERHUB_USER" \
  --from-literal=DOCKERHUB_PASSWORD="$DOCKERHUB_TOKEN" \
  --from-literal=GITHUB_USER="$GITHUB_USER" \
  --from-literal=GITHUB_PAT="$GITHUB_PAT" \
  --dry-run=client -o yaml | kubectl --context "$CTX" apply -f -

echo "OK: secret/$SECRET_NAME in $NS on $CTX"
echo "Next: argocd app sync jenkins-management"
echo "      kubectl --context $CTX -n $NS delete pod jenkins-management-0"
echo "      (JCasC tạo credential dockerhub-credentials + github-go-micro-pat lúc pod lên)"
