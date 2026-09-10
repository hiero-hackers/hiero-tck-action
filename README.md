# hiero-tck-action

A GitHub Action to run the **Hiero SDK Technology Compatibility Kit (TCK)** test suite against a target JSON-RPC server and network node. 

> [!WARNING]
> This is an unofficial GitHub Action designed to simplify SDK testing against [`hiero-ledger/hiero-sdk-tck`](https://github.com/hiero-ledger/hiero-sdk-tck).



## Quick Start

Add this step to your GitHub Actions workflow file (e.g., `.github/workflows/tck-tests.yml`) to test SDK's JSON-RPC server:

```yaml
- name: Run Hiero TCK Test Suite
  uses: hiero-hackers/hiero-tck-action@main
  with:
    sdk: python
```

For a details and refrences, see the [Testing Guide](./docs/testing.md).

##  Inputs

### Server under test

| Input | Description | Default |
| ----- | ----------- | ------- |
| `startServer` | Build and run the server. Set `false` if your workflow starts it (it must background and terminate it; the action then only waits for it to answer). | `true` |
| `sdk` | Recommended: bundled SDK server preset. The workspace must be that SDK's checkout. | `""` |
| `dockerfilePath` | Escape hatch: custom Dockerfile path, relative to the workspace (not to `buildContext`). Mutually exclusive with `sdk`. Falls back to `./Dockerfile` when neither is set. | `""` |
| `rpcServerPort` | Port the JSON-RPC server listens on. Overrides a preset; otherwise 8544. | preset / `8544` |
| `serverEnv` | Environment passed to the container, one `KEY=VALUE` per line. Keys override preset defaults. | preset / `""` |
| `serverStartupTimeout` | Seconds to wait for the server to answer | `120` |
| `buildContext` | Directory used as the `docker build` context. Set it when the SDK is checked out into a subdirectory. | workspace root |
| `dockerBuildArgs` | Extra arguments appended to `docker build`, e.g. `--cache-from`/`--cache-to`, `--build-arg`. See [slow-building SDKs](#slow-building-sdks). | `""` |

### Supported SDK presets

Presets select a Dockerfile and server defaults; they do not fetch source. The workflow must
first check out the matching upstream SDK. Every bundled Dockerfile builds that checkout using
the consumer workspace as its Docker build context.

<!-- sdk-table:start -->
| ID | SDK | Aliases | Upstream | Expected build |
| -- | --- | ------- | -------- | -------------: |
| `cpp` | Hiero C++ SDK | `c++`, `cplusplus` | [hiero-ledger/hiero-sdk-cpp](https://github.com/hiero-ledger/hiero-sdk-cpp) | 60 min |
| `go` | Hiero Go SDK | `golang` | [hiero-ledger/hiero-sdk-go](https://github.com/hiero-ledger/hiero-sdk-go) | 3 min |
| `java` | Hiero Java SDK | `jvm` | [hiero-ledger/hiero-sdk-java](https://github.com/hiero-ledger/hiero-sdk-java) | 12 min |
| `javascript` | Hiero JavaScript SDK | `js`, `node` | [hiero-ledger/hiero-sdk-js](https://github.com/hiero-ledger/hiero-sdk-js) | 4 min |
| `python` | Hiero Python SDK | `py` | [hiero-ledger/hiero-sdk-python](https://github.com/hiero-ledger/hiero-sdk-python) | 2 min |
| `rust` | Hiero Rust SDK | `rs` | [hiero-ledger/hiero-sdk-rust](https://github.com/hiero-ledger/hiero-sdk-rust) | 6 min |
| `swift` | Hiero Swift SDK | `ios` | [hiero-ledger/hiero-sdk-swift](https://github.com/hiero-ledger/hiero-sdk-swift) | 4 min |
<!-- sdk-table:end -->

The C++ preset is intentionally called out as slow: budget about an hour and use the layer
cache configuration below. `serverEnv` and `rpcServerPort` remain available for overrides.

> [!IMPORTANT]
> The build context is the workspace, so anything else checked out beside the SDK ends up in
> it - and inside every image built by a Dockerfile that does `COPY . .`. When the workflow
> checks out more than the SDK, give the SDK its own directory and point `buildContext` at it:
>
> ```yaml
> - uses: actions/checkout@v7.0.1
>   with:
>     repository: hiero-ledger/hiero-sdk-python
>     path: sdk
> - uses: hiero-hackers/hiero-tck-action@main
>   with:
>     sdk: python
>     buildContext: ${{ github.workspace }}/sdk
> ```
>
> Leaving stray directories in the context also changes it on every run, which costs the C++
> preset its layer cache and about half an hour.

### Network under test

Defaults match [`hiero-solo-action`](https://github.com/hiero-ledger/hiero-solo-action) with `installMirrorNode: true`.

| Input | Description | Default |
| ----- | ----------- | ------- |
| `nodeIp` | Consensus node address | `127.0.0.1:35211` |
| `nodeAccountId` | Consensus node account | `0.0.3` |
| `operatorAccountId` | Operator account | `0.0.2` |
| `operatorPrivateKey` | Operator key (masked in logs) | Solo genesis key |
| `mirrornodeGrpcUrl` | Mirror node gRPC | `127.0.0.1:5600` |
| `mirrornodeRestUrl` | Mirror node REST | `http://127.0.0.1:38081` |
| `mirrornodeRestJavaUrl` | Mirror node Java REST | `http://127.0.0.1:8084` |
| `nodeTimeout` | Consensus request timeout (ms) | `30000` |

### Which tests to run

| Input | Description | Default |
| ----- | ----------- | ------- |
| `tckTag` | Tag, branch or SHA of `hiero-sdk-tck` | `v0.12.4` |
| `testMatrix` | Mocha arguments naming what to run: specs, globs, `--grep`. Runs **only** these. Overrides `testScript`. | `""` |
| `testScript` | npm script for a whole-suite run, used when `testMatrix` is empty. Falls back to `test` on tags without `test:ci`. | `test:ci` |

### Reporting

| Input | Description | Default |
| ----- | ----------- | ------- |
| `uploadReport` | Upload the mochawesome report as an artifact | `true` |
| `artifactName` | Artifact name. Vary per matrix leg. | `tck-report` |


##  Choosing what to run

**The whole suite** is the default: `testScript` runs the TCK's own `test:ci`, which executes
every spec in parallel and gates the result on the mochawesome report rather than mocha's exit
code, so a worker killed mid-run fails the job instead of silently passing. Expect **16-20
minutes**. Nothing needs configuring:

```yml
- uses: hiero-hackers/hiero-tck-action@main
  with:
    sdk: python
```

**While implementing a single method**, name its spec file with `testMatrix`. Only that file is
loaded and compiled, so the run takes about a minute instead of twenty:

```yml
    testMatrix: "src/tests/crypto-service/test-account-create-transaction.ts"
```

`testMatrix` takes mocha arguments, so globs and filters work too, and quoted phrases survive:

```yml
    testMatrix: "src/tests/token-service/*.ts"
    # or narrow to one test:
    testMatrix: "src/tests/crypto-service/*.ts --grep 'Creates an account with'"
```

### Sharding the suite

`testMatrix` is designed to pair with a job matrix. Giving each shard its own Solo network keeps
any single network off the critical path, and each shard's report is uploaded separately:

```yml
strategy:
  fail-fast: false
  matrix:
    include:
      - shard: crypto
        spec: "src/tests/crypto-service/*.ts"
      - shard: token
        spec: "src/tests/token-service/*.ts"
      - shard: topic
        spec: "src/tests/topic-service/*.ts"
steps:
  - uses: hiero-ledger/hiero-solo-action@v0.24.0   # one network per shard
    with: { installMirrorNode: true }
  - uses: hiero-hackers/hiero-tck-action@main
    with:
      testMatrix: ${{ matrix.spec }}
      artifactName: tck-report-${{ matrix.shard }}
```

> [!NOTE]
> `test:ci` and `test` run mocha with `--parallel`, and mochawesome does not populate per-test
> detail under parallel mode: the counts are correct but no failing test names are recorded, and
> the HTML report is empty. When you need to know *which* tests failed, re-run the affected specs
> with `testMatrix`, or the whole suite with `testScript: test:serial`. The action says so in the
> job summary rather than showing an empty list.

> [!TIP]
> A common pattern is `testMatrix` on pull requests for fast feedback, and the full suite
> nightly on a schedule.


## Slow-building SDKs

For the Java and Python SDKs the image build is noise. For a compiled SDK it is the entire
run: on `ubuntu-latest` the C++ server takes **~58 minutes** to build, against **30 seconds**
for the spec that then exercises it. Two things make that bearable.

**Put the expensive layers above `COPY . .`.** A Dockerfile that copies the source in before
building its dependencies re-does everything on every commit. Copy in only the files that pin
the dependencies, build them, and copy the source last - see
[`dockerfiles/cpp_sdk.Dockerfile`](./dockerfiles/cpp_sdk.Dockerfile), where the 22-minute vcpkg
layer is keyed on `vcpkg.json` alone and survives any source change.

**Then cache those layers across runs** with `dockerBuildArgs`:

```yml
- uses: docker/setup-buildx-action@v3
  with:
    install: true          # makes `docker build` use buildx

- uses: hiero-hackers/hiero-tck-action@main
  with:
    dockerfilePath: ./src/tck/Dockerfile
    dockerBuildArgs: "--load --cache-from type=gha --cache-to type=gha,mode=max"
```

> [!IMPORTANT]
> `--load` is required whenever buildx is not using the plain `docker` driver. Without it the
> image is built and discarded, and the action's `docker run` fails with "Unable to find image".

> [!NOTE]
> The GitHub Actions cache is capped at 10 GB per repository, which a large C++ build stage can
> exceed. If layers keep being evicted, cache to a registry instead
> (`type=registry,ref=ghcr.io/OWNER/REPO:buildcache`), or publish a prebuilt dependencies image
> and start the Dockerfile `FROM` it.

Note that the action builds the server image *before* it checks out the TCK, so the build
context is your repository as checked out, and nothing the action itself adds. A Dockerfile
doing `COPY . .` gets your sources and nothing else.


##  Outputs

The action always lets the TCK suite run to completion, then publishes its results before failing the
job. Results come from the mochawesome report the suite writes to `hiero-tck/mochawesome-report/`.

| Output | Description |
| ------ | ----------- |
| `total` | Total number of TCK tests executed |
| `passed` | Number of passing tests |
| `failed` | Number of failing tests |
| `pending` | Number of pending tests |
| `hookFailures` | Failed suite hooks, counted separately from test failures |
| `skipped` | Registered tests that never ran, usually after a hook failure |
| `registered` | Tests registered by the suite, including those that never ran |
| `genuineFailures` | Genuine assertion failures, excluding server/network failures |
| `infraFailures` | Server, network, or harness failures |
| `unimplementedMethods` | Comma-separated JSON-RPC methods reported as not implemented |
| `reportPath` | Path to the mochawesome report directory, empty if no report was produced |

In addition, the action writes a pass/fail table (and a collapsed list of failing tests) to the
[job summary](https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#adding-a-job-summary),
uploads the HTML and JSON report as an artifact, and dumps the RPC server container logs when the
suite fails.

To act on the results yourself, give the step an `id` and read its outputs:

```yml
- name: Run TCK test
  id: tck
  uses: hiero-hackers/hiero-tck-action@main

- name: Report
  if: always()
  run: echo "${{ steps.tck.outputs.passed }}/${{ steps.tck.outputs.total }} TCK tests passed"
```

> [!NOTE]
> `artifactName` must be unique per job. When running this action in a matrix, vary it
> (e.g. `artifactName: tck-report-${{ matrix.sdk }}`) or the artifact upload will fail on
> duplicate names.


##  Requirements and caveats

- **Linux runners only.** The server container is started with `--network host` so it can reach
  Solo on `localhost`. Host networking is a no-op on macOS and Windows runners.
- **Docker and `jq`** must be present. Both are preinstalled on `ubuntu-latest`.
- **A crashing managed server fails fast.** The action reports its exit code and groups its
  container logs instead of waiting for the startup timeout. Externally started servers are
  still polled for the full timeout because the action cannot determine their lifecycle.
- **The action runs `actions/setup-node`**, which changes the Node version for the rest of the
  job. If your workflow depends on a specific Node version afterwards, re-run `setup-node`.
- **`operatorPrivateKey` is masked** via `::add-mask::`, but action inputs are not secrets.
  The default is the well-known Solo genesis key. Never pass a key with real value.

> [!IMPORTANT]
> `rpcServerPort` tells the action where to *probe*; it does not tell your server where to
> *listen*. SDK presets configure both values together. With a custom `dockerfilePath`, use
> `serverEnv` to pass the port through in whatever form your server expects, or they may disagree.

## Usage

A pull-request check that runs only the method being worked on, plus the full suite nightly:

```yml
name: TCK

on:
  pull_request:
  schedule:
    - cron: "0 3 * * *"

permissions:
  contents: read

jobs:
  tck:
    name: TCK
    runs-on: ubuntu-latest
    timeout-minutes: 90

    steps:
      - name: Checkout repository
        uses: actions/checkout@v7.0.1

      - name: Prepare Hiero Solo
        id: solo
        uses: hiero-ledger/hiero-solo-action@v0.24.0
        with:
          installMirrorNode: true

      - name: Run TCK
        id: tck
        uses: hiero-hackers/hiero-tck-action@main
        with:
          sdk: python
          # Fast, targeted run on PRs; whole suite on the nightly.
          testMatrix: ${{ github.event_name == 'pull_request' && 'src/tests/crypto-service/test-account-create-transaction.ts' || '' }}
          artifactName: tck-report-${{ github.event_name }}

      - name: Summarise
        if: always()
        run: |
          echo "${{ steps.tck.outputs.passed }}/${{ steps.tck.outputs.total }} passed, \
                ${{ steps.tck.outputs.skipped }} never ran"
```
