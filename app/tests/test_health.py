import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import pytest
import app as app_module


@pytest.fixture
def client():
    app_module.app.config["TESTING"] = True
    with app_module.app.test_client() as client:
        yield client


def test_index(client):
    resp = client.get("/")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "running"


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "healthy"


def test_ready_default(client, monkeypatch):
    monkeypatch.setattr(app_module, "READY_OVERRIDE", True)
    monkeypatch.setattr(app_module, "DB_PASSWORD_SET", True)
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ready"


def test_ready_forced_not_ready(client, monkeypatch):
    monkeypatch.setattr(app_module, "READY_OVERRIDE", False)
    resp = client.get("/ready")
    assert resp.status_code == 503


def test_api_status(client):
    resp = client.get("/api/status")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["status"] == "operational"
    assert "region" in body


def test_api_slow(client):
    resp = client.get("/api/slow?delay=0")
    assert resp.status_code == 200
    assert resp.get_json()["delayed_seconds"] == 0


def test_api_failure_default_ok(client, monkeypatch):
    monkeypatch.setattr(app_module, "FAILURE_MODE", False)
    resp = client.get("/api/failure")
    assert resp.status_code == 200


def test_api_failure_forced(client):
    resp = client.get("/api/failure?force=true")
    assert resp.status_code == 500
