#!/usr/bin/env bash
# DevOps-owned Terraform runner for Jenkins. Not go-micro-ci.
set -euo pipefail

ACTION="${1:?usage: run.sh plan|apply|destroy-all}"

: "${TF_STATE_BUCKET:?set TF_STATE_BUCKET}"
: "${AWS_ACCESS_KEY_ID:?}"
: "${AWS_SECRET_ACCESS_KEY:?}"

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-southeast-2}"
export TF_IN_AUTOMATION=1
export TF_INPUT=0

use_stack() {
  STACK="$1"
  case "${STACK}" in
    rke2-management | rke2-dev | rke2-prod | networking) ;;
    *)
      echo "TF_STACK allowlist: rke2-management rke2-dev rke2-prod networking" >&2
      exit 1
      ;;
  esac
  CHDIR="terraform/environments/${STACK}"
  cat >"${CHDIR}/backend.hcl" <<EOF
bucket       = "${TF_STATE_BUCKET}"
key          = "${STACK}/terraform.tfstate"
region       = "${AWS_DEFAULT_REGION}"
encrypt      = true
use_lockfile = true
EOF
}

tf() {
  terraform -chdir="${CHDIR}" "$@"
}

prepare() {
  use_stack "$1"
  tf init -backend-config=backend.hcl -input=false -no-color
  tf fmt -check
  tf validate -no-color
}

summarize_plan() {
  local txt="$1"
  if grep -q 'No changes' "${txt}"; then
    echo "add=0 change=0 destroy=0"
    return
  fi
  local line
  line="$(grep -E '^Plan: ' "${txt}" | tail -n1 || true)"
  if [[ -z "${line}" ]]; then
    echo "could not parse plan summary" >&2
    exit 1
  fi
  echo "${line}" | sed -n 's/^Plan: \([0-9]*\) to add, \([0-9]*\) to change, \([0-9]*\) to destroy.*/add=\1 change=\2 destroy=\3/p'
}

case "${ACTION}" in
  plan)
    prepare "${TF_STACK:-rke2-management}"
    tf plan -input=false -no-color -out=tfplan | tee "${CHDIR}/plan.txt"
    summarize_plan "${CHDIR}/plan.txt" | tee "${CHDIR}/plan-summary.txt"
    ;;
  apply)
    prepare "${TF_STACK:-rke2-management}"
    tf plan -input=false -no-color -out=tfplan | tee "${CHDIR}/plan.txt"
    summarize_plan "${CHDIR}/plan.txt" | tee "${CHDIR}/plan-summary.txt"
    if [[ "${SKIP_PR_COMPARE:-false}" != "true" ]]; then
      : "${PR_PLAN_SUMMARY:?PR_PLAN_SUMMARY required when SKIP_PR_COMPARE=false}"
      got="$(cat "${CHDIR}/plan-summary.txt")"
      if [[ "${got}" != "${PR_PLAN_SUMMARY}" ]]; then
        echo "plan mismatch: PR ${PR_PLAN_SUMMARY} vs apply ${got}" >&2
        exit 1
      fi
    fi
    tf apply -input=false -no-color tfplan
    ;;
  destroy-all | destroy-target)
    # Peering first, then the two app clusters, management last.
    # Management includes this Jenkins EC2, so the build can die on that last stack.
    for stack in networking rke2-dev rke2-prod rke2-management; do
      echo "=== destroy ${stack} ==="
      prepare "${stack}"
      tf destroy -auto-approve -input=false -no-color
    done
    ;;
  *)
    echo "unknown action ${ACTION}" >&2
    exit 1
    ;;
esac
