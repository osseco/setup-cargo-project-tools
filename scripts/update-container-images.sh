#!/usr/bin/env bash
# Pins the newest buildpack-deps image for every Ubuntu release in
# container-images, and for each release given as ubuntu:<codename>:
#
#   scripts/update-container-images.sh
#   scripts/update-container-images.sh ubuntu:resolute
#
# container-images-update.yml runs it weekly with the release behind
# ubuntu-latest, and opens the pull request itself.
#
# For each release it reads the multi-arch index of buildpack-deps:<codename>
# from Docker Hub, requires linux/amd64 and linux/arm64 images in it, and
# pins the index digest. Then it runs the tests. It never touches git: by
# hand, review `git diff container-images` and stage it yourself.
# Needs docker with buildx, and jq.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=src/lib.sh
source "$REPO_ROOT/src/lib.sh"
# shellcheck source=scripts/release-lib.sh
source "$REPO_ROOT/scripts/release-lib.sh"

readonly IMAGES="$REPO_ROOT/container-images"

releases=()
while IFS= read -r key; do
  releases+=("$key")
done < <({ cpt_image_keys "$IMAGES"; printf '%s\n' "$@"; } | awk 'NF && !seen[$0]++')

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for key in "${releases[@]}"; do
  if [[ ! "$key" =~ ^ubuntu:[a-z]+$ ]]; then
    cpt_error "not an Ubuntu release as ubuntu:<codename>: '$key'"
  fi
  codename="${key#ubuntu:}"
  docker buildx imagetools inspect "buildpack-deps:$codename" --format '{{json .Manifest}}' >"$tmp/manifest.json"
  if ! digest="$(cpt_index_digest "$tmp/manifest.json")"; then
    cpt_error "buildpack-deps:$codename is not a multi-arch index with linux/amd64 and linux/arm64 images"
  fi
  cpt_set_image "$IMAGES" "$key" "buildpack-deps:$codename@$digest"
  printf '%s buildpack-deps:%s@%s\n' "$key" "$codename" "$digest"
done

bash "$REPO_ROOT/test/run.sh" >/dev/null
