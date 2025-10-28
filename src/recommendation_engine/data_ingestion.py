from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

import pandas as pd

try:
    from google.cloud import bigquery
except ImportError:  # pragma: no cover - optional dependency for local runs
    bigquery = None  # type: ignore

from .config import PipelineConfig

LOGGER = logging.getLogger(__name__)


@dataclass
class DataIngestion:
    """Fetches activity logs from BigQuery or local CSV files."""

    config: PipelineConfig
    client: Optional["bigquery.Client"] = None

    def __post_init__(self) -> None:
        if self.client is None and bigquery is not None:
            self.client = bigquery.Client(project=self.config.project_id)

    def load_activity_frame(self, sample_path: Optional[Path] = None) -> pd.DataFrame:
        """Return a DataFrame with activity logs."""
        if sample_path:
            LOGGER.info("Loading sample data from %s", sample_path)
            return pd.read_csv(sample_path, parse_dates=["event_timestamp"])

        if not self.client:
            raise RuntimeError("BigQuery client unavailable and no sample_path provided.")

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
        LOGGER.info("Querying BigQuery table %s", self.config.activity_table_fqn)
        result = self.client.query(query, job_config=job_config).result()
        dataframe = result.to_dataframe(create_bqstorage_client=True)
        LOGGER.info("Fetched %s rows from BigQuery", len(dataframe))
        return dataframe
