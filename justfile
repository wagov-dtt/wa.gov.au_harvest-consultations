set dotenv-load

# Choose a task to run
default:
  just --choose

# Install project tools
prereqs:
  brew bundle install
  minikube config set memory no-limit
  minikube config set cpus no-limit

# Setup minikube
minikube:
  which k9s || just prereqs
  kubectl get nodes || minikube status || minikube start # if kube configured use that cluster, otherwise start minikube

# Forward mysql from k8s cluster
mysql-svc: minikube
  kubectl apply -k kustomize/minikube
  ss -ltpn | grep 3306 || kubectl port-forward service/mysqldb 3306:3306 -n harvest-consultations & sleep 1

# SQLMesh ui for local dev
dev: mysql-svc
  uv run sqlmesh ui

# Build and test container
test: mysql-svc
  docker build . -t harvest-consultations
  @docker run --net=host \
    -e SECRETS_YAML='{{env('SECRETS_YAML')}}' \
    -e MYSQL_PWD='{{env('MYSQL_PWD')}}' \
    -e MYSQL_DUCKDB_PATH='{{env('MYSQL_DUCKDB_PATH')}}' \
    harvest-consultations \
    sqlmesh plan --auto-apply --run --verbose

# Dump the sqlmesh database to logs/consultations.sql.gz (run test to create/populate db first)
dump-consultations: mysql-svc
  mkdir logs; mysqldump -uroot -h127.0.0.1 --set-gtid-purged=OFF --single-transaction sqlmesh | gzip > logs/consultations.sql.gz

# use aws sso login profiles
awslogin:
  which aws || just prereqs
  aws sts get-caller-identity > /dev/null || aws sso login --use-device-code || echo please run '"aws configure sso"' and add AWS_PROFILE/AWS_REGION to your .env file # make sure aws logged in

export CLUSTER := env_var_or_default("CLUSTER", "auto01")

# Create an eks cluster for testing
setup-eks: awslogin
  eksctl get cluster --name {{CLUSTER}} > /dev/null || cat eks/eksctl-cluster-template.yaml | envsubst | eksctl create cluster -f - # default auto cluster
  aws kms describe-key --key-id alias/eks/secrets > /dev/null || aws kms create-alias --alias-name alias/eks/secrets --target-key-id $(aws kms create-key --query 'KeyMetadata.KeyId' --output text)
  eksctl utils enable-secrets-encryption --cluster {{CLUSTER}} --key-arn $(aws kms describe-key --key-id alias/eks/secrets --query 'KeyMetadata.Arn' --output text) --region $AWS_REGION # enable kms secrets
  eksctl utils write-kubeconfig --cluster {{CLUSTER}}
  kubectl apply -f eks/auto-class-manifests.yaml # default storage/alb classes

# Deploy scheduled task to eks with secrets
schedule-with-eks:
  #!/usr/bin/env bash
  export SECRETS_YAML_B64=$(echo -n "$SECRETS_YAML" | base64 --wrap=0)
  kubectl get ns harvest-consultations || kubectl create ns harvest-consultations
  cat eks/k8s-harvestjob.yaml | envsubst | kubectl apply -f -
  kubectl apply -f eks/k8s-adminer.yaml
  kubectl port-forward service/adminer-service 8000:80 -n harvest-consultations & sleep 1
