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
    mysql-svc          # Forward mysql from service defined in env
    dev                # SQLMesh ui for local dev
    test               # Build and test container (run dev first to make sure db exists)
    skaffold *args     # skaffold configured with env and minikube
    dump-consultations # Dump the sqlmesh database to logs/consultations.sql.gz
    mysql *args        # mysql configured with same env as SQLMesh
    everestctl         # Install percona everest cli
    everest            # Percona Everest webui to manage databases
```

To get started, run `just everest` and use the web ui to create a database. Configure the database details in the `.env` file (refer [example.env](example.env)). Once configured you can run `just dev` to forward the mysql port and expose the sqlmesh ui.

To dump the `sqlmesh` database for validation/testing:

```bash
just dump-consultations
# grab output from logs/consultations.sql.gz
```

## Testing container with skaffold

Configure secrets then run `skaffold dev` (which expects secrets created in cluster).

## Using in production

To run the packaged container in a production environment, it will need `SECRETS_YAML` and `MYSQL_DUCKDB_PATH` configured (refer to [duckdb mysql extension](https://duckdb.org/docs/extensions/mysql#configuration)). The remaining env vars in [example.env](example.env) are just to simplify local development.

Current release is [v0.2.1-beta](https://github.com/wagov-dtt/wa.gov.au_harvest-consultations/releases/tag/v0.2.1-beta) which has a published [container image](https://github.com/wagov-dtt/wa.gov.au_harvest-consultations/pkgs/container/harvest-consultations) built for both `linux/amd64` and `linux/arm64` architectures from the [ghcr.io/astral-sh/uv:python3.12-bookworm-slim](https://docs.astral.sh/uv/guides/integration/docker/#available-images) image.

## Process Design

1. **Hourly Data Harvesting**: SQLMesh connects to and harvests data from external REST APIs
   - [SQLMesh Python Models](https://sqlmesh.readthedocs.io/en/stable/concepts/models/python_models/)
   - Configurable API endpoints and authentication
   - Runs every hour via scheduled task

2. **Data Transformation**: SQLMesh processes the harvested data
   - [SQLMesh SQL Models](https://sqlmesh.readthedocs.io/en/stable/concepts/models/sql_models/)
   - Data cleaning and standardization
   - Value translation in SQL views
   - Data clone from `duckdb` state engine to `mysql` target tables

4. **Content Management**:
   - Read-only imports of external content
   - Full management of Drupal-authored content

## Notes on Development
For detailed implementation guidance, refer to:
- [SQLMesh Documentation](https://sqlmesh.com/docs/)
- [Drupal Views Documentation](https://www.drupal.org/docs/user_guide/en/views-chapter.html)
