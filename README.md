# DuckDB SQL Pipeline for Harvesting Consultations

A single SQL file. Zero dependencies beyond DuckDB.

```bash
duckdb -c ".read harvest.sql"
```

## Architecture

```
harvest.sql (single file)
  ├─ Portal config (VALUES clause)
  ├─ read_json(url) ──→ CitizenSpace API
  ├─ read_text + regex → extract token → read_json(headers) ──→ EngagementHQ API
  ├─ Transform (CTEs → common schema)
  ├─ UNION ALL + filter → consultations
  └─ MySQL (ATTACH + CREATE TABLE)
```

MySQL connection is via standard [environment variables](https://duckdb.org/docs/current/core_extensions/mysql#configuration):

```bash
export MYSQL_HOST=localhost MYSQL_USER=root MYSQL_PWD=secret MYSQL_DATABASE=harvest
duckdb -c ".read harvest.sql"
```

## Kubernetes

### Local dev (kind + kustomize)

```bash
just kind-up       # Start kind + MariaDB, deploy CronJob
just test          # Trigger a one-off job
```

### Helm chart

The chart is generated from kustomize, not committed:

```bash
just helm-install  # Generate chart + install/upgrade
just helm-package  # Generate chart + package to dist/
```

Override values:

```bash
just helm-install
helm upgrade --install harvest deploy/helm/harvest-consultations \
  --namespace harvest-consultations --create-namespace \
  --set mysql.host=external-db --set mysql.password=secret --set schedule="@daily"
```

## Files

| Path | Purpose |
|------|---------|
| `harvest.sql` | The entire pipeline |
| `justfile` | Dev commands |
| `deploy/kustomize/` | Kustomize base (kind) |
