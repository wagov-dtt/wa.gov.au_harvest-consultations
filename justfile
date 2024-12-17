# Choose a task to run
default:
  @just --choose

# Install project tools
prereqs:
  brew bundle install
  minikube config set memory no-limit
  minikube config set cpus no-limit

# Build container images
build: prereqs
  skaffold build

# SQLmesh ui for local dev
local-dev:
  uv run sqlmesh ui

# Setup minikube
minikube: prereqs
  minikube status || minikube start

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
  kubectl port-forward svc/everest 8080:8080 -n everest-system &
  @echo "Manage databases: http://localhost:8080 (login admin/everest)"