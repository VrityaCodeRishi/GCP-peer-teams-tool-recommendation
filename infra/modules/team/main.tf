locals {
  topic_name         = "team-${var.team_id}-feedback"
  subscription_name  = "team-${var.team_id}-feedback-runner"
  sanitized_team_id  = replace(var.team_id, "_", "-")
  service_account_id = substr("team-${replace(var.team_id, "_", "-")}-builder", 0, 30)
  bucket_name        = lower(substr(replace("${var.project_id}-${var.team_id}-artifacts", "_", "-"), 0, 63))
  artifact_repo_id   = substr("team-${replace(var.team_id, "_", "-")}-repo", 0, 63)
}


resource "google_logging_project_sink" "activity_sink" {
  name        = "team-${var.team_id}-activity-sink"
  project     = var.project_id
  description = "Exports DevOps activity logs for ${var.display_name}."
  

  destination = "bigquery.googleapis.com/projects/${var.dataset_project}/datasets/${var.dataset_id}/tables/team_activity"
  

  filter = <<-EOT
    (
      (
        resource.type="cloud_run_revision"
        AND (
          resource.labels.service_name="shared-heartbeat"
          OR resource.labels.service_name="team-${var.team_id}-unique"
        )
        AND httpRequest.requestUrl=~"/heartbeat/${var.team_id}"
      )
      OR
      (
        resource.type="cloud_build"
        AND (
          labels.team_id="${var.team_id}"
          OR jsonPayload.team_id="${var.team_id}"
        )
      )
      OR
      (
        protoPayload.serviceName="artifactregistry.googleapis.com"
        AND (
          labels.team_id="${var.team_id}"
          OR protoPayload.resourceName=~".*${var.team_id}.*"
        )
      )
      OR
      (
        ${var.log_filter}
      )
    )
  EOT
  
  unique_writer_identity = true
  
  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_pubsub_topic" "feedback" {
  name   = local.topic_name
  labels = var.labels
}

resource "google_pubsub_subscription" "feedback_runner" {
  name  = local.subscription_name
  topic = google_pubsub_topic.feedback.name

  ack_deadline_seconds       = 30
  message_retention_duration = "604800s" # 7 days
  retain_acked_messages      = true

  labels = var.labels
}

resource "google_pubsub_subscription_iam_member" "runner_subscriber" {
  subscription = google_pubsub_subscription.feedback_runner.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.runner_sa_email}"
}

resource "google_service_account" "team_builder" {
  account_id   = local.service_account_id
  display_name = "${var.display_name} Builder"
  description  = "Executes Cloud Build and deployment actions for ${var.display_name}."
}

resource "google_artifact_registry_repository" "team_repo" {
  count = var.enable_dedicated_repo ? 1 : 0

  location      = var.region
  repository_id = local.artifact_repo_id
  description   = "Container images for ${var.display_name}."
  format        = "DOCKER"
  mode          = "STANDARD_REPOSITORY"
  labels        = var.labels
}

resource "google_storage_bucket" "team_artifacts" {
  count = var.enable_dedicated_bucket ? 1 : 0

  name          = local.bucket_name
  location      = var.location
  force_destroy = false

  uniform_bucket_level_access = true
  labels                      = var.labels

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 60
    }
  }
}

locals {
  final_repo_project  = try(google_artifact_registry_repository.team_repo[0].project, var.shared_artifact_repo_project)
  final_repo_location = try(google_artifact_registry_repository.team_repo[0].location, var.shared_artifact_repo_location)
  final_repo_id       = try(google_artifact_registry_repository.team_repo[0].repository_id, var.shared_artifact_repo_id)

  final_bucket_name     = try(google_storage_bucket.team_artifacts[0].name, var.shared_artifact_bucket_name)
  final_bucket_location = try(google_storage_bucket.team_artifacts[0].location, var.shared_artifact_bucket_location)
}

resource "google_artifact_registry_repository_iam_member" "team_writer" {
  project    = local.final_repo_project
  location   = local.final_repo_location
  repository = local.final_repo_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.team_builder.email}"
}

resource "google_project_iam_member" "team_builder_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.team_builder.email}"
}

resource "google_storage_bucket_iam_member" "team_artifacts_admin" {
  bucket = local.final_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.team_builder.email}"
}

output "sink_writer_identity" {
  description = "Service account used by the logging sink."
  value       = google_logging_project_sink.activity_sink.writer_identity
}

output "feedback_topic" {
  description = "Feedback Pub/Sub topic name."
  value       = google_pubsub_topic.feedback.name
}

output "feedback_subscription" {
  description = "Runner subscription that consumes feedback messages."
  value       = google_pubsub_subscription.feedback_runner.name
}

output "team_service_account_email" {
  description = "Service account representing the team's CI/CD identity."
  value       = google_service_account.team_builder.email
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository backing the team's container images."
  value       = "${local.final_repo_project}/${local.final_repo_location}/${local.final_repo_id}"
}

output "artifact_bucket" {
  description = "Cloud Storage bucket for team-specific build artifacts."
  value       = local.final_bucket_name
}
