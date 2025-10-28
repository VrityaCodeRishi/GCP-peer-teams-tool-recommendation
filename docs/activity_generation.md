# Synthetic Activity Generation

Terraform provisions lightweight Cloud Run workloads that continuously emit activity for each team so the recommendation pipeline has realistic data even before production pipelines are onboarded.

## Components

- **Service accounts**: `team-<team>-builder` identities invoke the heartbeat services, producing Cloud Run request logs and corresponding audit entries that flow through the existing logging sinks into BigQuery.
- **Cloud Run services**:
  - `shared-heartbeat` — shared across all teams, logs requests to `/heartbeat/<team_id>`.
  - `team-<team>-unique` — provisioned for teams with `dedicated_service = true`, logs requests to `/ping` with team-specific metadata.
- **Cloud Scheduler jobs**: `team-<team>-shared-heartbeat` (and, when applicable, `team-<team>-unique-heartbeat`) fire every five minutes by default (`activity_trigger_schedule` variable). Each job issues an authenticated HTTP GET to the corresponding Cloud Run endpoint while impersonating the team’s service account.

## Manual execution

Kick off a heartbeat immediately for a given team:

```bash
gcloud scheduler jobs run team-team-atlas-shared-heartbeat \
  --location=us-central1 \
  --project=buoyant-episode-386713
```

## Verifying ingestion

1. Open Cloud Run → Services and inspect recent request logs for `shared-heartbeat` (and any `team-*-unique` services).
2. In Logs Explorer, filter by:
   ```
   resource.type="cloud_run_revision"
   protoPayload.authenticationInfo.principalEmail="team-team-atlas-builder@buoyant-episode-386713.iam.gserviceaccount.com"
   ```
3. Query BigQuery to confirm rows landed:
   ```sql
   SELECT COUNT(*) FROM `buoyant-episode-386713.devops_activity.team_activity`
   WHERE team_id = "team-atlas"
     AND event_timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY);
   ```

Adjust the cron expression via `activity_trigger_schedule` in `infra/terraform.tfvars` if you need faster or slower synthetic activity.
