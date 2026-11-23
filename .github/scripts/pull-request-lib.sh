# shellcheck shell=bash
# The signed commit and pull request the update workflows open. Sourced,
# never run.

# cpt_open_signed_pr <branch> <title> <body file> <path>...: commits the
# paths, as they are in the working tree, to a new branch from BASE_SHA and
# opens a pull request against BASE_BRANCH. The commit is made through the
# GraphQL API (createCommitOnBranch), so GitHub signs it as the GitHub App
# whose token is in GH_TOKEN. Does nothing when a pull request for the branch
# is open; fails when the branch exists without one.
#
# Env: GH_TOKEN (App installation token with contents and pull-requests
# write), GH_REPO (owner/name), BASE_SHA (the commit the files were written
# on), BASE_BRANCH, RUNNER_TEMP.
cpt_open_signed_pr() {
  local branch="$1"
  local title="$2"
  local body="$3"
  shift 3
  local open additions path

  open="$(gh pr list --head "$branch" --state open --json number --jq length)"
  if [[ "$open" != "0" ]]; then
    echo "A pull request for $branch is already open"
    return 0
  fi

  if gh api "repos/$GH_REPO/git/ref/heads/$branch" >/dev/null 2>&1; then
    echo "::error::branch $branch exists without an open pull request; delete it or open the pull request by hand"
    return 1
  fi
  gh api "repos/$GH_REPO/git/refs" -f "ref=refs/heads/$branch" -f "sha=$BASE_SHA" >/dev/null

  additions="$(
    for path in "$@"; do
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

  gh pr create --base "$BASE_BRANCH" --head "$branch" --title "$title" --body-file "$body"
}
