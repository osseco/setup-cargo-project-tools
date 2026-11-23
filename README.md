# setup-cargo-project-tools

A GitHub Action that installs [cargo-project-tools](https://github.com/osseco/cargo-project-tools), builds your project's tools with it, and can audit their locks. It replaces the cache, install and `PATH` steps from the [cargo-project-tools CI guide](https://osseco.github.io/cargo-project-tools/docs/ci) with one step.

This version of the action installs cargo-project-tools <!-- cargo-project-tools-version -->5.6.0<!-- /cargo-project-tools-version -->.

- Each action version installs exactly one cargo-project-tools version. Its sha256 for every platform is pinned in [`cargo-project-tools.sha256`](cargo-project-tools.sha256), and the binary is checked against it before it runs.
- Downloads come only from the cargo-project-tools GitHub releases. Nothing is built from source to get cargo-project-tools itself.
- `cargo project-tools check` runs first: this runner against each tool's `targets`, the audit, and the [build review](https://osseco.github.io/cargo-project-tools/docs/build-review) of every build script and proc macro. Nothing is built until all of it passes.
- The tools build in a sandbox: on Linux in a Docker container with no network, no capabilities and only the build output writable; on macOS in `sandbox-exec`. Windows has no sandbox.
- `cargo project-tools install` runs with the tool binaries and builds in your repository's Actions cache, saved only from the default branch by default, and `.project-tools/bin` goes on `PATH`.
- `audit` runs `cargo project-tools audit` first, optionally failing on warnings too, and works without `install`. The advisory database is cached per week.
- Findings show as annotations on the files to change, and every JSON record is in the `records` output.
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

Before the first run, decide every tool's build-time code where you work, and commit the result:

```bash
cargo project-tools review
```

That writes `.project-tools/crates/<tool>/build-review.toml`. `check` fails on anything it doesn't record, or records as `pending`, and the annotation says which tool and piece. If you set `targets` in `project-tools.toml`, list the triple of every runner you build on. The action never approves anything or adds targets: it doesn't pass `--auto-approve` or `--approve-target`. To make sure a person reviewed each change to `build-review.toml`, give those files a code owner: see [Who approved it](https://osseco.github.io/cargo-project-tools/docs/build-review#who-approved-it).

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
| `install`           | `true`  | `true`: run `cargo project-tools check`, then `install`, and put `.project-tools/bin` on `PATH`. `false`: only install cargo-project-tools.                          |
| `audit`             | `false` | `false`: only the audit `check` runs. `true`: `cargo project-tools audit` before `check`, which then skips its own. `deny-warnings`: also fail on unmaintained, unsound, notice, yanked and git-source warnings. |
| `cache`             | `auto`  | Tool binaries, tool builds and the advisory database in the Actions cache. `auto`: save on the default branch, restore elsewhere. `true`: restore, and save after a build or fetch, on any ref. `restore`: restore only. `false`: none. |
| `working-directory` | `.`     | Directory holding `project-tools.toml`, relative to the workspace. No `..`, no absolute paths.                                                                      |
| `sandbox`           | `container` | `container`: on Linux, build in a Docker container (see [How the tools are built](#how-the-tools-are-built)). `cpt`: build on the runner with the project's own `[build].sandbox`, for job containers and runners without Docker. macOS always requires `sandbox-exec`; Windows has none. |
| `container-image`   | (empty) | Image for `sandbox: container`. It needs `cc` and the runner's glibc. Empty: `buildpack-deps` for the runner's Ubuntu release, pinned by digest in [`container-images`](container-images). A name without `@sha256:` gets a warning. |

Any other value fails the step.

`auto` compares `github.ref` with the repository's default branch. Events whose payload has no repository (rare) only restore.

## Outputs

| Output      | Description                                                                 |
| ----------- | --------------------------------------------------------------------------- |
| `version`   | Installed cargo-project-tools version, for example `0.3.0`.                 |
| `path`      | Absolute path to the `cargo-project-tools` binary.                          |
| `cache-hit` | `true` when the tool binaries came from the Actions cache with an exact key. |
| `records`   | Path to a file with every [JSON record](https://osseco.github.io/cargo-project-tools/docs/commands#json-output) cargo-project-tools wrote in this step, one per line. Values in it come from locks, crates and the advisory database: check them before you use them. |

## How the tools are built

1. `audit` (with `audit: true` or `deny-warnings`), then `check`. `check` reports every problem in one run and builds nothing. For each tool that isn't up to date it fetches the source and vendors the dependencies, through [sfw](#usage) when it's on `PATH`.
2. `install` builds what `check` prepared:
   - **Linux**, `sandbox: container`: `install --offline` inside `docker run --network none --read-only --cap-drop ALL --security-opt no-new-privileges`, as the runner's user. The workspace is read-only; only `.project-tools/targets`, `.project-tools/bin` and cargo's `.crates.toml` and `.crates2.json` are writable. The runner's rustup toolchain and the checked cargo-project-tools binary are mounted read-only, and `CARGO_HOME` is an empty read-only directory. When `check` found every tool up to date, no container starts.
   - **macOS**: `--sandbox require`, so the build runs in `sandbox-exec`, with no network and writes only to the build output.
   - **Windows**, and Linux with `sandbox: cpt`: the project's own `[build].sandbox` setting. Windows has no sandbox, and the step says so.
3. Annotations: errors and warnings on the files to change, from the records. A build review that needs a decision points to `cargo project-tools review <tool>`, never to approving.

All cargo-project-tools output runs with workflow commands turned off (`::stop-commands::`), since it carries text from crates and their builds.

## Caches

| Cache            | Path under `working-directory`                                         | Key                                                                                  |
| ---------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Tool binaries    | `.project-tools/bin`, `.project-tools/.crates.toml`, `.crates2.json`   | OS, arch, cargo-project-tools version, `project-tools.toml` and everything in `.project-tools/crates` (locks, build reviews, overrides); falls back to the latest entry for the OS and arch. Restored for `install` and `audit`, saved only by `install`. |
| Tool builds      | `.project-tools/targets`, except `*/vendor`, `*/previous` and `*/prepared.json` | Same key; falls back to the latest build for the OS and arch. Only used on a bin miss. |
| Advisory database | `.project-tools/advisory-db`                                          | ISO week; falls back to an older week. Restored for `install` and `audit`.            |

`cargo project-tools install` runs on a cache hit too. It keeps a stamp and a sha256 per tool in `.project-tools/bin`, skips every tool whose stamp and binaries still match, and rebuilds the rest. After a change to `project-tools.toml` or anything in `.project-tools/crates` the key misses, an older entry is restored, and only the tools that changed are rebuilt. `audit` keeps what each tool builds in `.project-tools/bin/.stamps`, so a restored bin cache also saves it downloads. Vendored sources are fetched again by `check` for every build, and what `check` prepares is only valid for that run, so neither is cached. cargo-project-tools revalidates the advisory database itself (one small request when it's older than a day). That check catches a corrupt or partial entry; it doesn't prove where the entry came from: see [SECURITY.md](SECURITY.md#the-actions-cache).

## Requirements

- The repository checked out (cargo-project-tools needs `project-tools.toml` and a git checkout), unless `install` and `audit` are both `false`.
- A committed `build-review.toml` for every tool, with no `pending` entries, and the runners' triples in `targets` when it's set. See [Usage](#usage).
- `cargo` on `PATH` for `install` and `audit`. GitHub-hosted runners have it; elsewhere install a toolchain first.
- With `install: true` on Linux and the default `sandbox: container`: Docker, and a rustup toolchain (`RUSTUP_HOME`, or `~/.rustup`) that the container can mount. GitHub-hosted Ubuntu runners have both. In a job container (`container:`) or on a runner without Docker, set `sandbox: cpt`.
- `bash` and `curl`; `jq` for annotations and for skipping an unneeded container (without it, findings are only in the log). Alpine containers need `apk add bash curl git jq musl-dev` (and a Rust image such as `rust:1-alpine`).

## Secrets and permissions

None. The action downloads public release assets and uses the Actions cache through the runner's own credentials. It works with `permissions: {}`; `actions/checkout` needs `contents: read`.

## Environment variables

- Adds the directory holding `cargo-project-tools` and, with `install: true`, `.project-tools/bin` to `PATH`.
- Reads `RUNNER_TEMP`, `RUNNER_OS`, `RUNNER_ARCH` and `GITHUB_WORKSPACE`; for the Linux container also `RUSTUP_HOME`, `RUSTUP_TOOLCHAIN` and `/etc/os-release`. No other variable reaches the container.

## Platforms

Linux x64 and arm64 (static musl binaries, so glibc and Alpine alike), macOS arm64, Windows x64. Other runners, such as macOS x64 and Windows arm64, fail the step: cargo-project-tools has no release binary for them.

## Limitations

- **Restored tool binaries are trusted as cached.** With the default `cache: auto` only default-branch runs write entries; protect that branch. Use `cache: false` in jobs whose output you release.
- **An advisory against cargo-project-tools itself fails `install` and `audit`** until this action pins a fixed release. To keep CI running meanwhile, accept it in `.project-tools/self-audit-ignore.toml` (see the cargo-project-tools [configuration docs](https://osseco.github.io/cargo-project-tools/docs/configuration#advisories-against-cargo-project-tools-itself)).
- **Audit and builds run in `working-directory`.** One project per step; use several steps for several projects.
- **The default build image only has what `buildpack-deps` has.** A tool that links a system library the image lacks fails to build in the container: set `container-image` to an image that has it, for the runner's distro release.
- **A failed build needs a new `check`.** What `check` prepared is used once. The action doesn't retry; the next run checks again.
- **Windows builds have no sandbox.** Build scripts and proc macros run with network and write access there; the build review is the only control.

## Security

See [SECURITY.md](SECURITY.md) for how to report a vulnerability, how this action is built and released, and how to verify a release.

## License

This action is [MIT licensed](LICENSE). cargo-project-tools is downloaded from its own releases at run time and not redistributed.
