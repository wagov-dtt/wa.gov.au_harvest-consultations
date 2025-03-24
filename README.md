# SQLMesh Data Pipeline for Drupal Integration

## Overview
This document outlines an hourly process using SQLMesh to harvest data from external REST APIs, transform it, and store it in MySQL for consumption by Drupal views.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/wagov-dtt/wa.gov.au_harvest-consultations)

## Developing locally
The `justfile` in this repository has most useful commands (run `just prereqs` and restart codespace/devcontainer before diving in to make sure all cli utilities are in place):

```bash
$ just -l -u
Available recipes:
    default            # Choose a task to run
    prereqs            # Install project tools
    minikube           # Setup minikube
    mysql-svc          # Forward mysql from k8s cluster
    dev                # SQLMesh ui for local dev
    test               # Build and test container
    dump-consultations # Dump the sqlmesh database to logs/consultations.sql.gz (run test to create/populate db first)
    awslogin           # use aws sso login profiles
    setup-eks          # Create an eks cluster for testing
    schedule-with-eks  # Deploy scheduled task to eks with secrets
```

To get started, run `just dev` to create a minikube cluster, forward the mysql service and expose the sqlmesh ui.

To dump the `sqlmesh` database for validation/testing:

```bash
just clean # This tears down the kubernetes namespace, including local db
just test # Builds and pushes local docker image into minikube, then runs the job once off (and schedules for hourly runs)
just dump-consultations # Exports current database from minikube
# grab output from logs/consultations.sql.gz
```

## Using in production

To run the packaged container in a production environment, it will need `HARVEST_PORTALS` and `MYSQL_DUCKDB_PATH` configured (refer to [duckdb mysql extension](https://duckdb.org/docs/extensions/mysql#configuration)). The remaining env vars in [example.env](example.env) are just to simplify local development. The below example also includes adjusting the output database/table (note that the database in the `MYSQL_DUCKDB_PATH` connection and the `SQLMESH__VARIABLES__OUTPUT_DB` should match.

```bash
# .env example
HARVEST_PORTALS='{"engagementhq":["https://ehq-site1.example.domain","https:/ehq-site2.example.domain"],"citizenspace":["https://cs-site3.example.domain","https://cs-site4.example.domain"]}'
MYSQL_PWD='...'
MYSQL_DUCKDB_PATH='host=localhost user=root database=sqlmesh'
SQLMESH__VARIABLES__OUTPUT_DB="sqlmesh"
SQLMESH__VARIABLES__OUTPUT_TABLE="consultations"
```

The justfile with this repository includes a default configuration that can be used with `just setup-eks` and then `just schedule-with-eks` which will create an [AWS EKS Auto](https://docs.aws.amazon.com/eks/latest/userguide/quickstart.html) cluster, then schedule a job and database admin container in the `harvest-consultations` namespace. Note that secrets will also be pulled from local env vars and saved in the cluster (which will be using KMS encrypted sealed secrets if setup as above). Reviewing the [justfile](justfile) and the [eks](eks) manifest directory should be enough to configure for specific use cases (e.g. [Use existing VPC](https://eksctl.io/usage/vpc-configuration/#use-existing-vpc-other-custom-configuration) and customising security groups / NAT gateways).

For further runtime customisation, see [environment overrides](https://sqlmesh.readthedocs.io/en/stable/guides/configuration/#overrides) in the [sqlmesh configuration guide](https://sqlmesh.readthedocs.io/en/stable/guides/configuration/) and this projects [config.yaml](./config.yaml).

Current release is [v0.3.1](https://github.com/wagov-dtt/wa.gov.au_harvest-consultations/releases/tag/v0.3.1) which has a published [container image](https://github.com/wagov-dtt/wa.gov.au_harvest-consultations/pkgs/container/harvest-consultations/379042309?tag=0.3.1) built for both `linux/amd64` and `linux/arm64` architectures from the [ghcr.io/astral-sh/uv:python3.13-bookworm-slim](https://docs.astral.sh/uv/guides/integration/docker/#available-images) image.

## Process Design

1. **Hourly Data Harvesting**: SQLMesh connects to and harvests data from external REST APIs
   - [SQLMesh Python Models](https://sqlmesh.readthedocs.io/en/stable/concepts/models/python_models/)
   - Configurable API endpoints and authentication
   - Runs every hour via kubernetes [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)

2. **Data Transformation**: SQLMesh processes the harvested data
   - [SQLMesh SQL Models](https://sqlmesh.readthedocs.io/en/stable/concepts/models/sql_models/)
   - Data cleaning and standardization
   - Value translation in SQL views
   - Data clone from `duckdb` state engine to `mysql` target tables using [DuckDB MySQL Extension](https://duckdb.org/docs/stable/extensions/mysql.html)

4. **Content Management**:
   - Read-only imports of external content
   - Full management of Drupal-authored content

## Notes on Development
For detailed implementation guidance, refer to:
- [SQLMesh Documentation](https://sqlmesh.com/docs/)
