#!/usr/bin/env bash
# Installs the tools that check prepared, inside a container with no network,
# no capabilities and a read-only file system. Only the build output is
# writable: .project-tools/targets, .project-tools/bin and cargo's install
# records. The runner's rustup toolchain and the verified cargo-project-tools
# binary are mounted read-only; CARGO_HOME is an empty read-only directory,
# since an offline install after check needs nothing else from it.
# Runs in the working-directory, with CPT_RECORDS, CPT_PATH and
# CPT_CONTAINER_IMAGE set.
set -euo pipefail

# shellcheck source=src/lib.sh
source "$GITHUB_ACTION_PATH/src/lib.sh"

records="$(cpt_unix_path "$CPT_RECORDS")"
if command -v jq >/dev/null 2>&1 && ! cpt_has_prepared "$records"; then
  echo "Nothing to build: check found every tool up to date."
  exit 0
fi

cargo_bin="$(dirname "$(command -v cargo)")"
rustup_home="${RUSTUP_HOME:-$HOME/.rustup}"
case "$cargo_bin" in
  /bin | /sbin | /usr/bin | /usr/sbin | /usr/local/bin)
    cpt_error "sandbox: container mounts the runner's rustup toolchain, but cargo is in $cargo_bin. Install Rust with rustup, or set sandbox: cpt."
    ;;
esac
if [[ ! -d "$rustup_home" ]]; then
  cpt_error "sandbox: container mounts the runner's rustup toolchain, and $rustup_home doesn't exist. Install Rust with rustup, or set sandbox: cpt."
fi

tools="$PWD/.project-tools"
mkdir -p "$tools/targets" "$tools/bin"
touch "$tools/.crates.toml" "$tools/.crates2.json"
cargo_home="$(dirname "$records")/cargo-home"
mkdir -p "$cargo_home"

args=(
  run --rm
  --network none --read-only --cap-drop ALL --security-opt no-new-privileges
  --tmpfs /tmp --user "$(id -u):$(id -g)"
  --env HOME=/tmp --env CARGO_HOME=/cargo-home --env RUSTUP_HOME="$rustup_home"
  --env PATH="$cargo_bin:/usr/local/bin:/usr/bin:/bin"
  --volume "$GITHUB_WORKSPACE:$GITHUB_WORKSPACE:ro"
  --volume "$tools/targets:$tools/targets"
  --volume "$tools/bin:$tools/bin"
  --volume "$tools/.crates.toml:$tools/.crates.toml"
  --volume "$tools/.crates2.json:$tools/.crates2.json"
  --volume "$rustup_home:$rustup_home:ro"
  --volume "$cargo_bin:$cargo_bin:ro"
  --volume "$cargo_home:/cargo-home:ro"
  --volume "$(cpt_unix_path "$CPT_PATH"):/usr/local/bin/cargo-project-tools:ro"
  --workdir "$PWD"
)
if [[ -n "${RUSTUP_TOOLCHAIN:-}" ]]; then
  args+=(--env RUSTUP_TOOLCHAIN="$RUSTUP_TOOLCHAIN")
fi

echo "Building in $CPT_CONTAINER_IMAGE with no network"
cpt_run_recorded "$records" docker "${args[@]}" "$CPT_CONTAINER_IMAGE" \
  cargo project-tools install --offline --no-audit --sandbox off --message-format json
