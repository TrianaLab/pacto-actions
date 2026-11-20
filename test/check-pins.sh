#!/usr/bin/env bash
# Every remote uses: is pinned by a 40-hex commit SHA with a version comment
# (a local ./ reference runs at the same commit), and ci.yml pins the pacto
# release it runs by version and sha256.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "::error::$*"; exit 1; }

unpinned=$(grep -nE '^[[:space:]]*(-[[:space:]]+)?uses:' .github/workflows/*.yml action.yml \
  | grep -vE 'uses:[[:space:]]*\./' \
  | grep -vE 'uses:[[:space:]]*[^@[:space:]]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]' || true)
[ -z "$unpinned" ] || fail "uses: not pinned by SHA with a version comment:
$unpinned"

version=$(yq '.env.PACTO_VERSION' .github/workflows/ci.yml)
case "$version" in
  ''|null|latest) fail "ci.yml PACTO_VERSION must name a release, got '$version'" ;;
esac
for arch in AMD64 ARM64; do
  sum=$(yq ".env.PACTO_SHA256_$arch" .github/workflows/ci.yml)
  [[ "$sum" =~ ^[0-9a-f]{64}$ ]] || fail "ci.yml PACTO_SHA256_$arch is not 64 hex: '$sum'"
done
echo "pins: ok"
