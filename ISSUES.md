# Audit Issues

> Generated with [oy-cli](https://github.com/wagov-dtt/oy-cli): `OY_MODEL=github-copilot/gpt-5.5 oy audit` · 2026-05-08

## Findings summary

> Updated 2026-05-08: low-risk fixes were applied where they do not require production deployment redesign or major operator workflow changes.

| Status | Severity | Finding | Code reference |
| --- | --- | --- | --- |
| Open | High | DB connections are not TLS-enforced and default to root while executing destructive DDL | `harvest.php::connect_mysql`, `harvest.php::export_final` |
| Partial | High | Portal fetching permits arbitrary HTTPS hosts and unvalidated redirects, enabling SSRF/token leakage from the CronJob network | `harvest.php::is_https_url`, `harvest.php::http_get` |
| Partial | Medium | `.k8s.env` writes DB secrets into the repo workspace and is not cleaned up on failed `just ci-dump` dependency steps | `justfile::_local-env`, `justfile::ci-dump` |
| Fixed | Medium | External API responses are read and decoded without size limits, allowing a portal to OOM/fail the nightly job | `harvest.php::http_get`, `harvest.php::http_json` |
| Fixed | Medium | API-controlled record URLs are published without scheme/host validation | `harvest.php::validated_record_url` |
| Fixed | Medium | Source Kubernetes manifest uses a mutable untagged runtime image | `k8s/base/cronjob.yaml` |
| Fixed | Low | Environment parsing mutates secret values by trimming leading/trailing quote characters | `harvest.php::env_value`, `justfile::_local-env` |
| Fixed | Low | DB password defaults allow empty/`secret` credentials despite docs marking the value required | `harvest.php::db_password`, `justfile::_local-env`, `example.env` |

## Detailed findings

### 1. DB connections are not TLS-enforced and default to root while executing destructive DDL

**Status:** Open. Not changed in this pass because requiring DB TLS, removing root defaults, or removing runtime database creation/DDL would require production deployment changes and could break existing local/CI flows.

**Category:** ASVS V9 Communications, V4 Access Control, V14 Configuration

**Original evidence:**

- `harvest.php::config` defaults the DB user to `root` and reads `DB_PASSWORD` directly from env.
- `harvest.php::connect_mysql` builds only `mysql:host=%s;port=%s;charset=utf8mb4...`; no `PDO::MYSQL_ATTR_SSL_*` options, CA, or server verification are configured.
- `harvest.php::export_final` drops, creates, renames, and deletes tables.
- `sql/harvest.sql` includes `DROP TABLE IF EXISTS {{table}}`, `CREATE TABLE {{table}}`, and `RENAME TABLE {{table}} TO {{old_table}}, {{new_table}} TO {{table}}`.

**Trust boundary / sink:** CronJob/container environment and network → MySQL/MariaDB server via PDO; sink is authenticated DDL/DML against the configured database.

**Impact:** If `DB_HOST` points to a remote DB or hostile cluster network segment and the server does not independently require TLS, harvested data and DDL traffic are not protected by this client. There is also no DB server identity check. Because the default user is root and the app performs destructive DDL, a DB credential or connection compromise has full-table/database blast radius, not just write access to the exported table.

**Exploitability / preconditions:** Requires network position between the CronJob and DB, a malicious DB endpoint, or DB service misrouting; impact is highest when production uses the documented/default root user.

**Fix:**

- Require TLS for non-local DB hosts and fail closed if CA/server verification is not configured.
- Add explicit PDO SSL options from env/config, e.g. CA/cert/key paths.
- Stop defaulting production to `root`; use a dedicated DB user scoped to one database/schema.
- Prefer pre-creating the database in production and removing `CREATE DATABASE`/root requirements from the runtime path.

---

### 2. Portal fetching permits arbitrary HTTPS hosts and unvalidated redirects, enabling SSRF/token leakage from the CronJob network

**Status:** Partially fixed. HTTP redirects are disabled, portal/request URLs must be public HTTPS, and localhost/private IP literals plus internal hostname suffixes are rejected. Exact portal host allowlists and DNS resolved-address enforcement remain open to avoid breaking unknown legitimate portal hosts without operator input.

**Category:** ASVS V5 Validation / SSRF, V9 Communications

**Original evidence:**

- `harvest.php::is_https_url` only checks `scheme === https` and non-empty `host`.
- `harvest.php::parse_portals` accepts any host in `PORTALS_JSON` for the allowed source names.
- `harvest.php::http_get` calls `file_get_contents($url, false, $context)` without disabling redirects or validating the final URL.
- `harvest.php:227` sends `Authorization: Bearer $token` to the EngagementHQ API URL.

**Trust boundary / sink:** `PORTALS_JSON` and remote portal redirect responses → outbound HTTP client running inside the Kubernetes CronJob network.

**Impact:** A party that can modify `PORTALS_JSON`, compromise a configured portal, or abuse an open redirect can make the CronJob connect to internal HTTPS services reachable from the cluster. For EngagementHQ, PHP stream headers are applied through redirects unless explicitly controlled, so the scraped bearer token can be sent to a redirected host.

**Exploitability / preconditions:** Requires control over portal config or a configured portal/redirect response. The initial URL must pass the current HTTPS check; redirects are not constrained by the application.

**Fix:**

- Allowlist exact expected portal hostnames or approved suffixes per source.
- Reject loopback, link-local, private, and cluster-internal resolved addresses.
- Set `follow_location`/redirect following off in the stream context, or switch to cURL with protocol and redirect restrictions.
- If redirects are required, manually validate each redirect target and drop `Authorization` on any host change.

---

### 3. `.k8s.env` writes DB secrets into the repo workspace and is not cleaned up on failed `just ci-dump` dependency steps

**Status:** Partially fixed. `just ci-dump` now registers cleanup before build/deploy/job work starts, `.env` and `.k8s.env` are ignored, and missing local DB passwords are random. The local kustomize overlays still use a stable `.k8s.env` file.

**Category:** ASVS V6 Secret Management, V8 Data Protection, V14 Configuration

**Original evidence:**

- `justfile:38-58` recipe `_local-env` writes `.k8s.env` in the repository root.
- `justfile:53` writes `DB_PASSWORD=%s`.
- `justfile:194` defines `ci-dump` with dependencies: `build _deploy-db _wait-db _run-job _dump-db verify-dump`.
- `justfile:195` removes `.k8s.env` only in the `ci-dump` recipe body, which does not run if any dependency fails.
- Current note: `.gitignore` includes `.env` and `.k8s.env`; the remaining issue is the stable repo-root plaintext file while local kustomize commands are running.

**Trust boundary / sink:** Local or CI environment secrets → plaintext file in the source checkout.

**Impact:** A failed build/deploy/job leaves DB credentials and portal configuration in `.k8s.env`. On developer machines this is easy to accidentally commit. In CI, it remains in the workspace after failed dependency steps and can be picked up by broad artifact/debug collection.

**Exploitability / preconditions:** Run `just _local-env` directly or run `just ci-dump` where any dependency fails before line 195.

**Fix:**

- Do not write generated secrets to a stable repo-root filename.
- Use `mktemp`, pass that path into kustomize, and `trap` cleanup in the same shell process that creates it.
- Add `.env`, `.k8s.env`, and generated secret files to `.gitignore`.
- Restructure `ci-dump` so cleanup is registered before build/deploy/job work starts, not after dependency completion.

---

### 4. External API responses are read and decoded without size limits, allowing a portal to OOM/fail the nightly job

**Status:** Fixed. `http_get` enforces `MAX_HTTP_RESPONSE_BYTES` (default 10 MiB) using `Content-Length` when present and a hard stream read cap before JSON decoding.

**Category:** ASVS V12 Files/Resources, V13 API

**Original evidence:**

- `harvest.php::http_get` reads the whole response body with `file_get_contents`.
- `harvest.php::http_json` decodes the whole body with `json_decode`.
- `harvest.php:227` requests EngagementHQ projects with `per_page=10000`.
- `k8s/base/cronjob.yaml:32-37` caps the harvest container at `1Gi` memory.

**Trust boundary / sink:** External portal HTTP responses → PHP heap / JSON decoder / DB insert path.

**Impact:** A compromised, misconfigured, or malicious configured portal can return a very large body and cause PHP memory exhaustion. That fails the CronJob and prevents the nightly SQL artifact from being produced.

**Exploitability / preconditions:** Attacker controls a configured portal response, a redirect target, or a misconfigured portal URL.

**Fix:**

- Enforce a maximum response size before decoding JSON.
- Check `Content-Length` when present, but also enforce a hard read cap while streaming.
- Page API requests instead of requesting 10,000 records at once.
- Apply per-field length limits before inserting into MySQL `TEXT` columns.

---

### 5. API-controlled record URLs are published without scheme/host validation

**Status:** Fixed. API-provided record URLs are now normalized only when they are HTTPS on the configured portal host/port; invalid or cross-host values fall back to the validated portal URL.

**Category:** ASVS V5 Validation, data integrity

**Original evidence:**

- `harvest.php:237` sets EngagementHQ `$recordUrl` from `$links['self'] ?? $row['url'] ?? $url`.
- `harvest.php:275` sets CitizenSpace `$recordUrl` from `$row['url']`.
- Those values are inserted into the stage table and exported.
- `sql/harvest.sql:192` defines final `url TEXT NOT NULL`; no SQL-side scheme/host validation exists.

**Trust boundary / sink:** External portal API payloads → final MySQL table and `dist/sql.tar.gz` artifact.

**Impact:** A portal can publish `javascript:`, `data:`, phishing, or internal URLs into the normalized dataset. Any downstream consumer that renders the `url` as a link inherits that unsafe value.

**Exploitability / preconditions:** Requires a compromised/buggy portal API response or hostile configured endpoint.

**Fix:**

- Validate response record URLs before insert/export.
- Require HTTPS.
- Require the record URL host to match the configured portal host or a source-specific allowlist.
- If invalid, either drop the row or replace with the validated base portal URL.

---

### 6. Source Kubernetes manifest uses a mutable untagged runtime image

**Status:** Fixed. The source CronJob image is pinned to the current release tag (`0.4.2`); local overlays still override it to `harvest-consultations:test`.

**Category:** ASVS V10 Supply Chain, V14 Configuration

**Original evidence:**

- `k8s/base/cronjob.yaml:25-26` uses `image: ghcr.io/wagov-dtt/harvest-consultations` with no tag or digest.
- `k8s/base/cronjob.yaml:26` uses `imagePullPolicy: IfNotPresent`.
- `k8s/public/kustomization.yaml` consumes the same base CronJob.

**Trust boundary / sink:** Container registry → Kubernetes image resolution and node cache.

**Impact:** Raw kustomize/base deployments resolve a mutable image tag, effectively `latest`. Different nodes or deployment times can run different code. If the mutable tag is overwritten or compromised, the CronJob can execute unexpected code with DB credentials from `harvest-env`.

**Exploitability / preconditions:** Requires use of the raw manifests or generated output that preserves the mutable image, plus registry write compromise/mistagging or node cache divergence.

**Fix:**

- Pin the source manifest to an immutable semver tag or digest.
- Prefer digest pinning for production chart defaults.
- Keep local overlays overriding to `harvest-consultations:test` only for kind/local use.

---

### 7. Environment parsing mutates secret values by trimming leading/trailing quote characters

**Status:** Fixed. PHP runtime env values are now treated as opaque strings. The local justfile strips only one matching quote pair for compatibility on non-secret convenience values and never strips `DB_PASSWORD`.

**Category:** ASVS V2 Credential Handling, V14 Configuration

**Original evidence:**

- `harvest.php::env_value` returns `trim(..., "'\"")` for every env key, including `DB_PASSWORD`.
- `justfile:41-44` `_local-env` also strips leading/trailing single and double quotes.

**Trust boundary / sink:** Environment/Secret values → runtime configuration and DB authentication.

**Impact:** Secrets are not treated as opaque bytes/strings. A valid DB password beginning or ending with `'` or `"` is silently changed before PDO authentication. This can break production after a password rotation and makes the actual credential used by the app differ from the configured Kubernetes Secret.

**Exploitability / preconditions:** Operator uses a generated password with leading/trailing quote characters or a portal value where those characters are meaningful.

**Fix:**

- Do not trim quotes in the PHP runtime config path.
- Let dotenv tooling handle quoted `.env` syntax before values enter the process.
- If local compatibility is still needed, strip only one matching quote pair in the justfile and never for `DB_PASSWORD`.

---

### 8. DB password defaults allow empty/`secret` credentials despite docs marking the value required

**Status:** Fixed. Runtime config rejects empty `DB_PASSWORD` and the example placeholder, local kustomize generation creates a random disposable password when unset, and docs/examples no longer use `secret`.

**Category:** ASVS V14 Configuration

**Original evidence:**

- `harvest.php:16` reads `DB_PASSWORD` with no required/non-empty validation; default is empty.
- `justfile:53` emits `DB_PASSWORD=secret` when unset.
- `example.env:2` contains `DB_PASSWORD='secret'`.
- `README.md` marks `DB_PASSWORD` as required but lists default `empty`.

**Trust boundary / sink:** Missing or copied configuration → DB root authentication and Kubernetes Secret generation.

**Impact:** The repo has executable paths that run with an empty DB password or the literal password `secret`. If copied into a real environment, this weakens the DB credential protecting the harvested database and any co-located data reachable by the configured DB user.

**Exploitability / preconditions:** Operator omits `DB_PASSWORD`, uses `_local-env` defaults, or copies `example.env` without changing the password.

**Fix:**

- Fail startup if `DB_PASSWORD` is empty.
- Generate a random local-only password for kind instead of hardcoding `secret`.
- Make `example.env` use a placeholder that cannot run unchanged, e.g. `DB_PASSWORD='<set-a-real-password>'`, and reject that sentinel at runtime.
