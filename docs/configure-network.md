# Configure the Network

The **Hiero TCK Action** requires connection details for the Hiero network under test.

By default, the action is configured for a [Solo](https://github.com/hiero-ledger/solo) network set up using the [Hiero Solo Action](https://github.com/hiero-ledger/hiero-solo-action).

!!! note

    If you use the Hiero TCK Action with its default network configuration, you must set up and start a Solo network before running the TCK. The default connection details are configured to connect to the local Solo network.
    
    If you are testing against a different Hiero network, configure the network inputs to match that network.


---

## Network Configuration

The following inputs configure the network used by the TCK:

| Input                   | Default                  | Description                                    |
| ----------------------- | ------------------------ | ---------------------------------------------- |
| `nodeIp`                | `127.0.0.1:35211`        | IP address and port of the consensus node      |
| `nodeAccountId`         | `0.0.3`                  | Account ID of the consensus node               |
| `operatorAccountId`     | `0.0.2`                  | Operator account ID used to sign transactions  |
| `operatorPrivateKey`    | See action default admin key       | Operator account private key                   |
| `mirrornodeGrpcUrl`     | `127.0.0.1:5600`         | Mirror Node gRPC address                       |
| `mirrornodeRestUrl`     | `http://127.0.0.1:38081` | Mirror Node REST API URL                       |
| `mirrornodeRestJavaUrl` | `http://127.0.0.1:8084`  | Java-based Mirror Node REST API URL            |
| `nodeTimeout`           | `30000`                  | Consensus node request timeout in milliseconds |

---

## Using the Default Solo Network

If you use the default configuration, first set up the Solo network using the [Hiero Solo Action](https://github.com/hiero-ledger/hiero-solo-action) with `installMirrorNode: true`.

For example:

```yaml
- name: Set up Solo
  uses: hiero-ledger/hiero-solo-action@0.24.0
  with:
    installMirrorNode: true


- name: Run Hiero TCK
  uses: hiero-hackers/hiero-tck-action@main
```

No network inputs are required when the Solo network is available at the default addresses.

The default configuration expects:

* Consensus node: `127.0.0.1:35211`
* Consensus node account: `0.0.3`
* Operator account: `0.0.2`
* Mirror Node gRPC: `127.0.0.1:5600`
* Mirror Node REST: `http://127.0.0.1:38081`
* Mirror Node Java REST: `http://127.0.0.1:8084`

---

## Configure the Consensus Node

Use `nodeIp` to configure the IP address and port of the consensus node:

```yaml
- name: Run Hiero TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    nodeIp: 127.0.0.1:35211
```

The default is:

```text
127.0.0.1:35211
```

Use this input when the consensus node is running at a different address or port.

---

## Configure the Node Account

Use `nodeAccountId` to specify the account ID associated with the consensus node:

```yaml
- name: Run Hiero TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    nodeAccountId: 0.0.3
```

The default is:

```text
0.0.3
```

---

## Configure the Operator Account

The TCK uses an operator account to sign transactions.

Configure the account ID with `operatorAccountId`:

```yaml
- name: Run Hiero TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    operatorAccountId: 0.0.2
```

The default is:

```text
0.0.2
```

---

## Configure the Operator Private Key

Use `operatorPrivateKey` to provide the private key for the operator account:

```yaml
- name: Run Hiero TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    operatorPrivateKey: ${{ secrets.TCK_OPERATOR_PRIVATE_KEY }}
```

The action masks the operator private key in GitHub Actions logs.

!!! warning
    
    Do not commit or pass a real private key directly in a workflow file. Store sensitive keys in GitHub Actions secrets.


---

## Configure Mirror Node Endpoints

The TCK uses Mirror Node services for operations that require Mirror Node access.

### Mirror Node gRPC

Configure the Mirror Node gRPC service with `mirrornodeGrpcUrl`:

```yaml
- name: Run Hiero TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    mirrornodeGrpcUrl: 127.0.0.1:5600
```

The default is:

```text
127.0.0.1:5600
```

### Mirror Node REST

Configure the Mirror Node REST API with `mirrornodeRestUrl`:

```yaml
- name: Run Hiero TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    mirrornodeRestUrl: http://127.0.0.1:38081
```

The default is:

```text
http://127.0.0.1:38081
```

### Mirror Node Java REST

Configure the Java-based Mirror Node REST API with `mirrornodeRestJavaUrl`:

```yaml
- name: Run Hiero TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    mirrornodeRestJavaUrl: http://127.0.0.1:8084
```

The default is:

```text
http://127.0.0.1:8084
```

---

## Configure the Node Timeout

Use `nodeTimeout` to control the consensus node request timeout in milliseconds.

```yaml
- name: Run Hiero TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    nodeTimeout: 30000
```

The default is:

```text
30000
```

For example, to use a 60-second timeout:

```yaml
- name: Run Hiero TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    nodeTimeout: 60000
```

---

## Complete Network Configuration

The network inputs can be configured together:

```yaml
- name: Run Hiero TCK
  uses: hiero-hackers/hiero-tck-action@main
  with:
    nodeIp: 127.0.0.1:35211
    nodeAccountId: 0.0.3
    operatorAccountId: 0.0.2
    operatorPrivateKey: ${{ secrets.TCK_OPERATOR_PRIVATE_KEY }}
    mirrornodeGrpcUrl: 127.0.0.1:5600
    mirrornodeRestUrl: http://127.0.0.1:38081
    mirrornodeRestJavaUrl: http://127.0.0.1:8084
    nodeTimeout: 30000
```

You only need to specify values that differ from the defaults.

If the network is not the default Solo setup, make sure all network inputs point to the corresponding services of the network under test.
