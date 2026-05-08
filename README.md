# WA Gov Consultation Harvester

Fetches WA Government consultation data with a small PHP CLI script and writes a normalised table to MariaDB/MySQL via PDO.

## Quick start

```bash
mise install
cp example.env .env # edit portal URLs/password
just check
```

## Configuration

Local/CI uses dotenv `.env`:

```dotenv
PORTALS_JSON='{"engagementhq":["https://..."],"citizenspace":["https://..."]}'
DB_PASSWORD='secret'
DB_NAME='harvest_consultations'
DB_TABLE='consultations'
```

Production uses a helmify-generated chart. Secrets stay in Kubernetes Secret `harvest-env`; schedule/image live in Helm values. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Commands

```bash
just check         # Fast checks: PHP syntax, Helm render/lint, Docker build
just cluster-smoke # Faster cluster smoke: kind + kustomize + MariaDB readiness
just ci-dump       # Full kind run, harvest Job, verified dist/sql.tar.gz
just verify-dump   # Check dist/sql.tar.gz has expected mysqldump content
just helmify       # Regenerate public Helm chart from kustomize output
just chart-test    # Regenerate, lint, and render the Helm chart
just install-cron  # Helm install/upgrade with values.prod.yaml
just clean         # Stop local services/kind cluster
```

## Publishing

Images are published to:

```text
ghcr.io/wagov-dtt/harvest-consultations:<semver>
```

The generated Helm chart is published as an OCI chart to GHCR:

```text
oci://ghcr.io/wagov-dtt/charts/harvest-consultations
```

## Project structure

```text
Dockerfile                         # Official PHP CLI image build
harvest.php                        # API fetching, normalisation, validation, MySQL export
k8s/base/                          # Plain Kubernetes source manifests
k8s/local/                         # kustomize overlay for local/CI secrets + MariaDB + Job
k8s/public/                        # kustomize input for helmify public CronJob chart
charts/harvest-consultations/      # generated Helm chart
```
