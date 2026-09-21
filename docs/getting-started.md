# Getting Started

This guide shows how to run the [Hiero SDK Technology Compatibility Kit (TCK)](https://github.com/hiero-ledger/hiero-sdk-tck) using the **Hiero TCK Action** in GitHub Actions.

---

## Prerequisites

Before using the action, make sure:

* Docker is available on the GitHub Actions runner.
* Your SDK provides a JSON-RPC server compatible with the TCK.
* The workflow has access to any credentials required by the TCK.

---

## Quick Start

The simplest way to run the TCK is to use one of the SDK presets supported by the action.

For example:

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

The action will:

1. Build the JSON-RPC server using the selected SDK preset.
2. Start the server.
3. Wait for the server to become ready.
4. Run the TCK.
5. Collect and report the test results.
6. Upload the Mochawesome report.

!!! tip

    Use an SDK preset when your repository follows one of the layouts supported by the action.


---

## Run the TCK Without an SDK Preset

If your SDK does not have a bundled preset, the action can build the JSON-RPC server using a `Dockerfile` in the project root.

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
```

By default, the action looks for the `Dockerfile` in the workspace root.

If your Dockerfile is located elsewhere, specify its path using `dockerfilePath`:

```yaml
with:
  dockerfilePath: path/to/Dockerfile
```

!!! note
    
    The Dockerfile must build a JSON-RPC server that is compatible with the TCK.


For more information about Docker and server configuration, see [Configure the Server](configure-server.md).

---

## Pin the TCK Version

The action uses a default TCK version, but you can specify the version explicitly using `tckTag`.

```yaml
with:
  sdk: python
  tckTag: v0.12.4
```

You can also pin the TCK to a specific commit:

```yaml
with:
  sdk: python
  tckTag: <commit-sha>
```

Pinning the TCK version makes the workflow reproducible and prevents changes to the TCK from unexpectedly affecting your CI results.

For more information, see [Configure TCK Tests](configure-tests.md).

---

## Configure the Operator Key

The action uses the default Solo admin key unless `operatorPrivateKey` is provided.

To use a different operator key, store it as a GitHub Actions secret:

```yaml
with:
  sdk: python
  operatorPrivateKey: ${{ secrets.TCK_OPERATOR_PRIVATE_KEY }}
```

For example:

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
          operatorPrivateKey: ${{ secrets.TCK_OPERATOR_PRIVATE_KEY }}
```

!!! warning
    
    Never commit a private key directly to the repository. Store sensitive credentials in GitHub Actions secrets.

For additional operator and network configuration, see [Configure the Network](configure-network.md).

---

## Run Selected Tests

By default, the action runs the complete TCK suite.

Use `testMatrix` to run a specific group of tests:

```yaml
with:
  sdk: python
  testMatrix: "src/tests/token-service/*.ts"
```

You can also run a specific test file:

```yaml
with:
  sdk: python
  testMatrix: "src/tests/crypto-service/test-account-create-transaction.ts"
```

Or combine a test path with a Mocha filter:

```yaml
with:
  sdk: python
  testMatrix: "src/tests/crypto-service/*.ts --grep 'Creates an account'"
```

For more information about test selection and test sharding, see [Configure TCK Tests](configure-tests.md).

---

## Run Against an Existing Server

The action can also run against a JSON-RPC server that is managed by your workflow.

Set `startServer` to `false` to prevent the action from building and starting its own server:

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
          ./start-server.sh &

      - name: Run Hiero TCK
        uses: hiero-hackers/hiero-tck-action@main
        with:
          startServer: false
```

When `startServer` is `false`, the action:

* Does not build a Docker image.
* Does not start a server container.
* Waits for the configured JSON-RPC server to become ready.
* Runs the TCK against the running server.

Your workflow is responsible for starting and stopping the server.

!!! warning
    
    Make sure the server is running and accessible on the configured `rpcServerPort` before the action attempts to run the TCK.


For more information, see [Configure the Server](configure-server.md).

---

## Use Docker Buildx

If your SDK has a long Docker build, you can use Docker Buildx caching to speed up subsequent workflow runs.

```yaml
steps:
  - name: Checkout SDK
    uses: actions/checkout@v7
  
  - name: Start Hiero Solo
    uses: hiero-ledger/hiero-solo-action@v0.24.0
    with:
      installMirrorNode: true

  - name: Set up Docker Buildx
    uses: docker/setup-buildx-action@v3

  - name: Run Hiero TCK
    uses: hiero-hackers/hiero-tck-action@main
    with:
      sdk: python
      dockerBuildArgs: >-
        --load
        --cache-from type=gha
        --cache-to type=gha,mode=max
```

The `--load` option loads the built image into the local Docker image store so that it can be used by the action.

!!! tip
    
    Docker Buildx caching is optional. Start with the basic workflow first and add caching if Docker build time becomes a significant part of your CI.


For more information, see [Configure the Server](configure-server.md).

---

## View Test Results

The action uploads the Mochawesome report as a GitHub Actions artifact by default.

You can customize the artifact name:

```yaml
with:
  uploadReport: "true"
  artifactName: tck-report
```

The action also exposes the TCK results as GitHub Actions outputs.

For example:

```yaml
- name: Run Hiero TCK
  id: tck
  uses: hiero-hackers/hiero-tck-action@main

- name: Print Results
  run: |
    echo "Total: ${{ steps.tck.outputs.total }}"
    echo "Passed: ${{ steps.tck.outputs.passed }}"
    echo "Failed: ${{ steps.tck.outputs.failed }}"
    echo "Pending: ${{ steps.tck.outputs.pending }}"
```

For the complete list of reports and outputs, see [Reports and Outputs](reports.md).
