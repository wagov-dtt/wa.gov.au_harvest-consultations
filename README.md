# WA Gov Consultation Harvester

Small PHP CLI that harvests WA Government consultation APIs and writes a normalized MariaDB/MySQL table.

The repo intentionally has one application entrypoint, plain SQL transforms, plain Kubernetes source manifests, and a generated-on-demand Helm chart.

## What it produces

- Database: `DB_NAME`, default `harvest_consultations`
- Table: `DB_TABLE`, default `consultations`
- Nightly artifact: `dist/sql.tar.gz`, containing `sql.sql` from `mariadb-dump`
- Release packages:
  - image: `ghcr.io/wagov-dtt/harvest-consultations:<semver>`
  - chart: `oci://ghcr.io/wagov-dtt/charts/harvest-consultations`

## Quick start

```bash
mise install
cp example.env .env # edit portal URLs/password
just check
```

Run the full local/CI artifact path when you need the dump:

```bash
just ci-dump
```

## Configuration

`just` loads `.env` locally. Docker and Kubernetes receive the same values through `--env-file` or Secret `harvest-env`.

```dotenv
PORTALS_JSON={"engagementhq":["https://..."],"citizenspace":["https://..."]}
DB_PASSWORD=<set-a-real-password>
DB_NAME=harvest_consultations
DB_TABLE=consultations
DB_PORT=3306
MAX_HTTP_RESPONSE_BYTES=10485760
```

| Key | Required | Default | Notes |
| --- | --- | --- | --- |
| `PORTALS_JSON` | yes for `run`/`ci-dump` | `{}` | JSON object with `engagementhq` and/or `citizenspace` URL arrays. URLs must be public HTTPS; local/private hostnames and IP literals are rejected. |
| `DB_PASSWORD` | yes | none | Must be non-empty and not the example placeholder. Local `just ci-dump` generates a random disposable password when unset. |
| `DB_NAME` | no | `harvest_consultations` | Must be a MySQL identifier. |
| `DB_TABLE` | no | `consultations` | Must be a MySQL identifier. |
| `DB_HOST` | no | `localhost` | `k8s/local` overrides this to `mariadb`. |
| `DB_PORT` | no | `3306` | Port only; host comes from `DB_HOST`. |
| `DB_USER` | no | `root` | Optional DB user. Use a dedicated least-privilege user for production. |
| `MAX_HTTP_RESPONSE_BYTES` | no | `10485760` | Maximum HTTP response body size before JSON decoding. |

## Common commands

```bash
just check         # PHP syntax, Helm render/lint, Docker build
just cluster-smoke # kind + kustomize + MariaDB readiness, no API harvest
just deploy-local  # local kind DB + one harvest Job, no dump artifact
just ci-dump       # full kind harvest + verified dist/sql.tar.gz
just verify-dump   # verify an existing dist/sql.tar.gz
just helmify       # generate public Helm chart into dist/helm
just clean         # delete local kind cluster/temp env/chart files
```

Run `just --list` for the public command surface.

## Installing the chart

Create/update the runtime secret:

```bash
kubectl create namespace harvest --dry-run=client -o yaml | kubectl apply -f -
kubectl -n harvest create secret generic harvest-env \
  --from-env-file=.env \
  --dry-run=client -o yaml | kubectl apply -f -
```

Install the published chart:

```bash
helm upgrade --install harvest-consultations \
  oci://ghcr.io/wagov-dtt/charts/harvest-consultations \
  --namespace harvest --create-namespace \
  -f values.prod.yaml
```

Minimal values file:

```yaml
harvestConsultations:
  schedule: "0 18 * * *"
```

## Restoring the nightly artifact

```bash
tar -xzf sql.tar.gz
mariadb -h "$DB_HOST" -P "${DB_PORT:-3306}" -u "${DB_USER:-root}" -p < sql.sql
```

## Project structure

```text
VERSION                 # release/chart/image version
Dockerfile              # PHP CLI image build
harvest.php             # fetch, validate, normalize, export
sql/harvest.sql         # named SQL statements used by harvest.php
k8s/base/               # source Kubernetes manifests
k8s/local*/             # local/CI kustomize overlays
k8s/public/             # input for generated public Helm chart
values.prod.example.yaml # minimal production values example
```
