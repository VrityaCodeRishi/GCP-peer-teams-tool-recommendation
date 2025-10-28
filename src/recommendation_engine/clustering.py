from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Dict, List

import pandas as pd
from sklearn.cluster import MiniBatchKMeans

LOGGER = logging.getLogger(__name__)


@dataclass
class ClusterModel:
    kmeans: MiniBatchKMeans
    cluster_assignments: pd.Series

    def describe(self) -> pd.DataFrame:
        return self.cluster_assignments.value_counts().rename("teams_per_cluster").to_frame()


def fit_clusters(
    features: pd.DataFrame,
    cluster_count: int,
    random_state: int = 42,
    batch_size: int = 16,
) -> ClusterModel:
    LOGGER.info("Fitting MiniBatchKMeans with k=%s", cluster_count)
    kmeans = MiniBatchKMeans(
        n_clusters=cluster_count,
        random_state=random_state,
        batch_size=batch_size,
        n_init="auto",
    )
    assignments = kmeans.fit_predict(features)
    cluster_series = pd.Series(assignments, index=features.index, name="cluster_id")
    LOGGER.info("Cluster distribution:\n%s", cluster_series.value_counts())
    return ClusterModel(kmeans=kmeans, cluster_assignments=cluster_series)
