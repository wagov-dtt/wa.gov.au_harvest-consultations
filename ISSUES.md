# Audit Issues

> Generated with [oy-cli](https://github.com/wagov-dtt/oy-cli): `OY_MODEL=opencode-go/deepseek-v4-pro oy audit` · 2026-05-09

## Findings summary
| # | Severity | Title | Evidence (file:line) |
|---|----------|-------|----------------------|
| 1 | High | Hardcoded database credentials in Kubernetes manifests | `deploy/kustomize/mariadb-statefulset.yaml:26`; `deploy/kustomize/harvest-cronjob-patch.yaml:7-8` |
| 2 | Medium | Database password exposed via command-line arguments | `deploy/kustomize/mariadb-statefulset.yaml:32` (readiness probe); `justfile:79` (mariadb-dump); `justfile:33` (mariadb-admin) |
| 3 | Medium | Application uses MySQL root account (least privilege violation) | `deploy/kustomize/harvest-cronjob-patch.yaml:7` (MYSQL_USER=root) |
| 4 | Medium | MariaDB StatefulSet lacks persistent storage – data loss on pod restart | `deploy/kustomize/mariadb-statefulset.yaml` (no volumeClaimTemplates) |
| 5 | Low | CronJob missing `concurrencyPolicy` – overlapping runs possible | `deploy/kustomize/harvest-cronjob.yaml:7-8` (spec.schedule, no concurrencyPolicy) |
| 6 | Low | Duplicated configuration values increase maintenance risk | `justfile:39,60` (mysqlHost repeated); patches vs. justfile vs. helm values |

## Detailed findings

### 1. Hardcoded database credentials in plaintext Kubernetes manifests
**Category:** Credential Storage / Configuration Security  
**Reference:** OWASP ASVS V2.10.4 (Secrets not in code/config), V6.1.1 (Credential storage)  
**Trust boundary:** Repository & Kubernetes API – anyone with read access obtains database credentials.  

**Evidence:**
- `deploy/kustomize/mariadb-statefulset.yaml:26`  
  ```yaml
  - name: MARIADB_ROOT_PASSWORD
    value: harvest
  ```
- `deploy/kustomize/harvest-cronjob-patch.yaml:7-8`  
  ```yaml
  - name: MYSQL_PWD
    value: harvest
  ```

The same password (`harvest`) is used for the MariaDB root user and the application’s MySQL connection. Both are defined as literal `value` strings in pod environment variables. These manifests are part of the Kustomize base; the justfile generates a Helm chart from them and offers install instructions (`justfile:helm-install`). As written, the password is stored in the VCS and appears in the Kubernetes API objects (ConfigMap/Pod spec).

**Impact:** An attacker with access to the repository, the Kubernetes cluster (e.g., `kubectl describe`), or the etcd database can retrieve the password. The root account can then be used to read, modify, or delete all database content, potentially pivot to other systems if the database is exposed.

**Exploitability:** High – the value is directly readable in the manifest and in the deployed pod specification. No special privilege is required.

**Fix:**
- Use Kubernetes `Secret` objects and reference them via `secretKeyRef` instead of plain `value`.
- Generate unique passwords at install time (e.g., via Helm chart templates or kustomize `secretGenerator`).
- For local development, at minimum use `.env` files excluded from VCS.

### 2. Database password exposed through command-line arguments
**Category:** Information Exposure / Logging & Monitoring  
**Reference:** OWASP ASVS V6.2.7 (Passwords not passed on command line), V7.1.2 (No sensitive data in process args)  

**Evidence:**
- `deploy/kustomize/mariadb-statefulset.yaml:32` (readiness probe)  
  ```yaml
  command: ["mariadb-admin", "-uroot", "-pharvest", "-h", "127.0.0.1", "ping"]
  ```
- `justfile:33` (port-forward / exec) – indirectly passes `-pharvest` in `kubectl exec`.  
- `justfile:79` (ci-test dump)  
  ```bash
  kubectl exec -n {{ns}} "$POD" -- \
    mariadb-dump -uroot -pharvest harvest consultations \
  ```
- `justfile:39,60` (helm-install and ci-test) pass `mysqlHost` but not `mysqlPwd`; however the password defaults to the value from the patch, which is embedded in the chart.

**Impact:** Any user or process with the ability to list running processes (`ps aux`, `/proc`) inside the container or on the CI runner can capture the cleartext password. This includes CI logs if `set -x` is ever enabled or the command is echoed.

**Exploitability:** Medium – requires local access to the node/container or CI environment. In shared CI runners, other jobs might capture process arguments.

**Fix:**
- Readiness probe: use `MYSQL_PWD` environment variable instead of `-p`, or use a MySQL option file.
- `justfile` dump: pass credentials via environment variable (`MYSQL_PWD`) or a `--defaults-file` mounted in the container; avoid `-p` on the command line.
- For the CI test, reuse the environment variables set in the job instead of hard-coding.

### 3. Application uses MySQL root account (least privilege violation)
**Category:** Access Control / Least Privilege  
**Reference:** OWASP ASVS V4.1.2 (Principle of least privilege)  

**Evidence:**  
`deploy/kustomize/harvest-cronjob-patch.yaml:7`  
```yaml
- name: MYSQL_USER
  value: root
```

The harvest job connects as MariaDB `root` with full administrative privileges, yet its only required operation is `CREATE OR REPLACE TABLE` within the `harvest` database.

**Impact:** Compromise of the harvest job credentials (already exposed via plaintext) grants complete control over the database server, including system configuration, user management, and access to other databases. A limited account would contain the blast radius.

**Exploitability:** High if the password is obtained; the root account can execute arbitrary commands (e.g., `LOAD DATA INFILE`, `system` commands via UDFs).

**Fix:**
- Create a dedicated database user with `SELECT, INSERT, UPDATE, DELETE, DROP, CREATE` privileges only on the `harvest` database.
- Update the CronJob env to use that user and a unique password.

### 4. Ephemeral MariaDB – no persistent volume (operational data loss)
**Category:** Data Protection / Resilience  
**Reference:** OWASP ASVS V8.1.4 (Data backup / retention)  

**Evidence:**  
The file `deploy/kustomize/mariadb-statefulset.yaml` defines a StatefulSet but contains **no** `volumeClaimTemplates` and no volume mounts for a persistent disk. The container’s data directory lives inside the ephemeral container filesystem.

**Impact:** Any pod restart (upgrade, node failure, manual reschedule) wipes the entire MySQL dataset. While the CronJob repopulates the `consultations` table hourly, any data accumulated between runs (e.g., if the job were extended to do incremental updates) or additional tables would be lost. If this chart is deployed to production without awareness, it leads to silent data loss and potential unavailability of the harvested data during the gap.

**Exploitability:** Almost certain on any pod reschedule; no exploit needed.

**Fix:**
- Add a `volumeClaimTemplates` section to the StatefulSet spec to request a persistent volume.
- For local dev, document that the lack of persistence is intentional and warn against production use.
- Alternatively, provide a production overlay with persistent storage.

### 5. Missing CronJob concurrency policy – risk of overlapping jobs
**Category:** Resource Management / Safety  
**Reference:** **OWASP ASVS V11.1.1** (Business logic – race conditions)  

**Evidence:**  
`deploy/kustomize/harvest-cronjob.yaml:7-13`  
```yaml
spec:
  schedule: "@hourly"
  jobTemplate:
    spec:
      ...
```
The manifest sets `schedule` but does not set `concurrencyPolicy` (defaults to `Allow`).

**Impact:** If a harvest job runs longer than one hour (network delay, large upstream dataset, database contention), the next scheduled job starts concurrently. Two DuckDB instances may both attempt to `ATTACH` to MariaDB, create/replace the same table simultaneously, leading to lock contention, partial data, or failed jobs. This can cause missed data windows or resource exhaustion.

**Exploitability:** Low likelihood but increases with data size and network latency. In a production setting, it can degrade reliability.

**Fix:**
- Set `concurrencyPolicy: Forbid` (or `Replace` if you prefer to abort a long-running job) in the CronJob spec.

### 6. Configuration duplication across justfile, kustomize patches, and helm values
**Category:** Maintainability / Complexity  
**Reference:** grugbrain “local reasoning” – duplicated values hide the true source of truth.  

**Evidence:**
- The MySQL hostname is set in `harvest-cronjob-patch.yaml` (`mariadb`), in the justfile’s `helm-install` recipe (`justfile:39`: `harvest-harvest-consultations-mariadb`), and in `ci-test` (`justfile:60`).
- The password is duplicated in the StatefulSet env, CronJob patch, and implicitly in CI commands.
- Changing the database name or credentials requires touching 3+ files, risking inconsistency.

**Impact:** Incorrect or missed updates can break the pipeline in subtle ways (job points to wrong host, wrong password). This increases the chance of a security misconfiguration (e.g., a test environment using production-like credentials) and complicates auditing.

**Fix:**
- Centralize shared values in a single kustomize component or Helm values file that is referenced by all targets.
- In the justfile, derive the hostname dynamically (e.g., from the namespace and release name) rather than hard-coding.
- Template the CI test to reuse the same values used for deployment.

## Resolutions (2026-05-09)

### 1. Hardcoded credentials → kustomize secretGenerator
Credentials are now generated via kustomize `secretGenerator` and referenced via `secretKeyRef` in both the StatefulSet and CronJob patch. The `Secret` resource is deployed as a proper Kubernetes Secret (base64-encoded). Default credentials (`harvest` / `harvest`) for local dev convenience are no longer plaintext in pod specs. Production deployments should override via kustomize overlays or `--set` on the Helm chart.

### 2. Command-line password exposure → env vars
- **Readiness probe** in `mariadb-statefulset.yaml`: removed `-pharvest` flag; uses `MYSQL_PWD` environment variable (set from Secret) instead.
- **justfile ci-test dump**: changed from `mariadb-dump -pharvest` to `sh -c 'mariadb-dump ...'` which inherits the container's `MYSQL_PWD` env var.

### 3. Least privilege → dedicated user
MariaDB StatefulSet now sets `MARIADB_USER=harvest` and `MARIADB_PASSWORD=harvest` (from Secret). The MariaDB image automatically creates this user with privileges restricted to the `harvest` database. The CronJob uses this user instead of `root`.

### 4. Ephemeral storage → volumeClaimTemplates
Added `volumeClaimTemplates` to the StatefulSet requesting a 1Gi persistent volume. For local dev with kind, the default storage class provisions a hostPath volume. Users can scale up or replace with a cloud storage class for production. PVC cleanup: `kubectl delete pvc -n harvest-consultations --all` or `just clean`.

### 5. Overlapping CronJob runs → concurrencyPolicy
Set `concurrencyPolicy: Forbid` on the CronJob to prevent overlapping harvest runs.

### 6. Configuration duplication → centralised variable
Added `helmHost` variable in `justfile` so the Helm hostname is defined once and reused in `helm-install` and `ci-test` recipes. All other configuration values (credentials, db name) are now sourced from the kustomize `secretGenerator`/ConfigMap rather than duplicated across files.
