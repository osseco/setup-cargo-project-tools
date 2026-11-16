# AGENTS.md

How AI agents work in this repository. What the action does, and how to use it: [README.md](README.md). CI, versions and releases: [CONTRIBUTING.md](CONTRIBUTING.md).

## Commits

Agents never commit. The maintainer reviews and signs every commit. The one exception is the update pull request that `cargo-project-tools-update.yml` commits as its GitHub App (signed by GitHub).

- Never run `git commit`, `git tag`, `git push`, or anything that rewrites history (`rebase`, `reset --hard`, `commit --amend`, force pushes).
- Work in reviewable chunks. At the end of each chunk, stage exactly that chunk's files with explicit paths (`git add <path>…`, never `git add -A` or `git add .`), show `git diff --cached --stat`, and propose a commit message. Staged means "commit this". Then wait until the maintainer has committed before starting the next chunk. On requested changes, edit and re-stage.
- Staging is the only git write an agent does.

Messages use [Conventional Commits](https://www.conventionalcommits.org/):

```text
type(scope): imperative subject
```

- Types: `feat`, `fix`, `docs`, `refactor`, `test`, `build`, `ci`, `chore`.
- Scopes when useful: `action`, `cache`, `audit`, `cpt`, `ci`.
- The subject is lowercase imperative, with no trailing period.
- Breaking changes to inputs, outputs or behaviour use `!` or a `BREAKING CHANGE:` footer.
- Types decide the next release version (see [CONTRIBUTING.md](CONTRIBUTING.md#versions)). Pick them deliberately: `feat` bumps minor, `!` or `BREAKING CHANGE:` bumps major, everything else bumps patch.
- A cargo-project-tools update is always `feat(cpt): update cargo-project-tools to X.Y.Z`.

## Branches

Never change or commit directly on `main`. If the current branch is `main`, create a branch from `origin/main` and work there:

```bash
git switch --no-track -c fix/short_description origin/main
```

Name it `type/short_description`, with the same types as commits.

## Socket Firewall

Prefix every command that downloads crates with `sfw` (`sfw cargo …`). cargo-project-tools uses `sfw` on its own when it's on `PATH`.

## Checks

Run `pre-commit run --all-files` before handing over a chunk. It runs shellcheck, the unit tests, the version rules self-check, zizmor, actionlint and basic file checks.

It needs these on PATH: `bash`, `shellcheck`, `zizmor`, `actionlint`, `pre-commit`.

Unit tests are plain bash in `test/run.sh` and must not touch the network. Logic lives in functions in `src/lib.sh` and `scripts/release-lib.sh` that take everything as arguments; the step scripts only wire environment variables to them. The action itself is tested end to end in `check.yml` against `test/fixture/`.

## Code map

- `action.yml`: the composite action — inputs, outputs, and the steps below.
- `cargo-project-tools.version`, `cargo-project-tools.sha256`: the one cargo-project-tools version this action installs, and the sha256 of every asset (sha256sum format). Only `scripts/update-cargo-project-tools.sh` writes them, together with the version marker in `README.md`. `0.0.0` with an empty sha256 file is the placeholder before the first release is adopted.
- `src/lib.sh`: input validation, runner to asset (`cpt_asset`), reading the pins, sha256, cache mode (`cpt_cache_mode`), path conversion for Windows.
- `src/resolve.sh`: step 1 — validates inputs, resolves asset, pinned sha256 and cache mode, checks `project-tools.toml` and `cargo`.
- `src/install-binary.sh`: step 2 — downloads, verifies, puts cargo-project-tools on `PATH`.
- `scripts/release-lib.sh`: version comparison, README marker.
- `scripts/update-cargo-project-tools.sh X.Y.Z`: adopts a release. By hand it creates a branch and stages the result; with `--ci` it only writes the files. Agents may run it only when asked, and never commit what it stages.
- `.github/scripts/check-cargo-project-tools.sh`, `.github/scripts/open-update-pr.sh`: the update workflow's check, and its signed commit and pull request.
- `test/run.sh`: unit tests. `test/fixture/`: a minimal cargo project with one tool (`hexyl`) for the e2e jobs.

## Security rules

- Never put a binary on `PATH` or run it before it has matched the sha256 in `cargo-project-tools.sha256`.
- Download only from `https://github.com/osseco/cargo-project-tools/releases/download/`. No mirrors, no other hosts.
- Never take a checksum from the same place as the binary at run time.
- No new actions in `action.yml` without the maintainer's agreement; pin them by full SHA.
- Validate every input against its allowed values before any other step uses it. Inputs reach `run:` only through `env:`, never inline in a script.

## GitHub Actions

- Pin every action to a full commit SHA with a version comment, in `action.yml`, workflows and README examples alike.
- Start each workflow with `permissions: {}`, and grant per job only what it needs.
- Set `persist-credentials: false` on checkout.
- Pass `${{ }}` values to `run:` through `env:`, never inline.
- zizmor and actionlint must report no findings.
