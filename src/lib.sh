# shellcheck shell=bash
# Shared functions for the action's steps and tests. Sourced, never run.
# Every function prints its result on stdout and fails with a message on
# stderr; none of them touches the network.

# shellcheck disable=SC2034 # used by the scripts that source this file
readonly CPT_REPO_URL="https://github.com/osseco/cargo-project-tools"
readonly CPT_SUPPORTED="Linux x64, Linux arm64, macOS arm64, Windows x64"
CPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CPT_LIB_DIR

cpt_error() {
  printf '::error::%s\n' "$*" >&2
  return 1
}

# cpt_check_choice <input name> <value> <allowed>...
cpt_check_choice() {
  local name="$1"
  local value="$2"
  shift 2
  local allowed
  for allowed in "$@"; do
    if [[ "$value" == "$allowed" ]]; then
      return 0
    fi
  done
  cpt_error "input $name must be one of: $*; got '$value'"
}

# cpt_check_workdir <path>: a relative path inside the workspace, without
# .. segments. Prints it with trailing slashes and ./ prefixes removed.
cpt_check_workdir() {
  local dir="$1"
  if [[ -z "$dir" ]]; then
    cpt_error "input working-directory must not be empty"
    return 1
  fi
  if [[ "$dir" == /* || "$dir" == \\* || "$dir" == [A-Za-z]:* ]]; then
    cpt_error "input working-directory must be relative to the workspace; got '$dir'"
    return 1
  fi
  if [[ "$dir" == *\\* ]]; then
    cpt_error "input working-directory must use / as separator; got '$dir'"
    return 1
  fi
  if [[ "/$dir/" == */../* ]]; then
    cpt_error "input working-directory must not contain ..; got '$dir'"
    return 1
  fi
  if [[ ! "$dir" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    cpt_error "input working-directory may only contain letters, digits, '.', '_', '-' and '/'; got '$dir'"
    return 1
  fi
  while [[ "$dir" == ./* ]]; do
    dir="${dir#./}"
  done
  while [[ "$dir" == */ ]]; do
    dir="${dir%/}"
  done
  printf '%s\n' "${dir:-.}"
}

# cpt_asset <RUNNER_OS> <RUNNER_ARCH>: the release asset for a runner.
cpt_asset() {
  case "$1/$2" in
    Linux/X64) printf 'cargo-project-tools-x86_64-unknown-linux-musl\n' ;;
    Linux/ARM64) printf 'cargo-project-tools-aarch64-unknown-linux-musl\n' ;;
    macOS/ARM64) printf 'cargo-project-tools-aarch64-apple-darwin\n' ;;
    Windows/X64) printf 'cargo-project-tools-x86_64-pc-windows-msvc.exe\n' ;;
    *)
      cpt_error "cargo-project-tools has no release binary for $1 $2. Supported: $CPT_SUPPORTED"
      ;;
  esac
}

# The runners cpt_asset maps, as RUNNER_OS/RUNNER_ARCH.
readonly CPT_RUNNERS=(Linux/X64 Linux/ARM64 macOS/ARM64 Windows/X64)

# cpt_all_assets: every asset the action can install, one per line.
cpt_all_assets() {
  local runner
  for runner in "${CPT_RUNNERS[@]}"; do
    cpt_asset "${runner%/*}" "${runner#*/}"
  done
}

# cpt_pinned_version <version file>: X.Y.Z from the first line.
cpt_pinned_version() {
  local version
  if ! IFS= read -r version <"$1"; then
    version=""
  fi
  version="${version%$'\r'}"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    cpt_error "$1 does not hold an X.Y.Z version; got '$version'"
    return 1
  fi
  printf '%s\n' "$version"
}

# cpt_pinned_sha256 <sha256 file> <asset>: the sha256 pinned for one asset.
# The file is in sha256sum format: "<64 hex>  <asset>" per line.
cpt_pinned_sha256() {
  local file="$1"
  local asset="$2"
  local sha
  sha="$(awk -v asset="$asset" '$2 == asset || $2 == "*" asset { print $1; n++ } END { exit n != 1 }' "$file")" || {
    cpt_error "$file must pin exactly one sha256 for $asset"
    return 1
  }
  if [[ ! "$sha" =~ ^[0-9a-f]{64}$ ]]; then
    cpt_error "$file pins an invalid sha256 for $asset: '$sha'"
    return 1
  fi
  printf '%s\n' "$sha"
}

# cpt_sha256 <file>: the file's sha256.
cpt_sha256() {
  local out
  if command -v sha256sum >/dev/null 2>&1; then
    out="$(sha256sum "$1")"
  elif command -v shasum >/dev/null 2>&1; then
    out="$(shasum -a 256 "$1")"
  else
    cpt_error "neither sha256sum nor shasum is available"
    return 1
  fi
  printf '%s\n' "${out%% *}"
}

# cpt_cache_mode <cache input> <GITHUB_REF> <default branch>: save, restore or
# off. auto saves only on the default branch; when the default branch is
# unknown it only restores.
cpt_cache_mode() {
  case "$1" in
    true) printf 'save\n' ;;
    restore) printf 'restore\n' ;;
    false) printf 'off\n' ;;
    auto)
      if [[ -n "$3" && "$2" == "refs/heads/$3" ]]; then
        printf 'save\n'
      else
        printf 'restore\n'
      fi
      ;;
    *) cpt_error "unknown cache mode '$1'" ;;
  esac
}

# cpt_binary_cache_mode <cache-binary input> <cache mode>: save, restore or
# off for the cargo-project-tools binary. It follows the cache input's mode
# when cache-binary is true.
cpt_binary_cache_mode() {
  if [[ "$1" == "true" ]]; then
    printf '%s\n' "$2"
  else
    printf 'off\n'
  fi
}

# cpt_native_path <path>: the path in the form GITHUB_PATH expects; Windows
# paths on Windows runners, unchanged elsewhere.
cpt_native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s\n' "$1"
  fi
}

# cpt_unix_path <path>: the path in the form bash expects.
cpt_unix_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1"
  else
    printf '%s\n' "$1"
  fi
}

# cpt_sandbox_mode <RUNNER_OS>: the --sandbox mode the action passes to check
# and install, or nothing to leave it to the project's [build].sandbox.
# macOS always has sandbox-exec, so a build there must use it.
cpt_sandbox_mode() {
  case "$1" in
    macOS) printf 'require\n' ;;
    *) ;;
  esac
}

# cpt_check_image <image>: a container image reference, name[:tag][@digest],
# with nothing a shell or docker could read as anything else.
cpt_check_image() {
  if [[ ! "$1" =~ ^[a-z0-9][a-z0-9./_-]*(:[A-Za-z0-9._-]+)?(@sha256:[0-9a-f]{64})?$ ]]; then
    cpt_error "input container-image must be an image reference like name:tag@sha256:<digest>; got '$1'"
    return 1
  fi
}

# cpt_container_image <os-release file> <images file>: the pinned default
# image for this distro release, from ID and VERSION_CODENAME.
cpt_container_image() {
  local id codename key image
  id="$(sed -n 's/^ID=//p' "$1" | tr -d '"')"
  codename="$(sed -n 's/^VERSION_CODENAME=//p' "$1" | tr -d '"')"
  key="$id:$codename"
  image="$(awk -v key="$key" '$1 == key { print $2 }' "$2")"
  if [[ -z "$id" || -z "$codename" || -z "$image" ]]; then
    cpt_error "no default build image for '$key'. Set container-image to an image with cc and the runner's glibc, or set sandbox: cpt."
    return 1
  fi
  printf '%s\n' "$image"
}

# cpt_token: a random hex token, for ::stop-commands::.
cpt_token() {
  od -An -N16 -tx1 /dev/urandom | tr -d ' \n'
  printf '\n'
}

# cpt_run_recorded <records file> <command>...: runs the command with its
# stdout appended to the records file, and workflow commands turned off for
# the rest of its output, which carries text from crates and their builds.
cpt_run_recorded() {
  local records="$1"
  shift
  local token status=0
  token="$(cpt_token)"
  printf '::stop-commands::%s\n' "$token"
  "$@" >>"$records" || status=$?
  printf '::%s::\n' "$token"
  return "$status"
}

# cpt_has_prepared <records file>: whether check prepared any tool, so the
# offline install has something to build. Needs jq.
cpt_has_prepared() {
  jq -e -R -s '[split("\n")[] | fromjson? // empty | objects | select(.version == 1 and .kind == "prepared")] | length > 0' "$1" >/dev/null
}

# cpt_annotate <working-directory> <records file>: one workflow command per
# finding in the JSON records cargo-project-tools wrote. Most values come
# from locks, crates and the advisory database, so src/annotate.jq checks or
# escapes every one of them. Needs jq.
cpt_annotate() {
  jq -rRs --arg workdir "$1" -f "$CPT_LIB_DIR/annotate.jq" "$2"
}
