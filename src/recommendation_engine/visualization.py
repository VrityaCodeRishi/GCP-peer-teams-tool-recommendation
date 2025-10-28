from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns

LOGGER = logging.getLogger(__name__)


def plot_cluster_heatmap(features: pd.DataFrame, assignments: pd.Series, output_dir: Optional[Path] = None) -> Path:
    """Plot a heatmap of average feature values per cluster."""
    plot_df = features.copy()
    plot_df["cluster_id"] = assignments
    means = plot_df.groupby("cluster_id").mean()

    plt.figure(figsize=(12, 6))
    sns.heatmap(means, cmap="Blues", annot=True, fmt=".2f")
    plt.title("Average Feature Values per Cluster")
    plt.tight_layout()

    output_dir = output_dir or Path("artifacts")
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / "cluster_heatmap.png"
    plt.savefig(path)
    plt.close()
    LOGGER.info("Saved cluster heatmap to %s", path)
    return path


def plot_recommendations_bar(recommendations: pd.DataFrame, output_dir: Optional[Path] = None) -> Path:
    """Plot confidence scores for recommendations."""
    plt.figure(figsize=(10, 5))
    sns.barplot(data=recommendations, x="team_id", y="confidence", hue="tool_name")
    plt.title("Recommendation Confidence by Tool")
    plt.ylabel("Confidence score")
    plt.tight_layout()

    output_dir = output_dir or Path("artifacts")
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / "recommendations.png"
    plt.savefig(path)
    plt.close()
    LOGGER.info("Saved recommendations bar chart to %s", path)
    return path
