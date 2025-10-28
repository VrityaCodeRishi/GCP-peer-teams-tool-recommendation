# Synthetic Activity Generation

Terraform provisions lightweight workloads that continuously emit Cloud Build activity for each team so the recommendation pipeline has realistic data even before production pipelines are onboarded.

## Components

- **Service accounts**: `team-<team>-builder` identities execute the synthetic builds, producing Cloud Build logs that flow through the existing logging sinks into BigQuery.
- **Scheduler runner**: `devops-activity-scheduler` service account owns the Cloud Scheduler jobs and has `roles/cloudbuild.builds.editor` to create builds programmatically.
- **Cloud Scheduler jobs**: `team-<team>-activity` (in `us-central1`) fire every six hours by default (`activity_trigger_schedule` variable). Each job issues a POST to the Cloud Build REST API with an inline build config that simply echoes telemetry.

## Manual execution

Kick off a build immediately for a given team:

```bash
gcloud scheduler jobs run team-team-atlas-activity \
  --location=us-central1 \
  --project=buoyant-episode-386713
```

## Verifying ingestion

1. Open Cloud Build → History and confirm a build appears under the team’s service account.
2. In Logs Explorer, filter by:
   ```
   resource.type="cloud_build_build"
   protoPayload.authenticationInfo.principalEmail="team-team-atlas-builder@buoyant-episode-386713.iam.gserviceaccount.com"
   ```
3. Query BigQuery to confirm rows landed:
   ```sql
   SELECT COUNT(*) FROM `buoyant-episode-386713.devops_activity.team_activity`
   WHERE team_id = "team-atlas"
     AND event_timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY);
   ```

Adjust the cron expression via `activity_trigger_schedule` in `infra/terraform.tfvars` if you need faster or slower synthetic activity.***
