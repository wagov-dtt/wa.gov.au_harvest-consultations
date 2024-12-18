# SQLMesh Data Pipeline for Drupal Integration

## Overview
This document outlines an hourly process using SQLMesh to harvest data from external REST APIs, transform it, and store it in MySQL for consumption by Drupal views.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/wagov-dtt/wa.gov.au_harvest-consultations)

## Developing locally
The `justfile` in this repository has most useful commands:

```bash
$ just -l -u
Available recipes:
    default    # Choose a task to run
    prereqs    # Install project tools
    build      # Build container images
    local-dev  # SQLmesh ui for local dev
    minikube   # Setup minikube
    everestctl # Install percona everest cli
    everest    # Percona Everest webui to manage databases
```

To get started, run `just everest` and use the web ui to create a database. Configure the database details in the `.env` file (refer [example.env](example.env)). Once configured you can run `just local-dev` to forward the mysql port and expose the sqlmesh ui.

To dump the `sqlmesh` database for validation/testing:

```bash
just mysqldump sqlmesh | gzip > sqlmesh.sql.gz
```

## Testing container with skaffold

Configure secrets then run `skaffold dev` (which expects secrets created in cluster).

## Container publish workflow

## Process Design

1. **Hourly Data Harvesting**: SQLMesh connects to and harvests data from external REST APIs
   - [SQLMesh Python Models](https://sqlmesh.readthedocs.io/en/stable/concepts/models/python_models/)
   - Configurable API endpoints and authentication
   - Runs every hour via scheduled task

2. **Data Transformation**: SQLMesh processes the harvested data
   - [SQLMesh SQL Models](https://sqlmesh.readthedocs.io/en/stable/concepts/models/sql_models/)
   - Data cleaning and standardization
   - Value translation based on mapping configuration
   - Data clone from `duckdb` state engine to `mysql` target tables

4. **Content Management**:
   - Read-only imports of external content
   - Full management of Drupal-authored content

## Notes on Development
For detailed implementation guidance, refer to:
- [SQLMesh Documentation](https://sqlmesh.com/docs/)
- [Drupal Views Documentation](https://www.drupal.org/docs/user_guide/en/views-chapter.html)
