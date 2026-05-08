# WA Gov Consultation Harvester

Fetches WA Government consultation data with a small PHP CLI script and writes a normalised `consultations` table to MariaDB/MySQL via PDO.

## Quick start

```bash
mise install
cp example.env .env # edit portal URLs/password
just check
```

## Configuration

Local/CI uses dotenv `.env` loaded by `just`, Docker `--env-file`, or Kubernetes Secret `harvest-env`:

```dotenv
PORTALS_JSON='{"engagementhq":["https://..."],"citizenspace":["https://..."]}'
DB_PASSWORD='secret'
DB_NAME='harvest_consultations'
DB_TABLE='consultations'
```

`DB_TABLE`, `DB_HOST`, `DB_PORT`, and `DB_USER` are optional. `DB_TABLE` defaults to `consultations` and must be a MySQL identifier.

## Commands

```bash
just check         # PHP syntax, Helm render/lint, Docker build
just cluster-smoke # kind + kustomize + MariaDB readiness, no API harvest
just ci-dump       # full kind run, harvest Job, verified dist/sql.tar.gz
just verify-dump   # check dist/sql.tar.gz has expected mysqldump content
just helmify       # generate public Helm chart into dist/helm
just clean         # delete local kind cluster/temp env/chart files
```

## Publishing

Project version lives in [`VERSION`](VERSION). Images are published to:

```text
ghcr.io/wagov-dtt/harvest-consultations:<semver>
```

The Helm chart is generated during CI/release and published as an OCI chart:

```text
oci://ghcr.io/wagov-dtt/charts/harvest-consultations
```

## Project structure

```text
VERSION                           # release/chart/image version
Dockerfile                        # PHP CLI image build
harvest.php                       # API fetching, normalisation, validation, MySQL export
sql/harvest.sql                   # named SQL statements used by the harvester
k8s/base/                         # plain Kubernetes source manifests
k8s/local/                        # kustomize overlay for local/CI CronJob + MariaDB
k8s/public/                       # kustomize input for generated public Helm chart
```
