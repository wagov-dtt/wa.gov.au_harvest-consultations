"""Tests using real API data from WA Gov consultation portals."""

import asyncio
import ibis
import pytest
from pathlib import Path

from harvest.__main__ import fetch_engagementhq, fetch_citizenspace, harvest_all
import httpx


EHQ_URLS = ["https://yoursay.dpird.wa.gov.au"]
CS_URLS = ["https://consultation.health.wa.gov.au"]


class TestHarvesters:
    def test_engagementhq_returns_data(self):
        async def fetch():
            async with httpx.AsyncClient(timeout=30) as client:
                return await fetch_engagementhq(client, EHQ_URLS[0])

        results = asyncio.run(fetch())
        assert len(results) > 0
        assert "id" in results[0]
        assert "name" in results[0]

    def test_citizenspace_returns_data(self):
        async def fetch():
            async with httpx.AsyncClient(timeout=30) as client:
                return await fetch_citizenspace(client, CS_URLS[0])

        results = asyncio.run(fetch())
        assert len(results) > 0
        assert "id" in results[0]
        assert "title" in results[0]

    def test_harvest_all_concurrent(self):
        portals = {"engagementhq": EHQ_URLS, "citizenspace": CS_URLS}
        ehq, cs = asyncio.run(harvest_all(portals))
        assert len(ehq) > 0
        assert len(cs) > 0


class TestTransforms:
    @pytest.fixture
    def con_with_data(self):
        """DuckDB connection with real harvested data."""
        con = ibis.duckdb.connect()
        portals = {"engagementhq": EHQ_URLS, "citizenspace": CS_URLS}
        ehq, cs = asyncio.run(harvest_all(portals))

        con.con.register("ehq_df", ehq)
        con.con.register("cs_df", cs)
        con.raw_sql("CREATE TABLE engagementhq_raw AS SELECT * FROM ehq_df")
        con.raw_sql("CREATE TABLE citizenspace_raw AS SELECT * FROM cs_df")

        sql_path = Path(__file__).parent / "models" / "transforms.sql"
        for stmt in sql_path.read_text().split(";"):
            if stmt.strip():
                con.raw_sql(stmt)
        return con

    def test_transforms_create_final_table(self, con_with_data):
        result = con_with_data.table("consultations_final").execute()
        assert len(result) > 0

    def test_final_has_required_columns(self, con_with_data):
        result = con_with_data.table("consultations_final").execute()
        required = ["source", "id", "name", "status", "agency", "url", "loaded_at"]
        for col in required:
            assert col in result.columns

    def test_status_filtered_to_open_closed(self, con_with_data):
        result = con_with_data.table("consultations_final").execute()
        assert set(result["status"].unique()).issubset({"open", "closed"})

    def test_source_is_set(self, con_with_data):
        result = con_with_data.table("consultations_final").execute()
        assert set(result["source"].unique()).issubset({"engagementhq", "citizenspace"})
