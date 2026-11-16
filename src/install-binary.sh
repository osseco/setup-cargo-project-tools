#!/usr/bin/env bash
# Step 2: download the pinned cargo-project-tools release asset, check it
# against the sha256 pinned in this action, and put it on PATH. Writes path
# to GITHUB_OUTPUT.
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

echo "Downloading $url"
curl --fail --silent --show-error --location \
  --proto '=https' --tlsv1.2 \
  --retry 5 --retry-all-errors --retry-delay 2 \
  --output "$download" "$url"

actual="$(cpt_sha256 "$download")"
if [[ "$actual" != "$CPT_SHA256" ]]; then
  rm -f "$download"
  cpt_error "sha256 mismatch for $CPT_ASSET: expected $CPT_SHA256, got $actual"
fi
echo "sha256 $actual matches the pinned value"

mv -f "$download" "$dir/$name"
chmod +x "$dir/$name"
cpt_native_path "$dir" >>"$GITHUB_PATH"
printf 'path=%s\n' "$(cpt_native_path "$dir/$name")" >>"$GITHUB_OUTPUT"
"$dir/$name" project-tools --version
