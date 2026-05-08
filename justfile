set dotenv-load

app_version := `cat VERSION`
image := "harvest-consultations"
cluster := "harvest-consultations"
namespace := "harvest"
dump_dir := "dist"
dump_file := "sql.tar.gz"
generated_chart := "dist/helm/harvest-consultations"
kind_node_image := "kindest/node:v1.35.1"

# List commands
default:
  @just --list

# Fast local checks: PHP syntax, chart render, image build
test:
  docker run --rm -v "$PWD:/app" -w /app php:8.4-cli-trixie php -l harvest.php

check: test chart-test build

# Build container image
build:
  docker build -t {{image}}:test .

# Create/reuse the local kind cluster
cluster-up:
  @kind get clusters | grep -qx '{{cluster}}' || kind create cluster --name {{cluster}} --image {{kind_node_image}} --wait 5m
  kubectl config use-context kind-{{cluster}}
  kubectl wait --for=condition=Ready nodes --all --timeout=5m
  -kubectl taint nodes --all node-role.kubernetes.io/control-plane- >/dev/null 2>&1

# Delete local Kubernetes namespace state but keep the kind cluster
cluster-reset: cluster-up
  -kubectl delete namespace {{namespace}} --ignore-not-found=true --wait=true

# Generate sanitized env file for kustomize secretGenerator
local-env:
  #!/usr/bin/env bash
  set -euo pipefail
  clean() {
    local value="${1:-}"
    value="${value#\'}"; value="${value%\'}"
    value="${value#\"}"; value="${value%\"}"
    printf '%s' "$value"
  }
  {
    portals="$(clean "${PORTALS_JSON:-{}}")"
    portals="${portals//\\\\\"/\"}"
    portals="${portals//\\\"/\"}"
    printf 'PORTALS_JSON=%s\n' "$portals"
    printf 'DB_PASSWORD=%s\n' "$(clean "${DB_PASSWORD:-secret}")"
    printf 'DB_NAME=%s\n' "$(clean "${DB_NAME:-harvest_consultations}")"
    printf 'DB_TABLE=%s\n' "$(clean "${DB_TABLE:-consultations}")"
    printf 'DB_PORT=%s\n' "$(clean "${DB_PORT:-3306}")"
    if [[ -n "${DB_USER:-}" ]]; then printf 'DB_USER=%s\n' "$(clean "$DB_USER")"; fi
  } > .k8s.env

# Load the locally built harvest image into kind
load-image: cluster-up
  kind load docker-image {{image}}:test --name {{cluster}}

# Deploy local/CI database resources and wait for MariaDB without running the harvest Job
cluster-smoke: build deploy-db wait-db
  @echo "kind cluster, image import, kustomize apply, and MariaDB readiness passed"

# Apply local DB-only kustomize overlay with fresh namespace state
deploy-db: local-env cluster-reset load-image
  kustomize build --load-restrictor LoadRestrictionsNone k8s/local-db | kubectl apply -f -

# Apply the full local overlay and run a one-shot Job from the CronJob template
deploy-local: deploy-db wait-db run-job

# Wait until the local MariaDB pod accepts SQL connections
wait-db:
  #!/usr/bin/env bash
  set -euo pipefail
  kubectl -n {{namespace}} rollout status statefulset/mariadb --timeout=3m
  kubectl -n {{namespace}} wait --for=condition=ready pod/mariadb-0 --timeout=5m
  deadline=$((SECONDS + 120))
  until kubectl -n {{namespace}} exec pod/mariadb-0 -- \
    sh -ceu 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -e "SELECT 1" >/dev/null'; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for MariaDB SQL login" >&2
      just dump-debug
      exit 1
    fi
    sleep 2
  done

# Run/re-run the local harvest Job after MariaDB is ready
run-job:
  #!/usr/bin/env bash
  set -euo pipefail
  kubectl -n {{namespace}} delete job harvest-run --ignore-not-found=true --wait=true
  kustomize build --load-restrictor LoadRestrictionsNone k8s/local | kubectl apply -f -
  kubectl -n {{namespace}} create job harvest-run --from=cronjob/harvest-consultations
  just wait-job

# Wait for the harvest Job and print diagnostics on failure
wait-job:
  #!/usr/bin/env bash
  set -euo pipefail
  deadline=$((SECONDS + 1200))
  last_report=0
  while true; do
    succeeded="$(kubectl -n {{namespace}} get job harvest-run -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
    failed="$(kubectl -n {{namespace}} get job harvest-run -o jsonpath='{.status.failed}' 2>/dev/null || true)"
    active="$(kubectl -n {{namespace}} get job harvest-run -o jsonpath='{.status.active}' 2>/dev/null || true)"
    succeeded="${succeeded:-0}"
    failed="${failed:-0}"
    active="${active:-0}"

    if [[ "$succeeded" != "0" ]]; then
      kubectl -n {{namespace}} logs job/harvest-run --all-containers=true --tail=-1
      exit 0
    fi
    if [[ "$failed" != "0" ]]; then
      echo "Harvest job failed" >&2
      just dump-debug
      exit 1
    fi
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for harvest job completion" >&2
      just dump-debug
      exit 1
    fi
    if (( SECONDS - last_report >= 30 )); then
      echo "harvest-run status: active=${active} succeeded=${succeeded} failed=${failed}"
      kubectl -n {{namespace}} get pods -l job-name=harvest-run || true
      last_report=$SECONDS
    fi
    sleep 5
  done

# Print local kind/Kubernetes diagnostics
dump-debug:
  #!/usr/bin/env bash
  set +e
  echo "\n--- diagnostics ---" >&2
  kubectl -n {{namespace}} get pods,jobs,statefulsets,services
  kubectl -n {{namespace}} get events --sort-by=.lastTimestamp | tail -50
  kubectl -n {{namespace}} describe pod mariadb-0
  kubectl -n {{namespace}} describe cronjob harvest-consultations
  kubectl -n {{namespace}} describe job harvest-run
  kubectl -n {{namespace}} logs job/harvest-run --all-containers=true --tail=-1
  echo "--- end diagnostics ---" >&2

# Dump MariaDB to dist/sql.tar.gz and verify restore/readback
dump-db:
  #!/usr/bin/env bash
  set -euo pipefail
  db_name="${DB_NAME:-harvest_consultations}"
  db_table="${DB_TABLE:-consultations}"

  mkdir -p {{dump_dir}}
  kubectl -n {{namespace}} exec pod/mariadb-0 -- \
    env DB_NAME="$db_name" sh -ceu '
      export MYSQL_PWD="$MARIADB_ROOT_PASSWORD"
      mariadb-dump \
        -uroot \
        --single-transaction \
        --routines \
        --triggers \
        --databases "$DB_NAME" \
        > /tmp/sql.sql
      test -s /tmp/sql.sql
    '

  kubectl -n {{namespace}} cp {{namespace}}/mariadb-0:/tmp/sql.sql {{dump_dir}}/sql.sql
  test -s {{dump_dir}}/sql.sql
  grep -q "CREATE DATABASE" {{dump_dir}}/sql.sql
  grep -q "CREATE TABLE" {{dump_dir}}/sql.sql
  grep -q "\`$db_table\`" {{dump_dir}}/sql.sql

  kubectl -n {{namespace}} cp {{dump_dir}}/sql.sql {{namespace}}/mariadb-0:/tmp/verify.sql
  kubectl -n {{namespace}} exec pod/mariadb-0 -- \
    env DB_NAME="$db_name" sh -ceu '
      export MYSQL_PWD="$MARIADB_ROOT_PASSWORD"
      mariadb -uroot -e "DROP DATABASE IF EXISTS \`$DB_NAME\`"
      mariadb -uroot < /tmp/verify.sql
    '
  row_count="$(kubectl -n {{namespace}} exec pod/mariadb-0 -- \
    env DB_NAME="$db_name" TABLE_NAME="$db_table" sh -ceu \
    'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -Nse "SELECT COUNT(*) FROM \`$DB_NAME\`.\`$TABLE_NAME\`"')"
  test "${row_count}" -gt 0

  tar -C {{dump_dir}} -czf {{dump_dir}}/{{dump_file}} sql.sql
  rm {{dump_dir}}/sql.sql
  echo "wrote {{dump_dir}}/{{dump_file}} (${row_count} rows)"

# Build current consultations data in kind and write dist/sql.tar.gz
ci-dump: build deploy-db wait-db run-job dump-db verify-dump
  rm -f .k8s.env

# Verify the SQL dump artifact has the expected mysqldump content
verify-dump:
  #!/usr/bin/env bash
  set -euo pipefail
  db_table="${DB_TABLE:-consultations}"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT

  tar -tzf {{dump_dir}}/{{dump_file}} | grep -qx 'sql.sql'
  tar -xOf {{dump_dir}}/{{dump_file}} sql.sql > "$tmp"
  grep -q 'CREATE DATABASE' "$tmp"
  grep -q 'CREATE TABLE' "$tmp"
  grep -q "\`$db_table\`" "$tmp"

# Generate public Helm chart from kustomize output
helmify:
  #!/usr/bin/env bash
  set -euo pipefail
  rm -rf {{generated_chart}}
  mkdir -p "$(dirname {{generated_chart}})"
  kustomize build --load-restrictor LoadRestrictionsNone k8s/public \
    | sed -E 's#ghcr.io/wagov-dtt/harvest-consultations(:[^[:space:]]*)?#ghcr.io/wagov-dtt/harvest-consultations:{{app_version}}#' \
    | helmify -original-name {{generated_chart}}
  cat > {{generated_chart}}/Chart.yaml <<'CHART'
  apiVersion: v2
  name: harvest-consultations
  description: Harvest WA Gov consultations into MySQL/MariaDB
  type: application
  version: {{app_version}}
  appVersion: "{{app_version}}"
  CHART

# Lint/render the generated Helm chart
chart-test: helmify
  helm lint {{generated_chart}}
  helm template harvest-consultations {{generated_chart}} >/dev/null

# Stop services
clean:
  -kind delete cluster --name {{cluster}} 2>/dev/null
  -rm -f .k8s.env
  -rm -rf dist/helm
