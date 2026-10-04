#!/usr/bin/env bash
# Run on Jenkins host after compose is up, or from a laptop with admin PAT.
# Jenkins is private (VPN). GitHub cannot webhook it; jobs poll SCM instead.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "${DIR}/configure-governance.sh"
