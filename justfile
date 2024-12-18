set dotenv-load

# Choose a task to run
default:
  @just --choose


# Install project tools
prereqs:
  brew bundle install
  minikube config set memory no-limit
  minikube config set cpus no-limit

# Setup minikube
minikube:
  which k9s || @just prereqs
  minikube status || minikube start

# Forward mysql from service defined in env
mysql-svc: minikube
  ss -ltpn | grep 3306 || kubectl port-forward $KUBECTL_FORWARD_MYSQL 3306:3306 -n everest & sleep 1

# SQLMesh ui for local dev
dev: mysql-svc
  @just mysql sqlmesh -e exit || just mysql -e 'create database sqlmesh; SET GLOBAL pxc_strict_mode=PERMISSIVE;'
  uv run sqlmesh ui

# skaffold configured with env and minikube
[positional-arguments]
skaffold *args: minikube
  skaffold "$@"

# mysqldump configured with same env as SQLMesh
[positional-arguments]
mysqldump *args: mysql-svc
  mysqldump -uroot -h127.0.0.1 "$@"

# mysql configured with same env as SQLMesh
[positional-arguments]
mysql *args: mysql-svc
  mysql -uroot -h127.0.0.1 "$@"

# Install percona everest cli
everestctl:
  curl -sSL -o everestctl-linux-amd64 https://github.com/percona/everest/releases/latest/download/everestctl-linux-amd64
  sudo install -m 555 everestctl-linux-amd64 /usr/local/bin/everestctl
  rm everestctl-linux-amd64

# Percona Everest webui to manage databases
everest: minikube
  which everestctl || @just everestctl
  everestctl accounts list || everestctl install --skip-wizard
  everestctl accounts set-password --username admin --new-password everest
  ss -ltpn | grep 8080 || kubectl port-forward svc/everest 8080:8080 -n everest-system &
  @echo "Manage databases: http://localhost:8080 (login admin/everest)"
