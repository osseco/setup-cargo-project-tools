#!/usr/bin/env bash
# shellcheck disable=SC2016 # Markdown backticks in the pull request body
# Commits the files update-cargo-project-tools.sh --ci wrote to a new branch
# and opens a pull request. The commit is made through the GraphQL API
# (createCommitOnBranch), so GitHub signs it as the GitHub App whose token is
# in GH_TOKEN. Does nothing when a pull request for the version is open.
#
# Env: GH_TOKEN (App installation token with contents and pull-requests
# write), GH_REPO (owner/name), VERSION, BASE_SHA (the commit the files were
# written on), BASE_BRANCH.
set -euo pipefail

readonly CHANGED_PATHS=(cargo-project-tools.version cargo-project-tools.sha256 README.md)

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "invalid version: $VERSION" >&2
  exit 1
fi
branch="feat/update_cargo_project_tools_$VERSION"
title="feat(cpt): update cargo-project-tools to $VERSION"

open="$(gh pr list --head "$branch" --state open --json number --jq length)"
if [[ "$open" != "0" ]]; then
  echo "A pull request for $branch is already open"
  exit 0
fi

if gh api "repos/$GH_REPO/git/ref/heads/$branch" >/dev/null 2>&1; then
  echo "::error::branch $branch exists without an open pull request; delete it or open the pull request by hand"
  exit 1
fi
gh api "repos/$GH_REPO/git/refs" -f "ref=refs/heads/$branch" -f "sha=$BASE_SHA" >/dev/null

additions="$(
  for path in "${CHANGED_PATHS[@]}"; do
    jq -n --arg path "$path" --arg contents "$(base64 <"$path" | tr -d '\n')" \
      '{path: $path, contents: $contents}'
  done | jq -s .
)"
jq -n \
  --arg query 'mutation($input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: $input) { commit { oid url } } }' \
  --arg repo "$GH_REPO" \
  --arg branch "$branch" \
  --arg head "$BASE_SHA" \
  --arg headline "$title" \
  --argjson additions "$additions" \
  '{query: $query, variables: {input: {
     branch: {repositoryNameWithOwner: $repo, branchName: $branch},
     expectedHeadOid: $head,
     message: {headline: $headline},
     fileChanges: {additions: $additions}
   }}}' >"$RUNNER_TEMP/commit.json"
gh api graphql --input "$RUNNER_TEMP/commit.json" --jq '.data.createCommitOnBranch.commit.url'

fence="$(printf '\140\140\140')"
{
  printf 'Adopts cargo-project-tools [v%s](https://github.com/osseco/cargo-project-tools/releases/tag/v%s).\n\n' "$VERSION" "$VERSION"
  printf 'Opened by `cargo-project-tools-update.yml` after `scripts/update-cargo-project-tools.sh --ci` checked every asset: local sha256, GitHub digest, `SHA256SUMS`, build provenance attestation and cosign bundle all agree.\n\n'
  printf 'Pinned hashes:\n\n%s\n' "$fence"
  cat cargo-project-tools.sha256
  printf '%s\n\n' "$fence"
  printf -- '- [ ] Read the release notes for changes to `install`, `audit` or the `.project-tools/` layout the caches rely on.\n'
  printf -- '- [ ] e2e jobs green on every platform.\n'
} >"$RUNNER_TEMP/pr.md"

gh pr create --base "$BASE_BRANCH" --head "$branch" --title "$title" --body-file "$RUNNER_TEMP/pr.md"
