# DuckDB SQL Pipeline for Harvesting Consultations

A single SQL file that pulls consultation data from WA government Citizen Space APIs,
normalises it, and mirrors it into MariaDB for downstream consumption.

## Quick start

```bash
# Preview the pipeline locally (read-only, no database needed)
duckdb -c ".read deploy/kustomize/harvest.sql"
```

To mirror results into a local MariaDB, set the standard [DuckDB MySQL environment variables](https://duckdb.org/docs/current/core_extensions/mysql#configuration):

```bash
export MYSQL_HOST=localhost MYSQL_PWD=harvest MYSQL_DATABASE=harvest
duckdb -c ".read deploy/kustomize/harvest.sql"
```

> **Note:** The pipeline needs a dedicated MySQL user with write access to the `harvest` database. The default credentials in `kustomization.yaml` create user `harvest` with password `harvest`. Override both for production.

## Kubernetes

### Local dev (kind + kustomize)

```bash
just kind-up       # Start kind + MariaDB (1Gi PVC), deploy CronJob
just test          # Trigger a one-off harvest job
just clean         # Tear down cluster and delete PVCs
```

Credentials live in `deploy/kustomize/kustomization.yaml` as a `secretGenerator` (default password: `harvest`). Override with a kustomize overlay or `--set` for production.

### Helm chart

Generated from kustomize, not committed to VCS:

```bash
just helm-install  # Generate chart + install/upgrade
```

Override the host or schedule at install time:

```bash
helm upgrade --install harvest deploy/helm/harvest-consultations \
  --namespace harvest-consultations --create-namespace \
  --set harvestCronjob.harvest.env.mysqlHost=external-db \
  --set harvestCronjob.schedule="@daily"
```

For credential overrides, regenerate the chart (`just helm-generate`) with a kustomize overlay or edit the generated `values.yaml` directly.

### CI test

```bash
just ci-test       # Full end-to-end: kind → helm → job → dump → validate
```

## Files

| Path | Purpose |
|------|---------|
| `deploy/kustomize/harvest.sql` | SQL pipeline (DuckDB) |
| `deploy/kustomize/` | Kustomize base (kind) |
| `justfile` | Dev commands |
