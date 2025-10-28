from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional


@dataclass
class PipelineConfig:
    """Static configuration for the analytics pipeline."""

    project_id: str
    dataset_id: str = "devops_activity"
    activity_table: str = "team_activity"
    recommendation_table: str = "team_recommendations"
    feedback_topic_prefix: str = "team"
    artifact_bucket: Optional[str] = None
    model_dir: Path = Path("artifacts")
    feature_window_days: int = 28
    cluster_count: int = 3
    recommendation_count: int = 5
    teams: List[str] = field(default_factory=lambda: ["team-atlas", "team-borealis", "team-cosmo", "team-draco"])

    def table_fqn(self, table_name: str) -> str:
        return f"{self.project_id}.{self.dataset_id}.{table_name}"

    @property
    def activity_table_fqn(self) -> str:
        return self.table_fqn(self.activity_table)

    @property
    def recommendation_table_fqn(self) -> str:
        return self.table_fqn(self.recommendation_table)
