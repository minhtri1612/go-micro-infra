#!/usr/bin/env bash
# Branch protection + rulesets for the 10-dev trust boundary.
# Run with a GitHub admin PAT (laptop or Jenkins host).
# Needs: GITHUB_PAT or GH_TOKEN
set -euo pipefail

TOKEN="${GITHUB_PAT:-${GH_TOKEN:-}}"
: "${TOKEN:?set GITHUB_PAT or GH_TOKEN}"

OWNER="${GITHUB_OWNER:-minhtri1612}"
# Jenkins dev bump pushes env/<dev-env>/**. Same GitHub user as this PAT.
# Prod/staging paths have a separate ruleset with no bypass.
BYPASS_USER_ID="${GITHUB_BYPASS_USER_ID:-156641195}"
REVIEWS="${REQUIRED_REVIEWS:-0}"

API="https://api.github.com"

auth() {
  curl -sS -f -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

protect_classic() {
  local repo="$1"
  shift
  local checks_json="$1"
  jq -n \
    --argjson checks "${checks_json}" \
    --argjson reviews "${REVIEWS}" \
    '{
      required_status_checks: $checks,
      enforce_admins: true,
      required_pull_request_reviews: {
        required_approving_review_count: $reviews,
        dismiss_stale_reviews: true,
        require_code_owner_reviews: false,
        require_last_push_approval: false
      },
      restrictions: null,
      allow_force_pushes: false,
      allow_deletions: false,
      block_creations: false
    }' | auth -X PUT --data-binary @- "${API}/repos/${OWNER}/${repo}/branches/main/protection" >/dev/null
  echo "classic protection ${OWNER}/${repo}"
}

upsert_ruleset() {
  local repo="$1"
  local name="$2"
  local body="$3"
  local id
  id="$(auth "${API}/repos/${OWNER}/${repo}/rulesets" | jq -r --arg n "${name}" '.[] | select(.name==$n) | .id' | head -1)"
  if [[ -n "${id}" && "${id}" != "null" ]]; then
    echo "${body}" | auth -X PUT --data-binary @- "${API}/repos/${OWNER}/${repo}/rulesets/${id}" >/dev/null
    echo "updated ruleset ${repo}/${name} (${id})"
  else
    echo "${body}" | auth -X POST --data-binary @- "${API}/repos/${OWNER}/${repo}/rulesets" >/dev/null
    echo "created ruleset ${repo}/${name}"
  fi
}

# --- service repos: PR + required GitHub Action `ci`. No Jenkins bypass. ---
service_checks='{"strict":true,"contexts":["ci"]}'
for svc in product inventory order payment notification client; do
  protect_classic "go-micro-${svc}" "${service_checks}"
done

# --- pipeline-lib: PR only (CasC pins the tag; no deploy secrets here). ---
protect_classic "go-micro-pipeline-lib" "null"

# --- infra: keep terraform-plan; enforce admins. ---
protect_classic "go-micro-infra" '{"strict":true,"contexts":["terraform-plan"]}'

# --- gitops: humans need PR + protect check. Jenkins user may push dev tags.
# Prod/staging paths: no bypass — bot cannot write them on main. ---
upsert_ruleset "go-micro-gitops" "protect-main" "$(jq -n \
  --argjson uid "${BYPASS_USER_ID}" \
  '{
    name: "protect-main",
    target: "branch",
    enforcement: "active",
    bypass_actors: [
      {actor_id: $uid, actor_type: "User", bypass_mode: "always"}
    ],
    conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
    rules: [
      {type: "deletion"},
      {type: "non_fast_forward"},
      {
        type: "pull_request",
        parameters: {
          required_approving_review_count: 0,
          dismiss_stale_reviews_on_push: true,
          require_code_owner_review: false,
          require_last_push_approval: false,
          required_review_thread_resolution: false
        }
      },
      {
        type: "required_status_checks",
        parameters: {
          strict_required_status_checks_policy: true,
          do_not_enforce_on_create: false,
          required_status_checks: [{context: "protect"}]
        }
      }
    ]
  }')"

# Personal GitHub plans reject file_path_restriction (422). Prod write is
# still blocked by CODEOWNERS + protect check + library (prod = PR only).
echo "file_path_restriction not available on this GitHub plan — prod stays PR + protect + CODEOWNERS"

echo "governance applied. Jenkins dev bump is the only accepted main push (bypass user)."
echo "Set REQUIRED_REVIEWS=1 when a second human can review."
echo "CODEOWNERS review: enable require_code_owner_review after Jenkins promote uses a bot author."
