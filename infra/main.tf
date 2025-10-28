locals {
  required_apis = [
    "bigquery.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "workflows.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudscheduler.googleapis.com",
    "run.googleapis.com",
  ]

  team_runtime = {
    for team_id, _cfg in var.team_configs :
    team_id => merge(
      {
        project_id = var.project_id
        dataset_id = var.dataset_id
      },
      lookup(
        var.team_runtime_overrides,
        team_id,
        {
          project_id = var.project_id
          dataset_id = var.dataset_id
        }
      )
    )
  }

  cloudbuild_trigger_enabled = length(trimspace(var.github_owner)) > 0 && length(trimspace(var.github_repo)) > 0 && length(trimspace(var.cloudbuild_repository)) > 0

  shared_service_image = "us-central1-docker.pkg.dev/${var.project_id}/${var.shared_artifact_repo_id}/shared-service:latest"
  unique_service_image = "us-central1-docker.pkg.dev/${var.project_id}/${var.shared_artifact_repo_id}/unique-service:latest"

  teams_with_dedicated_service = {
    for team_id, cfg in var.team_configs : team_id => cfg if cfg.dedicated_service
  }
}

data "google_project" "current" {
  project_id = var.project_id
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

resource "google_project_iam_member" "runner_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.runner.email}"
}

resource "google_project_iam_member" "runner_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.runner.email}"
}

resource "google_project_iam_member" "cloudbuild_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

resource "google_project_iam_member" "runner_logging" {
  project = var.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.runner.email}"
}

resource "google_project_iam_member" "runner_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
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

resource "google_cloudbuild_trigger" "recommendation" {
  count = local.cloudbuild_trigger_enabled ? 1 : 0

  project         = var.project_id
  location        = var.region
  name            = "devops-recommendation"
  description     = "Runs the recommendation pipeline when changes land in GitHub."
  service_account = google_service_account.runner.id

  repository_event_config {
    repository = var.cloudbuild_repository
    push {
      branch = var.github_branch_regex
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = merge(
    { for team_id, runtime in local.team_runtime :
      "_TEAM_${upper(replace(team_id, "-", "_"))}_PROJECT_ID" => runtime.project_id
    },
    { for team_id, runtime in local.team_runtime :
      "_TEAM_${upper(replace(team_id, "-", "_"))}_DATASET_ID" => runtime.dataset_id
    },
    { for team_id in keys(local.team_runtime) :
      "_TEAM_${upper(replace(team_id, "-", "_"))}_CLUSTER_COUNT" => tostring(var.cloudbuild_cluster_count)
    },
    { for team_id in keys(local.team_runtime) :
      "_TEAM_${upper(replace(team_id, "-", "_"))}_RECO_COUNT" => tostring(var.cloudbuild_recommendation_count)
    },
    { for team_id in keys(local.team_runtime) :
      "_TEAM_${upper(replace(team_id, "-", "_"))}_SAMPLE_DATA_PATH" => var.cloudbuild_sample_data_path
    }
  )

  depends_on = [
    google_project_service.required,
    google_service_account.runner,
  ]
}

resource "google_cloud_run_v2_service" "shared" {
  name     = "shared-heartbeat"
  location = var.region
  project  = var.project_id

  template {
    service_account = google_service_account.runner.email

    containers {
      image = local.shared_service_image
    }
  }

  ingress = "INGRESS_TRAFFIC_ALL"

  depends_on = [
    google_project_service.required,
    google_project_iam_member.cloudbuild_artifact_writer,
  ]
}

resource "google_cloud_run_v2_service" "team_unique" {
  for_each = local.teams_with_dedicated_service

  name     = "team-${each.key}-unique"
  location = var.region
  project  = var.project_id

  template {
    service_account = module.team_sinks[each.key].team_service_account_email

    containers {
      image = local.unique_service_image

      env {
        name  = "TEAM_ID"
        value = each.key
      }

      env {
        name  = "SERVICE_NAME"
        value = "team-${each.key}-unique-service"
      }
    }
  }

  ingress = "INGRESS_TRAFFIC_ALL"

  depends_on = [
    google_project_service.required,
    module.team_sinks,
    google_project_iam_member.cloudbuild_artifact_writer,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "shared_invoker" {
  for_each = var.team_configs

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.shared.name
  member   = "serviceAccount:${module.team_sinks[each.key].team_service_account_email}"
  role     = "roles/run.invoker"
}

resource "google_cloud_run_v2_service_iam_member" "unique_invoker" {
  for_each = local.teams_with_dedicated_service

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.team_unique[each.key].name
  member   = "serviceAccount:${module.team_sinks[each.key].team_service_account_email}"
  role     = "roles/run.invoker"
}

resource "google_service_account_iam_member" "scheduler_impersonation" {
  for_each = var.team_configs

  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.team_sinks[each.key].team_service_account_email}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}

resource "google_cloud_scheduler_job" "shared_activity" {
  for_each = var.team_configs

  project     = var.project_id
  region      = var.region
  name        = "team-${each.key}-shared-heartbeat"
  schedule    = var.activity_trigger_schedule
  time_zone   = "Etc/UTC"
  description = "Invokes shared Cloud Run heartbeat for ${each.value.display_name}."

  http_target {
    http_method = "GET"
    uri         = "${google_cloud_run_v2_service.shared.uri}/heartbeat/${each.key}"

    oidc_token {
      service_account_email = module.team_sinks[each.key].team_service_account_email
      audience              = google_cloud_run_v2_service.shared.uri
    }
  }

  attempt_deadline = "60s"

  depends_on = [
    google_cloud_run_v2_service.shared,
    google_cloud_run_v2_service_iam_member.shared_invoker,
    google_service_account_iam_member.scheduler_impersonation,
  ]
}

resource "google_cloud_scheduler_job" "unique_activity" {
  for_each = local.teams_with_dedicated_service

  project     = var.project_id
  region      = var.region
  name        = "team-${each.key}-unique-heartbeat"
  schedule    = var.activity_trigger_schedule
  time_zone   = "Etc/UTC"
  description = "Invokes unique Cloud Run heartbeat for ${each.value.display_name}."

  http_target {
    http_method = "GET"
    uri         = "${google_cloud_run_v2_service.team_unique[each.key].uri}/ping"

    oidc_token {
      service_account_email = module.team_sinks[each.key].team_service_account_email
      audience              = google_cloud_run_v2_service.team_unique[each.key].uri
    }
  }

  attempt_deadline = "60s"

  depends_on = [
    google_cloud_run_v2_service.team_unique,
    google_cloud_run_v2_service_iam_member.unique_invoker,
    google_service_account_iam_member.scheduler_impersonation,
  ]
}

output "runner_service_account_email" {
  value       = google_service_account.runner.email
  description = "Service account that executes the analytics pipeline."
}

output "artifact_bucket_name" {
  value       = google_storage_bucket.artifacts.name
  description = "Bucket storing pipeline artifacts and visualizations."
}
