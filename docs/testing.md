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
        uses: manishdait/hiero-tck-runner@main
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