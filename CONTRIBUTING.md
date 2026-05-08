# Contributing

This repo aims to stay small and boring:

- Single PHP CLI script for harvesting, normalisation, validation, and MySQL/MariaDB export.
- Docker image for execution.
- kustomize for local/CI Kubernetes.
- helmify-generated Helm chart for production installs.

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

`k8s/local` overrides `DB_HOST=mariadb` and runs a local MariaDB StatefulSet.

## Daily commands

```bash
just check         # PHP syntax + Helm render/lint + docker build
just cluster-smoke # kind + kustomize + MariaDB readiness, no harvest API run
just ci-dump       # kind + harvest Job + verified dump artifact
just verify-dump   # check dist/sql.tar.gz shape
just helmify       # regenerate public Helm chart from kustomize output
just chart-test    # regenerate, lint, and render Helm chart
just install-cron  # helm upgrade --install with values.prod.yaml
just clean         # delete local containers/kind cluster
```

## Local/CI artifact build

```bash
just ci-dump
```

This creates/reuses a local kind cluster, builds/imports the image, applies `k8s/local` into a fresh namespace, waits for the harvest Job, dumps MariaDB, verifies the dump can be read back, and writes:

```text
dist/sql.tar.gz
```

The GitHub nightly artifact workflow uses the same command.

## Public Helm chart

The source of truth is plain Kubernetes YAML under `k8s/base` plus kustomize overlays. The public chart is generated from `k8s/public`:

```bash
just helmify
```

This runs:

```bash
kustomize build --load-restrictor LoadRestrictionsNone k8s/public | helmify -original-name charts/harvest-consultations
```

Do not hand-edit generated chart templates unless you also accept that `just helmify` may overwrite them.

## Production/EKS install

Best publishing target: **GHCR for both image and Helm chart**.

Why:

- one registry/auth model,
- Helm 3 supports OCI charts natively,
- no GitHub Pages/index.yaml to maintain,
- EKS can pull the container image from GHCR using normal image pull secrets if the package is private.

Published artifacts:

```text
ghcr.io/wagov-dtt/harvest-consultations:<semver>
oci://ghcr.io/wagov-dtt/charts/harvest-consultations
```

Install from a target cluster context. First create/update the runtime secret from dotenv values:

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

Minimal `values.prod.yaml` for the helmified chart:

```yaml
harvestConsultations:
  harvest:
    image:
      repository: ghcr.io/wagov-dtt/harvest-consultations
      tag: 0.4.1
  schedule: "0 18 * * *"
```

For a quick install from this checkout, create `values.prod.yaml` and run:

```bash
just install-cron values.prod.yaml
```

## Pinning and upgrade policy

- GitHub Actions are pinned to commit SHAs, with comments showing the reviewed major tag.
- Project releases are semver tagged; image/chart publishing only happens for matching `vX.Y.Z` tags.
- Runtime/tooling outside GitHub Actions uses low-churn major or minor pins where upstream publishes them, for example `php:8.4-cli-trixie`, `mariadb:11`, `helm = "4"`.
- Keep exact Kubernetes node-image pins for kind because `kindest/node` tags are published per Kubernetes patch release.
- Run `just check` and `just cluster-smoke` for routine upgrades; run `just ci-dump` before release or when cluster/dump behaviour changes.

## One-month maintainability plan

Highest-value work that keeps the current cluster-packaged-job design:

### Week 1: make failures obvious

1. Keep `just check` as the default fast local gate.
2. Use `just cluster-smoke` for Kubernetes/MariaDB wiring without the slow API harvest.
3. Keep `just ci-dump` as the canonical full artifact build, with bounded waits and diagnostics.
4. Keep the artifact as `dist/sql.tar.gz` containing a `mysqldump`/`mariadb-dump` compatible `sql.sql`.

### Week 2: reduce release and chart drift

1. Keep kustomize as the local/CI source of truth and regenerate/lint/render the Helm chart in CI.
2. Keep GitHub Actions SHA-pinned and refresh SHAs against the reviewed major tags during routine maintenance.
3. Publish only semver-tagged image/chart releases; use `test` tags only for CI-local execution.

### Week 3: harden runtime safety

1. Fail closed before export: reject empty outputs, invalid identifiers, malformed portal config, bad response shapes, and invalid transformed data.
2. Keep Kubernetes resource/security defaults current for both Job and CronJob.
3. Keep local kind state disposable so Secret/DB drift cannot affect artifact builds.

### Week 4: make operation easier

1. Add a short runbook for debugging failed `ci-dump` diagnostics.
2. Document the expected `sql.tar.gz` restore command for artifact consumers.
3. Prefer small docs/check improvements over new execution paths: update README/CONTRIBUTING when commands or release flow change.

## Code style

- Prefer direct, boring Python with explicit data flow.
- Keep dependencies minimal.
- Put data-shaping logic in SQL when clearer.
- Add focused tests for parsing, transforms, and regressions.
