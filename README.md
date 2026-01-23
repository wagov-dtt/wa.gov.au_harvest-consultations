# WA Gov Consultation Harvester

Fetches consultation data from WA Gov portals → transforms with DuckDB → exports to MySQL/MariaDB.

## Quick Start

```bash
just test       # Run pytest (fast)
just test-full  # Build image, run with MariaDB, show stats (slow)
just clean      # Stop containers
```

## Configuration

Set in `.env` or environment variables:

```bash
HARVEST_PORTALS='{"engagementhq":["https://..."],"citizenspace":["https://..."]}'
MYSQL_PWD=secret
MYSQL_DUCKDB_PATH='host=localhost user=root'
OUTPUT_DB=harvest_consultations
OUTPUT_TABLE=consultations
```

Legacy `SQLMESH__VARIABLES__OUTPUT_DB` and `SQLMESH__VARIABLES__OUTPUT_TABLE` are also supported for backwards compatibility.

## Container Usage

```bash
# Run harvest pipeline (default)
docker run --rm --network host --env-file .env image:tag

# Show database stats
docker run --rm --network host --env-file .env --entrypoint python image:tag -m harvest stats

# Create database only
docker run --rm --network host --env-file .env --entrypoint python image:tag -m harvest init
```

## Local Development

```bash
uv run python -m harvest        # Run pipeline
uv run python -m harvest stats  # Show stats
uv run python -m harvest init   # Create database
```

## Project Structure

```
harvest/__main__.py   # Async API fetching + pipeline
models/transforms.sql # DuckDB SQL transforms
test_harvest.py       # Pytest with real API data
Procfile              # Container start command
```
