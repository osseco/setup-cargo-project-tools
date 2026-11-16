# Contributing

Conventions for commits, branches and sfw are in [AGENTS.md](AGENTS.md). This page covers setup, CI, versions, releases and cargo-project-tools updates.

## Setup

- `bash`, [shellcheck](https://www.shellcheck.net/), `zizmor`, `actionlint` and [pre-commit](https://pre-commit.com/).
- For the update script: [`gh`](https://cli.github.com/) (signed in), `jq`, `curl`, and optionally `cosign`.
- `pre-commit install`

| Command                                        | Does                                                                   |
| ---------------------------------------------- | ---------------------------------------------------------------------- |
| `bash test/run.sh`                             | runs the unit tests                                                    |
| `bash .github/calculate-version.sh --self-check` | checks the version rules                                             |
| `scripts/update-cargo-project-tools.sh X.Y.Z`  | adopts a new cargo-project-tools release on a new branch (see below)   |

## CI

| Workflow                                     | When                                 | What                                                                                                                         |
| -------------------------------------------- | ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `pr.yml`                                     | every pull request                   | calculates the next version, runs `check.yml`, then `Merge gate`                                                             |
| `check.yml`                                  | called by `pr.yml` and `release.yml` | shellcheck, unit tests, dependency review, CodeQL, zizmor, actionlint, and the action itself on every supported platform    |
| `release.yml`                                | push to `main` touching the action   | the same checks, then publishes the release                                                                                  |
| `cargo-project-tools-update.yml`             | on a cargo-project-tools release, and daily | opens a pull request that adopts a new cargo-project-tools release                                                    |
| `codeql.yml`, `zizmor.yml`, `actionlint.yml` | also weekly                          | report findings to code scanning                                                                                             |

The e2e jobs in `check.yml` run the action against `test/fixture/` (one tool, `hexyl`): install and audit on Linux x64, arm64 and Alpine, macOS arm64 and Windows x64; a cache save, then a restore that rebuilds nothing; `audit: deny-warnings` failing on the fixture's known warning; and rejections of an unsupported runner, an invalid input and a `..` working directory. While the pins are the `0.0.0` placeholder, the jobs that download cargo-project-tools are skipped.

## Versions

Tags look like `v0.3.0-0.1.0`:

- `0.3.0` is the cargo-project-tools version the action installs, read from `cargo-project-tools.version`.
- `0.1.0` is the action's own version. It never resets, and it comes from the latest tag and the [Conventional Commits](https://www.conventionalcommits.org/) since then (`.github/calculate-version.sh`). Without a tag it starts at `0.0.0`.
  - `feat!:` or a `BREAKING CHANGE:` footer bumps major.
  - `feat:` bumps minor; a cargo-project-tools update is a `feat`.
  - Anything else bumps patch.
  - Each release bumps once, by the highest-ranking commit.

The separator is `-`, not `+`: Dependabot can't parse `+`, so users pinned to a SHA would never get update PRs.

## Releases

A push to `main` that changes the action runs `release.yml`. When the version changed, the `publish` job (environment `release`):

1. Refuses to publish while the pins are the `0.0.0` placeholder.
2. Writes `SHA256SUMS` for `action.yml`, `src/*.sh`, `cargo-project-tools.version`, `cargo-project-tools.sha256` and `LICENSE`.
3. Attests build provenance for them.
4. Creates a draft GitHub Release for the commit with those files, then publishes it. Releases are immutable, so a broken release is fixed by the next version.

## Updating cargo-project-tools

`cargo-project-tools-update.yml` opens the pull request `feat(cpt): update cargo-project-tools to X.Y.Z` as soon as a release is published. cargo-project-tools' `release.yml` starts it with `workflow_dispatch`, and a daily run catches a missed one. cargo-project-tools is an osseco project, so there is no minimum release age.

The workflow:

1. `check` asks the GitHub API for the latest release and compares it with `cargo-project-tools.version`. It reads no dispatch inputs.
2. `pull-request` (environment `update`) installs cosign and runs `scripts/update-cargo-project-tools.sh X.Y.Z --ci`, which:
   - refuses drafts, prereleases, and versions that aren't newer than the pinned one;
   - downloads every asset and requires the local sha256, the digest GitHub reports, the release's `SHA256SUMS`, `gh attestation verify` and the cosign bundle to agree;
   - writes `cargo-project-tools.version`, `cargo-project-tools.sha256` and the version marker in `README.md`, then runs `test/run.sh`.
3. `.github/scripts/open-update-pr.sh` creates `feat/update_cargo_project_tools_X.Y.Z`, commits the three files through the GraphQL API with the update App's token (GitHub signs the commit as the App), and opens the pull request. It does nothing while one is open.

A maintainer then reads the release notes (changes to `install`, `audit` or the `.project-tools/` layout the caches rely on), waits for the e2e jobs, merges and approves the release.

To adopt a release by hand, from a clean checkout:

```bash
scripts/update-cargo-project-tools.sh X.Y.Z
```

It does the same checks (cosign only when it's on `PATH`), creates the branch from `origin/main`, and stages the files without committing. `--dry-run` only checks and downloads: no git, no writes.

`README.md` holds the version between `<!-- cargo-project-tools-version -->` markers; a test fails when it differs from `cargo-project-tools.version`. The exact `uses:` line (commit SHA and tag) is written into each release's notes by `release.yml`.

## Verifying a release

```bash
gh attestation verify action.yml --repo osseco/setup-cargo-project-tools
```

```bash
sha256sum --check SHA256SUMS
```

Renaming `release.yml` or releasing from another branch changes the signing identity.
