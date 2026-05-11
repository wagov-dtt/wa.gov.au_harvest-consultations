# Audit Issues

> Generated with [oy-cli](https://github.com/wagov-dtt/oy-cli): `OY_MODEL=opencode-go/deepseek-v4-pro oy audit` · 2026-05-11

## Findings summary

| # | Severity | Title | Status | Reference |
|---|---|---|---|---|
| 1 | High | SQL injection via Helm value `mysql.table` in SQL template | **Accepted** | `chart/harvest.sql`, `chart/templates/configmap.yaml` |
| 2 | High | Missing Secret template `mariadb-credentials` — chart broken | **Resolved** — `chart/templates/secret.yaml` present | `chart/templates/secret.yaml` |
| 3 | Medium | Default weak MariaDB credentials (`harvest`/`harvest`) | **Documented** — override for production | `README.md`, `chart/values.yaml:9-11` |

> Previously reported hardening issues remain resolved. Current accepted/documented risks are trusted Helm values and development-only default credentials.

## Detailed findings

### 1. SQL injection via Helm template `mysql.table` value (High)

**Category:** V5 Validation — Injection (CWE-89)  
**Trust boundary:** Helm values supplied at `helm install` / `--set` or via `values.yaml` (operator-controlled, potentially from CI or external configs).  
**Sink:** `chart/harvest.sql`, rendered through `tpl` in `chart/templates/configmap.yaml`.  

**Evidence:**  
The SQL file contains:
```sql
CREATE OR REPLACE TABLE mysqldb.{{ .Values.mysql.table }} AS
SELECT * FROM consultations_final;
```
The value is interpolated without any escaping or validation. Because the file is processed as a Helm template, an attacker who can influence the chart’s values can inject arbitrary SQL.

**Exploit example:**  
```bash
helm install harvest ./chart --set mysql.table="consultations; DROP DATABASE; --"
```
This results in the DuckDB process executing:
```sql
CREATE OR REPLACE TABLE mysqldb.consultations; DROP DATABASE; -- AS SELECT * FROM consultations_final;
```

**Impact:**  
Arbitrary SQL execution on the linked MariaDB server. An attacker could read, modify, delete data, escalate privileges, or compromise the entire database.

**Preconditions:**  
The attacker must control the Helm values (e.g., through a compromised CI pipeline, a tampered `values.yaml` in a shared repository, or an operator who blindly accepts user input for the table name). The chart is publicly available, and many deployment flows pass `--set` arguments from external systems.

**Risk acceptance:**  
The Helm template risk is accepted. Chart installers (`helm install`, `--set`) are trusted operators within the deployment boundary. An attacker who can influence Helm values already has sufficient access to compromise the cluster directly. The template rendering executes with the same trust as the operator who invokes it.

### 2. Missing Secret template for MariaDB credentials (High)

**Category:** V14 Configuration — Missing security resource  
**Status:** Resolved. `chart/templates/secret.yaml` exists and renders the `mariadb-credentials` Secret used by the StatefulSet and CronJob.

**Verification:**
```bash
helm template harvest chart | grep -A8 'name: mariadb-credentials'
```

### 3. Default weak MariaDB credentials (Medium)

**Category:** V2 Authentication — Weak credentials; V14 Configuration — Insecure defaults (CWE-521, CWE-1392)

**Evidence:**  
In `chart/values.yaml`, the bundled MariaDB defaults (`mariadb.rootPassword`, `mariadb.user`, and `mariadb.password`) are all set to the literal string `harvest`. When the bundled database is enabled, the NetworkPolicy is disabled by default (`networkPolicy.enabled: false`), meaning MariaDB is accessible from any pod in the cluster with these well-known credentials.

**Impact:**  
If a deployment uses the defaults (e.g., an automated pipeline that neglects to override them), an attacker who gains a foothold in the cluster (any pod) can connect to MariaDB as `harvest`/`harvest` and exfiltrate or destroy the consultation data.

**Preconditions:**  
The chart is installed with default values, a likely accidental scenario for users who skip reading the “override for production” note.

**Fix:**  
- For production, set `mariadb.enabled=false` and point `mysql.host` at an externally managed database.  
- Always override `mariadb.user` and `mariadb.password` for production/external databases.  
- A future hardening change could enforce non-empty credentials with `required` or generate strong random install-time passwords.
