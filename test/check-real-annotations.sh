#!/usr/bin/env bash
# Runs the annotate step of ci.yml over what pacto ci really plans on the
# monorepo fixture: one annotation per service that did not read as
# unchanged, each on <path>/<dir>/pacto.yaml.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "::error::$*"; exit 1; }
root=test/fixtures/monorepo
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

set +e
env -u GITHUB_ACTIONS -u GITHUB_STEP_SUMMARY pacto ci "$root" --output-format json > "$tmp/plan.json"
code=$?
set -e
[ "$code" = 2 ] || fail "pacto ci $root exited $code, want 2"

got=$(IN_PATH=$root test/annotate.sh "$tmp/plan.json")
want=$(jq -r --arg root "$root" '.rows[] | select(.changed != "no") | "file=\($root)/\(.dir)/pacto.yaml,"' "$tmp/plan.json")
[ -n "$want" ] || fail "the plan has no row to annotate"
[ "$(wc -l <<<"$got")" = "$(wc -l <<<"$want")" ] || fail "annotations:
$got
want one per line of:
$want"
while read -r file; do
  grep -qF -- "::warning $file" <<<"$got" || fail "no warning annotation on $file in:
$got"
done <<<"$want"
echo "real annotations: ok"
