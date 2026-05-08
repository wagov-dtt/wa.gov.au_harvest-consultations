ns := "harvest-consultations"

default:
  just --choose

clean:
  kind delete cluster --name harvest || true
  rm -rf deploy/helm dist

# Copy harvest.sql into kustomize tree (required by configMapGenerator)
_sync:
  cp harvest.sql deploy/kustomize/harvest.sql

# Start local k8s cluster with kind
kind-up: _sync
  kind get clusters | grep -q harvest || kind create cluster --name harvest
  kubectl apply -k deploy/kustomize

# Forward mariadb from k8s cluster
mariadb-svc: kind-up
  ss -ltpn | grep 3306 || kubectl port-forward service/mariadb 3306:3306 -n {{ns}} & sleep 1

# Run the DuckDB pipeline locally (expects MYSQL_* env vars or mariadb-svc)
run:
  duckdb -c ".read harvest.sql"

# Create a one-off test job in the cluster
test: kind-up
  kubectl delete job test -n {{ns}} --ignore-not-found
  kubectl create job test --from cronjob/harvest-cronjob -n {{ns}}

# Generate helm chart from kustomize
helm-generate: _sync
  rm -rf deploy/helm
  mkdir -p deploy/helm
  kustomize build deploy/kustomize | helmify deploy/helm/harvest-consultations
  @echo "Chart generated at deploy/helm/harvest-consultations"

# Install/upgrade helm chart (generates chart first)
helm-install: helm-generate
  helm upgrade --install harvest deploy/helm/harvest-consultations \
    --namespace {{ns}} --create-namespace

# Package helm chart
helm-package: helm-generate
  mkdir -p dist
  helm package deploy/helm/harvest-consultations -d dist/

# === CI / nightly validation ===

# Full end-to-end test: kind cluster → helm deploy → run job → dump → validate
# Designed to run in GitHub Actions (just ci-test)
ci-test:
  #!/usr/bin/env bash
  set -euo pipefail
  echo "=== CI: starting kind cluster ==="
  kind get clusters | grep -q harvest || kind create cluster --name harvest

  echo "=== CI: generating helm chart ==="
  just helm-generate

  echo "=== CI: installing helm chart ==="
  just helm-install

  echo "=== CI: waiting for MariaDB ==="
  kubectl wait --for=condition=ready pod -l app=mariadb -n {{ns}} --timeout=120s

  echo "=== CI: triggering harvest job ==="
  kubectl delete job ci-harvest -n {{ns}} --ignore-not-found
  kubectl create job ci-harvest --from cronjob/harvest-harvest-consultations-harvest-cronjob -n {{ns}}

  echo "=== CI: waiting for job to complete ==="
  kubectl wait --for=condition=complete job/ci-harvest -n {{ns}} --timeout=300s || {
    echo "Job failed — pod logs:"
    kubectl logs -l app=harvest-cronjob -n {{ns}} --tail=50
    exit 1
  }

  echo "=== CI: dumping consultations table ==="
  POD=$(kubectl get pod -l app=mariadb -n {{ns}} -o jsonpath='{.items[0].metadata.name}')
  mkdir -p dist
  kubectl exec -n {{ns}} "$POD" -- \
    mariadb-dump -uroot -pharvest harvest consultations \
    | gzip > dist/consultations.sql.gz

  echo "=== CI: validating dump ==="
  gunzip -c dist/consultations.sql.gz | head -20
  ROWS=$(gunzip -c dist/consultations.sql.gz | grep -c 'INSERT INTO' || echo 0)
  echo "Rows found: $ROWS"
  if [ "$ROWS" -eq 0 ]; then
    echo "ERROR: dump contains no INSERT statements"
    exit 1
  fi
  echo "=== CI: PASSED ==="
