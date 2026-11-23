#!/usr/bin/env bash
# Annotates the job with what cargo-project-tools found, from the records the
# earlier steps collected in CPT_RECORDS. Never fails the job by itself: the
# step that ran cargo-project-tools already did.
set -uo pipefail

# shellcheck source=src/lib.sh
source "$GITHUB_ACTION_PATH/src/lib.sh"

records="$(cpt_unix_path "$CPT_RECORDS")"
if [[ ! -s "$records" ]]; then
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  printf '::notice::jq is not on PATH, so cargo-project-tools findings are not annotated. They are in the log, and in the file the records output names.\n'
  exit 0
fi
if ! cpt_annotate "$CPT_WORKDIR" "$records"; then
  printf '::warning::Could not read the cargo-project-tools records in %s.\n' "$CPT_RECORDS"
fi
exit 0
