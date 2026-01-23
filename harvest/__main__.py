"""Harvest consultation data from WA Gov APIs → DuckDB → MySQL."""

import asyncio
import json
import os
import re
import sys
from pathlib import Path

import httpx
import ibis
import pandas as pd


def get_config() -> dict:
    def env(key: str, default: str = "") -> str:
        return os.getenv(key, default).strip("'\"")

    portals = env("HARVEST_PORTALS", "{}")
    return {
        "portals": json.loads(portals) if isinstance(portals, str) else portals,
        "mysql_pwd": env("MYSQL_PWD"),
        "mysql_path": env("MYSQL_DUCKDB_PATH", "host=localhost user=root"),
        # Support both new env vars and legacy SQLMESH__VARIABLES__ prefix
        "output_db": env("OUTPUT_DB")
        or env("SQLMESH__VARIABLES__OUTPUT_DB", "harvest_consultations"),
        "output_table": env("OUTPUT_TABLE")
        or env("SQLMESH__VARIABLES__OUTPUT_TABLE", "consultations"),
    }


def get_mysql_connection(cfg: dict, database: str | None = None):
    """Get DuckDB connection with MySQL attached."""
    con = ibis.duckdb.connect()
    con_str = cfg["mysql_path"]
    if cfg["mysql_pwd"] and "password=" not in con_str:
        con_str += f" password={cfg['mysql_pwd']}"
    if database and "database=" not in con_str:
        con_str += f" database={database}"
    con.raw_sql("INSTALL mysql; LOAD mysql")
    con.raw_sql(f"ATTACH '{con_str}' AS mysql (TYPE mysql)")
    return con


async def fetch_engagementhq(client: httpx.AsyncClient, url: str) -> list[dict]:
    """Fetch projects from single EngagementHQ portal."""
    try:
        page = (await client.get(url)).text
        tokens = re.findall(r"eyJ[A-Za-z0-9._-]+", page)
        if not tokens:
            tokens = re.findall(r'data-thunder="([^"]*)"', page)
        if not tokens:
            print(f"  No auth token: {url}")
            return []
        resp = await client.get(
            f"{url}/api/v2/projects",
            params={"per_page": 10000},
            headers={"Authorization": f"Bearer {tokens[0]}"},
        )
        results = []
        for row in resp.json().get("data", []):
            row.update(row.pop("attributes", {}))
            row["url"] = row.get("links", {}).pop("self", url)
            row.pop("relationships", None)
            row.pop("links", None)
            results.append(row)
        return results
    except Exception as e:
        print(f"  Error {url}: {e}")
        return []


async def fetch_citizenspace(client: httpx.AsyncClient, url: str) -> list[dict]:
    """Fetch consultations from single CitizenSpace portal."""
    try:
        resp = await client.get(f"{url}/api/2.3/json_search_results?fields=extended")
        return resp.json()
    except Exception as e:
        print(f"  Error {url}: {e}")
        return []


async def harvest_all(portals: dict) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Fetch all portals concurrently."""
    async with httpx.AsyncClient(timeout=30) as client:
        ehq_tasks = [
            fetch_engagementhq(client, u) for u in portals.get("engagementhq", [])
        ]
        cs_tasks = [
            fetch_citizenspace(client, u) for u in portals.get("citizenspace", [])
        ]
        results = await asyncio.gather(*ehq_tasks, *cs_tasks)
        ehq_results = [r for batch in results[: len(ehq_tasks)] for r in batch]
        cs_results = [r for batch in results[len(ehq_tasks) :] for r in batch]
        return pd.DataFrame(ehq_results), pd.DataFrame(cs_results)


def init_db() -> None:
    """Create database if it doesn't exist."""
    cfg = get_config()
    db = cfg["output_db"]
    con = get_mysql_connection(cfg)
    con.raw_sql(f"CALL mysql_execute('mysql', 'CREATE DATABASE IF NOT EXISTS {db}')")
    print(f"Database '{db}' ready")


def stats() -> None:
    """Show database statistics."""
    cfg = get_config()
    db, tbl = cfg["output_db"], cfg["output_table"]
    con = get_mysql_connection(cfg, db)

    print(f"\n=== {db}.{tbl} ===")
    try:
        total = con.raw_sql(f"SELECT COUNT(*) FROM mysql.{tbl}").fetchone()[0]
        print(f"Total rows: {total}\n")

        print("By source/status:")
        for row in con.raw_sql(
            f"SELECT source, status, COUNT(*) as count FROM mysql.{tbl} GROUP BY source, status"
        ).fetchall():
            print(f"  {row[0]:15} {row[1]:10} {row[2]}")

        print("\nSample rows:")
        for row in con.raw_sql(
            f"SELECT source, id, LEFT(name, 50) as name, status FROM mysql.{tbl} LIMIT 5"
        ).fetchall():
            print(f"  {row[0]:15} {row[1]:10} {row[2]:50} {row[3]}")
    except Exception as e:
        print(f"Error: {e}")


def run() -> None:
    """Main harvest pipeline."""
    cfg = get_config()
    con = ibis.duckdb.connect()

    print("Harvesting APIs (async)...")
    ehq, cs = asyncio.run(harvest_all(cfg["portals"]))

    con.con.register("ehq_df", ehq)
    con.raw_sql("CREATE TABLE engagementhq_raw AS SELECT * FROM ehq_df")
    print(f"  EngagementHQ: {len(ehq)} records")

    con.con.register("cs_df", cs)
    con.raw_sql("CREATE TABLE citizenspace_raw AS SELECT * FROM cs_df")
    print(f"  CitizenSpace: {len(cs)} records")

    print("Transforming...")
    sql_path = Path(__file__).parent.parent / "models" / "transforms.sql"
    for stmt in sql_path.read_text().split(";"):
        if stmt.strip():
            con.raw_sql(stmt)

    db, tbl = cfg["output_db"], cfg["output_table"]
    con_str = cfg["mysql_path"]
    if cfg["mysql_pwd"] and "password=" not in con_str:
        con_str += f" password={cfg['mysql_pwd']}"

    print(f"Exporting to MySQL ({db}.{tbl})...")
    con.raw_sql("INSTALL mysql; LOAD mysql")
    con.raw_sql(f"ATTACH '{con_str}' AS mysql (TYPE mysql)")
    con.raw_sql(f"CALL mysql_execute('mysql', 'CREATE DATABASE IF NOT EXISTS {db}')")
    # Reattach with database specified
    con.raw_sql("DETACH mysql")
    con.raw_sql(f"ATTACH '{con_str} database={db}' AS mysql (TYPE mysql)")
    con.raw_sql(
        f"CREATE OR REPLACE TABLE mysql.{tbl} AS SELECT * FROM consultations_final"
    )

    result = con.raw_sql(f"SELECT COUNT(*) FROM mysql.{db}.{tbl}").fetchone()
    print(f"  Done: {result[0]} rows")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "run"
    {"run": run, "init": init_db, "stats": stats}.get(cmd, run)()
