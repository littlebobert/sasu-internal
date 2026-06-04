from __future__ import annotations

from fastapi import Response
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.models import AppToken, Invite
from app.security import hash_secret, make_invite_code, make_app_token


def make_client(tmp_path, rate_limit_per_minute: int = 20) -> TestClient:
    settings = Settings(
        database_url=f"sqlite:///{tmp_path / 'test.db'}",
        openai_api_key="sk-test",
        token_hash_pepper="test-pepper",
        allowed_models={"gpt-5.5"},
        request_max_bytes=10_000,
        rate_limit_per_minute=rate_limit_per_minute,
        invite_base_url="http://sasu.jp/#invite=",
    )
    app = create_app(settings)
    client = TestClient(app)
    client.__enter__()
    return client


def close_client(client: TestClient) -> None:
    client.__exit__(None, None, None)


def add_invite(client: TestClient, label: str = "mom") -> str:
    code = make_invite_code()
    settings = client.app.state.settings
    with client.app.state.database.session_local() as db:
        db.add(Invite(label=label, code_hash=hash_secret(code, settings.token_hash_pepper)))
        db.commit()
    return code


def add_app_token(client: TestClient, label: str = "mom", revoked: bool = False) -> str:
    token = make_app_token()
    settings = client.app.state.settings
    with client.app.state.database.session_local() as db:
        app_token = AppToken(label=label, token_hash=hash_secret(token, settings.token_hash_pepper))
        if revoked:
            from app.models import utc_now

            app_token.revoked_at = utc_now()
        db.add(app_token)
        db.commit()
    return token


def test_redeems_invite_once(tmp_path) -> None:
    client = make_client(tmp_path)
    try:
        code = add_invite(client, label="mom")

        response = client.post("/v1/invites/redeem", json={"code": code})
        assert response.status_code == 200
        body = response.json()
        assert body["token_type"] == "bearer"
        assert body["label"] == "mom"
        assert body["access_token"].startswith("sasu_app_")

        second_response = client.post("/v1/invites/redeem", json={"code": code})
        assert second_response.status_code == 401
    finally:
        close_client(client)


def test_rejects_invalid_invite(tmp_path) -> None:
    client = make_client(tmp_path)
    try:
        response = client.post("/v1/invites/redeem", json={"code": "sasu_inv_nope_nope_nope"})
        assert response.status_code == 401
    finally:
        close_client(client)


def test_proxies_responses_with_valid_app_token(tmp_path, monkeypatch) -> None:
    client = make_client(tmp_path)
    try:
        token = add_app_token(client)

        async def fake_proxy(request_body, settings):
            return Response(content='{"output_text":"ok"}', media_type="application/json")

        monkeypatch.setattr("app.main._proxy_to_openai", fake_proxy)

        response = client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json={"model": "gpt-5.5", "input": []},
        )
        assert response.status_code == 200
        assert response.json() == {"output_text": "ok"}
    finally:
        close_client(client)


def test_rejects_revoked_app_token(tmp_path) -> None:
    client = make_client(tmp_path)
    try:
        token = add_app_token(client, revoked=True)
        response = client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json={"model": "gpt-5.5", "input": []},
        )
        assert response.status_code == 401
    finally:
        close_client(client)


def test_rejects_disallowed_model(tmp_path) -> None:
    client = make_client(tmp_path)
    try:
        token = add_app_token(client)
        response = client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json={"model": "gpt-4.1", "input": []},
        )
        assert response.status_code == 400
    finally:
        close_client(client)


def test_rate_limits_per_app_token(tmp_path, monkeypatch) -> None:
    client = make_client(tmp_path, rate_limit_per_minute=1)
    try:
        token = add_app_token(client)

        async def fake_proxy(request_body, settings):
            return Response(content='{"output_text":"ok"}', media_type="application/json")

        monkeypatch.setattr("app.main._proxy_to_openai", fake_proxy)

        first_response = client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json={"model": "gpt-5.5", "input": []},
        )
        assert first_response.status_code == 200

        second_response = client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json={"model": "gpt-5.5", "input": []},
        )
        assert second_response.status_code == 429
    finally:
        close_client(client)


def test_passes_openai_error_response_through(tmp_path, monkeypatch) -> None:
    client = make_client(tmp_path)
    try:
        token = add_app_token(client)

        async def fake_proxy(request_body, settings):
            return Response(content='{"error":{"message":"quota"}}', status_code=429, media_type="application/json")

        monkeypatch.setattr("app.main._proxy_to_openai", fake_proxy)

        response = client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json={"model": "gpt-5.5", "input": []},
        )
        assert response.status_code == 429
        assert response.json() == {"error": {"message": "quota"}}
    finally:
        close_client(client)
