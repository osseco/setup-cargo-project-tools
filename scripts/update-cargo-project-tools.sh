#!/usr/bin/env bash
# Adopt a new cargo-project-tools release. Run by a maintainer from a clean
# checkout:
#
#   scripts/update-cargo-project-tools.sh 0.3.0
#   scripts/update-cargo-project-tools.sh 0.3.0 --dry-run
#
# cargo-project-tools-update.yml runs it with --ci and opens the pull request
# itself.
#
# 1. Refuses drafts, prereleases, and versions that aren't newer than the
#    pinned one. cargo-project-tools is released by osseco too, so there is no
#    minimum age.
# 2. Creates feat/update_cargo_project_tools_X.Y.Z from origin/main.
# 3. Downloads every asset the action maps and requires four checks to agree
#    before a hash is pinned: the local sha256, the digest GitHub reports, the
#    release's SHA256SUMS, and the build provenance attestation (gh
#    attestation verify). With cosign on PATH, the cosign bundle too; with
#    --ci, cosign is required.
# 4. Writes cargo-project-tools.version, cargo-project-tools.sha256 and the
#    README marker, then runs the tests.
# 5. Stages the changes. It never commits or pushes: the maintainer reviews
#    and signs the commit.
#
# --dry-run does the checks and downloads only: no git, no writes.
# --ci does the checks and writes the files, but no git: no branch, no
# staging. It requires cosign.
# Needs gh (signed in), jq, curl, git. macOS and Linux.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=src/lib.sh
source "$REPO_ROOT/src/lib.sh"
# shellcheck source=scripts/release-lib.sh
source "$REPO_ROOT/scripts/release-lib.sh"

readonly UPSTREAM=osseco/cargo-project-tools
readonly SIGNER_WORKFLOW="$UPSTREAM/.github/workflows/release.yml"
readonly CERT_IDENTITY="https://github.com/$SIGNER_WORKFLOW@refs/heads/main"
readonly CHANGED_PATHS=(cargo-project-tools.version cargo-project-tools.sha256 README.md)

usage() {
  printf 'usage: %s X.Y.Z [--dry-run | --ci]\n' "$0" >&2
  exit 2
}

version=""
dry_run=false
ci=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    --ci) ci=true ;;
    -*) usage ;;
    *) [[ -z "$version" ]] || usage; version="$arg" ;;
  esac
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
[[ "$dry_run" == "false" || "$ci" == "false" ]] || usage

required=(gh jq curl git)
if [[ "$ci" == "true" ]]; then
  required+=(cosign)
fi
for tool in "${required[@]}"; do
  command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done

cd "$REPO_ROOT"
current="$(cpt_pinned_version cargo-project-tools.version)"
if ! cpt_version_gt "$version" "$current"; then
  echo "$version is not newer than the pinned $current" >&2
  exit 1
fi

release="$(gh api "repos/$UPSTREAM/releases/tags/v$version")"
if [[ "$(jq -r '.draft or .prerelease' <<<"$release")" != "false" ]]; then
  echo "v$version is a draft or prerelease" >&2
  exit 1
fi

if [[ "$dry_run" == "false" && "$ci" == "false" ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "the working tree is not clean" >&2
    exit 1
  fi
  git fetch origin main
  git switch --no-track -c "feat/update_cargo_project_tools_$version" origin/main
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

download() {
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --retry 5 --retry-all-errors --output "$work/$1" \
    "https://github.com/$UPSTREAM/releases/download/v$version/$1"
}

download SHA256SUMS
pins="$work/pins"
: >"$pins"
while IFS= read -r asset; do
  echo "== $asset"
  download "$asset"
  local_sha="$(cpt_sha256 "$work/$asset")"

  github_sha="$(jq -r --arg name "$asset" '.assets[] | select(.name == $name) | .digest // ""' <<<"$release")"
  if [[ "$github_sha" != "sha256:$local_sha" ]]; then
    echo "GitHub reports '$github_sha' for $asset, downloaded sha256:$local_sha" >&2
    exit 1
  fi

  sums_sha="$(cpt_pinned_sha256 "$work/SHA256SUMS" "$asset")"
  if [[ "$sums_sha" != "$local_sha" ]]; then
    echo "SHA256SUMS lists $sums_sha for $asset, downloaded $local_sha" >&2
    exit 1
  fi

  gh attestation verify "$work/$asset" --repo "$UPSTREAM" --signer-workflow "$SIGNER_WORKFLOW" >/dev/null
  echo "attestation ok"

  if command -v cosign >/dev/null; then
    download "$asset.sigstore.json"
    cosign verify-blob "$work/$asset" \
      --bundle "$work/$asset.sigstore.json" \
      --certificate-identity "$CERT_IDENTITY" \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com
  else
    echo "cosign not on PATH; skipping the cosign bundle"
  fi

  printf '%s  %s\n' "$local_sha" "$asset" >>"$pins"
done < <(cpt_all_assets)

cat "$pins"
if [[ "$dry_run" == "true" ]]; then
  echo "dry run: nothing written"
  exit 0
fi

printf '%s\n' "$version" >cargo-project-tools.version
cp "$pins" cargo-project-tools.sha256
cpt_set_readme_version README.md "$version"
bash test/run.sh
if [[ "$ci" == "true" ]]; then
  exit 0
fi
git add -- "${CHANGED_PATHS[@]}"
git diff --cached --stat
echo "Staged. Review, then commit signed as: feat(cpt): update cargo-project-tools to $version"
