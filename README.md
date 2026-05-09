# DuckDB SQL Pipeline for Harvesting Consultations

A single SQL file pulls consultation data from WA government Citizen Space and
EngagementHQ APIs, normalises it, and mirrors it into MariaDB for downstream consumption.
The runtime harvest path is DuckDB SQL only; Python is not required.

## Quick start

Set the standard [DuckDB MySQL environment variables](https://duckdb.org/docs/current/core_extensions/mysql#configuration) before running locally:

```bash
export MYSQL_HOST=localhost MYSQL_USER=harvest MYSQL_PWD=harvest MYSQL_DATABASE=harvest
duckdb -c ".read chart/harvest.sql"
```

> **Note:** The pipeline needs a dedicated MySQL user with write access to the
> `harvest` database. The local defaults use user/password `harvest` for developer
> convenience. Override credentials for production.

## Kubernetes

The Helm chart at `chart/` is the single source of truth
for Kubernetes deployment — hand-written, not generated.

```bash
just kind-up       # Start kind cluster, deploy MariaDB + CronJob via Helm
just test          # Trigger a one-off harvest job
just clean         # Tear down cluster
```

### Helm install

```bash
helm upgrade --install harvest chart \
  --namespace harvest-consultations --create-namespace \
  --set mysql.host=mariadb
```

Override for external databases or production credentials:

```bash
helm upgrade --install harvest chart \
  --namespace harvest-consultations --create-namespace \
  --set mysql.host=external-db \
  --set mysql.database=harvest \
  --set harvest.schedule="@daily" \
  --set mariadb.rootPassword='change-me' \
  --set mariadb.user=harvest \
  --set mariadb.password='change-me'
```

### Package

```bash
just helm-package    # writes dist/harvest-consultations-*.tgz
```

### CI test

```bash
just ci-test         # kind → helm install → harvest job → dump → validate
```

## Values

| Key | Default | Description |
|-----|---------|-------------|
| `mysql.host` | `mariadb` | MySQL hostname for the harvest job |
| `mysql.database` | `harvest` | Database name |
| `mariadb.rootPassword` | `harvest` | MariaDB root password (init only; not used by app/healthcheck) |
| `mariadb.user` | `harvest` | Application database user |
| `mariadb.password` | `harvest` | Application database password |
| `mariadb.image.repository` | `mariadb` | MariaDB image |
| `mariadb.image.tag` | `11` | MariaDB image tag |
| `mariadb.storage.size` | `1Gi` | PVC size for MariaDB data |
| `mariadb.storage.storageClassName` | (unset) | StorageClass for PVC (set to `"encrypted"` for at-rest encryption) |
| `mariadb.resources.requests.memory` | `256Mi` | MariaDB memory request |
| `mariadb.resources.requests.cpu` | `100m` | MariaDB CPU request |
| `mariadb.resources.limits.memory` | `1Gi` | MariaDB memory limit |
| `mariadb.resources.limits.cpu` | `1` | MariaDB CPU limit |
| `networkPolicy.enabled` | `false` | Enable NetworkPolicy to restrict ingress to MariaDB |
| `harvest.schedule` | `@hourly` | CronJob schedule |
| `harvest.image.repository` | `duckdb/duckdb` | DuckDB image |
| `harvest.image.tag` | `1.5.2` | DuckDB image tag |
| `harvest.resources.requests.memory` | `256Mi` | Harvest job memory request |
| `harvest.resources.requests.cpu` | `100m` | Harvest job CPU request |
| `harvest.resources.limits.memory` | `1Gi` | Harvest job memory limit |
| `harvest.resources.limits.cpu` | `1` | Harvest job CPU limit |

## Files

| Path | Purpose |
|------|---------|
| `chart/harvest.sql` | SQL-only DuckDB harvest pipeline |
| `chart/templates/secret.yaml` | Mariadb-credentials Secret (auto-generated from values) |
| `chart/templates/networkpolicy.yaml` | Optional NetworkPolicy for MariaDB ingress isolation |
| `chart/` | Helm chart (hand-written, source of truth) |
| `justfile` | Dev/test/package commands |
