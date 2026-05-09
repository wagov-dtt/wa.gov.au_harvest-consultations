# Audit Issues

> Generated during chart review · 2026-05-09 · updated post-fix

## Findings summary

| # | Severity | Title | Status |
|---|----------|-------|--------|
| 1 | Medium | CronJob containers have no resource limits or requests | Fixed |
| 2 | Medium | StatefulSet and CronJob containers lacked security contexts | Fixed |
| 3 | Low | MySQL connection over plaintext (no TLS) | Accepted |
| 4 | Low | Unsafe ETag checks disabled globally | Accepted |
| 5 | Low | No schema validation on ingested data | Accepted |
| 6 | Low | `justfile` port-forward exposes database to localhost | Accepted |
| 7 | Informational | Container images not pinned by digest | Accepted |

## Resolved findings

### 1. CronJob lacked resource limits (Medium) — Fixed

**Was:** `chart/templates/cronjob.yaml` had no `resources` block. DuckDB can consume
significant memory when processing large JSON datasets (configured with
`maximum_object_size = 100000000`).

**Fix:** Added `harvest.resources` to `values.yaml` and templated them in the CronJob
container spec:

```yaml
harvest:
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "1Gi"
      cpu: "1"
```

### 2. Containers lacked security contexts (Medium) — Fixed

**Was:** Neither the MariaDB StatefulSet nor the harvest CronJob container specified a
`securityContext`. Without capability dropping, a compromised container gains more
kernel privileges than necessary.

**Fix:** Added `securityContext` with `capabilities.drop: ["ALL"]` to both containers.
The harvest CronJob additionally sets `readOnlyRootFilesystem: true` with an
`emptyDir` volume mounted at `/root/.duckdb` (the `duckdb/duckdb` image runs as root)
so DuckDB can install extensions (httpfs, mysql) at runtime despite the read-only
root filesystem. MariaDB cannot use
readOnlyRootFilesystem because it writes to its data volume.

### 3. Root password no longer exposed to application — Fixed

**Was:** `MYSQL_PWD` was set to `MARIADB_ROOT_PASSWORD` in the StatefulSet, exposing
the root credential to every process in the container. The readiness probe and CI dump
both used `-uroot`.

**Fix:**
- Removed `MYSQL_PWD` from the StatefulSet entirely.
- Readiness probe now uses `mariadb-admin -u$(MARIADB_USER) -p$(MARIADB_PASSWORD)`.
- CI dump (`justfile`) now uses `mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD"`.
- The harvest CronJob already used `MYSQL_USER`/`MYSQL_PWD` (app credentials), not root.
- `MARIADB_ROOT_PASSWORD` is kept only because the MariaDB image requires it for
  initialization; it is never read by application or healthcheck code paths.

### 4. DuckDB extensions writable mount — Fixed

**Was:** The CronJob had `readOnlyRootFilesystem: true` but DuckDB needs to install
`httpfs` and `mysql` extensions at runtime into `~/.duckdb/extensions/`. The
`duckdb/duckdb` image runs as root so `HOME` is `/root`.

**Fix:** Added an `emptyDir` volume mounted at `/root/.duckdb` in the CronJob
container spec. This gives DuckDB a writable location for extension downloads while
keeping the root filesystem read-only.

## Accepted risks

### 5. MySQL connection uses plaintext (no TLS) (Low)

`chart/harvest.sql` — `ATTACH '' AS mysqldb (TYPE mysql)` connects without TLS.
Traffic between the harvest CronJob pod and MariaDB is unencrypted within the cluster.

**Accepted:** This is an internal cluster communication path on a private CNI network.
TLS would add certificate management complexity for a single-namespace CronJob.
Production deployments using an external database should configure TLS at the MySQL
server and set appropriate DuckDB MySQL extension parameters.

### 6. Unsafe ETag checks disabled globally (Low)

`chart/harvest.sql` — `SET unsafe_disable_etag_checks = true` disables DuckDB's
ETag-based HTTP cache consistency for the entire session.

**Accepted:** EngagementHQ portal homepages are dynamically generated HTML that changes
ETag on every request. Without this setting, DuckDB errors when reading the same URL
twice in one session. The harvest pipeline runs as a short-lived batch job (not a
persistent server), so cache staleness is bounded to a single run. Each CronJob
invocation starts a fresh DuckDB process.

### 7. No schema validation on ingested data (Low)

The pipeline consumes JSON from external APIs and uses only `CAST`/`TRY_CAST` for type
coercion. Required fields are not enforced, and there are no string length or format
constraints.

**Accepted:** The data sources are trusted WA government APIs. The pipeline already
filters on `status IN ('open', 'closed')`. Adding CHECK constraints would cause the
entire job to fail on malformed upstream data rather than surfacing the issue.
Downstream consumers should apply their own validation.

### 8. `justfile` port-forward exposes database to localhost (Low)

`justfile` — `mariadb-svc` runs `kubectl port-forward service/mariadb 3306:3306`
binding to localhost. If the operator uses default credentials, the database is
accessible to any local process.

**Accepted:** This is a development convenience recipe behind `just mariadb-svc`.
It is not used by CI or production workflows. Developers should be aware that
port-forward bypasses Kubernetes network policies.

### 9. Container images not pinned by digest (Informational)

`chart/values.yaml` uses mutable tags (`mariadb:11`, `duckdb/duckdb:1.5.2`) rather
than digest references.

**Accepted:** Digest pinning adds maintenance burden (regular digest updates) for a
small internal tool. The risk of a compromised upstream image under a stable tag is
low for official Docker Hub images. Teams requiring stricter supply-chain security
can override `image.repository` and `image.tag` at install time with digest references.

## Not a finding

### Secret template exists and is wired correctly

The audit tool flagged that `mariadb-credentials` was missing from the chart and that
the values were unused. This was incorrect:

- `chart/templates/secret.yaml` creates `mariadb-credentials` from
  `.Values.mariadb.rootPassword`, `.Values.mariadb.user`, and `.Values.mariadb.password`.
- `chart/templates/statefulset.yaml` and `chart/templates/cronjob.yaml` reference
  `mariadb-credentials` via `secretKeyRef`.
- `values.yaml` defaults (`harvest` / `harvest`) propagate through to the generated
  Secret correctly.

### CI dump persistence

`dist/` is listed in `.gitignore` (line 19). The CI dump at
`dist/consultations.sql.gz` is excluded from version control.
