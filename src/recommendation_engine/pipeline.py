from __future__ import annotations

import argparse
import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import pandas as pd

try:
    from google.cloud import bigquery
except ImportError:  # pragma: no cover - optional dependency
    bigquery = None  # type: ignore

from .clustering import fit_clusters
from .config import PipelineConfig
from .data_ingestion import DataIngestion
from .feature_engineering import build_feature_frame
from .recommendation import recommend_tools
from .visualization import plot_cluster_heatmap, plot_recommendations_bar

LOGGER = logging.getLogger(__name__)


def run_pipeline(config: PipelineConfig, sample_data: Optional[Path] = None) -> None:
    """Execute the end-to-end analytics pipeline."""
    LOGGER.info("Starting recommendation pipeline for project %s", config.project_id)
    ingestion = DataIngestion(config=config)
    raw_events = ingestion.load_activity_frame(sample_path=sample_data)

    feature_df, metrics_df, scaler = build_feature_frame(raw_events)
    cluster_model = fit_clusters(feature_df, cluster_count=config.cluster_count)
    rec_result = recommend_tools(cluster_model.cluster_assignments, metrics_df, raw_events, config.recommendation_count)

    config.model_dir.mkdir(exist_ok=True, parents=True)
    generated_at = datetime.now(timezone.utc)
    recommendation_df = rec_result.recommendations.copy()
    recommendation_df["generated_at"] = pd.Timestamp(generated_at)

    artifacts = {
        "cluster_assignments": cluster_model.cluster_assignments.to_dict(),
        "metrics_columns": metrics_df.columns.tolist(),
        "scaler_mean": scaler.mean_.tolist(),
        "scaler_scale": scaler.scale_.tolist(),
    }
    artifact_path = config.model_dir / "artifacts.json"
    artifact_path.write_text(json.dumps(artifacts, indent=2))
    LOGGER.info("Persisted model artifacts to %s", artifact_path)

    heatmap_path = plot_cluster_heatmap(feature_df, cluster_model.cluster_assignments, output_dir=config.model_dir)
    rec_plot_path = plot_recommendations_bar(rec_result.recommendations, output_dir=config.model_dir)

    recommendation_path = config.model_dir / "recommendations.csv"
    recommendation_df.to_csv(recommendation_path, index=False)
    LOGGER.info("Wrote recommendations to %s", recommendation_path)

    if ingestion.client and bigquery is not None:
        table_id = config.recommendation_table_fqn
        LOGGER.info("Publishing recommendations to BigQuery table %s", table_id)
        load_job_config = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        )
        upload_df = recommendation_df.rename(columns={"tool_name": "recommended_tool"})
        ingestion.client.load_table_from_dataframe(upload_df, table_id, job_config=load_job_config).result()

    LOGGER.info("Artifacts generated: %s, %s, %s", artifact_path, heatmap_path, rec_plot_path)


def _cli() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

    parser = argparse.ArgumentParser(description="Run the DevOps resource recommendation pipeline.")
    parser.add_argument("--project-id", required=False, default="example-project")
    parser.add_argument("--dataset-id", default="devops_activity")
    parser.add_argument("--activity-table", default="team_activity")
    parser.add_argument("--sample-data", type=Path, default=None, help="Optional path to CSV for local execution.")
    parser.add_argument("--cluster-count", type=int, default=3)
    parser.add_argument("--recommendation-count", type=int, default=5)
    parser.add_argument("--model-dir", type=Path, default=Path("artifacts"))
    args = parser.parse_args()

    config = PipelineConfig(
        project_id=args.project_id,
        dataset_id=args.dataset_id,
        activity_table=args.activity_table,
        cluster_count=args.cluster_count,
        recommendation_count=args.recommendation_count,
        model_dir=args.model_dir,
    )
    run_pipeline(config=config, sample_data=args.sample_data)


if __name__ == "__main__":
    _cli()
