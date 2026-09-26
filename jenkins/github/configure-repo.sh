#!/usr/bin/env bash
# Run on Jenkins host after compose is up: configures GitHub webhooks + main branch protection.
# Needs: GITHUB_PAT (repo + admin:repo_hook), JENKINS_URL, TF_PLAN_WEBHOOK_TOKEN, TF_APPLY_WEBHOOK_TOKEN
set -euo pipefail

REPO="${GITHUB_REPO:-minhtri1612/go-micro-infra}"
: "${GITHUB_PAT:?}"
: "${JENKINS_URL:?}"
: "${TF_PLAN_WEBHOOK_TOKEN:?}"
: "${TF_APPLY_WEBHOOK_TOKEN:?}"

JENKINS_URL="${JENKINS_URL%/}"
API="https://api.github.com/repos/${REPO}"

auth() {
  curl -sS -f -H "Authorization: Bearer ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

ensure_hook() {
  local url="$1"
  local events_json="$2"
  local existing
  existing="$(auth "${API}/hooks" | jq -r --arg url "${url}" '.[] | select(.config.url==$url) | .id' | head -n1)"
  if [[ -n "${existing}" ]]; then
    echo "webhook exists id=${existing} url=${url}"
    return
  fi
  jq -n --arg url "${url}" --argjson events "${events_json}" '{
    name: "web",
    active: true,
    events: $events,
    config: { url: $url, content_type: "json", insecure_ssl: "0" }
  }' | auth -X POST --data-binary @- "${API}/hooks" >/dev/null
  echo "created webhook ${url}"
}

ensure_hook "${JENKINS_URL}/generic-webhook-trigger/invoke?token=${TF_PLAN_WEBHOOK_TOKEN}" '["pull_request"]'
ensure_hook "${JENKINS_URL}/generic-webhook-trigger/invoke?token=${TF_APPLY_WEBHOOK_TOKEN}" '["push"]'

# 1 DevOps: no required reviews (self-merge). Required check terraform-plan. No direct push.
jq -n '{
  required_status_checks: { strict: true, contexts: ["terraform-plan"] },
  enforce_admins: true,
  required_pull_request_reviews: null,
  restrictions: null,
  allow_force_pushes: false,
  allow_deletions: false,
  block_creations: false
}' | auth -X PUT --data-binary @- "${API}/branches/main/protection" >/dev/null

echo "branch protection on main: required check terraform-plan, no force-push"
