# Agent Guide for Harvest Consultations

## Build/Test Commands
- **Setup environment**: `just prereqs` (install tools, configure minikube)
- **Local development**: `just dev` (starts minikube, MySQL service, SQLMesh UI)
- **Build and test**: `just test` (builds Docker image, runs job in minikube)
- **Run SQLMesh UI**: `uv run sqlmesh ui` (after `just mysql-svc`)
- **Clean environment**: `just clean` (deletes kubernetes namespace)
- **Dump database**: `just dump-consultations` (exports to logs/consultations.sql.gz)

## Architecture
- **SQLMesh data pipeline**: Hourly harvest from REST APIs (EngagementHQ, CitizenSpace)
- **Python models**: API harvesting (`models/*_api.py`) with pandas DataFrames
- **SQL models**: Data transformation and views (`models/*_view.sql`, `models/consultations_tbl.sql`)
- **Database**: DuckDB (local) → MySQL (target) using DuckDB MySQL extension
- **Deployment**: Kubernetes CronJob on minikube (local) or AWS EKS (production)
- **Config**: SQLMesh configuration in `config.yaml`, justfile for task automation

## Code Style
- **Python**: Standard library imports first, third-party second, sqlmesh imports last
- **Error handling**: Try/catch with print() for API errors, return empty DataFrame on failure
- **Variables**: Snake_case for functions/variables, environment variables in SCREAMING_SNAKE_CASE
- **Models**: Use SQLMesh @model decorator with explicit column definitions
- **SQL**: Uppercase keywords, explicit table aliases, prefer UNION ALL BY NAME for combining datasets
