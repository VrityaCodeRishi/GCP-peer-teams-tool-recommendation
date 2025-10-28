from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Dict

from flask import Flask, jsonify, request

app = Flask(__name__)


def _base_payload(team_id: str, service: str) -> Dict[str, str]:
    now = datetime.now(timezone.utc)
    return {
        "team_id": team_id,
        "service": service,
        "timestamp": now.isoformat(),
        "user_agent": request.headers.get("User-Agent", "unknown"),
        "payload": {"message": f"Heartbeat from {service} for {team_id}"},
    }


@app.route("/")
def root() -> str:
    return "shared-heartbeat", 200


@app.route("/heartbeat/<team_id>")
def heartbeat(team_id: str):
    payload = _base_payload(team_id, "shared-service")
    app.logger.info(json.dumps(payload))
    return jsonify(payload)


if __name__ == "__main__":  # pragma: no cover
    app.run(host="0.0.0.0", port=8080)
