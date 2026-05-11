# DuckDB SQL Pipeline for Harvesting Consultations

Harvests WA government consultation data from Citizen Space and EngagementHQ,
normalises it in DuckDB, and replaces a target MySQL/MariaDB table. The runtime
pipeline is SQL only; Python is not required.

## Quick start: Kubernetes

The Helm chart in `chart/` is the deployment source of truth. By default it
creates a local/dev MariaDB and writes `harvest.consultations`.

```bash
just kind-up       # Create/update kind cluster and Helm release
just test          # Trigger one harvest Job from the CronJob
just clean         # Delete the kind cluster and dist/
```

Install directly with Helm:

```bash
helm upgrade --install harvest chart \
  --namespace harvest-consultations --create-namespace \
  --set db.host=mariadb \
  --set db.table=consultations
```

## Production install

Use an externally managed database and override the default development
credentials:

```bash
helm upgrade --install harvest chart \
  --namespace harvest-consultations --create-namespace \
  --set mariadb.enabled=false \
  --set db.host=external-db.example.internal \
  --set db.database=harvest \
  --set db.table=consultations \
  --set db.user=harvest \
  --set db.password='change-me' \
  --set harvest.schedule='@daily'
```

Notes:

- `db.table` is rendered into SQL; use a simple trusted identifier such as
  `consultations`.
- The default `harvest`/`harvest` credentials are for local/dev only.
- Set `networkPolicy.enabled=true` only when your CNI enforces NetworkPolicy.

## Local DuckDB run

Helm normally renders `chart/harvest.sql`. For a manual local run, render the
output table placeholder yourself and use DuckDB's MySQL environment variables:

```bash
export MYSQL_HOST=localhost MYSQL_USER=harvest MYSQL_PWD=harvest MYSQL_DATABASE=harvest
sed 's/{{ .Values.db.table }}/consultations/g' chart/harvest.sql > /tmp/harvest.sql
duckdb -c ".read /tmp/harvest.sql"
```

## Common commands

```bash
just helm-install     # Install/upgrade into the configured namespace
just ci-test          # kind → Helm install → harvest Job → dump → validate
just helm-package     # Write dist/harvest-consultations-*.tgz
just bump-version X.Y.Z [DUCKDB_VERSION]
```

## Values

| Key | Default | Use |
|-----|---------|-----|
| `db.host` | `mariadb` | MySQL/MariaDB hostname |
| `db.database` | `harvest` | Target database |
| `db.table` | `consultations` | Table replaced on each harvest |
| `db.user` | `harvest` | Application database user |
| `db.password` | `harvest` | Application database password |
| `mariadb.enabled` | `true` | Deploy bundled local/dev MariaDB |
| `mariadb.rootPassword` | `harvest` | Bundled MariaDB root password |
| `mariadb.image.repository` | `mariadb` | Bundled MariaDB image |
| `mariadb.image.tag` | `11` | Bundled MariaDB image tag |
| `mariadb.storage.size` | `1Gi` | Bundled MariaDB PVC size |
| `mariadb.storage.storageClassName` | unset | Optional PVC StorageClass |
| `mariadb.resources.*` | see `values.yaml` | Bundled MariaDB requests/limits |
| `networkPolicy.enabled` | `false` | Restrict ingress to bundled MariaDB |
| `harvest.schedule` | `@hourly` | CronJob schedule |
| `harvest.image.repository` | `ghcr.io/wagov-dtt/harvest-duckdb` | Harvest image |
| `harvest.image.tag` | computed | Override computed image tag |
| `harvest.resources.*` | see `values.yaml` | Harvest Job requests/limits |

## Files

| Path | Purpose |
|------|---------|
| `chart/harvest.sql` | DuckDB SQL harvest pipeline |
| `chart/templates/` | Helm templates for CronJob, Secret, MariaDB, and NetworkPolicy |
| `chart/values.yaml` | Chart defaults |
| `justfile` | Development, test, package, and release commands |
