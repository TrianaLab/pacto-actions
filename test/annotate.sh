#!/usr/bin/env bash
# Runs the annotate step of ci.yml, the shipped text, over the plan JSON in $1.
# IN_PATH is the reusable workflow's path input.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$1" "$tmp/plan.json"
yq '.jobs.plan.steps[] | select(.id == "annotate") | .run' "$here/../.github/workflows/ci.yml" > "$tmp/annotate.sh"
[ -s "$tmp/annotate.sh" ] || { echo "ci.yml has no annotate step" >&2; exit 1; }
RUNNER_TEMP=$tmp bash --noprofile --norc -eo pipefail "$tmp/annotate.sh"
