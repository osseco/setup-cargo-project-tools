# setup-cargo-project-tools

A GitHub Action that installs [cargo-project-tools](https://github.com/osseco/cargo-project-tools), builds your project's tools with it, and can audit their locks. It replaces the cache, install and `PATH` steps from the [cargo-project-tools CI guide](https://osseco.github.io/cargo-project-tools/docs/ci) with one step.

This version of the action installs cargo-project-tools <!-- cargo-project-tools-version -->1.3.0<!-- /cargo-project-tools-version -->.

- Each action version installs exactly one cargo-project-tools version. Its sha256 for every platform is pinned in [`cargo-project-tools.sha256`](cargo-project-tools.sha256), and the binary is checked against it before it runs.
- Downloads come only from the cargo-project-tools GitHub releases. Nothing is built from source to get cargo-project-tools itself.
- `cargo project-tools install` runs with the tool binaries and builds in your repository's Actions cache, saved only from the default branch by default, and `.project-tools/bin` goes on `PATH`.
- `install` audits the locks before it builds and refuses a lock with a vulnerability. `audit` runs `cargo project-tools audit` first instead, optionally failing on warnings too, and works without `install`. The advisory database is cached per week. No other tool is needed.
- No token, no secrets.

## Usage

```yaml
permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: osseco/setup-cargo-project-tools@<commit sha> # <release tag>
      - run: cargo nextest run
```

Copy the exact `uses:` line, with the commit SHA and tag, from the notes of the [latest release](https://github.com/osseco/setup-cargo-project-tools/releases/latest). Pin by full commit SHA with the version as a comment, as above; Dependabot and Renovate update both.

Audit the locks in their own job:

```yaml
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: osseco/setup-cargo-project-tools@<commit sha> # <release tag>
        with:
          install: false
          audit: deny-warnings
```

To filter crate downloads through [Socket Firewall Free](https://github.com/osseco/setup-sfw-free), run `osseco/setup-sfw-free` before this action. With `settings.sfw = "auto"` in `project-tools.toml`, cargo-project-tools uses `sfw` when it's on `PATH`; `"require"` fails the step when it isn't. On Windows runners, also set `CARGO_HTTP_CHECK_REVOKE: "false"` in the job's `env:`: sfw's local certificate has no revocation endpoint (see the cargo-project-tools [configuration docs](https://osseco.github.io/cargo-project-tools/docs/configuration#sfw)).

## Versions

Versions look like `v0.3.0-0.1.0`: the cargo-project-tools version, then this action's own version. The action's part follows semver and never resets, so `0.1.0` → `0.2.0` can mean a new cargo-project-tools version or a new feature here, and a major bump means a breaking change to inputs or outputs.

New cargo-project-tools releases are adopted by a maintainer when they are published.

## Inputs

All inputs are optional.

| Input               | Default | Description                                                                                                                                                         |
| ------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `install`           | `true`  | `true`: run `cargo project-tools install` and put `.project-tools/bin` on `PATH`. `false`: only install cargo-project-tools.                                          |
| `audit`             | `false` | `false`: only the audit `install` runs. `true`: `cargo project-tools audit` before `install`, which then skips its own. `deny-warnings`: also fail on unmaintained, unsound, notice, yanked and git-source warnings. |
| `cache`             | `auto`  | Tool binaries, tool builds and the advisory database in the Actions cache. `auto`: save on the default branch, restore elsewhere. `true`: restore, and save after a build or fetch, on any ref. `restore`: restore only. `false`: none. |
| `working-directory` | `.`     | Directory holding `project-tools.toml`, relative to the workspace. No `..`, no absolute paths.                                                                      |

Any other value fails the step.

`auto` compares `github.ref` with the repository's default branch. Events whose payload has no repository (rare) only restore.

## Outputs

| Output      | Description                                                                 |
| ----------- | --------------------------------------------------------------------------- |
| `version`   | Installed cargo-project-tools version, for example `0.3.0`.                 |
| `path`      | Absolute path to the `cargo-project-tools` binary.                          |
| `cache-hit` | `true` when the tool binaries came from the Actions cache with an exact key. |

## Caches

| Cache            | Path under `working-directory`                                         | Key                                                                                  |
| ---------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Tool binaries    | `.project-tools/bin`, `.project-tools/.crates.toml`, `.crates2.json`   | OS, arch, cargo-project-tools version, `project-tools.toml` and every tool lock; falls back to the latest entry for the OS and arch |
| Tool builds      | `.project-tools/targets`                                               | Same key; falls back to the latest build for the OS and arch. Only used on a bin miss. |
| Advisory database | `.project-tools/advisory-db`                                          | ISO week; falls back to an older week. Restored for `install` and `audit`.            |

`cargo project-tools install` runs on a cache hit too. It keeps a stamp and a sha256 per tool in `.project-tools/bin`, skips every tool whose stamp and binaries still match, and rebuilds the rest. After a change to `project-tools.toml` or a lock the key misses, an older entry is restored, and only the tools that changed are rebuilt. cargo-project-tools revalidates the advisory database itself (one small request when it's older than a day). That check catches a corrupt or partial entry; it doesn't prove where the entry came from: see [SECURITY.md](SECURITY.md#the-actions-cache).

## Requirements

- The repository checked out (cargo-project-tools needs `project-tools.toml` and a git checkout), unless `install` and `audit` are both `false`.
- `cargo` on `PATH` for `install` and `audit`. GitHub-hosted runners have it; elsewhere install a toolchain first.
- `bash` and `curl`. Alpine containers need `apk add bash curl git musl-dev` (and a Rust image such as `rust:1-alpine`).

## Secrets and permissions

None. The action downloads public release assets and uses the Actions cache through the runner's own credentials. It works with `permissions: {}`; `actions/checkout` needs `contents: read`.

## Environment variables

- Adds the directory holding `cargo-project-tools` and, with `install: true`, `.project-tools/bin` to `PATH`.
- Reads `RUNNER_TEMP`, `RUNNER_OS`, `RUNNER_ARCH` and `GITHUB_WORKSPACE`.

## Platforms

Linux x64 and arm64 (static musl binaries, so glibc and Alpine alike), macOS arm64, Windows x64. Other runners, such as macOS x64 and Windows arm64, fail the step: cargo-project-tools has no release binary for them.

## Limitations

- **Restored tool binaries are trusted as cached.** With the default `cache: auto` only default-branch runs write entries; protect that branch. Use `cache: false` in jobs whose output you release.
- **An advisory against cargo-project-tools itself fails `install` and `audit`** until this action pins a fixed release. To keep CI running meanwhile, accept it in `.project-tools/self-audit-ignore.toml` (see the cargo-project-tools [configuration docs](https://osseco.github.io/cargo-project-tools/docs/configuration#advisories-against-cargo-project-tools-itself)).
- **Audit and builds run in `working-directory`.** One project per step; use several steps for several projects.

## Security

See [SECURITY.md](SECURITY.md) for how to report a vulnerability, how this action is built and released, and how to verify a release.

## License

This action is [MIT licensed](LICENSE). cargo-project-tools is downloaded from its own releases at run time and not redistributed.
