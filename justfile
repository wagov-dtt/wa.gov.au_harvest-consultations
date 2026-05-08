ns := "harvest-consultations"

default:
  just --choose

clean:
  kind delete cluster --name harvest || true
  rm -rf deploy/helm dist

# Start local k8s cluster with kind
kind-up:
  kind get clusters | grep -q harvest || kind create cluster --name harvest
  kubectl apply -k deploy/kustomize

# Forward mariadb from k8s cluster
mariadb-svc: kind-up
  ss -ltpn | grep 3306 || kubectl port-forward service/mariadb 3306:3306 -n {{ns}} & sleep 1

# Run the DuckDB pipeline locally
run:
  duckdb -c ".read deploy/kustomize/harvest.sql"

# Create a one-off test job in the cluster
test: kind-up
  kubectl delete job test -n {{ns}} --ignore-not-found
  kubectl create job test --from cronjob/harvest-cronjob -n {{ns}}

# Generate helm chart from kustomize
helm-generate:
  rm -rf deploy/helm
  mkdir -p deploy/helm
  kustomize build deploy/kustomize | helmify deploy/helm/harvest-consultations
  @echo "Chart generated at deploy/helm/harvest-consultations"

# Install/upgrade helm chart (generates chart first)
helm-install: helm-generate
  helm upgrade --install harvest deploy/helm/harvest-consultations \
    --namespace {{ns}} --create-namespace \
    --set harvestCronjob.harvest.env.mysqlHost=harvest-harvest-consultations-mariadb

# Package helm chart
helm-package: helm-generate
  mkdir -p dist
  helm package deploy/helm/harvest-consultations -d dist/

# === CI / nightly validation ===

# Full end-to-end test: kind cluster → helm deploy → run job → dump → validate
ci-test:
  #!/usr/bin/env bash
  set -euo pipefail

  echo "=== CI: starting kind cluster ==="
  kind get clusters | grep -q harvest || kind create cluster --name harvest

  echo "=== CI: generating and installing helm chart ==="
  just helm-generate
  helm upgrade --install harvest deploy/helm/harvest-consultations \
    --namespace {{ns}} --create-namespace \
    --set harvestCronjob.harvest.env.mysqlHost=harvest-harvest-consultations-mariadb

  echo "=== CI: waiting for MariaDB (up to 5 min) ==="
  kubectl wait --for=condition=ready pod -l app=mariadb -n {{ns}} --timeout=300s

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
  gunzip -c dist/consultations.sql.gz | head -20 || true
  ROWS=$(gunzip -c dist/consultations.sql.gz | grep -c 'INSERT INTO' || echo 0)
  echo "Rows found: $ROWS"
  if [ "$ROWS" -eq 0 ]; then
    echo "ERROR: dump contains no INSERT statements"
    exit 1
  fi
  echo "=== CI: PASSED ==="
