#!/usr/bin/env bash
# Runs cargo project-tools with the given arguments. Its JSON records are
# appended to CPT_RECORDS; its human output goes to the log with workflow
# commands turned off, since it carries text from crates and their builds.
set -euo pipefail

# shellcheck source=src/lib.sh
source "$GITHUB_ACTION_PATH/src/lib.sh"

cpt_run_recorded "$(cpt_unix_path "$CPT_RECORDS")" cargo project-tools "$@" --message-format json
