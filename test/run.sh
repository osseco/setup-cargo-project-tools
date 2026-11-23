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
expect_out "binary cache off by default" off cpt_binary_cache_mode false save
expect_out "binary cache follows save" save cpt_binary_cache_mode true save
expect_out "binary cache follows restore" restore cpt_binary_cache_mode true restore
expect_out "binary cache off with cache false" off cpt_binary_cache_mode true off

# --- sandbox and stop-commands
expect_out "sandbox required on macos" require cpt_sandbox_mode macOS
expect_out "sandbox left to the project on linux" "" cpt_sandbox_mode Linux
expect_out "sandbox left to the project on windows" "" cpt_sandbox_mode Windows
if [[ "$(cpt_token)" =~ ^[0-9a-f]{32}$ ]]; then pass "token is 32 hex digits"; else fail "token shape"; fi
if [[ "$(cpt_token)" != "$(cpt_token)" ]]; then pass "tokens differ"; else fail "tokens repeat"; fi

: >"$tmp/run.jsonl"
out="$(cpt_run_recorded "$tmp/run.jsonl" sh -c 'echo "{\"kind\":\"x\"}"; echo "::error::from a crate" >&2; exit 3' 2>&1)"
status=$?
if [[ "$status" == 3 ]]; then pass "run keeps the exit status"; else fail "run exit status: $status"; fi
if [[ "$(cat "$tmp/run.jsonl")" == '{"kind":"x"}' ]]; then pass "run appends stdout to records"; else fail "run records"; fi
if [[ "$out" =~ ^::stop-commands::([0-9a-f]{32})$'\n'::error::from\ a\ crate$'\n'::([0-9a-f]{32})::$ ]] &&
  [[ "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
  pass "run turns workflow commands off around the output"
else
  fail "run stop-commands: $out"
fi

# --- container
expect_ok "image with tag and digest" cpt_check_image "buildpack-deps:noble@sha256:$a"
expect_ok "image with registry and path" cpt_check_image ghcr.io/org/build-image:1.2
expect_ok "image name only" cpt_check_image buildpack-deps
expect_fail "image with shell characters" cpt_check_image 'x;id'
expect_fail "image with option" cpt_check_image --privileged
expect_fail "image with uppercase name" cpt_check_image Ubuntu:24.04
expect_fail "image with short digest" cpt_check_image buildpack-deps@sha256:abc
expect_fail "image with space" cpt_check_image 'a b'

printf 'x:y img:1@sha256:%s\nubuntu:noble buildpack-deps:noble@sha256:%s\n' "$a" "$b" >"$tmp/images"
printf 'NAME="Ubuntu"\nID=ubuntu\nVERSION_CODENAME=noble\n' >"$tmp/os-release"
expect_out "image for ubuntu noble" "buildpack-deps:noble@sha256:$b" cpt_container_image "$tmp/os-release" "$tmp/images"
printf 'ID="ubuntu"\nVERSION_CODENAME="noble"\n' >"$tmp/os-release"
expect_out "image for quoted os-release" "buildpack-deps:noble@sha256:$b" cpt_container_image "$tmp/os-release" "$tmp/images"
printf 'ID=ubuntu\nVERSION_CODENAME=focal\n' >"$tmp/os-release"
expect_fail "no image for another release" cpt_container_image "$tmp/os-release" "$tmp/images"
printf 'ID=alpine\n' >"$tmp/os-release"
expect_fail "no image without a codename" cpt_container_image "$tmp/os-release" "$tmp/images"

while read -r key image; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  if cpt_check_image "$image" 2>/dev/null && [[ "$image" == *@sha256:* ]]; then
    pass "committed image for $key is pinned by digest"
  else
    fail "committed image for $key: '$image'"
  fi
done <"$ROOT/container-images"

# --- annotations
# expect_lines <label> <workdir> <want> <record>...: cpt_annotate on the
# records prints exactly want.
expect_lines() {
  local label="$1"
  local workdir="$2"
  local want="$3"
  shift 3
  printf '%s\n' "$@" >"$tmp/records.jsonl"
  expect_out "$label" "$want" cpt_annotate "$workdir" "$tmp/records.jsonl"
}

if command -v jq >/dev/null 2>&1; then
  lock='"file":".project-tools/crates/hexyl/Cargo.lock"'
  expect_lines "advisory warning with line" . \
    '::warning file=.project-tools/crates/hexyl/Cargo.lock,line=63,title=RUSTSEC-1 in hexyl::anyhow@1.0.91: unsound (patched: >=1.0.103). Fix: cargo project-tools update hexyl anyhow' \
    '{"version":1,"kind":"advisory","tool":"hexyl",'"$lock"',"line":63,"id":"RUSTSEC-1","package":"anyhow","package_version":"1.0.91","title":"unsound","patched":[">=1.0.103"],"severity":"warning","fix":"cargo project-tools update hexyl anyhow"}'
  expect_lines "advisory error, platforms, working-directory prefix" test/fixture \
    '::error file=test/fixture/.project-tools/crates/hexyl/Cargo.lock,title=RUSTSEC-2 in hexyl::a@1: bad (only on: windows)' \
    '{"version":1,"kind":"advisory","tool":"hexyl",'"$lock"',"id":"RUSTSEC-2","package":"a","package_version":"1","title":"bad","severity":"error","affected":{"os":["windows"]}}'
  expect_lines "self-advisory points at the action" . \
    '::error file=.project-tools/self-audit-ignore.toml,title=RUSTSEC-3 in cargo-project-tools::cargo-project-tools@5.6.0: t. Update setup-cargo-project-tools, or accept it in .project-tools/self-audit-ignore.toml.' \
    '{"version":1,"kind":"advisory","tool":"cargo-project-tools","file":".project-tools/self-audit-ignore.toml","id":"RUSTSEC-3","package":"cargo-project-tools","package_version":"5.6.0","title":"t","severity":"error","fix":"upgrade"}'
  # shellcheck disable=SC2016 # backticks are part of the message
  expect_lines "review pending never suggests approving" . \
    '::error file=.project-tools/crates/hexyl/build-review.toml,line=4,title=Build review%3A hexyl::build-script libc@0.2.161 build.rs has no decision (changed: sha256). Decide it with `cargo project-tools review hexyl` where you work, then commit build-review.toml.' \
    '{"version":1,"kind":"review-pending","tool":"hexyl","file":".project-tools/crates/hexyl/build-review.toml","line":4,"item":{"type":"build-script","package":"libc","version":"0.2.161","path":"build.rs","previous":{"changed":["sha256"]}},"spec":"libc@0.2.161=ab","entry":"x"}'
  expect_lines "build-failed annotated once, its error skipped" . \
    '::error title=hexyl 0.17.0::hexyl 0.17.0 failed to build (cargo exit 101)' \
    '{"version":1,"kind":"build-failed","tool":"hexyl","tool_version":"0.17.0","sandbox":"none","exit_status":101,"prepared":true,"command":"cargo install","message":"hexyl 0.17.0 failed to build (cargo exit 101)"}' \
    '{"version":1,"kind":"error","tool":"hexyl","tool_version":"0.17.0","message":"hexyl 0.17.0: failed"}' \
    '{"version":1,"kind":"error","message":"install failed"}'
  expect_lines "error about a tool" . \
    '::error title=hexyl 0.17.0::hexyl 0.17.0: isn'"'"'t prepared' \
    '{"version":1,"kind":"error","tool":"hexyl","tool_version":"0.17.0","message":"hexyl 0.17.0: isn'"'"'t prepared"}' \
    '{"version":1,"kind":"error","message":"check failed"}'
  expect_lines "general error only when nothing else" . \
    '::error title=cargo-project-tools::no project-tools.toml' \
    '{"version":1,"kind":"error","message":"no project-tools.toml"}' \
    '{"version":1,"kind":"summary","ok":false}'
  expect_lines "warnings, duplicates collapsed" . \
    "$(printf '%s\n' \
      '::warning title=Socket Firewall::sfw not found' \
      '::warning file=project-tools.toml,line=9,title=Build sandbox%3A hexyl::no sandbox' \
      '::warning file=.project-tools/crates/hexyl/audit-ignore.toml,line=2,title=Audit ignore%3A hexyl::Ignore RUSTSEC-4 expired on 2026-01-01. Renew or remove it.')" \
    '{"version":1,"kind":"sfw-missing","message":"sfw not found"}' \
    '{"version":1,"kind":"sfw-missing","message":"sfw not found"}' \
    '{"version":1,"kind":"sandbox-missing","tool":"hexyl","file":"project-tools.toml","line":9,"message":"no sandbox"}' \
    '{"version":1,"kind":"ignore-expired","tool":"hexyl","file":".project-tools/crates/hexyl/audit-ignore.toml","line":2,"id":"RUSTSEC-4","expires":"2026-01-01"}'
  expect_lines "records without findings say nothing" . "" \
    '{"version":1,"kind":"prepared","tool":"hexyl","tool_version":"0.17.0"}' \
    '{"version":1,"kind":"built","tool":"hexyl","tool_version":"0.17.0","sandbox":"sandbox-exec","bins":["hexyl"]}' \
    '{"version":1,"kind":"up-to-date","tool":"hexyl","tool_version":"0.17.0","bins":["hexyl"]}' \
    '{"version":1,"kind":"summary","ok":true}'
  expect_lines "hostile values are escaped" . \
    '::warning file=.project-tools/crates/hexyl/Cargo.lock,title=X%2C%3A in hexyl::p@1: a%0A::error::b %2525 c%0D' \
    '{"version":1,"kind":"advisory","tool":"hexyl",'"$lock"',"line":0,"id":"X,:","package":"p","package_version":"1","title":"a\n::error::b %25 c\r","severity":"warning"}'
  expect_lines "unexpected file, line and tool are dropped" . \
    '::error title=Targets%3A a tool::This runner builds for x86_64-unknown-linux-gnu, which isn'"'"'t in the tool'"'"'s targets. Add it to project-tools.toml where you work, then commit it.' \
    '{"version":1,"kind":"target-missing","tool":"../x","file":"../../etc/passwd","line":4,"targets":["x86_64-unknown-linux-gnu"]}'
  expect_lines "other versions, bad lines and unknown kinds are skipped" . \
    "$(printf '%s\n' \
      "::notice::Skipped 2 lines from cargo-project-tools that aren't version 1 JSON records." \
      "::notice::Skipped 1 cargo-project-tools records of kinds this action doesn't know.")" \
    '{"version":2,"kind":"advisory"}' 'not json' '{"version":1,"kind":"mystery"}'

  printf '%s\n' 'not json' '{"version":1,"kind":"up-to-date","tool":"a"}' '{"version":1,"kind":"prepared","tool":"b"}' >"$tmp/records.jsonl"
  expect_ok "prepared found among other records" cpt_has_prepared "$tmp/records.jsonl"
  printf '%s\n' '{"version":1,"kind":"up-to-date","tool":"a"}' '{"version":2,"kind":"prepared"}' >"$tmp/records.jsonl"
  expect_fail "nothing prepared" cpt_has_prepared "$tmp/records.jsonl"
else
  printf 'skip annotations: jq is not on PATH\n'
fi

# --- release helpers
expect_ok "version gt patch" cpt_version_gt 1.2.4 1.2.3
expect_ok "version gt minor numeric" cpt_version_gt 1.10.0 1.9.9
expect_ok "version gt major" cpt_version_gt 2.0.0 1.99.99
expect_fail "version gt equal" cpt_version_gt 1.2.3 1.2.3
expect_fail "version gt older" cpt_version_gt 1.2.3 1.3.0


# --- build image helpers
if command -v jq >/dev/null 2>&1; then
  index='{"mediaType":"application/vnd.oci.image.index.v1+json","digest":"sha256:'"$a"'","manifests":[{"platform":{"os":"linux","architecture":"amd64"}},{"platform":{"os":"unknown","architecture":"unknown"}},{"platform":{"os":"linux","architecture":"arm64","variant":"v8"}}]}'
  printf '%s' "$index" >"$tmp/manifest.json"
  expect_out "index digest" "sha256:$a" cpt_index_digest "$tmp/manifest.json"
  printf '%s' "${index/application\/vnd.oci.image.index.v1+json/application\/vnd.docker.distribution.manifest.list.v2+json}" >"$tmp/manifest.json"
  expect_out "manifest list digest" "sha256:$a" cpt_index_digest "$tmp/manifest.json"
  printf '%s' "${index/\"arm64\"/\"ppc64le\"}" >"$tmp/manifest.json"
  expect_fail "index without arm64" cpt_index_digest "$tmp/manifest.json"
  printf '{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"sha256:%s"}' "$a" >"$tmp/manifest.json"
  expect_fail "single-platform manifest" cpt_index_digest "$tmp/manifest.json"
  printf '%s' "${index/sha256:$a/sha256:abc}" >"$tmp/manifest.json"
  expect_fail "index with a malformed digest" cpt_index_digest "$tmp/manifest.json"
fi

printf '# comment ubuntu:noble x\nubuntu:jammy old-jammy\nubuntu:noble old-noble\n' >"$tmp/images"
expect_out "image keys skip comments" "$(printf 'ubuntu:jammy\nubuntu:noble')" cpt_image_keys "$tmp/images"
cpt_set_image "$tmp/images" ubuntu:noble new-noble
cpt_set_image "$tmp/images" ubuntu:resolute new-resolute
expect_out "set image replaces and appends" \
  "$(printf '# comment ubuntu:noble x\nubuntu:jammy old-jammy\nubuntu:noble new-noble\nubuntu:resolute new-resolute')" \
  cat "$tmp/images"

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
