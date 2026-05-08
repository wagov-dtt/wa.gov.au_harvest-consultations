# Contributing

This repo aims to stay small and boring:

- Single PHP CLI script for harvesting, normalisation, validation, and MySQL/MariaDB export.
- No PHP package manager/runtime dependencies; use PHP built-ins plus PDO MySQL.
- Docker image for execution.
- kustomize for local/CI Kubernetes.
- Helm chart generated into `dist/helm` for releases; generated chart output is not committed.

## Setup

```bash
mise install
cp example.env .env
```

Edit `.env` for local/CI:

```dotenv
PORTALS_JSON='{"engagementhq":["https://..."],"citizenspace":["https://..."]}'
DB_PASSWORD='secret'
DB_NAME='harvest_consultations'
DB_TABLE='consultations'
```

`k8s/local` overrides `DB_HOST=mariadb` and runs a local MariaDB StatefulSet. `DB_TABLE` defaults to `consultations` and must be a MySQL identifier.

## Daily commands

```bash
just check         # PHP syntax + Helm render/lint + docker build
just cluster-smoke # kind + kustomize + MariaDB readiness, no harvest API run
just ci-dump       # kind + harvest Job + verified dump artifact
just verify-dump   # check dist/sql.tar.gz shape
just helmify       # generate public Helm chart into dist/helm
just clean         # delete local kind cluster/temp env/chart files
```

## Local/CI artifact build

```bash
just ci-dump
```

This creates/reuses a local kind cluster, builds/imports the image, applies `k8s/local`, creates a one-shot `harvest-run` Job from the CronJob template, dumps MariaDB, verifies the dump can be read back, and writes:

```text
dist/sql.tar.gz
```

The GitHub nightly artifact workflow uses the same command.

## Public Helm chart

The source of truth is plain Kubernetes YAML under `k8s/base` plus kustomize overlays. The public chart is generated from `k8s/public`:

```bash
just helmify
```

This writes the generated chart to:

```text
dist/helm/harvest-consultations
```

CI packages that generated chart on semver tags and publishes it to:

```text
oci://ghcr.io/wagov-dtt/charts/harvest-consultations
```

## Production/EKS install

Create/update the runtime secret from dotenv values:

```bash
kubectl create namespace harvest --dry-run=client -o yaml | kubectl apply -f -
kubectl -n harvest create secret generic harvest-env \
  --from-env-file=.env \
  --dry-run=client -o yaml | kubectl apply -f -
```

Then install the chart:

```bash
helm upgrade --install harvest-consultations \
  oci://ghcr.io/wagov-dtt/charts/harvest-consultations \
  --namespace harvest --create-namespace \
  -f values.prod.yaml
```

Minimal `values.prod.yaml`:

```yaml
harvestConsultations:
  schedule: "0 18 * * *"
```

## Pinning and upgrade policy

- GitHub Actions are pinned to commit SHAs, with comments showing the reviewed major tag.
- Project releases are semver tagged; image/chart publishing only happens for matching `vX.Y.Z` tags.
- Runtime/tooling outside GitHub Actions uses low-churn major or minor pins where upstream publishes them, for example `php:8.4-cli-trixie`, `mariadb:11`, `helm = "4"`.
- Keep exact Kubernetes node-image pins for kind because `kindest/node` tags are published per Kubernetes patch release.
- Run `just check` and `just cluster-smoke` for routine upgrades; run `just ci-dump` before release or when cluster/dump behaviour changes.

## Code style

- Prefer direct, boring PHP with explicit data flow.
- Keep dependencies minimal.
- Put data-shaping logic in SQL when clearer.
- Add focused tests for parsing, transforms, and regressions.
