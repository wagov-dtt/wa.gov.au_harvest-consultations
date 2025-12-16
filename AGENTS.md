# Agent Guide

## Quick Start

**Build & Test:**
```bash
just build          # Build with railpack
just mysql          # Start Percona MySQL
just test           # Run container with local MySQL
just clean          # Stop services
```

**Run Pipeline (via uv):**
```bash
uv run python -m harvest                    # Use .env defaults
uv run python -m harvest --help             # Show all flags
uv run python -m harvest --output_db mydb   # Override DB name
```

## Commands

### Local Development
- `just build` - Build image (auto-starts BuildKit)
- `just mysql` - Start/reuse MySQL on port 3306
- `just mysql-stop` - Stop MySQL
- `just test` - Build & run container with local MySQL
- `just clean` - Stop all services

### Pipeline (via uv)
Always use `uv run python` for all Python execution:
- `uv run python -m harvest` - Run with .env config
- `uv run python -m harvest --help` - Show available flags
- `uv run python -m harvest --harvest_portals '{...}'` - Portal config (JSON)
- `uv run python -m harvest --mysql_pwd SECRET` - MySQL password
- `uv run python -m harvest --mysql_duckdb_path "host=..."` - Connection string
- `uv run python -m harvest --output_db DB` - Target database
- `uv run python -m harvest --output_table TABLE` - Target table

**Precedence:** CLI flags > env vars > .env file > defaults

### Production
- `just publish` - Build multi-platform image & push

## Architecture

**Stack:** Python 3.13+ (uv) → Railpack → DuckDB → MySQL

**Configuration:** Pydantic-settings v2+ with native CLI parsing
- `config.py` - HarvestConfig with auto-parsed flags
- No manual argparse/click/typer
- `justfile` uses `set dotenv-load` (auto-loads .env)

**Pipeline:**
- `models/api/*.py` - API harvesting (pandas DataFrames)
- `models/transforms.sql` - DuckDB SQL transforms
- `harvest/__main__.py` - Harvester class

**Process:**
1. Fetch from portals → create `*_raw` tables
2. SQL transforms → create `*_std` views → `consultations_final` table
3. Export to MySQL via DuckDB MySQL extension

**Database:** DuckDB (in-memory) → MySQL (persistent target)

## Code Style

- Python: Full type hints (3.10+)
- Error handling: try/except with print(), return empty DataFrame
- Variables: snake_case for functions/vars, SCREAMING_SNAKE_CASE for env vars
- API models: functions in `models/api/*.py` returning DataFrames
- SQL: uppercase keywords, explicit aliases, UNION ALL BY NAME
- Config: Single HarvestConfig class with pydantic-settings v2+
