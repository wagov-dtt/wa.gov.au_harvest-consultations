# DuckDB SQL Pipeline for Harvesting Consultations

A single SQL file pulls consultation data from WA government Citizen Space and
EngagementHQ APIs, normalises it, and mirrors it into a MariaDB table for downstream consumption.
The runtime harvest path is DuckDB SQL only; Python is not required.

## Quick start

The recommended path is Helm, because `chart/harvest.sql` is templated with the
configured output table name.

For local DuckDB runs, set the standard [DuckDB MySQL environment variables](https://duckdb.org/docs/current/core_extensions/mysql#configuration), render the table name, then run the rendered SQL:

```bash
export MYSQL_HOST=localhost MYSQL_USER=harvest MYSQL_PWD=harvest MYSQL_DATABASE=harvest
sed 's/{{ .Values.mysql.table }}/consultations/g' chart/harvest.sql > /tmp/harvest.sql
duckdb -c ".read /tmp/harvest.sql"
```

> **Note:** The pipeline needs a dedicated MySQL user with write access to the
> target database/table. Helm installs write to `mysql.database`.`mysql.table`,
> defaulting to `harvest`.`consultations`. Use a simple table identifier such as
> `consultations`; do not pass untrusted input to `mysql.table`. The local defaults
> use user/password `harvest` for developer convenience. Override credentials for production.

## Kubernetes

The Helm chart at `chart/` is the single source of truth
for Kubernetes deployment — hand-written, not generated.

```bash
just kind-up       # Start kind cluster, deploy MariaDB + CronJob via Helm
just test          # Trigger a one-off harvest job
just clean         # Tear down cluster
```

Defaults deploy an in-cluster MariaDB for local/dev use and write to table
`harvest.consultations`. For production, disable the bundled database with
`--set mariadb.enabled=false` and point `mysql.host` at an externally managed
MySQL/MariaDB service. Change the table with `--set mysql.table=...` or the
`table` variable in `justfile`.

### Helm install

```bash
helm upgrade --install harvest chart \
  --namespace harvest-consultations --create-namespace \
  --set mysql.host=mariadb \
  --set mysql.table=consultations
```

For production/external databases, disable the bundled MariaDB StatefulSet and provide the external host plus credentials:

```bash
helm upgrade --install harvest chart \
  --namespace harvest-consultations --create-namespace \
  --set mariadb.enabled=false \
  --set mysql.host=external-db.example.internal \
  --set mysql.database=harvest \
  --set mysql.table=consultations \
  --set harvest.schedule="@daily" \
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
| `mysql.database` | `harvest` | Target MySQL database name |
| `mysql.table` | `consultations` | Target MySQL table replaced by each harvest run |
| `mariadb.enabled` | `true` | Deploy bundled MariaDB StatefulSet/Service for local/dev; set `false` for production/external databases |
| `mariadb.rootPassword` | `harvest` | Bundled MariaDB root password (init only; not rendered when `mariadb.enabled=false`) |
| `mariadb.user` | `harvest` | Application database user for bundled or external DB |
| `mariadb.password` | `harvest` | Application database password for bundled or external DB |
| `mariadb.image.repository` | `mariadb` | Bundled MariaDB image |
| `mariadb.image.tag` | `11` | Bundled MariaDB image tag |
| `mariadb.storage.size` | `1Gi` | PVC size for bundled MariaDB data |
| `mariadb.storage.storageClassName` | (unset) | StorageClass for bundled MariaDB PVC (set to `"encrypted"` for at-rest encryption) |
| `mariadb.resources.requests.memory` | `256Mi` | Bundled MariaDB memory request |
| `mariadb.resources.requests.cpu` | `100m` | Bundled MariaDB CPU request |
| `mariadb.resources.limits.memory` | `1Gi` | Bundled MariaDB memory limit |
| `mariadb.resources.limits.cpu` | `1` | Bundled MariaDB CPU limit |
| `networkPolicy.enabled` | `false` | Enable NetworkPolicy to restrict ingress to bundled MariaDB; ignored when `mariadb.enabled=false` |
| `harvest.schedule` | `@hourly` | CronJob schedule |
| `harvest.image.repository` | `ghcr.io/wagov-dtt/harvest-duckdb` | DuckDB image with extensions pre-installed |
| `harvest.image.tag` | `""` | Image tag override; empty computes `{chart-version}-duckdb{appVersion without dots}` |
| `harvest.resources.requests.memory` | `256Mi` | Harvest job memory request |
| `harvest.resources.requests.cpu` | `100m` | Harvest job CPU request |
| `harvest.resources.limits.memory` | `1Gi` | Harvest job memory limit |
| `harvest.resources.limits.cpu` | `1` | Harvest job CPU limit |

## Files

| Path | Purpose |
|------|---------|
| `chart/harvest.sql` | SQL-only DuckDB harvest pipeline; Helm templates `mysql.table` into the final write statement |
| `chart/templates/secret.yaml` | Mariadb-credentials Secret (auto-generated from values) |
| `chart/templates/networkpolicy.yaml` | Optional NetworkPolicy for MariaDB ingress isolation |
| `chart/` | Helm chart (hand-written, source of truth) |
| `justfile` | Dev/test/package commands |
