# Logging Sink Filter Guidance

Each team module ships with a default Cloud Logging advanced filter that captures:

- **Cloud Build** executions associated with the `team_id` label
- **Cloud Audit Logs** where the principal email matches the team identifier

```text
resource.type=("cloud_build_build" OR "audited_resource")
AND (jsonPayload.team_id="team-atlas" OR protoPayload.authenticationInfo.principalEmail="team-atlas")
```

Customize the filter to match your naming standards:

- Replace `protoPayload.authenticationInfo.principalEmail` with service account emails.
- Add additional resource bindings (e.g., Cloud Deploy, Workflows) using `OR` clauses.
- Scope to specific projects using `resource.labels.project_id="gcp-project-id"`.

The filters live in `infra/variables.tf` under `team_configs`. Update them before applying Terraform.
