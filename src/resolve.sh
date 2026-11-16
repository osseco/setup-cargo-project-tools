#!/usr/bin/env bash
# Step 1: validate the inputs, pick the release asset for this runner and
# read its pinned sha256. Writes version, asset, sha256, working-directory,
# cache (save, restore or off) and week to GITHUB_OUTPUT.
set -euo pipefail

# shellcheck source=src/lib.sh
source "$GITHUB_ACTION_PATH/src/lib.sh"

cpt_check_choice install "$INPUT_INSTALL" true false
cpt_check_choice audit "$INPUT_AUDIT" false true deny-warnings
cpt_check_choice cache "$INPUT_CACHE" auto true restore false
workdir="$(cpt_check_workdir "$INPUT_WORKING_DIRECTORY")"
cache="$(cpt_cache_mode "$INPUT_CACHE" "$GITHUB_REF" "$DEFAULT_BRANCH")"

asset="$(cpt_asset "$RUNNER_OS" "$RUNNER_ARCH")"
version="$(cpt_pinned_version "$GITHUB_ACTION_PATH/cargo-project-tools.version")"
sha256="$(cpt_pinned_sha256 "$GITHUB_ACTION_PATH/cargo-project-tools.sha256" "$asset")"

if [[ "$INPUT_INSTALL" == "true" || "$INPUT_AUDIT" != "false" ]]; then
  workspace="$(cpt_unix_path "$GITHUB_WORKSPACE")"
  if [[ ! -f "$workspace/$workdir/project-tools.toml" ]]; then
    cpt_error "no project-tools.toml in working-directory '$workdir'. Check out the repository first, or set install: false and audit: false to only install cargo-project-tools."
  fi
  if ! command -v cargo >/dev/null 2>&1; then
    cpt_error "cargo is not on PATH. Install a Rust toolchain before this step, or set install: false and audit: false."
  fi
fi

{
  printf 'version=%s\n' "$version"
  printf 'asset=%s\n' "$asset"
  printf 'sha256=%s\n' "$sha256"
  printf 'working-directory=%s\n' "$workdir"
  printf 'cache=%s\n' "$cache"
  printf 'week=%s\n' "$(date -u +%G-%V)"
} >>"$GITHUB_OUTPUT"
