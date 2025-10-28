# Architecture Overview

## Core components

### Log ingestion
- **Cloud Logging sinks** route Cloud Audit Logs (`cloudaudit.googleapis.com/activity`) and Cloud Build logs to a central BigQuery dataset.
- **BigQuery dataset** `devops_activity` stores normalized log entries partitioned by day with clustering on `team_id`.
- **Pub/Sub feedback topics** (`team-*-feedback`) collect lightweight satisfaction scores (1–5) via chatbots or forms for enrichment.

### Processing & analytics
- **Service account** `devops-reco-runner` executes scheduled data processing jobs (Cloud Run, Composer, or Vertex AI Workbench).
- **Cloud Storage bucket** `devops-recommendation-artifacts` stores model artifacts, clustering snapshots, and visualization exports.
- **Python pipeline** (see `src/recommendation_engine`) runs feature engineering, clustering, and recommendation scoring using scikit-learn.

### Per-team DevOps surfaces
- **CI/CD service account** `team-<team>-builder` for each team to execute Cloud Build or deployment jobs.
- **Artifact storage**: Teams can share the platform-wide repository/bucket or opt into dedicated `team-<team>-repo` and `<project>-<team>-artifacts` resources for isolation.
- **Feedback Pub/Sub topic/subscription** `team-<team>-feedback` feeding satisfaction scores back to the pipeline.
- **Configuration knobs**: Toggle `dedicated_repo` / `dedicated_bucket` inside `infra/variables.tf:30` to choose between shared or isolated storage per team.
- **Synthetic activity**: Cloud Scheduler jobs (`team-*-activity`) submit lightweight Cloud Build jobs for each team service account so `team_activity` always has fresh events when real pipelines are not yet emitting data.

### Visualization & delivery
- **BigQuery views** expose curated fact tables for Looker Studio dashboards.
- **Optional**: Cloud Functions or Workflows push recommended actions to team Slack channels.

## Data model

| field | type | description |
| --- | --- | --- |
| `event_timestamp` | TIMESTAMP | Event time from the originating service |
| `team_id` | STRING | Normalized team or service account identifier |
| `tool_name` | STRING | GCP tool or component (Cloud Build, Artifact Registry, etc.) |
| `action_type` | STRING | Normalized verb (deploy, build, audit, automate) |
| `outcome` | STRING | success, failure, warning |
| `satisfaction_score` | INT64 | Optional 1–5 feedback from teams |
| `latency_ms` | INT64 | Duration when provided |

## Clustering & recommendation workflow

1. **Extract** events from BigQuery for the trailing N weeks.
2. **Transform** raw logs into aggregated metrics per team: frequency, failure rate, diversity, peak hours.
3. **Cluster** teams using `MiniBatchKMeans` based on standardized features.
4. **Score recommendations** by comparing each team's toolset against high-performing peers in the same cluster.
5. **Deliver** top-N recommendations via BigQuery table `team_recommendations` and optional CSV exports.

## Security considerations

- Grant least-privilege IAM roles to the `devops-reco-runner` service account (BigQuery Data Viewer, Pub/Sub Subscriber, Storage Object Admin on the artifact bucket).
- Use CMEK or default encryption for BigQuery and Storage resources.
- Enable audit logging for Terraform service account to track infrastructure changes.
