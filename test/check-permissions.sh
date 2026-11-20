#!/usr/bin/env bash
# Only publish holds id-token: write and only comment writes to a pull
# request; publish honours the publish input; the caller in test.yml grants
# exactly the map a caller of ci.yml needs, which covers every job's map
# because GitHub checks skipped jobs too; nothing uses pull_request_target.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "::error::$*"; exit 1; }
ci=.github/workflows/ci.yml

holders() { yq "[.jobs | to_entries[] | select(.value.permissions[\"$1\"]) | .key] | join(\",\")" "$ci"; }
[ "$(holders id-token)" = publish ] || fail "id-token is held by '$(holders id-token)', want publish only"
[ "$(holders pull-requests)" = comment ] || fail "pull-requests is held by '$(holders pull-requests)', want comment only"
yq '.jobs.publish.if' "$ci" | grep -q 'inputs\.publish' || fail "publish does not read inputs.publish"

caller=$(yq -o=json '.jobs.reusable.permissions' .github/workflows/test.yml)
jq -e '. == {"contents":"read","packages":"write","id-token":"write","pull-requests":"write"}' <<<"$caller" > /dev/null \
  || fail "the reusable job grants $caller"
missing=$(yq -o=json '[.jobs[].permissions // {}]' "$ci" | jq -r --argjson caller "$caller" '
  def rank: {"none": 0, "read": 1, "write": 2}[.] // 0;
  [.[] | to_entries[] | select((($caller[.key] // "none") | rank) < (.value | rank)) | "\(.key): \(.value)"] | unique | join(", ")')
[ -z "$missing" ] || fail "the caller map does not cover: $missing"

! grep -rn 'pull_request_[t]arget' .github || fail "pull_request_target is used"
echo "permissions: ok"
