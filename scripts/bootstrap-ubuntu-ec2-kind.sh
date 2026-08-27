#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${1:-$HOME/go-micro}"

echo "==> Checking tools"
go-micro-check-tools

if [[ ! -d "${REPO_DIR}/.git" ]]; then
  echo "==> Cloning repo to ${REPO_DIR}"
  git clone https://github.com/minhtri1612/go-micro.git "${REPO_DIR}"
fi

cd "${REPO_DIR}"

echo "==> Repo ready at ${REPO_DIR}"
echo
echo "Next:"
echo "  cd ${REPO_DIR}"
echo "  sed -n '1,120p' kind/README.md"
echo
echo "Suggested first commands:"
echo "  kind version"
echo "  kubectl version --client"
echo "  helm version"
echo "  docker ps"
