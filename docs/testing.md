## Testing the TCK Runnner


The TCK Runner is used by the Forkedd Hiero Python SDK to validate its JSON-RPC endpoints.

A complete example of the TCK workflow can be found in the Forked Python SDK repository:
[Hiero SDK Python TCK test workflow](https://github.com/manishdait/hiero-sdk-python/tree/local/test-tck-action)

The workflow follows this structure:

```yaml
name: Test TCK endpoints

on:
  push:

  pull_request:

permissions:
  contents: read

jobs:
  tck-test:
    name: "Run TCK test"
    runs-on: ubuntu-latest

    steps:
      - name: Harden the runner (Audit all outbound calls)
        uses: step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920 # v2.20.0
        with:
          egress-policy: audit

      - name: Checkout repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Prepare Hiero Solo
        id: solo
        uses: hiero-ledger/hiero-solo-action@bdae0a37df52190b6b3801c1c981c0ed37f4616e # v0.23.0
        with:
          installMirrorNode: true
          mirrorNodeVersion: v0.153.0
          hieroVersion: v0.73.0
          soloVersion: 0.87.1

      - name: Run TCK test
        uses: hiero-hackers/hiero-tck-action@main
```

### Python SDK Dockerfile

The Python SDK provides the JSON-RPC server through a root-level `Dockerfile`. The TCK Runner builds this Dockerfile and starts the resulting container before executing the TCK tests.

The Dockerfile is responsible for:

* Installing the Python dependencies.
* Generating protobuf code.
* Starting the Python JSON-RPC server.
* Listening on port `8544`.

Example:

```dockerfile
FROM python:3.12-slim-bookworm

COPY --from=docker.io/astral/uv:latest /uv /uvx /bin/

ENV PDM_BUILD_SCM_VERSION=0.1.0

WORKDIR /app

RUN apt update && apt install -y curl

COPY . .

RUN uv sync --all-extras

RUN uv run generate_proto.py

EXPOSE 8544

CMD ["uv", "run", "-m", "tck"]
```

### Note For Python Sdk
Need to update the host for the tck server from `127.0.0.1` to `0.0.0.0`

```python
@dataclass
class ServerConfig:
    """Configuration for the TCK server."""

    host: str = field(default_factory=lambda: os.getenv("TCK_HOST", "0.0.0.0"))  # nosec B104
    port: int = field(default_factory=lambda: _parse_port(os.getenv("TCK_PORT", "8544")))
    ...
```

> [!NOTE]
> The TCK uses the `test:ci` command to run the test suite. This command is available in TCK versions `v0.12.1` and later. For older TCK versions, the runner falls back to `test`, which may fail due to the high resource usage of the TCK test suite when using tckTag below `v0.12.1`.

### Reference

For a working implementation, see the **`test-tck-action` branch of `hiero-sdk-python` fork**:

- [Forked Hiero SDK Python test-tck-action branch](https://github.com/manishdait/hiero-sdk-python/tree/local/test-tck-action)
- [TCK Runner Workflow Logs](https://github.com/manishdait/hiero-sdk-python/actions/runs/33972335265/job/101322936636)


**Note**

A working example of the TCK Runner with a fork of the Hiero Java SDK is available here:

- [Forked Hiero SDK Java test-tck-action branch](https://github.com/manishdait/hiero-sdk-java/tree/poc/tck-action)
- [TCK Runner Workflow Logs For Java Sdk](https://github.com/manishdait/hiero-sdk-java/actions/runs/33973314167/job/101325555201)

## C++ SDK

The C++ SDK is the slow case, and the one that shaped the action's build step. Its server
lives at `src/tck` in [`hiero-ledger/hiero-sdk-cpp`](https://github.com/hiero-ledger/hiero-sdk-cpp)
and is built by [`dockerfiles/cpp_sdk.Dockerfile`](../dockerfiles/cpp_sdk.Dockerfile).

```yaml
- name: Run TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    dockerfilePath: ./src/tck/Dockerfile
    serverEnv: |
      TCK_PORT=8544
```

Reference run: **42 passing, 0 failing**, no unimplemented methods, on TCK `v0.12.4` against
`src/tests/crypto-service/test-account-create-transaction.ts`. The job took **81 minutes** on
`ubuntu-latest`: 5 for Solo, 75 for the action, of which the suite itself was 33 seconds.

> [!TIP]
> The image build competes with Solo, which is already running by the time the action starts.
> Building the same Dockerfile in a step *before* Solo costs nothing extra - the action's own
> `docker build` then hits the daemon's layer cache - and the compile gets the runner to itself,
> which measured 58 minutes rather than 75. This only works because the action builds from a
> clean context; a warm-up build placed before an action that checked out the TCK first would
> miss the cache entirely and compile twice.

### Build cost

Measured on `ubuntu-latest` (4 vCPU) and on an Apple M5 (10 cores, `-j 6`). Both land near
an hour, so this is the size of the work rather than a slow runner:

| Layer | M5 | Notes |
| ----- | -: | ----- |
| vcpkg dependencies | 22m 30s | OpenSSL, protobuf, gRPC, Abseil, all from source |
| SDK + HAPI protobufs | 26m 24s | ~900 translation units, mostly generated `.pb.cc` |
| vcpkg clone + bootstrap | 18s | |
| HAPI shallow clone | 19s | `--depth 1`, against a 634 MB full clone otherwise |
| CMake configure | 5s | |
| **Total** | **50m 04s** | 58m on `ubuntu-latest` |

Give the job `timeout-minutes: 180`, and free disk before it runs - the build needs roughly
30 GB, more than an `ubuntu-latest` runner has spare:

```yaml
- name: Free disk space
  run: |
    sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc "$AGENT_TOOLSDIRECTORY" || true
```

See [Slow-building SDKs](../README.md#slow-building-sdks) for caching these layers between runs.

### Things specific to this SDK

**`BUILD_TCK` is off by default.** Without `-DBUILD_TCK=ON` the server target is never
generated and the build succeeds having produced nothing.

**Ninja Multi-Config needs the configuration twice.** The `linux-x64-release` preset uses a
multi-config generator, so `cmake --install` without `--config Release` looks for Debug
artifacts that were never built and fails.

**The port is `argv[1]`, not an environment variable.** `TckServer` takes it as a positional
argument, so `serverEnv: TCK_PORT=8544` is ignored unless the image maps it across. The
Dockerfile does that in its entrypoint, keeping the container configured like the others:

```dockerfile
ENTRYPOINT ["/bin/sh", "-c", "exec /app/tck/hiero-sdk-cpp-tck \"${TCK_PORT:-8544}\""]
```

**The server binds `localhost`, not `0.0.0.0`.** This is fine under the action, which runs the
container with `--network host`, but a published port (`-p 8544:8544`) will not reach it. On
macOS, where host networking is unavailable, the image cannot be smoke-tested without changing
the bind address.

**Dependencies Ubuntu does not ship.** `SystemLibraries.cmake` hard-fails without `zip` and
`linux-libc-dev`, and vcpkg's OpenSSL port needs `perl`. None are in `ubuntu:24.04`.

**x86_64 and arm64.** `CMakePresets.json` only covers linux-x64, so the Dockerfile configures
CMake explicitly and picks the vcpkg triplet from `TARGETARCH`. That is what lets it build
natively on an Apple Silicon machine instead of under emulation.


## Swift SDK

The Swift SDK is the cheap case. Its server is the `HieroTCK` Vapor executable in
[`hiero-ledger/hiero-sdk-swift`](https://github.com/hiero-ledger/hiero-sdk-swift), built by
[`dockerfiles/swift_sdk.Dockerfile`](../dockerfiles/swift_sdk.Dockerfile). The whole image
builds in about **two minutes** - less than a single CMake configure on the C++ SDK - so none
of the caching advice applies here.

```yaml
- name: Run TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    dockerfilePath: ./Sources/HieroTCK/Dockerfile
    serverEnv: |
      TCK_PORT=8544
```

Reference run: **42 passing, 0 failing**, no unimplemented methods, on TCK `v0.12.4` against
`src/tests/crypto-service/test-account-create-transaction.ts`. The whole job took **12 minutes**
on `ubuntu-latest` - 6 for Solo, 6 for the action, of which the suite itself was 35 seconds.

### Things specific to this SDK

**It has to be a debug build.** `Sources/HieroTCK/main.swift` does `@testable import Hiero`,
and that only links against a module compiled with `-enable-testing` - the default in debug and
not in release. `swift build -c release` fails with *module 'Hiero' was not compiled for
testing*; upstream CI builds plain `swift build` for the same reason.

**Do not check out the `protobufs` submodule.** It points at `hiero-consensus-node`, a 634 MB
repository, and nothing in the build reads it: the generated Swift is committed under
`Sources/HieroProtobufs/Generated`, and the target excludes `Protos` outright.

**Keep SwiftPM's scratch directory off the source tree.** `swift package resolve` writes to
`./.build`, so a later `COPY . .` overwrites the resolved dependencies with whatever the build
context happens to carry. Passing `--scratch-path /build` to both `resolve` and `build` puts it
somewhere the copy cannot reach.

**A `.dockerignore` is close to mandatory.** A working clone's `.build/` reaches tens of
gigabytes - 14 GB in the one measured here - and `docker build` sends all of it as context:

```
.build/
protobufs/
.git/
```

That takes the context from 16 GB to about 9 MB.

**The port and hostname come from the serve command.** `main.swift` hardcodes
`configuration.port = 8544` and leaves Vapor's default `127.0.0.1` hostname, but Vapor's `serve`
command overrides both, so the entrypoint can bind every interface and honour `TCK_PORT`:

```dockerfile
ENTRYPOINT ["/bin/sh", "-c", "exec /app/HieroTCK serve --hostname 0.0.0.0 --port \"${TCK_PORT:-8544}\""]
```

Binding `0.0.0.0` rather than loopback means this image, unlike the C++ one, also works behind a
published port (`-p 8544:8544`) and can therefore be smoke-tested on a macOS workstation.

**Coverage.** The server implements crypto, contract, file, key, token and topic methods plus
`setup`/`reset`/`setOperator`. There is no schedule service, so `src/tests/schedule-service/*`
reports as unimplemented rather than failing.


## JavaScript SDK

The JS SDK already ships a `tck/Dockerfile`, but it is not the one to point the action at.
That file runs `pnpm add @hiero-ledger/sdk@^2.70.0`, so it tests the **published** package
rather than the branch under review, and it expects the build context to be `tck/` while the
action always builds from the repository root.

[`dockerfiles/js_sdk.Dockerfile`](../dockerfiles/js_sdk.Dockerfile) builds the SDK from the
checkout, packs it, and installs that tarball over the pinned dependency. Add it to the
repository as `tck/Dockerfile.local` so it sits beside the original without replacing it:

```yaml
- name: Run TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    dockerfilePath: ./tck/Dockerfile.local
    serverEnv: |
      TCK_PORT=8544
```

The image builds in about **three minutes**, most of it `pnpm install` over ~2750 packages and
the rollup bundle.

Reference run: **42 passing, 0 failing**, no unimplemented methods, on TCK `v0.12.4` against
`src/tests/crypto-service/test-account-create-transaction.ts`. The job took **10 minutes** on
`ubuntu-latest`: 5.5 for Solo, 4.5 for the action, of which the suite itself was 29 seconds.

### Things specific to this SDK

**Do not check out the `packages/proto/src/services` submodule.** It points at
`hiero-consensus-node`, and `task build` was verified to complete without it. Checking out
submodules costs a 634 MB clone for nothing.

**Pin pnpm and go-task rather than using corepack.** The root `package.json` declares no
`packageManager` field, so `corepack enable` has nothing to resolve against and may pick a pnpm
that disagrees with `pnpm-lock.yaml`. `.github/workflows/build.yml` is the reference:
pnpm `9.15.5`, go-task `3.35.1`.

**Delete the pinned SDK before installing, and copy `tck/` before deleting it.** The order
matters in both directions:

```dockerfile
COPY tck/ ./
COPY --from=sdk-builder /sdk-package/*.tgz /tmp/hiero-sdk.tgz
RUN npm pkg delete "dependencies.@hiero-ledger/sdk" \
    && npm install \
    && npm install /tmp/hiero-sdk.tgz
```

Copying `tck/` *after* the install puts the original `package.json` back and restores the
published dependency in the manifest. `npm ci` cannot be used at all here, because deleting the
dependency puts `package.json` and `package-lock.json` out of agreement.

**Assert which SDK got installed.** Nothing fails loudly if the local tarball is not picked up -
the suite just quietly tests the published package. One line in the build turns that into a
build failure:

```dockerfile
RUN node -e "console.log(require.resolve('@hiero-ledger/sdk'))"
```

Checking the resolved version against the root `package.json` version is the real
confirmation: the reference build reported `2.88.0`, the version in the checkout, rather than
the `2.84.0` pinned by `tck/package.json`.

**The port is `argv[2]`, and Express binds every interface.** `tck/server.ts` defaults to 8544
and takes an override as its first script argument, so the entrypoint maps `TCK_PORT` onto it.
Unlike the C++ image, this one works behind a published port as well as under `--network host`.
