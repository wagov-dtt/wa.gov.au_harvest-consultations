# Changelog

## [0.5.7] — Unreleased

### Added
- **Schema guard assertions** in `harvest.sql`: validates output column names and order against `['source', 'name', 'description', 'status', 'agency', 'tags', 'region', 'url', 'publishdate', 'expirydate']` using `information_schema.columns`, and row count range (10–50,000). Mismatch calls `error()`, failing the job before MySQL mirror.
- **EngagementHQ agency mappings**: added tag-based rules for `dtmi`, `taxi`, `charter`, `on-demand`, `passenger transport` → Department of Transport; `hvs`, `heavy vehicle` → Main Roads Western Australia. Resolves 4 previously-unmapped projects falling through to "Government of Western Australia".

### Changed
- Simplified CSV report job (`justfile`, `ci-nightly.yaml`): removed in-cluster `duckdb` execution; dumps CSV directly from MariaDB via `COPY`.

## [0.5.6] — 2026-05-11

### Changed
- **Renamed chart values**: `mysql` → `db`, `mariadb-credentials` secret → `db-credentials`, `MARIADB_USER`/`MARIADB_PASSWORD` keys → `DB_USER`/`DB_PASSWORD`. The `harvest.sql` template reference changed from `.Values.mysql.table` to `.Values.db.table`.
- New `db.user` and `db.password` values for external database credentials.

## [0.5.5] — 2026-05-11

### Added
- **Optional bundled MariaDB**: `mariadb.enabled` flag gates StatefulSet, Service, and NetworkPolicy. When disabled, only the external-database secret keys are rendered (`DB_USER`/`DB_PASSWORD` without `MARIADB_ROOT_PASSWORD`).
- NetworkPolicy now also gated on `mariadb.enabled`.

## [0.5.4] — 2026-05-11

### Added
- **Dockerfile**: multi-stage build pinned to `duckdb/duckdb:1.5.2`, pre-installs `httpfs` and `mysql` extensions at build time, runs as non-root (`USER 1000:1000`).
- **`build-image.yaml` workflow**: builds and pushes container images to GHCR on `main` push (tags `:edge`) and on version tags (`:v0.5.x-duckdb152`).
- **`just bump-version`**: updates `Chart.yaml` version/appVersion and `Dockerfile` ARG in one command.
- **`just docker-build` / `docker-build-release`**: multi-arch buildx commands with auto-derived image tags from chart metadata.
- **`_helpers.tpl`**: `harvest-consultations.harvestImageTag` template computes image tag from chart version + DuckDB short version.

### Changed
- **Removed `INSTALL httpfs; INSTALL mysql;`** from `harvest.sql`: extensions now pre-installed in the Docker image, so the pipeline skips install at runtime (tightens `autoinstall_known_extensions = false` lock-down).
- **Removed `HOME=/tmp` env and `duckdb-extensions` emptyDir volume** from cronjob: extensions no longer need writable storage at runtime.
- **Removed `just run`** (local DuckDB execution); pipeline now runs exclusively in-cluster.
- **Image tag auto-derived**: `cronjob.yaml` uses `harvestImageTag` helper instead of a hardcoded `.Values.harvest.image.tag`.
- **`just helm-package`** now accepts a `version` parameter, used by release workflow.
- **Release workflow**: uses `just helm-package` instead of inline `sed` + `helm package`.
- **Removed manual `just` install** from CI workflows; `just` is now provided by `mise`.

## [0.5.3] — 2026-05-11

### Changed
- **Output schema simplified**: dropped `id` and `loaded_at` columns from `consultations_final`. Column order changed to `source, name, description, status, agency, tags, region, url, publishdate, expirydate` (10 columns). `tags` moved after `agency`.
- **Templated target table**: `configmap.yaml` switched from raw `.Files.Get` to `tpl (.Files.Get …)`, enabling `{{ .Values.mysql.table }}` in `harvest.sql`. The MySQL mirror table is now configurable via `mysql.table` (default: `consultations`).
- **CI triggers**: `ci-nightly.yaml` now also runs on push to `main` (previously only cron + manual dispatch).
- **`justfile` cleanup**: removed local `run` target, parameterized `mysql.table`, switched from hardcoded `helmHost` to `mysqlHost`.

## [0.5.0] — 2026-05-09

### Security
- **9 security hardening fixes**:
  - Container runs as non-root (`runAsUser: 1000`, `runAsGroup: 1000`)
  - Read-only root filesystem (`readOnlyRootFilesystem: true`)
  - Seccomp profile set to `RuntimeDefault`
  - All capabilities dropped (`drop: ["ALL"]`)
  - Community extensions locked (`allow_community_extensions = false`)
  - Auto-install/autoload disabled (`autoinstall_known_extensions = false`, `autoload_known_extensions = false`)
  - HTTP logging disabled (`enable_http_logging = false`)
  - Unredacted secrets disabled (`allow_unredacted_secrets = false`)
  - ETag checks disabled for EngagementHQ pages (`unsafe_disable_etag_checks = true`)

## [0.4.5] — 2026-05-09

### Changed
- **Complete rewrite**: replaced Python/SQLMesh/uv harvest pipeline with a pure DuckDB SQL pipeline packaged as a Helm chart.
- HTTP fetch and JWT token extraction done entirely in SQL via DuckDB `httpfs` extension.
- Added CI/CD workflows for nightly end-to-end tests and Helm chart releases.
