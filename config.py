"""Configuration management using Pydantic Settings.

This module uses pydantic-settings v2+ native CLI parsing. All settings are
auto-parsed from CLI flags, environment variables, and .env file (in that order
of precedence, with CLI flags highest).

Example usage:
    # From environment variables or .env
    config = HarvestConfig()
    
    # From CLI (auto-parsed when used as script)
    python -m harvest --help  # Shows all available flags
    python -m harvest --output_db custom_db --output_table custom_table
"""

import json
from typing import Any

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class HarvestConfig(BaseSettings):
    """Configuration for the harvest pipeline.

    Settings are loaded in the following order (highest to lowest precedence):
    1. CLI flags (e.g., --output_db mydb)
    2. Environment variables (e.g., OUTPUT_DB=mydb)
    3. .env file
    4. Field defaults

    Attributes:
        harvest_portals: Mapping of API types to their endpoint URLs (JSON).
            Format: {"engagementhq": ["url1", "url2"], "citizenspace": ["url3"]}
        mysql_pwd: MySQL root password for DuckDB connection.
        mysql_duckdb_path: DuckDB connection string for MySQL.
            Format: "host=localhost user=root database=harvest_consultations"
        output_db: Target database name in MySQL.
        output_table: Target table name in MySQL.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        cli_parse_args=True,
    )

    harvest_portals: dict[str, list[str]] = Field(
        default_factory=dict,
        description="Mapping of API types to endpoint URLs (JSON string or dict)",
    )

    mysql_pwd: str = Field(
        default="",
        description="MySQL root password",
    )

    mysql_duckdb_path: str = Field(
        default="host=localhost user=root database=harvest_consultations",
        description="DuckDB MySQL connection string",
    )

    output_db: str = Field(
        default="harvest_consultations",
        description="Target MySQL database name",
    )

    output_table: str = Field(
        default="consultations",
        description="Target MySQL table name",
    )

    @field_validator("harvest_portals", mode="before")
    @classmethod
    def parse_harvest_portals(cls, v: Any) -> dict[str, list[str]]:
        """Parse HARVEST_PORTALS from JSON string or dict.

        Args:
            v: Value from environment or CLI (string or dict)

        Returns:
            Parsed dictionary mapping portal types to URL lists
        """
        if isinstance(v, str):
            try:
                return json.loads(v)
            except json.JSONDecodeError:
                return {}
        return v or {}

    def get_duckdb_connection_string(self) -> str:
        """Get the DuckDB MySQL connection string with password.

        Returns:
            Complete connection string including password if set
        """
        if self.mysql_pwd and "password=" not in self.mysql_duckdb_path:
            return f"{self.mysql_duckdb_path} password={self.mysql_pwd}"
        return self.mysql_duckdb_path
