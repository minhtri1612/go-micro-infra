#!/usr/bin/env bash
# GitHub helpers for Terraform Jenkins jobs. Needs GITHUB_PAT.
set -euo pipefail

REPO="${GITHUB_REPO:-minhtri1612/go-micro-infra}"
API="https://api.github.com"
CONTEXT="${GITHUB_STATUS_CONTEXT:-terraform-plan}"
: "${GITHUB_PAT:?GITHUB_PAT required}"

github() {
  curl -sS -H "Authorization: Bearer ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

github_f() {
  curl -sS -f -H "Authorization: Bearer ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

cmd="${1:?usage: github.sh status|comment-plan|pr-summary ...}"
shift

case "${cmd}" in
  status)
    sha="${1:?sha}"
    state="${2:?pending|success|failure|error}"
    desc="${3:-}"
    jq -n \
      --arg state "${state}" \
      --arg description "${desc:0:140}" \
      --arg target_url "${BUILD_URL:-}" \
      --arg context "${CONTEXT}" \
      '{state:$state, description:$description, target_url:$target_url, context:$context}' |
      github_f -X POST --data-binary @- "${API}/repos/${REPO}/statuses/${sha}" >/dev/null
    ;;
  comment-plan)
    pr="${1:?pr number}"
    summary="$(cat terraform/environments/management/plan-summary.txt)"
    jq -n --arg summary "${summary}" --arg url "${BUILD_URL:-}" '{
      body: ("terraform plan (management)\n\n`" + $summary + "`\n\nBuild: " + $url + "\n\n<!-- tf-plan-summary:" + $summary + " -->")
    }' | github_f -X POST --data-binary @- "${API}/repos/${REPO}/issues/${pr}/comments" >/dev/null
    ;;
  pr-summary)
    sha="${1:?commit sha}"
    prs="$(github -H "Accept: application/vnd.github.groot-preview+json" \
      "${API}/repos/${REPO}/commits/${sha}/pulls" || echo '[]')"
    pr="$(echo "${prs}" | jq -r '.[0].number // empty')"
    if [[ -z "${pr}" ]]; then
      echo ""
      exit 0
    fi
    github "${API}/repos/${REPO}/issues/${pr}/comments" |
      jq -r '.[].body' |
      sed -n 's/.*<!-- tf-plan-summary:\([^>]*\) -->.*/\1/p' |
      tail -n1
    ;;
  *)
    echo "unknown ${cmd}" >&2
    exit 1
    ;;
esac
