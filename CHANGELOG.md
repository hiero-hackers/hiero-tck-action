# Changelog

## Unreleased

### Added

- `sdk` input selecting a bundled server preset, backed by `dockerfiles/sdks.json` as the
  single source of truth for Dockerfile, aliases, default `serverEnv` and `rpcServerPort`.
  Preset values are overridable per key by the caller's `serverEnv`, and the resolved source
  of every value is logged.
- `dockerBuildArgs` input, appended to `docker build` and split like a shell command line, so
  slow-building SDKs can pass `--cache-from`/`--cache-to`.
- `buildContext` input, so a workflow that checks out more than the SDK can keep the sibling
  directories out of the build context, and out of every image built by a Dockerfile doing
  `COPY . .`. The bundled workflows now check the SDK out into `sdk/` and use it.
- Optional `ref` per registry entry, letting the nightly pin a known-good SDK commit when an
  upstream default branch is broken, without editing the workflow.
- Standalone scripts under `scripts/`, each runnable outside Actions from documented
  environment variables, with `action.yml` reduced to glue.
- A bats suite under `tests/` covering result classification, output completeness, preset
  resolution and merging, argument splitting, readiness and teardown, with snapshot
  comparison of the rendered step summary.
- Lint, pull-request self-test, and registry-driven nightly workflows.
- `scripts/validate-sdks.sh`, asserting the registry and `dockerfiles/` agree in both
  directions and that the README's preset table is generated from the registry.

### Fixed

- Every declared output is now written on every path. A run that produced no report emitted
  only seven of eleven, leaving `genuineFailures`, `infraFailures` and `unimplementedMethods`
  as empty strings that broke arithmetic in consuming steps.
- The server image is built before the TCK is checked out. The checkout landed inside the
  workspace, which is the Docker build context, so the suite and its `node_modules` were
  copied into every image built by a Dockerfile doing `COPY . .` and invalidated any layer
  cache warmed earlier in the job.
- A managed server that dies is reported immediately with its exit code and grouped logs,
  rather than after the full `serverStartupTimeout` with a misleading "no response" error.
- Readiness retries the JSON-RPC `reset` for as long as the timeout allows. Failing the run on
  the first unanswered call turned an ordinary startup race - a process that binds its port
  before it finishes serving - into a hard error.
- A readiness timeout now distinguishes a port that never listened from one that listened but
  never answered JSON-RPC.
- The Go preset builds a statically linked binary on a pinned base image, replacing a
  glibc-linked binary shipped onto musl behind `libc6-compat`, and uses `go mod download`
  rather than `go mod tidy`, which rewrites the committed dependency set during a build.
- A crashing container's logs are printed again. The refactor that introduced a shared
  log-dumping helper guarded it on `docker ps`, which the crash path does not satisfy, so the
  `::group::` block disappeared from exactly the failure it exists to explain.
- An invalid `serverEnv` line now explains itself. The validation ran inside a pipeline, so
  its `::error` annotation was swallowed by the downstream `awk` and the run failed with no
  message at all.
- `serverEnv` is written to `$GITHUB_OUTPUT` under a randomised heredoc delimiter, so a value
  can never terminate the block early. The `KEY=VALUE` guard already prevented this; the
  delimiter is a second layer behind it.

### Changed

- Readiness probes TCP first and only then sends one `reset`. The previous probe issued a
  mutating `reset` every two seconds throughout startup, and its `curl --fail` rejected
  servers that answer unknown methods with a JSON-RPC error carried by HTTP 4xx.
- `dockerfilePath` now defaults to empty and falls back to `./Dockerfile` inside
  `resolve-server.sh`, so setting both it and `sdk` is detectable and is a hard error.
  Workflows that set neither are unaffected.
- Scripts avoid expanding empty arrays under `set -u`, which aborts on bash 3.2 and prevented
  `start-server.sh` from running on a macOS workstation.
- The bats suite refuses to run on bash 3.2, the /bin/bash on macOS, where bats silently
  passes a failing assertion unless it is the last command in a test. The suite reported green
  on a workstation while failing on a runner; `tests/setup_suite.bash` now stops that.
- The lint workflow runs actionlint from its pinned image and relies on the runner's
  preinstalled shellcheck, rather than building actionlint from source, which routinely took
  the job past its own two-minute timeout.
