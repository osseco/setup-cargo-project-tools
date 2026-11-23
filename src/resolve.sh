#!/usr/bin/env bash
# Step 1: validate the inputs, pick the release asset for this runner and
# read its pinned sha256. Writes version, asset, sha256, working-directory,
# cache (save, restore or off), binary-cache (the same, for the
# cargo-project-tools binary), binary-cache-file (where that cache keeps it),
# week, sandbox (the --sandbox mode, or empty),
# container-image (the image install runs in, or empty) and records (an empty
# file for the JSON records) to GITHUB_OUTPUT.
set -euo pipefail

# shellcheck source=src/lib.sh
source "$GITHUB_ACTION_PATH/src/lib.sh"

cpt_check_choice install "$INPUT_INSTALL" true false
cpt_check_choice audit "$INPUT_AUDIT" false true deny-warnings
cpt_check_choice cache "$INPUT_CACHE" auto true restore false
cpt_check_choice cache-binary "$INPUT_CACHE_BINARY" false true
cpt_check_choice sandbox "$INPUT_SANDBOX" container cpt
if [[ -n "$INPUT_CONTAINER_IMAGE" ]]; then
  cpt_check_image "$INPUT_CONTAINER_IMAGE"
fi
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

# On Linux the build runs in a container with no network, so check runs on
# the runner without a sandbox (it builds nothing) and install inside it with
# --sandbox off: the container is the sandbox.
sandbox="$(cpt_sandbox_mode "$RUNNER_OS")"
container_image=""
if [[ "$RUNNER_OS" == "Linux" && "$INPUT_SANDBOX" == "container" && "$INPUT_INSTALL" == "true" ]]; then
  if [[ -n "$INPUT_CONTAINER_IMAGE" ]]; then
    container_image="$INPUT_CONTAINER_IMAGE"
    if [[ "$container_image" != *@sha256:* ]]; then
      printf '::warning::container-image %s has no @sha256 digest, so the image can change between runs.\n' "$container_image"
    fi
  else
    container_image="$(cpt_container_image /etc/os-release "$GITHUB_ACTION_PATH/container-images")"
  fi
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    cpt_error "sandbox: container builds the tools in a Docker container, and Docker isn't available here. In a job container or on a runner without Docker, set sandbox: cpt."
  fi
  sandbox=off
fi

records_dir="$(mktemp -d "$(cpt_unix_path "$RUNNER_TEMP")/cargo-project-tools.XXXXXX")"
: >"$records_dir/records.jsonl"

{
  printf 'version=%s\n' "$version"
  printf 'asset=%s\n' "$asset"
  printf 'sha256=%s\n' "$sha256"
  printf 'working-directory=%s\n' "$workdir"
  printf 'cache=%s\n' "$cache"
  printf 'binary-cache=%s\n' "$(cpt_binary_cache_mode "$INPUT_CACHE_BINARY" "$cache")"
  printf 'binary-cache-file=%s\n' "$(cpt_native_path "$(cpt_unix_path "$RUNNER_TEMP")/cargo-project-tools-cache/$asset")"
  printf 'week=%s\n' "$(date -u +%G-%V)"
  printf 'sandbox=%s\n' "$sandbox"
  printf 'container-image=%s\n' "$container_image"
  printf 'records=%s\n' "$(cpt_native_path "$records_dir/records.jsonl")"
} >>"$GITHUB_OUTPUT"
