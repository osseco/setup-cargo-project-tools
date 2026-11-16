#!/usr/bin/env bash
# Unit tests for src/lib.sh and scripts/release-lib.sh, and the shape of the
# pinned files. No network. Run: bash test/run.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=src/lib.sh
source "$ROOT/src/lib.sh"
# shellcheck source=scripts/release-lib.sh
source "$ROOT/scripts/release-lib.sh"

failures=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}

# expect_out <label> <want> <command>...: the command succeeds and prints want.
expect_out() {
  local label="$1"
  local want="$2"
  shift 2
  local got
  if got="$("$@" 2>/dev/null)" && [[ "$got" == "$want" ]]; then
    pass "$label"
  else
    fail "$label: got '$got', want '$want'"
  fi
}

# expect_fail <label> <command>...: the command fails.
expect_fail() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$label: expected failure"
  else
    pass "$label"
  fi
}

# expect_ok <label> <command>...: the command succeeds.
expect_ok() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label: expected success"
  fi
}

# --- inputs
expect_ok "choice accepts allowed value" cpt_check_choice cache restore true restore false
expect_fail "choice rejects other value" cpt_check_choice cache yes true restore false
expect_fail "choice rejects case variant" cpt_check_choice install True true false
expect_fail "choice rejects empty value" cpt_check_choice install "" true false

expect_out "workdir dot" "." cpt_check_workdir .
expect_out "workdir dot slash" "." cpt_check_workdir ./
expect_out "workdir nested" "test/fixture" cpt_check_workdir ./test/fixture/
expect_out "workdir dotted name" "a.b/c-d_e" cpt_check_workdir a.b/c-d_e
expect_fail "workdir empty" cpt_check_workdir ""
expect_fail "workdir absolute" cpt_check_workdir /etc
expect_fail "workdir windows drive" cpt_check_workdir 'C:/x'
expect_fail "workdir backslash" cpt_check_workdir 'a\b'
expect_fail "workdir parent" cpt_check_workdir ..
expect_fail "workdir parent inside" cpt_check_workdir a/../b
expect_fail "workdir parent at end" cpt_check_workdir a/..
# shellcheck disable=SC2016 # the literal string is the test
expect_fail "workdir shell characters" cpt_check_workdir 'a$(id)'
expect_fail "workdir space" cpt_check_workdir 'a b'
expect_fail "workdir newline" cpt_check_workdir $'a\nb'

# --- platforms
expect_out "asset linux x64" cargo-project-tools-x86_64-unknown-linux-musl cpt_asset Linux X64
expect_out "asset linux arm64" cargo-project-tools-aarch64-unknown-linux-musl cpt_asset Linux ARM64
expect_out "asset macos arm64" cargo-project-tools-aarch64-apple-darwin cpt_asset macOS ARM64
expect_out "asset windows x64" cargo-project-tools-x86_64-pc-windows-msvc.exe cpt_asset Windows X64
expect_fail "asset macos x64 unsupported" cpt_asset macOS X64
expect_fail "asset windows arm64 unsupported" cpt_asset Windows ARM64
expect_fail "asset linux x86 unsupported" cpt_asset Linux X86
expect_out "all assets" "$(printf '%s\n' \
  cargo-project-tools-x86_64-unknown-linux-musl \
  cargo-project-tools-aarch64-unknown-linux-musl \
  cargo-project-tools-aarch64-apple-darwin \
  cargo-project-tools-x86_64-pc-windows-msvc.exe)" cpt_all_assets

# --- pins
printf '1.2.3\n' >"$tmp/version"
expect_out "version" 1.2.3 cpt_pinned_version "$tmp/version"
printf '1.2.3\r\n' >"$tmp/version"
expect_out "version with CRLF" 1.2.3 cpt_pinned_version "$tmp/version"
printf 'v1.2.3\n' >"$tmp/version"
expect_fail "version with v prefix" cpt_pinned_version "$tmp/version"
: >"$tmp/version"
expect_fail "version empty" cpt_pinned_version "$tmp/version"

a="$(printf 'a%.0s' {1..64})"
b="$(printf 'b%.0s' {1..64})"
printf '%s  x-linux\n%s  x-linux-musl\n' "$a" "$b" >"$tmp/sums"
expect_out "sha256 exact asset" "$a" cpt_pinned_sha256 "$tmp/sums" x-linux
expect_out "sha256 other asset" "$b" cpt_pinned_sha256 "$tmp/sums" x-linux-musl
expect_fail "sha256 missing asset" cpt_pinned_sha256 "$tmp/sums" x-mac
printf '%s  x\n%s  x\n' "$a" "$b" >"$tmp/sums"
expect_fail "sha256 duplicate asset" cpt_pinned_sha256 "$tmp/sums" x
printf 'ABC  x\n' >"$tmp/sums"
expect_fail "sha256 invalid hash" cpt_pinned_sha256 "$tmp/sums" x
printf '%s *x\n' "$a" >"$tmp/sums"
expect_out "sha256 binary mode line" "$a" cpt_pinned_sha256 "$tmp/sums" x

printf 'hello\n' >"$tmp/hello"
expect_out "sha256 of file" 5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03 cpt_sha256 "$tmp/hello"

# The committed pins: a placeholder (0.0.0, no hashes) until the first
# cargo-project-tools release is adopted, then one hash per asset.
version="$(cpt_pinned_version "$ROOT/cargo-project-tools.version")" || fail "committed version"
if [[ "$version" == "0.0.0" ]]; then
  if [[ -s "$ROOT/cargo-project-tools.sha256" ]]; then
    fail "placeholder version 0.0.0 must come with an empty cargo-project-tools.sha256"
  else
    pass "committed pins are the placeholder"
  fi
else
  while IFS= read -r asset; do
    expect_ok "committed sha256 for $asset" cpt_pinned_sha256 "$ROOT/cargo-project-tools.sha256" "$asset"
  done < <(cpt_all_assets)
  lines="$(grep -c . "$ROOT/cargo-project-tools.sha256")"
  if [[ "$lines" == "$(cpt_all_assets | grep -c .)" ]]; then
    pass "committed sha256 has no extra lines"
  else
    fail "committed sha256 has $lines lines"
  fi
fi
if grep -q -F "<!-- cargo-project-tools-version -->$version<!-- /cargo-project-tools-version -->" "$ROOT/README.md"; then
  pass "README marker matches the pinned version"
else
  fail "README marker does not show $version"
fi

# --- cache
expect_out "cache true saves" save cpt_cache_mode true refs/pull/1/merge main
expect_out "cache restore restores" restore cpt_cache_mode restore refs/heads/main main
expect_out "cache false is off" off cpt_cache_mode false refs/heads/main main
expect_out "cache auto saves on default branch" save cpt_cache_mode auto refs/heads/main main
expect_out "cache auto restores on other branch" restore cpt_cache_mode auto refs/heads/feat/x main
expect_out "cache auto restores on pull request" restore cpt_cache_mode auto refs/pull/1/merge main
expect_out "cache auto restores on tag named like branch" restore cpt_cache_mode auto refs/tags/main main
expect_out "cache auto restores without default branch" restore cpt_cache_mode auto refs/heads/main ""
expect_fail "cache unknown mode" cpt_cache_mode yes refs/heads/main main

# --- release helpers
expect_ok "version gt patch" cpt_version_gt 1.2.4 1.2.3
expect_ok "version gt minor numeric" cpt_version_gt 1.10.0 1.9.9
expect_ok "version gt major" cpt_version_gt 2.0.0 1.99.99
expect_fail "version gt equal" cpt_version_gt 1.2.3 1.2.3
expect_fail "version gt older" cpt_version_gt 1.2.3 1.3.0


printf 'x <!-- cargo-project-tools-version -->0.1.0<!-- /cargo-project-tools-version --> y\n' >"$tmp/readme"
cpt_set_readme_version "$tmp/readme" 0.2.0
expect_out "readme marker rewritten" \
  'x <!-- cargo-project-tools-version -->0.2.0<!-- /cargo-project-tools-version --> y' cat "$tmp/readme"
printf 'no marker\n' >"$tmp/readme"
expect_fail "readme without marker" cpt_set_readme_version "$tmp/readme" 0.2.0
printf '<!-- cargo-project-tools-version -->0.1.0\n' >"$tmp/readme"
expect_fail "readme with unclosed marker" cpt_set_readme_version "$tmp/readme" 0.2.0

if ((failures)); then
  printf '%d failed\n' "$failures"
  exit 1
fi
printf 'all passed\n'
