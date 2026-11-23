#!/usr/bin/env bash
# Runs cargo project-tools with the given arguments. Its JSON records are
# appended to CPT_RECORDS; its human output goes to the log with workflow
# commands turned off, since it carries text from crates and their builds.
set -euo pipefail

# shellcheck source=src/lib.sh
source "$GITHUB_ACTION_PATH/src/lib.sh"

records="$(cpt_unix_path "$CPT_RECORDS")"
token="$(cpt_token)"
printf '::stop-commands::%s\n' "$token"
status=0
cargo project-tools "$@" --message-format json >>"$records" || status=$?
printf '::%s::\n' "$token"
exit "$status"
