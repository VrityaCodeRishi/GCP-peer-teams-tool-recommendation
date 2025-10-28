variable "project_id" {
  type        = string
  description = "Project hosting the logging sink."
}

variable "region" {
  type        = string
  description = "Region for Artifact Registry and regional resources."
}

variable "dataset_project" {
  type        = string
  description = "Project where the BigQuery dataset resides."
}

variable "dataset_id" {
  type        = string
  description = "Target BigQuery dataset ID."
}

variable "team_id" {
  type        = string
  description = "Canonical team identifier."
}

variable "display_name" {
  type        = string
  description = "Human-readable team name."
}

variable "log_filter" {
  type        = string
  description = "Cloud Logging advanced filter to capture team activity."
}

variable "location" {
  type        = string
  description = "Location for feedback Pub/Sub resources."
}

variable "labels" {
  type        = map(string)
  description = "Labels inherited from root module."
}

variable "runner_sa_email" {
  type        = string
  description = "Service account consuming recommendation feedback."
}

variable "enable_dedicated_repo" {
  type        = bool
  description = "Whether to create a team-specific Artifact Registry repository."
}

variable "enable_dedicated_bucket" {
  type        = bool
  description = "Whether to create a team-specific artifact bucket."
}

variable "shared_artifact_repo_project" {
  type        = string
  description = "Project containing the shared Artifact Registry repository."
}

variable "shared_artifact_repo_location" {
  type        = string
  description = "Location of the shared Artifact Registry repository."
}

variable "shared_artifact_repo_id" {
  type        = string
  description = "Repository ID of the shared Artifact Registry repository."
}

variable "shared_artifact_bucket_name" {
  type        = string
  description = "Name of the shared Cloud Storage bucket."
}

variable "shared_artifact_bucket_location" {
  type        = string
  description = "Location of the shared Cloud Storage bucket."
}
