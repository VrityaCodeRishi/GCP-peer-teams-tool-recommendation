output "activity_dataset" {
  value       = google_bigquery_dataset.activity.dataset_id
  description = "Dataset receiving normalized DevOps activity logs."
}

output "shared_team_artifact_repository" {
  value       = google_artifact_registry_repository.shared_team.id
  description = "Artifact Registry repository shared by teams without dedicated repos."
}

output "shared_team_artifact_bucket" {
  value       = google_storage_bucket.shared_team.name
  description = "Shared Cloud Storage bucket for teams without dedicated buckets."
}

output "recommendation_table" {
  value       = google_bigquery_table.recommendations.table_id
  description = "BigQuery table storing generated recommendations."
}

output "feedback_topics" {
  value       = { for k, m in module.team_sinks : k => m.feedback_topic }
  description = "Per-team Pub/Sub topics accepting satisfaction feedback."
}

output "feedback_subscriptions" {
  value       = { for k, m in module.team_sinks : k => m.feedback_subscription }
  description = "Pull subscriptions for the runner service account."
}

output "team_service_accounts" {
  value       = { for k, m in module.team_sinks : k => m.team_service_account_email }
  description = "CI/CD service accounts provisioned for each team."
}

output "team_artifact_repositories" {
  value       = { for k, m in module.team_sinks : k => m.artifact_registry_repository }
  description = "Artifact Registry repository identifier each team pushes to (dedicated or shared)."
}

output "team_artifact_buckets" {
  value       = { for k, m in module.team_sinks : k => m.artifact_bucket }
  description = "Cloud Storage bucket each team uses for build artifacts (dedicated or shared)."
}
