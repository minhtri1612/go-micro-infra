#!/usr/bin/env bash
# Run on Jenkins host after compose is up: branch protection only.
# Jenkins is private (VPN). GitHub cannot webhook it; jobs poll SCM instead.
# Needs: GITHUB_PAT (repo admin)
set -euo pipefail

REPO="${GITHUB_REPO:-minhtri1612/go-micro-infra}"
: "${GITHUB_PAT:?}"

API="https://api.github.com/repos/${REPO}"

auth() {
  curl -sS -f -H "Authorization: Bearer ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

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
echo "no GitHub webhooks: Jenkins is private; plan/apply poll GitHub"
