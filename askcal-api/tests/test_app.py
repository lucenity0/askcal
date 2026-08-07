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
