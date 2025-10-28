from __future__ import annotations

import json
import os
from datetime import datetime, timezone

from flask import Flask, jsonify, request

app = Flask(__name__)
SERVICE_NAME = os.environ.get("SERVICE_NAME", "unique-service")
TEAM_ID = os.environ.get("TEAM_ID", "team-unknown")


@app.route("/")
def root():
    return f"{SERVICE_NAME}-root", 200


@app.route("/ping")
def ping():
    now = datetime.now(timezone.utc)
    payload = {
        "team_id": TEAM_ID,
        "service": SERVICE_NAME,
        "timestamp": now.isoformat(),
        "path": request.path,
    }
    app.logger.info(json.dumps(payload))
    return jsonify(payload)


if __name__ == "__main__":  # pragma: no cover
    app.run(host="0.0.0.0", port=8080)
