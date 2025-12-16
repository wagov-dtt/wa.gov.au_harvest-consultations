# Consultation Data Harvest Pipeline

Batch ingestion from REST APIs (EngagementHQ, CitizenSpace) → DuckDB transformations → MySQL export.

## Local Development

```bash
just build    # Build container
just mysql    # Start MySQL
just test     # Run with local MySQL
just clean    # Stop services
```

Standard uv project. Railpack auto-generates Dockerfile.

## Running the Pipeline

```bash
# Use .env defaults
uv run python -m harvest

# Override settings via CLI
uv run python -m harvest --output_db mydb --output_table mytable

# Show all available flags
uv run python -m harvest --help
```

### Configuration Precedence

1. CLI flags (highest)
2. Environment variables
3. .env file
4. Defaults (lowest)

### Available Flags

```
--harvest_portals JSON       Portal URLs mapping
--mysql_pwd TEXT             MySQL password
--mysql_duckdb_path TEXT     DuckDB connection string
--output_db TEXT             Target database name
--output_table TEXT          Target table name
```

## Production

```bash
just publish  # Build multi-platform image (linux/amd64 + linux/arm64)
```

### Environment Variables

```bash
HARVEST_PORTALS='{"engagementhq":["https://..."],"citizenspace":["https://..."]}'
MYSQL_PWD='password'
MYSQL_DUCKDB_PATH='host=mysql-host user=root database=harvest_consultations'
OUTPUT_DB='harvest_consultations'
OUTPUT_TABLE='consultations'
```

Refer to [DuckDB MySQL extension docs](https://duckdb.org/docs/extensions/mysql#configuration) for connection options.

## Architecture

**Stack:** Python 3.13+ with uv → Ibis+DuckDB → MySQL

**Configuration:** Pydantic-settings v2+ with native CLI parsing (no argparse/click/typer)

**Pipeline:**
1. `models/api/*.py` - Fetch from REST APIs (returns DataFrames)
2. `models/transforms.sql` - DuckDB SQL transforms (raw → standardised → final)
3. `harvest/__main__.py` - Harvester class orchestrates the flow

**Database:** DuckDB (ephemeral) → MySQL (persistent)

## Adding a New Portal

1. Create `models/api/newsource.py` with `harvest(urls: list[str]) -> pd.DataFrame`
2. Add transformation views and union in `models/transforms.sql`
3. Update `HARVEST_PORTALS` config with source URLs

## Code Style

- Python 3.10+ type hints throughout
- Snake_case functions/vars, SCREAMING_SNAKE_CASE env vars
- Try/except with print() for errors, return empty DataFrame on failure
- SQL: uppercase keywords, explicit aliases, UNION ALL BY NAME
- Always use `uv run python` (not plain `python`)
