#!/usr/bin/env bash
# DevOps-owned Terraform runner for Jenkins. Not go-micro-ci.
set -euo pipefail

CHDIR="terraform/environments/management"
ACTION="${1:?usage: run.sh plan|apply|destroy-target}"

: "${TF_STATE_BUCKET:?set TF_STATE_BUCKET}"
: "${AWS_ACCESS_KEY_ID:?}"
: "${AWS_SECRET_ACCESS_KEY:?}"
: "${TF_VAR_db_password:?}"
: "${TF_VAR_stripe_secret_key:?}"
: "${TF_VAR_admin_ingress_cidr:?}"

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-southeast-2}"
export TF_IN_AUTOMATION=1
export TF_INPUT=0

write_backend() {
  cat >"${CHDIR}/backend.hcl" <<EOF
bucket       = "${TF_STATE_BUCKET}"
key          = "management/terraform.tfstate"
region       = "${AWS_DEFAULT_REGION}"
encrypt      = true
use_lockfile = true
EOF
}

tf() {
  terraform -chdir="${CHDIR}" "$@"
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

write_backend
tf init -backend-config=backend.hcl -input=false -no-color
tf fmt -check
tf validate -no-color

case "${ACTION}" in
  plan)
    tf plan -input=false -no-color -out=tfplan | tee "${CHDIR}/plan.txt"
    summarize_plan "${CHDIR}/plan.txt" | tee "${CHDIR}/plan-summary.txt"
    ;;
  apply)
    tf plan -input=false -no-color -out=tfplan | tee "${CHDIR}/plan.txt"
    summarize_plan "${CHDIR}/plan.txt" | tee "${CHDIR}/plan-summary.txt"
    if [[ "${SKIP_PR_COMPARE:-true}" != "true" ]]; then
      : "${PR_PLAN_SUMMARY:?PR_PLAN_SUMMARY required when SKIP_PR_COMPARE=false}"
      got="$(cat "${CHDIR}/plan-summary.txt")"
      if [[ "${got}" != "${PR_PLAN_SUMMARY}" ]]; then
        echo "plan mismatch: PR ${PR_PLAN_SUMMARY} vs apply ${got}" >&2
        exit 1
      fi
    fi
    tf apply -input=false -no-color tfplan
    ;;
  destroy-target)
    TARGET="${2:?destroy-target needs module address}"
    case "${TARGET}" in
      module.kind_host) ;;
      *)
        echo "destroy-target allowlist: module.kind_host only (not jenkins/vpc)" >&2
        exit 1
        ;;
    esac
    if [[ "${TARGET}" == *jenkins* ]]; then
      echo "refusing TARGET that mentions jenkins" >&2
      exit 1
    fi
    tf destroy -input=false -no-color -auto-approve -target="${TARGET}"
    ;;
  *)
    echo "unknown action ${ACTION}" >&2
    exit 1
    ;;
esac
