# Install project tools
prereqs:
  brew bundle install
  minikube config set memory no-limit
  minikube config set cpus no-limit

# Build container images
build: prereqs
  eval $(minikube -p minikube docker-env)
  skaffold build

# SQLmesh ui for local dev
local-dev:
  uv run sqlmesh ui

# Setup minikube
minikube: prereqs
  minikube start

# Percona Everest webui to manage databases
everest: minikube
  curl -sSL -o everestctl-linux-amd64 https://github.com/percona/everest/releases/latest/download/everestctl-linux-amd64
  sudo install -m 555 everestctl-linux-amd64 /usr/local/bin/everestctl
  rm everestctl-linux-amd64
  everestctl install
  everestctl accounts initial-admin-password
  kubectl port-forward svc/everest 8080:8080 -n everest-system