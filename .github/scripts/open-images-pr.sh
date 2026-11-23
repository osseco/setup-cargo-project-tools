#!/usr/bin/env bash
# shellcheck disable=SC2016 # Markdown backticks in the pull request body
# Commits the container-images update-container-images.sh wrote to a new
# branch and opens a pull request, signed by GitHub as the App (see
# pull-request-lib.sh). Does nothing when one is open.
#
# Env: GH_TOKEN (App installation token with contents and pull-requests
# write), GH_REPO (owner/name), BASE_SHA (the commit the file was written
# on), BASE_BRANCH.
set -euo pipefail

# shellcheck source=.github/scripts/pull-request-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/pull-request-lib.sh"

fence="$(printf '\140\140\140')"
{
  printf 'Pins the newest `buildpack-deps` image for every Ubuntu release in `container-images`, including the one behind `ubuntu-latest`.\n\n'
  printf 'Opened by `container-images-update.yml`. `scripts/update-container-images.sh` read each multi-arch index from Docker Hub and required linux/amd64 and linux/arm64 images in it.\n\n'
  printf '%sdiff\n' "$fence"
  git diff -- container-images
  printf '%s\n\n' "$fence"
  printf -- '- [ ] e2e jobs green on every Ubuntu runner, `ubuntu-latest` included.\n'
} >"$RUNNER_TEMP/pr.md"

cpt_open_signed_pr fix/update_container_images \
  "fix(action): update the build images" \
  "$RUNNER_TEMP/pr.md" container-images
