# Contributing

Keep this repo small and boring:

- One PHP CLI script for harvesting, validation, and export.
- Plain SQL for normalization where SQL is clearer than PHP.
- No PHP package manager/runtime dependencies.
- Plain Kubernetes manifests as source of truth.
- Helm chart generated into `dist/helm`; generated chart output is not committed.

## Setup

```bash
mise install
cp example.env .env
```

Edit `.env` with real portal URLs and DB password. Use normal JSON for `PORTALS_JSON` and replace the password placeholder:

```dotenv
PORTALS_JSON={"engagementhq":["https://..."],"citizenspace":["https://..."]}
DB_PASSWORD=<set-a-real-password>
DB_NAME=harvest_consultations
DB_TABLE=consultations
```

`DB_NAME` and `DB_TABLE` are validated as MySQL identifiers. `k8s/local` always sets `DB_HOST=mariadb` for the disposable local DB.

## Daily workflow

```bash
just check         # fast gate: PHP syntax + chart lint/render + Docker build
just cluster-smoke # kind + local MariaDB readiness, no external API harvest
just ci-dump       # canonical full artifact build
just clean         # remove local kind cluster and generated temp files
```

Prefer adding focused checks to `just check` over adding new command paths.

## Artifact build flow

`just ci-dump` does the same thing as the nightly workflow:

1. builds `harvest-consultations:test`,
2. creates/reuses a kind cluster,
3. deploys local MariaDB and the CronJob manifest,
4. creates one `harvest-run` Job from that CronJob,
5. dumps MariaDB to `dist/sql.tar.gz`,
6. restores/verifies the dump before succeeding.

The artifact must contain exactly one file:

```text
sql.sql
```

## Helm chart flow

Source of truth:

```text
k8s/base/cronjob.yaml
k8s/public/kustomization.yaml
```

Generate and test the chart locally:

```bash
just helmify
helm lint dist/helm/harvest-consultations
helm template harvest-consultations dist/helm/harvest-consultations >/dev/null
```

On semver tags, CI packages that generated chart and pushes it to:

```text
oci://ghcr.io/wagov-dtt/charts/harvest-consultations
```

## Release checklist

1. Update `VERSION`.
2. Run `just check`.
3. Commit and push `main`.
4. Tag and push `v$(cat VERSION)`.
5. Watch `CI and Release` for the tag.
6. Trigger/watch `Nightly consultations dump` if artifact behavior changed.
7. Verify the nightly run has a non-expired `sql` artifact.

Useful commands:

```bash
gh run list --limit 10
gh run view <run-id> --log-failed
gh api repos/:owner/:repo/actions/runs/<run-id>/artifacts
```

## Nightly environment secrets

The `nightly` GitHub environment needs these secrets:

```text
PORTALS_JSON
DB_PASSWORD
DB_NAME
DB_TABLE
DB_PORT
```

Update from local `.env` without printing values:

```bash
gh api --method PUT repos/:owner/:repo/environments/nightly >/dev/null
gh secret set --env nightly --env-file .env
```

## Troubleshooting

### `PORTALS_JSON must be a JSON object`

Validate the local env-to-kustomize rendering without printing secret values:

```bash
just _local-env
python3 - <<'PY'
import json
from pathlib import Path
vals = dict(line.split('=', 1) for line in Path('.k8s.env').read_text().splitlines() if '=' in line)
data = json.loads(vals['PORTALS_JSON'])
print(sorted(data))
PY
rm -f .k8s.env
```

If this fails, fix `.env` first, then push the environment secrets again.

### Harvest Job failed in kind/CI

`just _wait-job` prints diagnostics automatically during `just ci-dump`. For an existing failed local cluster, run:

```bash
just _dump-debug
```

Check the final `Error:` line from `job/harvest-run` first; Kubernetes events are often secondary.

### Artifact missing

Confirm the nightly workflow reached the upload step and query artifacts directly:

```bash
gh api repos/:owner/:repo/actions/runs/<run-id>/artifacts \
  --jq '.artifacts[] | [.name,.size_in_bytes,.expired] | @tsv'
```

Expected artifact name: `sql`.

## Pinning and upgrade policy

- GitHub Actions are pinned to commit SHAs, with comments showing the reviewed tag and Node runtime.
- Use current Node-based action majors to avoid Node runtime deprecation warnings.
- Runtime/tooling pins should be low-churn majors/minors where upstream supports them, e.g. `php:8.4-cli-trixie`, `mariadb:11`, `helm = "4"`.
- Keep exact `kindest/node` pins because kind node images are Kubernetes-patch-specific.

## Code style

- Prefer direct, explicit PHP and SQL over new abstraction layers.
- Keep validation near trust boundaries: env parsing, API response parsing, SQL export.
- Fail closed before export: empty/malformed inputs should not publish a final table.
- Do not add dependencies or new execution paths unless they remove more complexity than they add.
