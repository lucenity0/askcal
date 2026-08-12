"""Smoke tests that don't need a database."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    # Reported so a deploy can be verified without shelling into the VM.
    assert body["llm_provider"] in {"claude_code", "gemini"}
    assert isinstance(body["classifier_configured"], bool)


def test_protected_routes_return_contract_error_shape():
    for path in ("/api/today", "/api/inbox", "/api/tracks", "/api/carry-forward"):
        r = client.get(path)
        assert r.status_code == 401
        body = r.json()
        assert body["error"] == "AUTH_EXPIRED"
        assert body["code"] == 401
        assert "message" in body


def test_google_auth_without_credentials_is_503(monkeypatch):
    # Force empty credentials regardless of what's in .env
    monkeypatch.setenv("ASKCAL_GOOGLE_CLIENT_ID", "")
    monkeypatch.setenv("ASKCAL_GOOGLE_CLIENT_SECRET", "")
    from app.config import get_settings

    get_settings.cache_clear()
    try:
        r = client.post("/auth/google", json={"code": "fake"})
        assert r.status_code == 503
        assert r.json()["error"] == "GMAIL_NOT_CONFIGURED"
    finally:
        get_settings.cache_clear()


def test_task_list_accepts_a_date_range():
    """The month grid asks for a whole month in one request.

    Without `start`/`end` the only per-day query was `on`, so drawing one month
    of dots meant 31 round trips — which is why the grid never asked and marked
    today only. This checks the parameters actually reached the schema; there is
    no DB fixture in this suite, so the query itself is covered by the client.
    """
    params = {
        p["name"]
        for p in client.get("/openapi.json").json()["paths"]["/api/tasks"]["get"][
            "parameters"
        ]
    }
    assert {"on", "start", "end"} <= params


def test_task_delete_is_registered():
    """The app had no way to remove a task for a long time even though this
    endpoint existed, so it is worth asserting it stays."""
    assert "delete" in client.get("/openapi.json").json()["paths"]["/api/tasks/{task_id}"]


def test_all_contract_routes_registered():
    paths = set(client.get("/openapi.json").json()["paths"])
    assert {
        "/auth/google",
        "/auth/refresh",
        "/auth/revoke",
        "/api/today",
        "/api/inbox",
        "/api/tracks",
        "/api/closing-time",
        "/api/carry-forward",
    } <= paths
