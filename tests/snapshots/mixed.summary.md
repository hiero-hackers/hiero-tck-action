### Hiero TCK Results

| Total | Passed | Failed | Pending | Hook failures | Skipped | Duration |
| ----: | -----: | -----: | ------: | ------------: | ------: | -------: |
| 3 | 1 | 2 | 0 | 0 | 0 | 0m 4s |

> [!WARNING]
> 1 of 2 failures are server or network errors rather than SDK
> incompatibilities. Genuine test failures: **1**.

**Failures by cause**

| Count | Cause | Kind |
| ----: | ----- | ---- |
| 1 | `Internal error: server unhealthy` | server |
| 1 | `expected 1 to equal 2` | test |

<details><summary>Failing tests (2)</summary>

##### server - Internal error: server unhealthy (1)

- updates account

##### test - expected 1 to equal 2 (1)

- creates account

</details>
