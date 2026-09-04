"""
Enterprise Platform API
A minimal SaaS-style Flask service built purely to act as a production
workload for demonstrating Azure/AKS/CI-CD/monitoring/SRE capabilities.

This is NOT meant to be a feature-rich application. Every endpoint exists
to exercise a specific infrastructure/SRE concept:
    /               -> basic service identity
    /health          -> liveness probe
    /ready           -> readiness probe (can be forced to fail)
    /api/status       -> realistic API response
    /api/slow          -> latency simulation (P95/P99 demo)
    /api/failure        -> 5xx error simulation
    CRASH_ON_STARTUP env -> CrashLoopBackOff simulation
"""

import json
import logging
import os
import sys
import time
from datetime import datetime, timezone

from flask import Flask, jsonify, request

# --------------------------------------------------------------------------
# Structured (JSON) logging setup
# Container stdout -> AKS -> Azure Monitor -> Log Analytics -> KQL
# --------------------------------------------------------------------------


class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "level": record.levelname,
            "service": SERVICE_NAME,
            "message": record.getMessage(),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload)


SERVICE_NAME = os.environ.get("SERVICE_NAME", "enterprise-platform-api")
SERVICE_VERSION = os.environ.get("SERVICE_VERSION", "1.0.0")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "production")
REGION = os.environ.get("REGION", "azure-central-india")

logger = logging.getLogger(SERVICE_NAME)
logger.setLevel(logging.INFO)
_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(JsonFormatter())
logger.addHandler(_handler)

app = Flask(__name__)

# --------------------------------------------------------------------------
# Failure-injection switches (all controlled via env vars / ConfigMap so
# that behaviour can be changed at deploy time without a code change)
# --------------------------------------------------------------------------
CRASH_ON_STARTUP = os.environ.get("CRASH_ON_STARTUP", "false").lower() == "true"
FAILURE_MODE = os.environ.get("FAILURE_MODE", "false").lower() == "true"
READY_OVERRIDE = os.environ.get("READY_OVERRIDE", "true").lower() == "true"

# A dummy "secret" consumed from a Kubernetes Secret / env var, just to
# demonstrate secret consumption without leaking it in responses.
DB_PASSWORD_SET = bool(os.environ.get("DB_PASSWORD"))


# --------------------------------------------------------------------------
# CrashLoopBackOff simulation
# If CRASH_ON_STARTUP=true, the process exits immediately after logging,
# so Kubernetes will restart the container repeatedly.
# --------------------------------------------------------------------------
if CRASH_ON_STARTUP:
    logger.error("CRASH_ON_STARTUP is set to true — simulating startup crash")
    sys.exit(1)


@app.before_request
def start_timer():
    request._start_time = time.time()
    logger.info(f"Incoming request: {request.method} {request.path}")


@app.after_request
def log_response(response):
    # duration_ms feeds the P95/P99 KQL queries in azure-monitor/performance.kql
    duration_ms = round((time.time() - getattr(request, "_start_time", time.time())) * 1000, 2)
    payload = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "level": "INFO",
        "service": SERVICE_NAME,
        "message": "Request completed",
        "method": request.method,
        "path": request.path,
        "status_code": response.status_code,
        "duration_ms": duration_ms,
    }
    print(json.dumps(payload), file=sys.stdout, flush=True)
    return response


@app.route("/")
def index():
    return jsonify(
        {
            "service": SERVICE_NAME,
            "version": SERVICE_VERSION,
            "status": "running",
        }
    )


@app.route("/health")
def health():
    """
    Liveness probe.
    Kubernetes uses this to decide whether the CONTAINER should be
    restarted. Keep this cheap and dependency-free — it should only fail
    if the process itself is unrecoverable (deadlock, OOM-adjacent state).
    """
    logger.info("Health check successful")
    return jsonify({"status": "healthy"}), 200


@app.route("/ready")
def ready():
    """
    Readiness probe.
    Kubernetes uses this to decide whether the POD should receive traffic
    from the Service. This can legitimately fail (e.g. warming up,
    dependency down) without the pod being killed.
    """
    if not READY_OVERRIDE:
        logger.error("Readiness check failed: READY_OVERRIDE is false")
        return jsonify({"status": "not_ready"}), 503

    if not DB_PASSWORD_SET and ENVIRONMENT == "production":
        logger.warning("Readiness check failed: required secret DB_PASSWORD missing")
        return jsonify({"status": "not_ready", "reason": "missing_secret"}), 503

    logger.info("Readiness check successful")
    return jsonify({"status": "ready"}), 200


@app.route("/api/status")
def api_status():
    logger.info("Serving /api/status")
    return jsonify(
        {
            "service": SERVICE_NAME,
            "environment": ENVIRONMENT,
            "region": REGION,
            "status": "operational",
        }
    )


@app.route("/api/slow")
def api_slow():
    """
    Latency simulation for P95/P99 monitoring demos.
    Optional query param: ?delay=<seconds> (default 2, capped at 10).
    """
    try:
        delay = float(request.args.get("delay", 2))
    except ValueError:
        delay = 2
    delay = max(0, min(delay, 10))

    logger.info(f"Simulating latency of {delay}s on /api/slow")
    time.sleep(delay)
    return jsonify({"service": SERVICE_NAME, "delayed_seconds": delay, "status": "ok"})


@app.route("/api/failure")
def api_failure():
    """
    5xx error simulation for HTTP-error-rate monitoring demos.
    Fails when FAILURE_MODE=true (env var / ConfigMap) OR when
    ?force=true is passed on the request.
    """
    force = request.args.get("force", "false").lower() == "true"

    if FAILURE_MODE or force:
        logger.error("Simulated failure triggered on /api/failure")
        return jsonify({"error": "Backend dependency unavailable"}), 500

    logger.info("Serving /api/failure successfully (no failure triggered)")
    return jsonify({"status": "ok"}), 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    logger.info(f"Starting {SERVICE_NAME} v{SERVICE_VERSION} on port {port}")
    app.run(host="0.0.0.0", port=port)
