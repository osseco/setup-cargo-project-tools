#!/usr/bin/env bash
# shellcheck disable=SC2016 # Markdown backticks in the pull request body
# Commits the files update-cargo-project-tools.sh --ci wrote to a new branch
# and opens a pull request, signed by GitHub as the App (see
# pull-request-lib.sh). Does nothing when a pull request for the version is
# open.
#
# Env: GH_TOKEN (App installation token with contents and pull-requests
# write), GH_REPO (owner/name), VERSION, BASE_SHA (the commit the files were
# written on), BASE_BRANCH.
set -euo pipefail

# shellcheck source=.github/scripts/pull-request-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/pull-request-lib.sh"

readonly CHANGED_PATHS=(cargo-project-tools.version cargo-project-tools.sha256 README.md)

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "invalid version: $VERSION" >&2
  exit 1
fi

fence="$(printf '\140\140\140')"
{
  printf 'Adopts cargo-project-tools [v%s](https://github.com/osseco/cargo-project-tools/releases/tag/v%s).\n\n' "$VERSION" "$VERSION"
  printf 'Opened by `cargo-project-tools-update.yml` after `scripts/update-cargo-project-tools.sh --ci` checked every asset: local sha256, GitHub digest, `SHA256SUMS`, build provenance attestation and cosign bundle all agree.\n\n'
  printf 'Pinned hashes:\n\n%s\n' "$fence"
  cat cargo-project-tools.sha256
  printf '%s\n\n' "$fence"
  printf -- '- [ ] Read the release notes for changes to `install`, `audit` or the `.project-tools/` layout the caches rely on.\n'
  printf -- '- [ ] e2e jobs green on every platform.\n'
} >"$RUNNER_TEMP/pr.md"

cpt_open_signed_pr "feat/update_cargo_project_tools_$VERSION" \
  "feat(cpt): update cargo-project-tools to $VERSION" \
  "$RUNNER_TEMP/pr.md" "${CHANGED_PATHS[@]}"
