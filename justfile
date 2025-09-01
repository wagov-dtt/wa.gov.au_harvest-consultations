set dotenv-load

ns := "harvest-consultations"
image := "harvest-consultations"
registry := "ghcr.io/wagov-dtt"

# Choose a task to run
default:
  just --choose

# Build local test image
build:
  docker buildx bake test --progress=plain

# Show local/env secrets for injecting into other tools
@show-secrets:
  jq -n 'env | {HARVEST_PORTALS, MYSQL_PWD, MYSQL_DUCKDB_PATH, SQLMESH__VARIABLES__OUTPUT_DB, SQLMESH__VARIABLES__OUTPUT_TABLE}'

# Setup k3d cluster
k3d:
  kubectl get nodes || k3d cluster list {{ns}} | grep -q {{ns}} || k3d cluster create {{ns}} --port "3306:3306@loadbalancer"

clean:
  k3d cluster delete {{ns}} || true

# Configures harvest-secret using kubectl
install-harvest-secret:
  cat kustomize/secrets-template.yaml | NAME=harvest-secret SECRET_JSON=$(just show-secrets) envsubst | kubectl apply -n {{ns}} -f -

# Deploy mysql service to k3d
mysql-svc: k3d
  kubectl apply -k kustomize/minikube
  just install-harvest-secret

# SQLMesh development (use VSCode extension - UI is deprecated)
dev: mysql-svc
  @echo "SQLMesh UI is deprecated. Install the SQLMesh VSCode extension for development."
  @echo "Run 'sqlmesh plan' and 'sqlmesh apply' from terminal or use VSCode extension."

# Build and test container in k3d
test: mysql-svc build
  k3d image import {{image}}:test --cluster {{ns}}
  kubectl delete job test -n {{ns}} --ignore-not-found
  kubectl create job test --from cronjob/harvest-cronjob -n {{ns}}

# Publish multi-platform release image
publish:
  docker buildx bake release --progress=plain

# Dump the sqlmesh database to logs/consultations.sql.gz (run test to create/populate db first)
dump-consultations: mysql-svc
  mkdir logs; kubectl exec -n {{ns}} percona-mysql-0 -- mysqldump -uroot --password=$MYSQL_PWD --compact --single-transaction --no-create-info sqlmesh | gzip > logs/consultations.sql.gz

# use aws sso login profiles
awslogin:
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
