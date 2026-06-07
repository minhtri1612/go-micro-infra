#!/bin/bash
# Apply jenkins-ci-env từ file local — KHÔNG ghi đè jenkins-ci.env từ .example.
#
# Lần đầu (một lần duy nhất):
#   cp scripts/jenkins-ci.env.example scripts/jenkins-ci.env
#   # sửa DOCKERHUB_TOKEN + GITHUB_PAT trong jenkins-ci.env
#
# Sau mỗi lần reboot / cluster mới — CHỈ chạy script này:
#   bash scripts/jenkins-apply-ci-secrets.sh
#   kubectl -n jenkins delete pod jenkins-management-0   # optional, reload JCasC creds
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/scripts/jenkins-ci.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Thiếu $ENV_FILE" >&2
  echo "Lần đầu: cp scripts/jenkins-ci.env.example scripts/jenkins-ci.env && sửa token" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"
bash "$ROOT/scripts/jenkins-setup-ci-secrets.sh"
