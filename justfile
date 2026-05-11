ns := "harvest-consultations"
mysqlHost := "mariadb"
table := "consultations"
owner := "wagov-dtt"
image := "harvest-duckdb"

# Versions come from chart metadata. Docker image tags are derived, not stored.
chart_version := `awk '/^version:/ {print $2; exit}' chart/Chart.yaml`
duckdb_version := `awk '/^appVersion:/ {gsub(/"/, "", $2); print $2; exit}' chart/Chart.yaml`
duckdb_short := `awk '/^appVersion:/ {gsub(/[".]/, "", $2); print $2; exit}' chart/Chart.yaml`
image_tag := chart_version + "-duckdb" + duckdb_short

default:
  just --choose

# Bump chart/app versions. The Helm image tag is computed from Chart.yaml.
# Usage: just bump-version 0.5.5           (same DuckDB)
#        just bump-version 0.5.5 1.6.0     (new DuckDB)
bump-version chart duckdb=duckdb_version:
  @echo "=== chart: {{chart_version}} → {{chart}}"
  @echo "=== duckdb: {{duckdb_version}} → {{duckdb}}"
  sed -i 's/^version: .*/version: {{chart}}/' chart/Chart.yaml
  sed -i 's/^appVersion: .*/appVersion: "{{duckdb}}"/' chart/Chart.yaml
  sed -i 's/^ARG DUCKDB_VERSION=.*/ARG DUCKDB_VERSION={{duckdb}}/' Dockerfile
  @echo "=== image tag: {{chart}}-duckdb{{replace(duckdb, ".", "")}}"
  @echo "=== done — verify with: git diff"

clean:
  kind delete cluster --name harvest || true
  rm -rf dist

# Start local k8s cluster with kind
kind-up:
  kind get clusters | grep -q harvest || kind create cluster --name harvest
  helm upgrade --install harvest chart \
    --namespace {{ns}} --create-namespace \
    --set mysql.host={{mysqlHost}} \
    --set mysql.table={{table}}

# Forward mariadb from k8s cluster
mariadb-svc: kind-up
  ss -ltpn | grep 3306 || kubectl port-forward service/mariadb 3306:3306 -n {{ns}} & sleep 1

# Create a one-off test job in the cluster
test: kind-up
  kubectl delete job test -n {{ns}} --ignore-not-found
  kubectl create job test --from cronjob/harvest-cronjob -n {{ns}}

# Install/upgrade helm chart
helm-install:
  helm upgrade --install harvest chart \
    --namespace {{ns}} --create-namespace \
    --set mysql.host={{mysqlHost}} \
    --set mysql.table={{table}}

# Build and push docker image.
#   just docker-build                    → uses {chart-version}-duckdb{short}
#   just docker-build edge               → tags as :edge
#   just docker-build 0.5.6-duckdb170    → explicit tag
docker-build tag=image_tag:
  docker buildx build --platform linux/amd64,linux/arm64 \
    --build-arg DUCKDB_VERSION="{{duckdb_version}}" \
    -t "ghcr.io/{{owner}}/{{image}}:{{tag}}" --push .

# Build release image with chart version from a git tag, without leading 'v'.
docker-build-release chart: (docker-build chart + "-duckdb" + duckdb_short)

# Package helm chart
helm-package version=chart_version:
  mkdir -p dist
  helm package chart --version "{{version}}" -d dist/

# === CI / nightly validation ===

# Full end-to-end test: kind cluster → helm deploy → run job → dump → validate
ci-test:
  #!/usr/bin/env bash
  set -euo pipefail

  echo "=== CI: starting kind cluster ==="
  kind get clusters | grep -q harvest || kind create cluster --name harvest

  echo "=== CI: installing helm chart ==="
  helm upgrade --install harvest chart \
    --namespace {{ns}} --create-namespace \
    --set mysql.host={{mysqlHost}} \
    --set mysql.table={{table}}

  echo "=== CI: waiting for MariaDB (up to 5 min) ==="
  kubectl rollout status statefulset/mariadb -n {{ns}} --timeout=300s

  echo "=== CI: triggering harvest job ==="
  kubectl delete job ci-harvest -n {{ns}} --ignore-not-found
  kubectl create job ci-harvest --from cronjob/harvest-cronjob -n {{ns}}

  echo "=== CI: waiting for job to complete ==="
  kubectl wait --for=condition=complete job/ci-harvest -n {{ns}} --timeout=300s || {
    echo "Job failed — pod logs:"
    kubectl logs -l app=harvest-cronjob -n {{ns}} --tail=50
    exit 1
  }

  echo "=== CI: dumping {{table}} table ==="
  POD=$(kubectl get pod -l app=mariadb -n {{ns}} -o jsonpath='{.items[0].metadata.name}')
  mkdir -p dist
  kubectl exec -n {{ns}} "$POD" -- \
    sh -c 'MYSQL_PWD="$MARIADB_PASSWORD" exec mariadb-dump -u"$MARIADB_USER" -h 127.0.0.1 harvest {{table}}' \
    | gzip > dist/{{table}}.sql.gz

  echo "=== CI: validating dump ==="
  gunzip -c dist/{{table}}.sql.gz | head -20 || true
  ROWS=$(gunzip -c dist/{{table}}.sql.gz | grep -c 'INSERT INTO' || echo 0)
  echo "Rows found: $ROWS"
  if [ "$ROWS" -eq 0 ]; then
    echo "ERROR: dump contains no INSERT statements"
    exit 1
  fi
  echo "=== CI: PASSED ==="

# Check for newer versions of pinned GitHub Actions
check-actions:
  #!/usr/bin/env bash
  set -euo pipefail
  echo "Checking pinned action versions..."
  for f in .github/workflows/*.yaml; do
    echo "  → $(basename "$f")"
    grep -oP 'uses:\s+\K\S+@\S+' "$f" | sort -u | while read -r ref; do
      repo="${ref%%@*}"
      sha="${ref##*@}"
      sha_short="${sha:0:7}"
      latest_tag=$(gh api "repos/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null) || latest_tag="unknown"
      latest_sha=$(gh api "repos/${repo}/commits/${latest_tag}" --jq '.sha' 2>/dev/null) || latest_sha="unknown"
      if [ "$latest_sha" = "unknown" ]; then
        echo "      ??? ${repo} (could not fetch latest)"
      elif [[ "$sha" != "$latest_sha"* ]]; then
        echo "      OUTDATED: ${repo} → ${latest_tag} (pinned: ${sha_short}, latest: ${latest_sha:0:7})"
      else
        echo "      OK: ${repo} @ ${latest_tag}"
      fi
    done
  done
