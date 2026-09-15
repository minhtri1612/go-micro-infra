#!/usr/bin/env bash
set -euo pipefail

INFRA_DIR="${1:-$HOME/go-micro-infra}"

echo "==> Checking tools"
go-micro-check-tools

if [[ ! -d "${INFRA_DIR}/.git" ]]; then
  echo "==> Cloning go-micro-infra to ${INFRA_DIR}"
  git clone https://github.com/minhtri1612/go-micro-infra.git "${INFRA_DIR}"
fi

echo "==> Infra ready at ${INFRA_DIR}"
echo "Next: clone go-micro-gitops and follow ${INFRA_DIR}/kind/README.md"
