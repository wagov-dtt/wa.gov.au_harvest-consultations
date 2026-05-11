# Audit Issues

> Generated with [oy-cli](https://github.com/wagov-dtt/oy-cli): `OY_MODEL=opencode-go/deepseek-v4-pro oy audit` · 2026-05-11

## Summary

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | High | `db.table` is rendered into SQL | **Accepted** — Helm values are trusted operator input |
| 2 | High | Missing DB credentials Secret | **Resolved** — `chart/templates/secret.yaml` renders `db-credentials` |
| 3 | Medium | Development default credentials | **Documented** — override `db.user`/`db.password` for production |

## 1. SQL injection via `db.table` (High, accepted)

**Trust boundary:** Helm values passed by the installer.
**Sink:** `chart/harvest.sql`, rendered through `tpl` in `chart/templates/configmap.yaml`.

```sql
CREATE OR REPLACE TABLE mysqldb.{{ .Values.db.table }} AS
SELECT * FROM consultations_final;
```

A malicious table value can inject SQL. This risk is accepted because chart
installers and CI inputs that control Helm values are trusted within the same
deployment boundary; that access is already sufficient to modify cluster
workloads. Operators must pass a simple trusted table identifier such as
`consultations`.

## 2. DB credentials Secret (High, resolved)

`chart/templates/secret.yaml` renders the `db-credentials` Secret consumed by
the MariaDB StatefulSet and harvest CronJob.

Verify with:

```bash
helm template harvest chart | grep -A8 'name: db-credentials'
```

## 3. Development default credentials (Medium, documented)

The bundled local/dev MariaDB defaults use `harvest` for
`mariadb.rootPassword`, `db.user`, and `db.password`. With
`networkPolicy.enabled=false`, any pod in the cluster can reach that database if
the defaults are used.

Production guidance:

- Set `mariadb.enabled=false` and use an externally managed database.
- Override `db.user` and `db.password`.
- Consider enabling `networkPolicy.enabled=true` when your CNI enforces it.
