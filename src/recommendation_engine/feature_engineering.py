from __future__ import annotations

import logging
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler

LOGGER = logging.getLogger(__name__)


def _normalize_outcome(outcome: str) -> str:
    if not outcome:
        return "unknown"
    outcome = outcome.lower()
    if outcome.startswith("succ"):
        return "success"
    if outcome.startswith("warn"):
        return "warning"
    if outcome.startswith("fail") or outcome.startswith("err"):
        return "failure"
    return outcome


def build_feature_frame(df: pd.DataFrame) -> Tuple[pd.DataFrame, pd.DataFrame, StandardScaler]:
    """Return (feature_df, metrics_df, scaler)."""
    LOGGER.info("Engineering features for %s raw events", len(df))
    df = df.copy()
    df["outcome_norm"] = df["outcome"].fillna("unknown").apply(_normalize_outcome)
    df["satisfaction_score"] = df["satisfaction_score"].fillna(df["satisfaction_score"].mean())

    aggregations: Dict[str, List[Tuple[str, str]]] = {
        "event_timestamp": [("events_per_day", "count")],
        "tool_name": [("unique_tools", pd.Series.nunique)],
        "latency_ms": [("avg_latency_ms", "mean")],
        "satisfaction_score": [("avg_satisfaction", "mean")],
    }

    metrics = (
        df.groupby("team_id")
        .agg(**{alias: (col, fn) for col, pairs in aggregations.items() for alias, fn in pairs})
        .fillna(0)
    )

    outcome_pivot = (
        df.groupby(["team_id", "outcome_norm"])
        .size()
        .unstack(fill_value=0)
        .rename(columns=str)
    )
    action_pivot = (
        df.groupby(["team_id", "action_type"])
        .size()
        .unstack(fill_value=0)
        .rename(columns=lambda c: f"action_{c}")
    )
    tool_pivot = (
        df.groupby(["team_id", "tool_name"])
        .size()
        .unstack(fill_value=0)
        .rename(columns=lambda c: f"tool_{c.replace(' ', '_').lower()}")
    )

    feature_frame = pd.concat([metrics, outcome_pivot, action_pivot, tool_pivot], axis=1).fillna(0)
    feature_frame = feature_frame.replace([np.inf, -np.inf], 0)

    scaler = StandardScaler()
    scaled_values = scaler.fit_transform(feature_frame)
    feature_df = pd.DataFrame(scaled_values, index=feature_frame.index, columns=feature_frame.columns)

    LOGGER.info("Feature frame shape: %s", feature_df.shape)
    return feature_df, metrics, scaler
