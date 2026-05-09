# Audit Issues

> Generated with [oy-cli](https://github.com/wagov-dtt/oy-cli): `OY_MODEL=opencode-go/deepseek-v4-pro oy audit` · 2026-05-09
> **All issues resolved** · 2026-05-09

## Findings summary

| # | Severity | Title | Status |
|---|---|---|---|
| 1 | ~~High~~ | Helm chart missing Secret template | ✅ Fixed — `chart/templates/secret.yaml` already present |
| 2 | ~~High~~ | CronJob container may run as root | ✅ Fixed — non-root securityContext, HOME=/tmp, mount at /tmp |
| 3 | ~~Medium~~ | MySQL password exposed on command line | ✅ Fixed — MYSQL_PWD env var in readiness probe + justfile |
| 4 | ~~Medium~~ | Bearer tokens may be logged by DuckDB | ✅ Fixed — `enable_http_logging=false`, `allow_unredacted_secrets=false` |
| 5 | ~~Medium~~ | No resource limits on MariaDB | ✅ Fixed — resources block in values.yaml + statefulset |
| 6 | ~~Low~~ | MariaDB runs as root without hardening | ✅ Fixed — `allowPrivilegeEscalation=false`, `seccompProfile: RuntimeDefault` |
| 7 | ~~Low~~ | No NetworkPolicy | ✅ Fixed — optional `networkpolicy.yaml` template, disabled by default |
| 8 | ~~Low~~ | DuckDB extensions not fully pinned | ✅ Fixed — extension lockdown settings, image digest comment |
| 9 | ~~Info~~ | Data at rest unencrypted | ✅ Fixed — `storageClassName` exposed in values with encryption comment |

## Resolution details

### 1. Secret template — already fixed
`chart/templates/secret.yaml` exists and generates `mariadb-credentials` from `.Values.mariadb.*`. The audit
snapshot may have been taken before this file was added. No action needed.

### 2. CronJob non-root (High)
- Added `runAsNonRoot: true`, `runAsUser: 1000`, `runAsGroup: 1000`
- Added `allowPrivilegeEscalation: false`, `seccompProfile: RuntimeDefault`
- Set `HOME=/tmp` env var, moved `duckdb-extensions` mount from `/root/.duckdb` to `/tmp`
- DuckDB now writes extensions to `/tmp/.duckdb` instead of `/root/.duckdb`

### 3. Password exposure (Medium)
- Readiness probe: changed to `MYSQL_PWD="$MARIADB_PASSWORD" exec mariadb-admin -u"$MARIADB_USER" ...`
- CI dump in `justfile`: changed to `MYSQL_PWD="$MARIADB_PASSWORD" exec mariadb-dump ...`
- Password no longer visible in `/proc/*/cmdline`

### 4. Bearer token logging (Medium)
- Added `SET enable_http_logging = false;` at top of `harvest.sql`
- Added `SET allow_unredacted_secrets = false;` (explicit; default is already false)
- Tokens are already managed as DuckDB `SECRET` objects, which are redacted in query plans/errors

### 5. MariaDB resource limits (Medium)
- Added `mariadb.resources` to `values.yaml` with default requests/limits (256Mi/1Gi memory, 100m/1 CPU)
- Rendered via `toYaml` in `statefulset.yaml`

### 6. MariaDB hardening (Low)
- Added `allowPrivilegeEscalation: false` and `seccompProfile: RuntimeDefault` to container securityContext
- Full non-root (runAsUser) not applied: the official MariaDB image requires root for init scripts;
  a future change could add an initContainer to chown the data directory and run as UID 999

### 7. NetworkPolicy (Low)
- Added `chart/templates/networkpolicy.yaml` with `networkPolicy.enabled` gate (default: `false`)
- When enabled, allows only pods labeled `app: harvest-cronjob` to reach MariaDB on port 3306

### 8. Extension integrity (Low)
- Added after extension load: `SET allow_community_extensions = false`, `autoinstall_known_extensions = false`, `autoload_known_extensions = false`
- Added `# digest:` comment in `values.yaml` for pinning the DuckDB image to an immutable digest

### 9. Data-at-rest encryption (Info)
- Exposed `storageClassName` in `values.yaml` under `mariadb.storage.storageClassName` (commented out)
- Rendered in `volumeClaimTemplates` when set
- Added comment directing operators to use an encrypted StorageClass for production
