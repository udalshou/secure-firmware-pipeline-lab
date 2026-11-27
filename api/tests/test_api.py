from fastapi.testclient import TestClient

from lab_api import app

client = TestClient(app)


def test_health_reports_ok() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_status_reports_version_and_uptime() -> None:
    response = client.get("/status")
    assert response.status_code == 200
    body = response.json()
    assert body["version"] == "0.1.0"
    assert isinstance(body["uptime_seconds"], int)
    assert body["uptime_seconds"] >= 0
