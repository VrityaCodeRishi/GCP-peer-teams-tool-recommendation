from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Dict, List

import pandas as pd

LOGGER = logging.getLogger(__name__)


@dataclass
class RecommendationResult:
    recommendations: pd.DataFrame


def recommend_tools(
    assignments: pd.Series,
    metrics: pd.DataFrame,
    raw_events: pd.DataFrame,
    top_n: int,
) -> RecommendationResult:
    """Generate top-N tool recommendations per team."""
    LOGGER.info("Generating recommendations for %s teams", len(assignments))
    data = raw_events.copy()
    data["cluster_id"] = data["team_id"].map(assignments.to_dict())

    cluster_tool_usage = (
        data.groupby(["cluster_id", "tool_name"])["team_id"]
        .nunique()
        .rename("team_count")
        .reset_index()
    )

    team_tool_usage = (
        data.groupby(["team_id", "tool_name"])["event_timestamp"]
        .count()
        .rename("usage_count")
        .reset_index()
    )

    recommendations: List[pd.DataFrame] = []
    for team_id, cluster_id in assignments.items():
        peer_tools = cluster_tool_usage[cluster_tool_usage["cluster_id"] == cluster_id]
        already_used = set(team_tool_usage[team_tool_usage["team_id"] == team_id]["tool_name"])
        candidate_tools = peer_tools[~peer_tools["tool_name"].isin(already_used)]
        if candidate_tools.empty:
            continue
        enriched = candidate_tools.copy()
        enriched["team_id"] = team_id
        enriched["confidence"] = enriched["team_count"] / peer_tools["team_count"].sum()
        enriched["cluster_id"] = cluster_id
        enriched = enriched.sort_values(by=["confidence", "team_count"], ascending=False).head(top_n)
        recommendations.append(enriched)

    if not recommendations:
        LOGGER.warning("No recommendations generated. Returning empty DataFrame.")
        return RecommendationResult(
            recommendations=pd.DataFrame(columns=["team_id", "tool_name", "confidence", "cluster_id"])
        )

    result = pd.concat(recommendations).reset_index(drop=True)
    ordered = result[["team_id", "tool_name", "confidence", "cluster_id"]]
    LOGGER.info("Generated %s total recommendations", len(ordered))
    return RecommendationResult(recommendations=ordered)
