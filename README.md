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

Install from the published OCI chart:

```bash
helm upgrade --install harvest \
  oci://ghcr.io/wagov-dtt/harvest-consultations \
  --version 0.5.9 \
  --namespace harvest-consultations --create-namespace \
  --set db.host=mariadb \
  --set db.table=consultations
```

Use `chart/` instead of the OCI URL when developing locally.

## Production install

Use an externally managed database and a pre-existing Kubernetes Secret. The
default bundled MariaDB and credentials are for local development only.

```bash
helm upgrade --install harvest \
  oci://ghcr.io/wagov-dtt/harvest-consultations \
  --version 0.5.9 \
  --namespace harvest-consultations --create-namespace \
  --set mariadb.enabled=false \
  --set db.host=external-db.example.internal \
  --set db.database=harvest \
  --set db.table=consultations \
  --set db.existingSecret=harvest-db \
  --set harvest.schedule='@daily'
```

Notes:

- `db.table` is rendered into SQL; use a simple trusted identifier such as
  `consultations`.
- An existing Secret must contain `DB_USER` and `DB_PASSWORD` keys. Override
  `db.secretKeys` when it uses different key names.
- With bundled MariaDB, an existing Secret must also contain the configured
  `db.secretKeys.rootPassword` key.
- Set `harvest.image.digest` to an immutable `sha256:...` digest when required;
  it takes precedence over `harvest.image.tag`.
- The default `harvest`/`harvest` credentials are for local/dev only.
- Set `networkPolicy.enabled=true` only when your CNI enforces NetworkPolicy.

## Local DuckDB run

Helm normally renders `chart/harvest.sql`. For a manual local run, render the
output table placeholder yourself and use DuckDB's MySQL environment variables:

```bash
export MYSQL_HOST=localhost MYSQL_USER=harvest MYSQL_PWD=harvest MYSQL_DATABASE=harvest
sed -e 's/{{ .Values.db.table }}/consultations/g' \
    -e 's#/etc/config/transform.sql#chart/transform.sql#' \
    chart/harvest.sql > /tmp/harvest.sql
duckdb -c ".read /tmp/harvest.sql"
```

## Common commands

```bash
just helm-install     # Install/upgrade into the configured namespace
just check            # Run fixture SQL tests and validate chart rendering
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
| `db.existingSecret` | unset | Existing database credentials Secret |
| `db.secretKeys.*` | see `values.yaml` | Keys within the database Secret |
| `mariadb.enabled` | `true` | Deploy bundled local/dev MariaDB |
| `mariadb.rootPassword` | `harvest` | Bundled MariaDB root password |
| `mariadb.image.repository` | `mariadb` | Bundled MariaDB image |
| `mariadb.image.tag` | `11` | Bundled MariaDB image tag |
| `mariadb.storage.size` | `1Gi` | Bundled MariaDB PVC size |
| `mariadb.storage.storageClassName` | unset | Optional PVC StorageClass |
| `mariadb.resources.*` | see `values.yaml` | Bundled MariaDB requests/limits |
| `networkPolicy.enabled` | `false` | Restrict ingress to bundled MariaDB |
| `harvest.schedule` | `@hourly` | CronJob schedule |
| `harvest.suspend` | `false` | Suspend scheduled harvests |
| `harvest.startingDeadlineSeconds` | `1800` | Deadline for starting a missed run |
| `harvest.activeDeadlineSeconds` | `900` | Maximum Job duration |
| `harvest.backoffLimit` | `2` | Failed pod retries per Job |
| `harvest.successfulJobsHistoryLimit` | `1` | Successful Jobs retained |
| `harvest.failedJobsHistoryLimit` | `3` | Failed Jobs retained |
| `harvest.ttlSecondsAfterFinished` | `86400` | Finished Job retention time |
| `harvest.image.repository` | `ghcr.io/wagov-dtt/harvest-duckdb` | Harvest image |
| `harvest.image.tag` | computed | Override computed image tag |
| `harvest.image.digest` | unset | Immutable image digest; overrides tag |
| `harvest.resources.*` | see `values.yaml` | Harvest Job requests/limits |

## Maintaining the SQL

- `chart/harvest.sql` owns network extraction, validation, and MySQL publication.
- `chart/transform.sql` owns deterministic status, agency, date, and output-shape
  logic. Add EngagementHQ agency mappings to `engagementhq_agency_rules`; lower
  priorities win when multiple rules match.
- `tests/transform.sql` supplies fixture rows and assertions. Update it with each
  business-rule change, then run `just check`.

The nightly workflow exercises live sources and MariaDB; fixture tests keep
transformation changes independent of upstream availability.

## Manual run

```bash
kubectl create job harvest-manual --from=cronjob/harvest-cronjob -n harvest-consultations
kubectl logs -f job/harvest-manual -n harvest-consultations
```

## Files

| Path | Purpose |
|------|---------|
| `chart/harvest.sql` | DuckDB SQL harvest pipeline |
| `chart/transform.sql` | Deterministic transformations and agency mappings |
| `chart/templates/` | Helm templates for CronJob, Secret, MariaDB, and NetworkPolicy |
| `chart/values.yaml` | Chart defaults |
| `chart/values.schema.json` | Helm values validation |
| `tests/transform.sql` | Fixture-based transformation assertions |
| `justfile` | Development, test, package, and release commands |
