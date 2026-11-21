#!/usr/bin/env bash
# Runs the component's install lines alone in its default image with no pacto
# on PATH: the pinned release downloads and passes the sha256 check, and a
# corrupted hash fails the step. The pinned release may predate pacto ci, so
# the capability check that follows the install is not run here.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "::error::$*"; exit 1; }
component=templates/pacto.yml
image=$(yq 'select(di == 0) | .spec.inputs.image.default' "$component")
install=$(yq 'select(di == 1) | .["pacto-plan"].before_script[0]' "$component")
var() { yq "select(di == 1) | .[\"pacto-plan\"].variables.$1" "$component"; }
version=$(var PACTO_VERSION) amd64=$(var PACTO_SHA256_AMD64) arm64=$(var PACTO_SHA256_ARM64)

run() {
  docker run --rm -e PATH=/usr/local/bin:/usr/bin:/bin -e PACTO_VERSION="$version" -e PACTO_VERSION_INPUT= \
    -e PACTO_SHA256_AMD64="$1" -e PACTO_SHA256_ARM64="$2" -e PACTO_NO_UPDATE_CHECK=1 \
    "$image" sh -ec "$install
pacto version"
}

out=$(run "$amd64" "$arm64" 2>&1) || fail "the pinned install failed:
$out"
grep -q "$version" <<<"$out" || fail "the installed pacto is not $version:
$out"
echo "installer: pacto $version downloaded and checked"

bad=$(printf '0%.0s' $(seq 64))
if out=$(run "$bad" "$bad" 2>&1); then
  fail "a corrupted hash passed the install:
$out"
fi
echo "installer: a corrupted hash fails the install"
