#!/usr/bin/env bash
# Runs the before_script and script lines of the component's pacto-plan job,
# with each input at its default, inside the component's default image and
# with the pacto under test on PATH. The install must skip the download and
# the job must exit with the code pacto ci gives when run directly:
# monorepo 2 (unverified), collision 1 (blocked) and declared 0 (clear).
# Needs a registry on $REGISTRY_HOST (default localhost:5000) and PACTO_BIN,
# the directory holding a static linux pacto (PACTO_HOST_BIN, when the
# host is not linux, the one the direct run uses).
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "::error::$*"; exit 1; }
: "${PACTO_BIN:?PACTO_BIN names the directory of the pacto under test}"
reg=${REGISTRY_HOST:-localhost:5000}
component=templates/pacto.yml
image=$(yq 'select(di == 0) | .spec.inputs.image.default' "$component")
lines=$(yq 'select(di == 1) | explode(.) | .["pacto-plan"] | (.before_script + .script) | join("\n")' "$component")

# substitute replaces every $[[ inputs.<name> ]] with the input's default,
# or with the registry this test serves for the registry input when asked.
substitute() {
  local out=$lines name value
  for name in $(yq 'select(di == 0) | .spec.inputs | keys | .[]' "$component"); do
    value=$(yq "select(di == 0) | .spec.inputs[\"$name\"].default" "$component")
    if [ "$name" = registry ] && [ -n "$1" ]; then value=$1; fi
    out=${out//"\$[[ inputs.$name ]]"/$value}
  done
  grep -q '\$\[\[' <<<"$out" && fail "an input is left in: $out"
  printf '%s\n' "$out"
}

for case in monorepo:2 collision:1 declared:0; do
  fixture=${case%%:*} want=${case##*:} registry=
  [ "$fixture" = declared ] && registry=$reg/acme
  dir=test/fixtures/$fixture

  set +e
  (cd "$dir" && env -u GITHUB_ACTIONS -u GITHUB_STEP_SUMMARY PACTO_INSECURE_REGISTRIES="$reg" \
    "${PACTO_HOST_BIN:-$PACTO_BIN}/pacto" ci . ${registry:+--registry "$registry"} > /dev/null 2>&1)
  direct=$?
  out=$(docker run --rm --network host -v "$PWD:/w" -w "/w/$dir" -v "$PACTO_BIN:/opt/pacto:ro" \
    -e PATH=/opt/pacto:/usr/local/bin:/usr/bin:/bin -e GITLAB_CI=true -e CI_PROJECT_DIR=/tmp \
    -e CI_REGISTRY_IMAGE="$reg/acme" -e PACTO_INSECURE_REGISTRIES="$reg" -e PACTO_NO_UPDATE_CHECK=1 \
    "$image" sh -ec "$(substitute "$registry")" 2>&1)
  code=$?
  set -e

  grep -q 'skipping the download' <<<"$out" || fail "$fixture: the install did not skip the download:
$out"
  [ "$direct" = "$want" ] || fail "$fixture: pacto ci exited $direct, want $want"
  [ "$code" = "$want" ] || fail "$fixture: the component's lines exited $code, want $want:
$out"
  echo "$fixture: pacto ci and the component both exit $code"
done
echo "gitlab script: ok"
