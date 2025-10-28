# Personalized DevOps Resource Recommendation Engine for GCP Teams

This repository deploys a GCP analytics and recommendation platform that ingests DevOps activity logs for four engineering teams, clusters similar behaviors, and recommends GCP tooling or workflow improvements based on high-performing peers.

## Repository layout

- `infra/` &mdash; Terraform configuration that provisions log sinks, BigQuery datasets, Pub/Sub topics, service accounts, and (optionally) Cloud Build triggers when GitHub settings are supplied.
- `src/` &mdash; Python package that cleans log data, engineers features, clusters teams, scores recommendations, and produces visualizations.
- `data/` &mdash; Sample synthetic datasets that mirror the BigQuery schema for local experimentation.
- `docs/` &mdash; Architecture diagrams, playbooks, and operational context (including `activity_generation.md` for synthetic workload details).

## High-level architecture

1. **Log ingestion**  
   Cloud Logging sinks export Cloud Audit Logs and Cloud Build logs into a curated BigQuery dataset (`devops_activity`). Cloud Function triggers can be added to push feedback events (1&ndash;5 satisfaction scores) into Pub/Sub topics for each team.

2. **Team scaffolding**  
   Terraform provisions shared platform surfaces (e.g., a common Artifact Registry repo and artifact bucket) and, where configured, team-specific CI/CD identities, dedicated repositories/buckets, and feedback channels so synthetic or real workloads can emit activity tied to each team.
   The default configuration demonstrates a mix: some teams push to the shared repository/bucket while others use isolated resources to mimic varied DevOps footprints.

3. **Analytics pipeline**  
   Python jobs (or Cloud Composer/Cloud Run jobs) run the code in `src/recommendation_engine` to clean logs, engineer features (usage frequency, error rates, adoption diversity), and cluster teams via unsupervised learning.

4. **Recommendations and visualization**  
   Recommendations are materialized back into BigQuery tables or CSVs for visualization in Looker Studio, or rendered locally via Matplotlib/Seaborn dashboards.

## Getting started

1. Copy `infra/terraform.tfvars.example` to `infra/terraform.tfvars` and provide project IDs, region, and billing configurations.
2. (Optional) Populate `github_owner`/`github_repo` and the `cloudbuild_repository` resource path (from the Cloud Build console) in `infra/terraform.tfvars` to let Terraform create a Cloud Build trigger tied to this repo.
3. Review/enable the required GCP services enumerated in `infra/main.tf` (Terraform enables them on apply).
4. Run Terraform:
   ```bash
   cd infra
   terraform init
   terraform apply
   ```
5. Install Python dependencies and run the sample notebook or pipeline job:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   python src/recommendation_engine/pipeline.py --sample-data data/sample_logs.csv
   ```
   Cloud Build runs against live BigQuery data; keep the `--sample-data` flag for local smoke tests only.

## Next steps

- Configure Cloud Scheduler or Workflows to invoke the pipeline on a cadence.
- Connect Looker Studio to the BigQuery dataset for interactive dashboards.
- Extend the recommender with qualitative feedback (chatbot, forms) for hybrid scoring.

- Populate the per-team resources (Artifact Registry repository, artifact bucket, Pub/Sub topic) with synthetic builds to simulate real-world activity before log sinks are live.
- Synthetic Cloud Run heartbeats are scheduled for each team via Cloud Scheduler (`team-*-shared-heartbeat` and, where configured, `team-*-unique-heartbeat`). Jobs call the shared/unique services using the team service accounts; inspect Cloud Scheduler or run `gcloud scheduler jobs run team-team-atlas-shared-heartbeat --location=us-central1` to trigger one on demand.
