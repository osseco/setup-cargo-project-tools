#!/usr/bin/env bash
# Step 2: get the pinned cargo-project-tools release asset, check it against
# the sha256 pinned in this action, and put it on PATH. Writes path and
# cache-hit to GITHUB_OUTPUT.
#
# With CPT_CACHE_FILE set (cache-binary: true), a copy restored from the
# Actions cache is used when it matches the pinned sha256, instead of
# downloading. One that doesn't is deleted and the release is downloaded.
# After a download, the checked binary is copied there for the save step.
set -euo pipefail

# shellcheck source=src/lib.sh
source "$GITHUB_ACTION_PATH/src/lib.sh"

url="$CPT_REPO_URL/releases/download/v$CPT_VERSION/$CPT_ASSET"
dir="$(cpt_unix_path "$RUNNER_TEMP")/cargo-project-tools/$CPT_VERSION"
name="cargo-project-tools"
if [[ "$CPT_ASSET" == *.exe ]]; then
  name="$name.exe"
fi
mkdir -p "$dir"
download="$dir/$CPT_ASSET.download"
rm -f "$download"

cached=""
if [[ -n "${CPT_CACHE_FILE:-}" ]]; then
  cached="$(cpt_unix_path "$CPT_CACHE_FILE")"
fi

hit=false
if [[ -n "$cached" && -f "$cached" ]]; then
  actual="$(cpt_sha256 "$cached")"
  if [[ "$actual" == "$CPT_SHA256" ]]; then
    echo "Using $CPT_ASSET from the Actions cache"
    cp "$cached" "$download"
    hit=true
  else
    printf '::warning::The cached %s has sha256 %s, not the pinned %s; downloading it instead.\n' "$CPT_ASSET" "$actual" "$CPT_SHA256"
    rm -f "$cached"
  fi
fi

if [[ "$hit" == "false" ]]; then
  echo "Downloading $url"
  curl --fail --silent --show-error --location \
    --proto '=https' --tlsv1.2 \
    --retry 5 --retry-all-errors --retry-delay 2 \
    --output "$download" "$url"
fi

actual="$(cpt_sha256 "$download")"
if [[ "$actual" != "$CPT_SHA256" ]]; then
  rm -f "$download"
  cpt_error "sha256 mismatch for $CPT_ASSET: expected $CPT_SHA256, got $actual"
fi
echo "sha256 $actual matches the pinned value"

if [[ -n "$cached" && "$hit" == "false" ]]; then
  mkdir -p "$(dirname "$cached")"
  cp "$download" "$cached"
fi

mv -f "$download" "$dir/$name"
chmod +x "$dir/$name"
cpt_native_path "$dir" >>"$GITHUB_PATH"
{
  printf 'path=%s\n' "$(cpt_native_path "$dir/$name")"
  printf 'cache-hit=%s\n' "$hit"
} >>"$GITHUB_OUTPUT"
"$dir/$name" project-tools --version
