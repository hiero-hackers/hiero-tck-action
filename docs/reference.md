# Inputs Reference

The **Hiero TCK Action** provides inputs for configuring the server under test, network connection, TCK test execution, and report generation.

## Server Under Test

| Input                  | Default | Description                                                                                                                                |
| ---------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `startServer`          | `true`  | Whether the action builds and starts the JSON-RPC server. Set to `false` when the workflow starts the server separately.                   |
| `sdk`                  | `""`    | Bundled SDK server preset. The SDK source must be available in the workspace. Mutually exclusive with `dockerfilePath`.                    |
| `dockerfilePath`       | `""`    | Path to a custom Dockerfile, resolved relative to the workspace. Used when `startServer` is `true`.                                        |
| `rpcServerPort`        | `""`    | Port of the target JSON-RPC server. Uses the SDK preset default when available, otherwise `8544`.                                          |
| `serverEnv`            | `""`    | Environment variables passed to the server container, one `KEY=VALUE` per line.                                                            |
| `serverStartupTimeout` | `120`   | Number of seconds to wait for the JSON-RPC server to become ready.                                                                         |
| `buildContext`         | `""`    | Docker build context. Defaults to the GitHub workspace root.                                                                               |
| `dockerBuildArgs`      | `""`    | Additional arguments passed to `docker build`. Supports options such as `--build-arg`, `--platform`, `--target`, and Buildx cache options. |

See [Configure the Server](configure-server.md) for details about configuring the server.

---

## Network Under Test

| Input                   | Default                  | Description                                     |
| ----------------------- | ------------------------ | ----------------------------------------------- |
| `nodeIp`                | `127.0.0.1:35211`        | IP address and port of the consensus node.      |
| `nodeAccountId`         | `0.0.3`                  | Account ID of the consensus node.               |
| `operatorAccountId`     | `0.0.2`                  | Operator account ID used to sign transactions.  |
| `operatorPrivateKey`    | Action default admin key           | Private key of the operator account.            |
| `mirrornodeGrpcUrl`     | `127.0.0.1:5600`         | Mirror Node gRPC service address.               |
| `mirrornodeRestUrl`     | `http://127.0.0.1:38081` | Mirror Node REST API URL.                       |
| `mirrornodeRestJavaUrl` | `http://127.0.0.1:8084`  | Java-based Mirror Node REST API URL.            |
| `nodeTimeout`           | `30000`                  | Consensus node request timeout in milliseconds. |

See [Configure the Network](configure-network.md) for details about configuring the network.

---

## TCK Test Execution

| Input        | Default   | Description                                                                                                                                    |
| ------------ | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `tckTag`     | `v0.12.4` | Tag or commit SHA of `hiero-sdk-tck` to use.                                                                                                   |
| `testMatrix` | `""`      | Test files or globs to run. When set, runs only the specified tests using the TCK `test:file` script.                                          |
| `testScript` | `test:ci` | npm script used for a whole-suite run when `testMatrix` is empty. Falls back to `test` if the selected TCK version does not provide `test:ci`. |

See [Configure TCK Tests](configure-tests.md) for details about configuring TCK tests.

---

## Reporting

| Input          | Default      | Description                                                                    |
| -------------- | ------------ | ------------------------------------------------------------------------------ |
| `uploadReport` | `true`       | Whether to upload the generated Mochawesome TCK report as a workflow artifact. |
| `artifactName` | `tck-report` | Name of the uploaded TCK report artifact.                                      |

See [Reports and Output](reports.md) for details about reporting.

---

## Outputs

The action also exposes test results as outputs.

| Output                 | Description                                                                               |
| ---------------------- | ----------------------------------------------------------------------------------------- |
| `total`                | Total number of TCK tests executed.                                                       |
| `passed`               | Number of passing TCK tests.                                                              |
| `failed`               | Number of failing TCK tests.                                                              |
| `pending`              | Number of pending TCK tests.                                                              |
| `hookFailures`         | Number of failed suite hooks.                                                             |
| `skipped`              | Number of registered tests that never ran.                                                |
| `registered`           | Number of tests registered by the suite.                                                  |
| `genuineFailures`      | Failures classified as actual test failures.                                              |
| `infraFailures`        | Failures caused by server or network errors.                                              |
| `unimplementedMethods` | Comma-separated list of JSON-RPC methods not implemented by the server under test.        |
| `reportPath`           | Path to the generated Mochawesome report directory, or empty when no report was produced. |

---

## Examples

### Basic Action Usage

The following example checks out an SDK, starts a local Solo network with a Mirror Node, and runs the TCK against the Python SDK server.

```yaml
name: Hiero TCK

on:
  pull_request:

jobs:
  tck:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout SDK
        uses: actions/checkout@v7

      - name: Start Hiero Solo
        uses: hiero-ledger/hiero-solo-action@v0.24.0
        with:
          installMirrorNode: true

      - name: Run Hiero TCK
        uses: hiero-hackers/hiero-tck-action@main
        with:
          sdk: python
```

The TCK Action's default network configuration expects the local Solo network to be available at the default node and Mirror Node endpoints.

### Server Started Separately

If your workflow starts the JSON-RPC server separately, set `startServer` to `false`. In this mode, the TCK Action does not build or start a server and connects directly to the server already running on the configured `rpcServerPort`.

```yaml
name: Hiero TCK

on:
  pull_request:

jobs:
  tck:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout SDK
        uses: actions/checkout@v7

      - name: Start Hiero Solo
        uses: hiero-ledger/hiero-solo-action@v0.24.0
        with:
          installMirrorNode: true

      - name: Start JSON-RPC Server
        run: |
          # Start the SDK JSON-RPC server here in background
          ./start-server.sh

      - name: Run Hiero TCK
        uses: hiero-hackers/hiero-tck-action@main
        with:
          startServer: false
          sdk: python
          rpcServerPort: 8544
```

!!! note
    
    When `startServer` is `false`, the server must already be running and accessible on the configured `rpcServerPort` before the TCK tests start.



### Test Sharding

Use `testMatrix` to split the TCK suite across multiple GitHub Actions jobs.

For example:

```yaml
name: Hiero TCK

on:
  pull_request:

jobs:
  tck:
    strategy:
      fail-fast: false
      matrix:
        test:
          - "src/tests/crypto-service/*.ts"
          - "src/tests/token-service/*.ts"
          - "src/tests/file-service/*.ts"

    runs-on: ubuntu-latest

    steps:
      - name: Checkout SDK
        uses: actions/checkout@v7

      - name: Start Hiero Solo
        uses: hiero-ledger/hiero-solo-action@v0.24.0
        with:
          installMirrorNode: true

      - name: Run Hiero TCK
        uses: hiero-hackers/hiero-tck-action@main
        with:
          sdk: python
          testMatrix: ${{ matrix.test }}
          artifactName: tck-report-${{ strategy.job-index }}
```

Each matrix job runs only the tests specified by its `testMatrix` value.

### Test Sharding with a Filter

`testMatrix` can also include Mocha options such as `--grep`:

```yaml
name: Hiero TCK

on:
  pull_request:

jobs:
  tck:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout SDK
        uses: actions/checkout@v7

      - name: Start Hiero Solo
        uses: hiero-ledger/hiero-solo-action@v0.24.0
        with:
          installMirrorNode: true

      - name: Run Hiero TCK
        uses: hiero-hackers/hiero-tck-action@main
        with:
          sdk: python
          testMatrix: "src/tests/crypto-service/*.ts --grep 'Creates an account'"
```

### Custom Network

To run the TCK against a network other than the default local Solo configuration, override the network inputs:

```yaml
name: Hiero TCK

on:
  pull_request:

jobs:
  tck:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout SDK
        uses: actions/checkout@v7

      - name: Run Hiero TCK
        uses: hiero-hackers/hiero-tck-action@main
        with:
          sdk: python
          nodeIp: 10.0.0.10:35211
          nodeAccountId: 0.0.3
          operatorAccountId: 0.0.2
          operatorPrivateKey: ${{ secrets.TCK_OPERATOR_PRIVATE_KEY }}
          mirrornodeGrpcUrl: 10.0.0.10:5600
          mirrornodeRestUrl: http://10.0.0.10:38081
          mirrornodeRestJavaUrl: http://10.0.0.10:8084
```

Only specify inputs that differ from the defaults.
