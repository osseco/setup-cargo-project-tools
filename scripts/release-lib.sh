# shellcheck shell=bash
# Functions shared by the maintainer scripts that adopt a cargo-project-tools
# release. Sourced, never run. No network access here.

# cpt_version_gt <a> <b>: succeeds when X.Y.Z a is newer than b.
cpt_version_gt() {
  local a="$1"
  local b="$2"
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<<"$a"
  IFS=. read -r b1 b2 b3 <<<"$b"
  if ((a1 != b1)); then
    ((a1 > b1))
  elif ((a2 != b2)); then
    ((a2 > b2))
  else
    ((a3 > b3))
  fi
}

# cpt_set_readme_version <readme> <version>: rewrites the version between the
# cargo-project-tools-version markers. Fails unless exactly one marker pair
# is on one line.
cpt_set_readme_version() {
  local readme="$1"
  local version="$2"
  local open='<!-- cargo-project-tools-version -->'
  local close='<!-- /cargo-project-tools-version -->'
  local count
  count="$(grep -c -F "$open" "$readme" || true)"
  if [[ "$count" != "1" ]]; then
    printf '%s must contain the version marker exactly once\n' "$readme" >&2
    return 1
  fi
  awk -v open="$open" -v closing="$close" -v version="$version" '
    index($0, open) {
      start = index($0, open) + length(open)
      rest = substr($0, start)
      end = index(rest, closing)
      if (!end) { exit 2 }
      $0 = substr($0, 1, start - 1) version substr(rest, end)
    }
    { print }
  ' "$readme" >"$readme.tmp" || {
    rm -f "$readme.tmp"
    printf '%s: version marker is not closed on the same line\n' "$readme" >&2
    return 1
  }
  mv "$readme.tmp" "$readme"
}
