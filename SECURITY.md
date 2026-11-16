# Security policy

## Reporting a vulnerability

Report vulnerabilities privately through GitHub: **Security → Report a vulnerability** on [osseco/setup-cargo-project-tools](https://github.com/osseco/setup-cargo-project-tools/security/advisories/new). Don't open a public issue.

Include the action version, the runner OS and architecture, what you did, and what happened. You'll get a reply within a week.

Vulnerabilities in cargo-project-tools itself go to [osseco/cargo-project-tools](https://github.com/osseco/cargo-project-tools/security).

## Supported versions

Only the latest release gets fixes. Releases are immutable, so a fix always ships as a new version.

## How the binary is trusted

- `cargo-project-tools.version` and `cargo-project-tools.sha256` pin one cargo-project-tools version and the sha256 of every asset the action can install.
- A maintainer pins a release with `scripts/update-cargo-project-tools.sh`. It refuses drafts and prereleases, downloads every asset, and requires four sources to agree: the sha256 it computes, the digest GitHub reports, the release's `SHA256SUMS`, and the build provenance attestation from cargo-project-tools' `release.yml`. With `cosign` available it checks the cosign bundle too.
- At run time the action downloads only from `https://github.com/osseco/cargo-project-tools/releases/download/`, over https only (`curl --proto '=https'`), with no mirrors.
- Nothing is made executable, run or put on `PATH` until the hash matches the pinned one. On a mismatch the file is deleted and the step fails.
- Checksums are never read from the place the binary comes from.

## The Actions cache

The tool binaries `cargo project-tools install` builds, their build directories and the advisory database can be kept in the Actions cache. The trust model is the default branch:

- With the default `cache: auto`, only runs on the default branch save entries; branches and pull requests restore them. Pull requests from forks can't write to the base repository's cache scope at all.
- So what is restored was built by a workflow on the default branch. Protect it (required reviews, signed commits, no direct pushes) and keep its workflows' dependencies pinned: code running in any default-branch workflow can write cache entries.
- `cargo project-tools install` checks restored tool binaries against the record it wrote when it built them, which travels in the same entry, and rebuilds what doesn't match. This detects corruption and partial entries, not tampering: whoever can write the entry can write the record. A forgery-proof check would need a trust anchor outside the cache (committed hashes of reproducible builds, or signed attestations from a dedicated workflow), which this action doesn't do.
- Keys cover the OS, arch, cargo-project-tools version, `project-tools.toml` and every tool lock.
- `cache: false` for jobs whose output is released.

cargo-project-tools itself is never cached; it is downloaded and checked against the pinned sha256 on every run.

## How cargo-project-tools updates are adopted

- cargo-project-tools' release workflow starts `cargo-project-tools-update.yml` here with `workflow_dispatch`, using a token that can only start workflows (Actions: write). A daily schedule catches a missed dispatch. The workflow takes no inputs; it reads the latest release from the GitHub API.
- There is no minimum release age: cargo-project-tools is released by osseco, from a protected `release` environment, with attestations and cosign signatures.
- The workflow checks every asset five ways (local sha256, GitHub digest, `SHA256SUMS`, build provenance attestation, cosign bundle) before writing the pins.
- It opens a pull request with a GitHub App token (Contents and Pull requests: write, this repository only), held in the `update` environment, which is limited to `main`. The commit is made through the API, so GitHub signs it as the App. Nothing merges without a maintainer and the e2e jobs on every platform.

## Dependencies

- The action uses only `actions/cache/restore` and `actions/cache/save`, pinned by full commit SHA. It installs nothing but cargo-project-tools. A new action needs a maintainer's agreement.
- Dependabot updates actions weekly, with a 7-day cooldown.

## Workflows

- Every workflow starts with `permissions: {}`; each job asks only for what it needs.
- Actions are pinned to full commit SHAs. Our own workflows and action are referenced with `$/` (the workflow's own commit).
- `actions/checkout` runs with `persist-credentials: false`.
- `${{ }}` values reach `run:` steps through `env:`, never inline — in workflows and in `action.yml`.
- zizmor and actionlint must report no findings; CodeQL analyses the workflows and the action; dependency review runs on every pull request.

## Releases

- Releases run from `main` only, in the protected `release` environment with required reviewers.
- Releases are immutable: a published tag and its assets can't be changed.
- Each release carries `SHA256SUMS` for `action.yml`, `src/*.sh`, the pin files and `LICENSE`, with a build provenance attestation.
- Use the action by full commit SHA.

## The action itself

- Inputs are checked against their allowed values before anything else runs; anything else fails the step. `working-directory` must be a relative path of `[A-Za-z0-9._/-]` without `..`.
- Input values reach scripts only through environment variables.

## Verifying a release

```bash
gh attestation verify action.yml --repo osseco/setup-cargo-project-tools
```

```bash
sha256sum --check SHA256SUMS
```

The files at the release's commit hash to the same values as the release assets.
