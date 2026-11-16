# TODO

Manual steps for a maintainer. Check them off as they're done.

## Repository settings

Needed before the workflows work as intended:

- [ ] `git init`, create the GitHub repository `osseco/setup-cargo-project-tools` (public) and push `main`.
- [ ] **Releases → Immutable releases**: on.
- [ ] **Security → Private vulnerability reporting**: on (`SECURITY.md` points there).
- [ ] **Security → Dependabot alerts** and **Dependabot security updates**: on.
- [ ] **Security → Code scanning**: on, so CodeQL, zizmor and actionlint results show up.
- [ ] **Environments**: create `release`, limit deployment branches to `main`, add required reviewers.
- [ ] **Ruleset for `main`**: require pull requests and the `Merge gate` status check; block force pushes and deletion; require signed commits.
- [ ] **Ruleset for tags `v*`**: block updates and deletion.
- [ ] **Actions → General**:
  - [ ] Workflow permissions: read-only default token.
  - [ ] Don't allow GitHub Actions to create or approve pull requests.
  - [ ] Require actions to be pinned to a full-length commit SHA.
- [ ] Set the owner in `.github/CODEOWNERS`, then require Code Owner review in the `main` ruleset.

## Pin cargo-project-tools

- [ ] Adopt v1.2.0: `gh auth login`, then `scripts/update-cargo-project-tools.sh 1.2.0` (needs cosign). Until then the pins are the `0.0.0` placeholder, the e2e jobs are skipped, and `release.yml` refuses to publish (pushes to `main` that touch the action fail at `publish`).
- macOS x64 and Windows arm64 stay unsupported for now.

## Feature requests for cargo-project-tools

- [ ] **Start the update workflow on release.** After `gh release edit … --draft=false`, `release.yml` runs `cargo-project-tools-update.yml` here. `GITHUB_TOKEN` is scoped to its own repository, so this needs a token from the notify App (see GitHub Apps below), narrowed to **Actions: write** on this repository. Without it, the daily run finds the release within a day.

  ```yaml
  - uses: actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510 # v3.3.0
    id: notify
    with:
      client-id: ${{ vars.NOTIFY_APP_CLIENT_ID }}
      private-key: ${{ secrets.NOTIFY_APP_PRIVATE_KEY }}
      owner: osseco
      repositories: setup-cargo-project-tools
      permission-actions: write
  - name: Start the setup-cargo-project-tools update
    env:
      GH_TOKEN: ${{ steps.notify.outputs.token }}
    run: gh workflow run cargo-project-tools-update.yml --repo osseco/setup-cargo-project-tools --ref main
  ```

## GitHub Apps

Two Apps, so the key held by cargo-project-tools can't write code here:

- [ ] **Update App** (opens the update pull request). Permissions: Contents: write, Pull requests: write, Metadata: read. Install on `osseco/setup-cargo-project-tools` only. Create the environment `update` here, limited to `main`, with variable `UPDATE_APP_CLIENT_ID` and secret `UPDATE_APP_PRIVATE_KEY`. Its pull requests trigger `check.yml`, which a `GITHUB_TOKEN` pull request wouldn't.
- [ ] **Notify App** (starts the update workflow). Permissions: Actions: write, Metadata: read. Install on `osseco/setup-cargo-project-tools` only. Put `NOTIFY_APP_CLIENT_ID` and `NOTIFY_APP_PRIVATE_KEY` in cargo-project-tools' `release` environment.
- [ ] If the `main` ruleset requires Code Owner review or limits who may push branches, check the Update App can still create `feat/update_cargo_project_tools_*` branches.

## Open decisions

- [x] License for this repository: MIT, `Copyright (c) 2026 osseco contributors`.
- [ ] Publish to the GitHub Marketplace (`action.yml` has branding).

## First release

- [ ] After pinning (above): commit signed as `feat(cpt): update cargo-project-tools to 1.2.0`, open a pull request.
- [ ] Check that every job in `check.yml` passes, in particular:
  - [ ] the e2e jobs on all five platforms, including the `rust:1-alpine` container;
  - [ ] `Action restores from cache` reports `cache-hit: true` and doesn't rebuild hexyl;
  - [ ] `audit deny-warnings fails on a warning` (the fixture's hexyl lock has RUSTSEC-2026-0190, unsound, in anyhow 1.0.91; if cargo-project-tools doesn't report it, pick another known warning);
  - [ ] the rejection jobs, including `macos-15-intel`.
- [ ] Merge to `main`, approve the `release` environment, and check release `vX.Y.Z-0.1.0`.
- [ ] Verify it: `gh attestation verify action.yml --repo osseco/setup-cargo-project-tools` and `sha256sum --check SHA256SUMS`.
- [ ] The release notes start with the `uses: osseco/setup-cargo-project-tools@<sha> # vX.Y.Z-0.1.0` line, and that SHA is the release commit.
- [ ] Point `cargo-project-tools/docs/ci.md` at this action.

## Follow-ups to check

- [ ] Dependabot opens pull requests for the actions pinned in `action.yml` (directory `/`) as well as the workflows.
