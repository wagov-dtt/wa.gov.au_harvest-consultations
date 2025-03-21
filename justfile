set dotenv-load

ns := "harvest-consultations"

# Choose a task to run
default:
  just --choose

# Install project tools
prereqs:
  brew bundle install
  minikube config set memory no-limit
  minikube config set cpus no-limit

clean:
  kubectl delete ns {{ns}}

# Show local/env secrets for injecting into other tools
@show-secrets:
  jq -n 'env | {HARVEST_PORTALS, MYSQL_PWD, MYSQL_DUCKDB_PATH, SQLMESH__VARIABLES__OUTPUT_DB, SQLMESH__VARIABLES__OUTPUT_TABLE}'

# Setup minikube
minikube:
  which k9s || just prereqs
  kubectl get nodes || minikube status || minikube start # if kube configured use that cluster, otherwise start minikube

# Configures harvest-secret using kubectl
install-harvest-secret:
  cat kustomize/secrets-template.yaml | NAME=harvest-secret SECRET_JSON=$(just show-secrets) envsubst | kubectl apply -n {{ns}} -f -

# Forward mysql from k8s cluster
mysql-svc: minikube
  kubectl apply -k kustomize/minikube
  just install-harvest-secret
  ss -ltpn | grep 3306 || kubectl port-forward service/mysqldb 3306:3306 -n {{ns}} & sleep 1

# SQLMesh ui for local dev
dev: mysql-svc
  uv run sqlmesh ui

# Build and test container
test: mysql-svc
  minikube image build -t ghcr.io/wagov-dtt/harvest-consultations:dev .
  kubectl delete job test -n {{ns}} --ignore-not-found
  kubectl create job test --from cronjob/harvest-cronjob -n {{ns}}

# Dump the sqlmesh database to logs/consultations.sql.gz (run test to create/populate db first)
dump-consultations: mysql-svc
  mkdir logs; kubectl exec -n {{ns}} percona-mysql-0 -- mysqldump -uroot --password=$MYSQL_PWD --compact --single-transaction --no-create-info sqlmesh | gzip > logs/consultations.sql.gz

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
  kubectl get ns {{ns}} || kubectl create ns {{ns}}
  cat eks/k8s-harvestjob.yaml | envsubst | kubectl apply -f -
  kubectl apply -f eks/k8s-adminer.yaml
  kubectl port-forward service/adminer-service 8000:80 -n {{ns}} & sleep 1
