# DuckDB SQL Pipeline for Harvesting Consultations

A single SQL file. Zero dependencies beyond DuckDB.

```bash
duckdb -c ".read deploy/kustomize/harvest.sql"
```

MySQL connection via standard [environment variables](https://duckdb.org/docs/current/core_extensions/mysql#configuration):

```bash
export MYSQL_HOST=localhost MYSQL_USER=root MYSQL_PWD=secret MYSQL_DATABASE=harvest
duckdb -c ".read deploy/kustomize/harvest.sql"
```

## Kubernetes

### Local dev (kind + kustomize)

```bash
just kind-up       # Start kind + MariaDB, deploy CronJob
just test          # Trigger a one-off job
```

### Helm chart

Generated from kustomize, not committed:

```bash
just helm-install  # Generate chart + install/upgrade
```

Override values:

```bash
just helm-install
helm upgrade --install harvest deploy/helm/harvest-consultations \
  --namespace harvest-consultations --create-namespace \
  --set harvestCronjob.harvest.env.mysqlHost=external-db \
  --set harvestCronjob.harvest.env.mysqlPwd=secret \
  --set harvestCronjob.schedule="@daily"
```

### CI test

```bash
just ci-test       # Full end-to-end: kind → helm → job → dump → validate
```

## Files

| Path | Purpose |
|------|---------|
| `deploy/kustomize/harvest.sql` | The entire pipeline |
| `deploy/kustomize/` | Kustomize base (kind) |
| `justfile` | Dev commands |
