#!/usr/bin/env bash
# Checks the annotate step and the sticky-comment lookup of ci.yml against
# hostile fixtures: a reason that tries to start a workflow command, and a
# marker comment posted by someone other than github-actions[bot].
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "::error::$*"; exit 1; }

got=$(IN_PATH=test/fixtures/monorepo test/annotate.sh test/plan-hostile.json)
want='::error file=test/fixtures/monorepo/services/pay/pacto.yaml,line=1,title=pacto ci%3A pay::blocked (breaks checkout): line1%0A::add-mask::x 100%25 a,b:c
::warning file=test/fixtures/monorepo/services/web/pacto.yaml,line=1,title=pacto ci%3A web::unverified (pass --registry)
::notice file=test/fixtures/monorepo/services/api/pacto.yaml,line=1,title=pacto ci%3A api::clear'
[ "$got" = "$want" ] || fail "annotations differ:
got:
$got
want:
$want"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# A hostile property: a service name with a comma and a colon stays one property.
printf '%s' '{"rows":[{"service":"a,b:c","dir":".","changed":"yes","impact":{"gate":"clear","text":"clear"}}]}' > "$tmp/root.json"
got=$(IN_PATH=. test/annotate.sh "$tmp/root.json")
[ "$got" = '::notice file=pacto.yaml,line=1,title=pacto ci%3A a%2Cb%3Ac::clear' ] || fail "root annotation: $got"

filter=$(yq '.jobs.comment.steps[] | select(.id == "lookup") | .env.FILTER' .github/workflows/ci.yml)
[ -n "$filter" ] && [ "$filter" != null ] || fail "ci.yml has no lookup filter"
got=$(jq -r "$filter" test/comments-hostile.json)
[ "$got" = 102 ] || fail "lookup on comments-hostile.json = '$got', want 102"
got=$(jq -r "$filter" test/comments-foreign.json)
[ -z "$got" ] || fail "lookup on comments-foreign.json = '$got', want nothing"
echo "annotations and comment lookup: ok"
