# Agent Guide

## Quick Start

```bash
just test            # Run pytest
just build           # Build with railpack  
just test-full       # Run container with local MariaDB
just clean           # Stop services
```

**Run Pipeline:**
```bash
uv run python -m harvest       # Use .env defaults
uv run python -m harvest stats # Show database stats
uv run python -m harvest init  # Create database only
```

## Commands

### Local Development
- `just test` - Run pytest tests
- `just test-full` - Build image, run with MariaDB, show stats
- `just clean` - Stop all services

### Production
- `just publish` - Build multi-platform image & push

## Architecture

**Stack:** Python 3.13+ (uv) → Ibis/DuckDB → MySQL/MariaDB

**Files:**
- `harvest/__main__.py` - Async API fetching + pipeline (~180 lines)
- `models/transforms.sql` - DuckDB SQL transforms (~60 lines)
- `test_harvest.py` - Pytest tests with real API data

**Pipeline:**
1. Fetch from EngagementHQ/CitizenSpace portals → create `*_raw` tables
2. SQL transforms → create `*_std` views → `consultations_final` table
3. Export to MySQL via DuckDB MySQL extension

**Config:** Environment variables from .env:
- `HARVEST_PORTALS` - JSON dict of portal URLs
- `MYSQL_PWD` - MySQL password
- `MYSQL_DUCKDB_PATH` - DuckDB connection string
- `OUTPUT_DB` / `OUTPUT_TABLE` - Target table
- Legacy: `SQLMESH__VARIABLES__OUTPUT_DB/TABLE` also supported

## Code Style

- Python: Type hints, minimal deps, grug-brain simple
- SQL: Uppercase keywords, UNION ALL BY NAME
- Error handling: try/except with print(), return empty DataFrame
