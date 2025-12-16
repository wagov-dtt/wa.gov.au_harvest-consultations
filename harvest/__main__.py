"""Harvest consultation data from APIs and load to MySQL.

This module orchestrates the complete data pipeline:
1. Harvest from external API portals (EngagementHQ, CitizenSpace)
2. Create DuckDB tables from raw data
3. Transform and standardize data via SQL
4. Export final table to MySQL

CLI Usage:
    python -m harvest                                    # Use .env defaults
    python -m harvest --help                             # Show all flags
    python -m harvest --output_db mydb --output_table mytable
    HARVEST_PORTALS='{"engagementhq":["url"]}' python -m harvest

The Harvester class accepts a single HarvestConfig object that is auto-parsed
from CLI flags, environment variables, and .env file by pydantic-settings.
"""

import ibis

from config import HarvestConfig
from models.api import engagementhq, citizenspace


class Harvester:
    """Orchestrates the consultation data harvest pipeline.

    This class encapsulates the three-stage pipeline:
    - harvest_apis(): Fetch from external portals
    - run_transforms(): Apply DuckDB SQL transformations
    - export_mysql(): Write final table to MySQL

    The configuration is fully determined by a HarvestConfig object that is
    auto-parsed from CLI flags, environment variables, and .env file by
    pydantic-settings (v2+). No other arguments are needed.

    Attributes:
        config: HarvestConfig instance with all pipeline settings
        con: Ibis DuckDB connection for in-memory data processing
    """

    def __init__(self, config: HarvestConfig) -> None:
        """Initialize harvester with pydantic-settings configuration.

        Args:
            config: HarvestConfig instance (auto-parsed from CLI/env/dotenv)

        Raises:
            TypeError: If config is not a HarvestConfig instance
        """
        if not isinstance(config, HarvestConfig):
            raise TypeError(
                f"config must be HarvestConfig, got {type(config).__name__}"
            )
        self.config = config
        self.con = ibis.duckdb.connect(":memory:")

    def harvest_apis(self) -> None:
        """Fetch data from all configured portals.

        Creates raw tables in DuckDB for each API source:
        - engagementhq_raw: Projects from EngagementHQ portals
        - citizenspace_raw: Consultations from CitizenSpace portals

        Logs the number of records fetched from each source.
        """
        portals = self.config.harvest_portals

        print("Harvesting EngagementHQ...")
        ehq_df = engagementhq.harvest(portals.get("engagementhq", []))
        self.con.create_table("engagementhq_raw", ehq_df)
        print(f"  Loaded {len(ehq_df)} records")

        print("Harvesting CitizenSpace...")
        cs_df = citizenspace.harvest(portals.get("citizenspace", []))
        self.con.create_table("citizenspace_raw", cs_df)
        print(f"  Loaded {len(cs_df)} records")

    def run_transforms(self) -> None:
        """Execute DuckDB SQL transformations.

        Reads models/transforms.sql which:
        1. Creates standardized views (*_std) from raw tables
        2. Unions views into consultations_final
        3. Filters to only open/closed consultations
        """
        print("Running transformations...")
        with open("models/transforms.sql") as f:
            for stmt in f.read().split(";"):
                stmt = stmt.strip()
                if stmt:
                    self.con.sql(stmt)

    def export_mysql(self) -> None:
        """Export final table to MySQL.

        Uses DuckDB MySQL extension to attach to MySQL and create/replace
        the target table. Logs the final record count.

        Table location: {config.output_db}.{config.output_table}
        """
        con_str = self.config.get_duckdb_connection_string()
        print(
            f"Exporting to MySQL ({self.config.output_db}.{self.config.output_table})..."
        )

        self.con.sql(f"""
            INSTALL mysql;
            LOAD mysql;
            ATTACH '{con_str}' AS mysql (TYPE mysql);
            CREATE OR REPLACE TABLE mysql.{self.config.output_db}.{self.config.output_table} AS
            SELECT * FROM consultations_final;
        """)

        result = self.con.sql(
            f"SELECT COUNT(*) as cnt FROM mysql.{self.config.output_db}.{self.config.output_table}"
        ).execute()
        print(f"  Export complete: {result[0][0]} rows in MySQL")

    def run(self) -> None:
        """Execute the complete pipeline: harvest → transform → export."""
        self.harvest_apis()
        self.run_transforms()
        self.export_mysql()


def main() -> None:
    """Entry point: instantiate pydantic-settings config and run harvester.

    HarvestConfig() auto-parses from:
    1. CLI flags (highest precedence)
    2. Environment variables
    3. .env file
    4. Field defaults
    """
    config = HarvestConfig()
    harvester = Harvester(config)
    harvester.run()


if __name__ == "__main__":
    main()
