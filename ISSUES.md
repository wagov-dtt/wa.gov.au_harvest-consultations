# Audit Issues

> Generated with [oy-cli](https://github.com/wagov-dtt/oy-cli): `OY_MODEL=opencode-go/deepseek-v4-pro oy audit` · 2026-05-11

## Findings summary

| # | Severity | Title | Status | Reference |
|---|---|---|---|---|
| 1 | High | SQL injection via Helm value `mysql.table` in SQL template | **Accepted** | `chart/harvest.sql:243`, `chart/templates/configmap.yaml:10` |
| 2 | High | Missing Secret template `mariadb-credentials` — chart broken | **Regressed** | `chart/templates/statefulset.yaml:39,47,52`; `cronjob.yaml:44,49` |
| 3 | Medium | Default weak MariaDB credentials (`harvest`/`harvest`) | **New** | `chart/values.yaml:9-11` |

> All previously reported issues #2–9 from ISFSMS.md remain resolved; only the Secret template (#1 originally) has regressed.

## Detailed findings

### 1. SQL injection via Helm template `mysql.table` value (High)

**Category:** V5 Validation — Injection (CWE-89)  
**Trust boundary:** Helm values supplied at `helm install` / `--set` or via `values.yaml` (operator-controlled, potentially from CI or external configs).  
**Sink:** `chart/harvest.sql` line 243, rendered through `tpl` in `chart/templates/configmap.yaml:10`.  

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

**Evidence:**  
The chart defines credential values in `chart/values.yaml` (`mariadb.rootPassword`, `mariadb.user`, `mariadb.password`), and both the StatefulSet (`chart/templates/statefulset.yaml` lines 39, 47, 52) and the CronJob (`chart/templates/cronjob.yaml` lines 44, 49) reference a Kubernetes Secret named `mariadb-credentials`. No Secret template exists in the chart (`chart/templates/secret.yaml` is absent from the repository contents).  

**Impact:**  
Any attempt to install the chart will result in pod errors (`CreateContainerConfigError`) because the required Secret is missing. The chart is unusable without manual intervention, defeating its purpose as a self-contained deployment.

**Preconditions:**  
None — the chart fails to deploy immediately with default values (as shown in the README commands).

**Fix:**  
Add a `chart/templates/secret.yaml` with content similar to:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mariadb-credentials
type: Opaque
stringData:
  MARIADB_ROOT_PASSWORD: {{ .Values.mariadb.rootPassword | quote }}
  MARIADB_USER: {{ .Values.mariadb.user | quote }}
  MARIADB_PASSWORD: {{ .Values.mariadb.password | quote }}
```

### 3. Default weak MariaDB credentials (Medium)

**Category:** V2 Authentication — Weak credentials; V14 Configuration — Insecure defaults (CWE-521, CWE-1392)

**Evidence:**  
In `chart/values.yaml`, the entries `mariadb.rootPassword`, `mariadb.user`, and `mariadb.password` are all set to the literal string `harvest`. The NetworkPolicy is disabled by default (`networkPolicy.enabled: false`), meaning the database is accessible from any pod in the cluster with these well-known credentials.

**Impact:**  
If a deployment uses the defaults (e.g., an automated pipeline that neglects to override them), an attacker who gains a foothold in the cluster (any pod) can connect to MariaDB as `harvest`/`harvest` and exfiltrate or destroy the consultation data.

**Preconditions:**  
The chart is installed with default values, a likely accidental scenario for users who skip reading the “override for production” note.

**Fix:**  
- Enforce that credentials must be provided by using `required` in the Secret template:  
  `{{ required "mariadb.password is required" .Values.mariadb.password }}`  
- Or generate strong random passwords at install time (e.g., with `randAlphaNum`) and store them in the Secret.  
- At minimum, set the defaults to empty strings so the deployment fails clearly rather than running with weak credentials.
