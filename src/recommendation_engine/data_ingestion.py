from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

import pandas as pd

try:
    from google.api_core import exceptions as api_exceptions  # type: ignore
    from google.cloud import bigquery
    from google.auth import exceptions as auth_exceptions  # type: ignore
except ImportError:  # pragma: no cover - optional dependency for local runs
    bigquery = None  # type: ignore
    auth_exceptions = None  # type: ignore
    api_exceptions = None  # type: ignore

from .config import PipelineConfig

LOGGER = logging.getLogger(__name__)


@dataclass
class DataIngestion:
    """Fetches activity logs from BigQuery or local CSV files."""

    config: PipelineConfig
    client: Optional["bigquery.Client"] = None

    def __post_init__(self) -> None:
        if self.client is None and bigquery is not None:
            try:
                self.client = bigquery.Client(project=self.config.project_id)
            except Exception as exc:  # pragma: no cover - relies on ADC
                if auth_exceptions and isinstance(exc, auth_exceptions.DefaultCredentialsError):
                    LOGGER.warning("BigQuery credentials not found; falling back to sample/local data. Details: %s", exc)
                    self.client = None
                else:
                    raise

    def load_activity_frame(self, sample_path: Optional[Path] = None) -> pd.DataFrame:
        """Return a DataFrame with activity logs, seeding from sample data if BigQuery is empty."""
        # Attempt to pull from BigQuery when a client is available.
        bq_df = self._fetch_bigquery_frame()
        if bq_df is not None:
            if not bq_df.empty:
                return bq_df
            if sample_path and self.client:
                LOGGER.info(
                    "BigQuery table %s is empty; seeding with sample data from %s",
                    self.config.activity_table_fqn,
                    sample_path,
                )
                sample_df = self._load_sample(sample_path)
                self._seed_bigquery(sample_df)
                return sample_df

        if sample_path:
            LOGGER.info("Loading sample data from %s", sample_path)
            return self._load_sample(sample_path)

        if bq_df is not None:
            LOGGER.info("BigQuery query returned 0 rows and no sample data provided.")
            return bq_df

        raise RuntimeError("BigQuery client unavailable and no sample data provided.")

    def _fetch_bigquery_frame(self) -> Optional[pd.DataFrame]:
        if not self.client or bigquery is None:
            return None

        lower_bound = datetime.utcnow() - timedelta(days=self.config.feature_window_days)
        query = f"""
            SELECT
              event_timestamp,
              team_id,
              tool_name,
              action_type,
              outcome,
              satisfaction_score,
              latency_ms
            FROM `{self.config.activity_table_fqn}`
            WHERE event_timestamp >= @lower_bound
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("lower_bound", "TIMESTAMP", lower_bound)
            ]
        )
        try:
            LOGGER.info("Querying BigQuery table %s", self.config.activity_table_fqn)
            result = self.client.query(query, job_config=job_config).result()
            dataframe = result.to_dataframe(create_bqstorage_client=True)
            LOGGER.info("Fetched %s rows from BigQuery", len(dataframe))
            return dataframe
        except Exception as exc:  # pragma: no cover - relies on external service
            if api_exceptions and isinstance(exc, api_exceptions.NotFound):
                LOGGER.warning("BigQuery table %s not found. Returning empty frame.", self.config.activity_table_fqn)
                return pd.DataFrame()
            if auth_exceptions and isinstance(exc, auth_exceptions.DefaultCredentialsError):
                LOGGER.warning("BigQuery credentials not found; cannot query table. Details: %s", exc)
                return None
            raise

    def _load_sample(self, sample_path: Path) -> pd.DataFrame:
        df = pd.read_csv(sample_path, parse_dates=["event_timestamp"])
        # Ensure column order matches target schema (pandas preserves CSV order but enforce explicitly)
        expected_cols = [
            "event_timestamp",
            "team_id",
            "tool_name",
            "action_type",
            "outcome",
            "satisfaction_score",
            "latency_ms",
        ]
        missing = set(expected_cols) - set(df.columns)
        if missing:
            raise ValueError(f"Sample data missing required columns: {missing}")
        return df[expected_cols]

    def _seed_bigquery(self, dataframe: pd.DataFrame) -> None:
        if not self.client or bigquery is None:
            LOGGER.warning("Cannot seed BigQuery table because client is unavailable.")
            return

        load_config = bigquery.LoadJobConfig(write_disposition=bigquery.WriteDisposition.WRITE_APPEND)
        load_job = self.client.load_table_from_dataframe(
            dataframe,
            self.config.activity_table_fqn,
            job_config=load_config,
        )
        load_job.result()
        LOGGER.info(
            "Seeded %s rows into BigQuery table %s",
            len(dataframe),
            self.config.activity_table_fqn,
        )
