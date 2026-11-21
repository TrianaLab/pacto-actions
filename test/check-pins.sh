#!/usr/bin/env bash
# Every remote uses: is pinned by a 40-hex commit SHA with a version comment
# (a local ./ reference runs at the same commit), and ci.yml pins the pacto
# release it runs by version and sha256. The GitLab component pins every
# image by digest, and the component and the composite action pin the same
# pacto release and hashes as ci.yml.
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

component=templates/pacto.yml
images=$(yq 'select(di == 1) | [.. | select(has("image") or has("services")) | (.image, (.services // [])[] | (.name // .))] | .[] | select(. != null)' "$component")
images=$(printf '%s\n%s\n' "$images" "$(yq 'select(di == 0) | .spec.inputs.image.default' "$component")")
while read -r image; do
  case "$image" in
    ''|'$[[ inputs.image ]]') ;;
    *@sha256:*) [[ "$image" =~ @sha256:[0-9a-f]{64}$ ]] || fail "$component image $image has no full digest" ;;
    *) fail "$component image $image is not pinned by digest" ;;
  esac
done <<<"$images"

for name in PACTO_VERSION PACTO_SHA256_AMD64 PACTO_SHA256_ARM64; do
  want=$(yq ".env.$name" .github/workflows/ci.yml)
  got=$(yq "select(di == 1) | .[\"pacto-plan\"].variables.$name" "$component")
  [ "$got" = "$want" ] || fail "$component $name is '$got', ci.yml has '$want'"
  got=$(yq ".runs.steps[] | select(.id == \"setup\") | .env.$name" action.yml)
  [ "$got" = "$want" ] || fail "action.yml $name is '$got', ci.yml has '$want'"
done
echo "pins: ok"
