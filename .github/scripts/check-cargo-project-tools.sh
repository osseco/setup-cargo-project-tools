#!/usr/bin/env bash
# Looks for a cargo-project-tools release newer than the pinned one. When
# there is one, writes version to GITHUB_OUTPUT; otherwise writes nothing.
# Needs GH_TOKEN, gh and jq.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=src/lib.sh
source "$REPO_ROOT/src/lib.sh"
# shellcheck source=scripts/release-lib.sh
source "$REPO_ROOT/scripts/release-lib.sh"

current="$(cpt_pinned_version "$REPO_ROOT/cargo-project-tools.version")"
if ! release="$(gh api repos/osseco/cargo-project-tools/releases/latest)"; then
  echo "::warning::could not read the latest cargo-project-tools release (none published yet?)"
  exit 0
fi
tag="$(jq -r '.tag_name' <<<"$release")"
version="${tag#v}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "latest release tag $tag is not vX.Y.Z" >&2
  exit 1
fi
if ! cpt_version_gt "$version" "$current"; then
  echo "pinned $current is current (latest $version)"
  exit 0
fi

printf 'version=%s\n' "$version" >>"$GITHUB_OUTPUT"
