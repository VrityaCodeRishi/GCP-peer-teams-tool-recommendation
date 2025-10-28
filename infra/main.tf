locals {
  required_apis = [
    "bigquery.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "workflows.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each           = toset(local.required_apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "runner" {
  account_id   = "devops-reco-runner"
  display_name = "DevOps Recommendation Runner"
}

resource "google_project_iam_member" "runner_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.runner.email}"
}

resource "google_project_iam_member" "runner_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.runner.email}"
}

resource "google_project_iam_member" "runner_logging" {
  project = var.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.runner.email}"
}

resource "google_artifact_registry_repository" "shared_team" {
  location      = var.region
  repository_id = var.shared_artifact_repo_id
  description   = "Shared repository for teams without dedicated Artifact Registry."
  format        = "DOCKER"
  mode          = "STANDARD_REPOSITORY"
  labels        = var.labels
}

resource "google_storage_bucket" "shared_team" {
  name          = var.shared_team_bucket_name
  location      = var.location
  force_destroy = false

  uniform_bucket_level_access = true
  labels                      = var.labels

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 120
    }
  }
}

resource "google_storage_bucket" "artifacts" {
  name          = var.artifact_bucket_name
  location      = var.location
  force_destroy = false

  uniform_bucket_level_access = true
  labels                      = var.labels
  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365
    }
  }
}

resource "google_storage_bucket_iam_member" "runner_bucket_admin" {
  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.runner.email}"
}

resource "google_bigquery_dataset" "activity" {
  dataset_id = var.dataset_id
  project    = var.project_id
  location   = var.location

  labels = var.labels

  default_table_expiration_ms = 90 * 24 * 60 * 60 * 1000

  access {
    role          = "OWNER"
    user_by_email = google_service_account.runner.email
  }

  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  depends_on = [google_project_service.required]
}

resource "google_bigquery_table" "activity" {
  dataset_id          = google_bigquery_dataset.activity.dataset_id
  project             = google_bigquery_dataset.activity.project
  table_id            = "team_activity"
  deletion_protection = false

  schema = jsonencode([
    { name = "event_timestamp", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "team_id", type = "STRING", mode = "REQUIRED" },
    { name = "tool_name", type = "STRING", mode = "REQUIRED" },
    { name = "action_type", type = "STRING", mode = "NULLABLE" },
    { name = "outcome", type = "STRING", mode = "NULLABLE" },
    { name = "satisfaction_score", type = "INTEGER", mode = "NULLABLE" },
    { name = "latency_ms", type = "INTEGER", mode = "NULLABLE" }
  ])

  time_partitioning {
    type  = "DAY"
    field = "event_timestamp"
  }

  clustering = ["team_id", "tool_name"]

  labels = var.labels
}

resource "google_bigquery_table" "recommendations" {
  dataset_id          = google_bigquery_dataset.activity.dataset_id
  project             = google_bigquery_dataset.activity.project
  table_id            = "team_recommendations"
  deletion_protection = false

  schema = jsonencode([
    { name = "team_id", type = "STRING", mode = "REQUIRED" },
    { name = "recommended_tool", type = "STRING", mode = "REQUIRED" },
    { name = "confidence", type = "FLOAT", mode = "NULLABLE" },
    { name = "cluster_id", type = "INTEGER", mode = "NULLABLE" },
    { name = "generated_at", type = "TIMESTAMP", mode = "REQUIRED" }
  ])

  labels = var.labels
}

module "team_sinks" {
  for_each = var.team_configs

  source                          = "./modules/team"
  project_id                      = var.project_id
  dataset_id                      = google_bigquery_dataset.activity.dataset_id
  dataset_project                 = google_bigquery_dataset.activity.project
  location                        = var.location
  region                          = var.region
  team_id                         = each.key
  display_name                    = each.value.display_name
  log_filter                      = each.value.log_filter
  labels                          = var.labels
  runner_sa_email                 = google_service_account.runner.email
  enable_dedicated_repo           = each.value.dedicated_repo
  enable_dedicated_bucket         = each.value.dedicated_bucket
  shared_artifact_repo_project    = google_artifact_registry_repository.shared_team.project
  shared_artifact_repo_location   = google_artifact_registry_repository.shared_team.location
  shared_artifact_repo_id         = google_artifact_registry_repository.shared_team.repository_id
  shared_artifact_bucket_name     = google_storage_bucket.shared_team.name
  shared_artifact_bucket_location = google_storage_bucket.shared_team.location

  depends_on = [
    google_bigquery_table.activity,
    google_artifact_registry_repository.shared_team,
    google_storage_bucket.shared_team,
  ]
}

resource "google_bigquery_dataset_iam_member" "sink_writers" {
  for_each = module.team_sinks

  project    = google_bigquery_dataset.activity.project
  dataset_id = google_bigquery_dataset.activity.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = each.value.sink_writer_identity
}

output "runner_service_account_email" {
  value       = google_service_account.runner.email
  description = "Service account that executes the analytics pipeline."
}

output "artifact_bucket_name" {
  value       = google_storage_bucket.artifacts.name
  description = "Bucket storing pipeline artifacts and visualizations."
}
