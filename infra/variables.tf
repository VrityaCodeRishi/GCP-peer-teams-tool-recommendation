variable "project_id" {
  type        = string
  description = "GCP project ID hosting the analytics platform."
}

variable "region" {
  type        = string
  description = "Primary region for regional resources."
  default     = "us-central1"
}

variable "location" {
  type        = string
  description = "BigQuery and Storage location."
  default     = "US"
}

variable "dataset_id" {
  type        = string
  description = "BigQuery dataset ID for activity logs."
  default     = "devops_activity"
}

variable "artifact_bucket_name" {
  type        = string
  description = "Cloud Storage bucket for model artifacts."
  default     = "devops-recommendation-artifacts"
}

variable "team_configs" {
  description = "Map of team identifiers to logging sink filters and resource preferences."
  type = map(object({
    display_name     = string
    log_filter       = string
    dedicated_repo   = bool
    dedicated_bucket = bool
  }))
  default = {
    "team-atlas" = {
      display_name     = "Team Atlas"
      log_filter       = "resource.type=(\"cloud_build_build\" OR \"audited_resource\") AND (jsonPayload.team_id=\"team-atlas\" OR protoPayload.authenticationInfo.principalEmail=\"team-atlas\")"
      dedicated_repo   = true
      dedicated_bucket = true
    }
    "team-borealis" = {
      display_name     = "Team Borealis"
      log_filter       = "resource.type=(\"cloud_build_build\" OR \"audited_resource\") AND (jsonPayload.team_id=\"team-borealis\" OR protoPayload.authenticationInfo.principalEmail=\"team-borealis\")"
      dedicated_repo   = false
      dedicated_bucket = true
    }
    "team-cosmo" = {
      display_name     = "Team Cosmo"
      log_filter       = "resource.type=(\"cloud_build_build\" OR \"audited_resource\") AND (jsonPayload.team_id=\"team-cosmo\" OR protoPayload.authenticationInfo.principalEmail=\"team-cosmo\")"
      dedicated_repo   = true
      dedicated_bucket = false
    }
    "team-draco" = {
      display_name     = "Team Draco"
      log_filter       = "resource.type=(\"cloud_build_build\" OR \"audited_resource\") AND (jsonPayload.team_id=\"team-draco\" OR protoPayload.authenticationInfo.principalEmail=\"team-draco\")"
      dedicated_repo   = false
      dedicated_bucket = false
    }
  }
}

variable "shared_artifact_repo_id" {
  type        = string
  description = "Artifact Registry repository ID shared by teams that opt out of dedicated repos."
  default     = "devops-shared-repo"
}

variable "shared_team_bucket_name" {
  type        = string
  description = "Cloud Storage bucket shared by teams that opt out of dedicated buckets."
  default     = "devops-shared-team-artifacts"
}

variable "labels" {
  description = "Common labels applied to created resources."
  type        = map(string)
  default = {
    application = "devops-recommendation-engine"
    owner       = "platform-team"
    environment = "development"
  }
}
