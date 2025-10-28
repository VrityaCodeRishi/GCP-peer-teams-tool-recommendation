from google.cloud import bigquery
from datetime import datetime, timedelta
import random
import functions_framework
import os

@functions_framework.http
def generate_activity(request):
    project_id = os.environ.get('PROJECT_ID', 'buoyant-episode-386713')
    dataset_id = os.environ.get('DATASET_ID', 'devops_activity')
    table_id = f"{project_id}.{dataset_id}.team_activity"
    
    client = bigquery.Client(project=project_id)
    
    teams = ["team-atlas", "team-borealis", "team-cosmo", "team-draco"]
    
    tools = [
        "cloud-build",
        "artifact-registry", 
        "cloud-run",
        "gcs-bucket",
        "cloud-scheduler",
        "cloud-logging",
        "bigquery",
        "terraform"
    ]
    
    action_types = {
        "cloud-build": ["build", "deploy", "trigger"],
        "artifact-registry": ["push", "pull", "scan"],
        "cloud-run": ["deploy", "invoke", "scale"],
        "gcs-bucket": ["upload", "download", "sync"],
        "cloud-scheduler": ["schedule", "trigger", "execute"],
        "cloud-logging": ["export", "query", "sink"],
        "bigquery": ["query", "load", "export"],
        "terraform": ["plan", "apply", "destroy"]
    }
    
    outcomes = ["success", "success", "success", "failure"]  # 75% success rate
    

    rows_to_insert = []
    current_time = datetime.utcnow()
    

    request_json = request.get_json(silent=True)
    events_per_team = 20
    if request_json and 'events_per_team' in request_json:
        events_per_team = int(request_json['events_per_team'])
    
    for team in teams:
        for i in range(events_per_team):
            event_time = current_time - timedelta(minutes=random.randint(0, 60))
            tool = random.choice(tools)
            action = random.choice(action_types[tool])
            outcome = random.choice(outcomes)

            if outcome == "success":
                latency = random.randint(50, 2000)
                satisfaction = random.randint(3, 5)
            else:
                latency = random.randint(2000, 10000)
                satisfaction = random.randint(1, 3)
            
            rows_to_insert.append({
                "event_timestamp": event_time.isoformat(),
                "team_id": team,
                "tool_name": tool,
                "action_type": action,
                "outcome": outcome,
                "satisfaction_score": satisfaction,
                "latency_ms": latency
            })
    

    try:
        errors = client.insert_rows_json(table_id, rows_to_insert)
        if errors:
            print(f"Errors inserting rows: {errors}")
            return {"status": "error", "errors": errors}, 500
        
        return {
            "status": "success",
            "message": f"Generated {len(rows_to_insert)} activity events",
            "events_per_team": events_per_team,
            "total_events": len(rows_to_insert)
        }, 200
        
    except Exception as e:
        print(f"Exception: {str(e)}")
        return {"status": "error", "message": str(e)}, 500


@functions_framework.cloud_event
def generate_activity_pubsub(cloud_event):

    class MockRequest:
        def get_json(self, silent=True):
            return {"events_per_team": 20}
    
    return generate_activity(MockRequest())
