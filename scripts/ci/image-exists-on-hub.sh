#!/usr/bin/env bash
# Usage: image-exists-on-hub.sh <image-tag>
# Exit 0 nếu minhtri1612/go-microservice:<tag> có trên Docker Hub.
set -euo pipefail
tag="${1:?tag}"
repo="${IMAGE_REPO:-minhtri1612/go-microservice}"
if docker manifest inspect "${repo}:${tag}" >/dev/null 2>&1; then
  exit 0
fi
echo "NOT on Hub: ${repo}:${tag}" >&2
exit 1
