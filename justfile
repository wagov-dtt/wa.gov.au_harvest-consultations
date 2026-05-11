ns := "harvest-consultations"
table := "consultations"
image := "ghcr.io/wagov-dtt/harvest-duckdb"

chart_version := `dasel -i yaml --compact '$this.version' < chart/Chart.yaml`
duckdb_version := `dasel -i yaml --compact appVersion < chart/Chart.yaml | tr -d '"'`
duckdb_short := `dasel -i yaml --compact appVersion < chart/Chart.yaml | tr -d '".'`
image_tag := chart_version + "-duckdb" + duckdb_short
csv_sql := "LOAD mysql; ATTACH '' AS mysqldb (TYPE mysql); COPY (SELECT * FROM mysqldb." + table + ") TO '/dev/stdout' (HEADER);"

default:
  just --choose

helm-install:
  helm upgrade --install harvest chart \
    --namespace {{ns}} --create-namespace \
    --set db.table={{table}}

kind-up:
  kind get clusters | grep -q harvest || kind create cluster --name harvest
  just helm-install

test: kind-up
  kubectl delete job test -n {{ns}} --ignore-not-found
  kubectl create job test --from cronjob/harvest-cronjob -n {{ns}}

ci-test: kind-up
  #!/usr/bin/env bash
  set -euo pipefail

  wait_job() {
    kubectl wait --for=condition=complete "job/$1" -n {{ns}} --timeout="$2" || {
      kubectl logs "job/$1" -n {{ns}} --tail=50
      exit 1
    }
  }

  kubectl rollout status statefulset/mariadb -n {{ns}} --timeout=300s

  kubectl delete job ci-harvest -n {{ns}} --ignore-not-found
  kubectl create job ci-harvest --from cronjob/harvest-cronjob -n {{ns}}
  wait_job ci-harvest 300s

  mkdir -p dist
  pod=$(kubectl get pod -l app=mariadb -n {{ns}} -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n {{ns}} "$pod" -- \
    sh -c 'MYSQL_PWD="$MARIADB_PASSWORD" exec mariadb-dump -u"$MARIADB_USER" -h 127.0.0.1 harvest {{table}}' \
    | gzip > dist/{{table}}.sql.gz

  kubectl delete job ci-csv-report -n {{ns}} --ignore-not-found
  kubectl create job ci-csv-report --from cronjob/harvest-cronjob -n {{ns}} --dry-run=client -o yaml \
    | sed "s#\.read /etc/config/harvest.sql#{{csv_sql}}#" \
    | kubectl apply -f -
  wait_job ci-csv-report 120s
  kubectl logs job/ci-csv-report -n {{ns}} > dist/{{table}}.csv
  kubectl delete job ci-csv-report -n {{ns}} --ignore-not-found

  rows=$(gunzip -c dist/{{table}}.sql.gz | grep -c 'INSERT INTO' || true)
  test "$rows" -gt 0
  test -s dist/{{table}}.csv

clean:
  kind delete cluster --name harvest || true
  rm -rf dist

helm-package version=chart_version:
  mkdir -p dist
  helm package chart --version "{{version}}" -d dist/

docker-build tag=image_tag:
  docker buildx build --platform linux/amd64,linux/arm64 \
    --build-arg DUCKDB_VERSION="{{duckdb_version}}" \
    -t "{{image}}:{{tag}}" --push .

docker-build-release chart: (docker-build chart + "-duckdb" + duckdb_short)

bump-version chart duckdb=duckdb_version:
  dasel -i yaml -o yaml --root '$this.version = "{{chart}}"' < chart/Chart.yaml > chart/Chart.yaml.tmp
  dasel -i yaml -o yaml --root 'appVersion = "{{duckdb}}"' < chart/Chart.yaml.tmp > chart/Chart.yaml
  rm chart/Chart.yaml.tmp
  sed -i 's/^ARG DUCKDB_VERSION=.*/ARG DUCKDB_VERSION={{duckdb}}/' Dockerfile
  @echo "image tag: {{chart}}-duckdb{{replace(duckdb, ".", "")}}"
