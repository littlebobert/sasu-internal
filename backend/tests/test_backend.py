from __future__ import annotations

import httpx
from fastapi import Response
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.models import AppToken, Invite
from app.security import hash_secret, make_invite_code, make_app_token


def make_client(
    tmp_path,
    rate_limit_per_minute: int = 20,
    monthly_usage_limit_per_token: int = 0,
    image_request_usage_units: int = 10,
    text_request_usage_units: int = 1,
    unlimited_token_labels: set[str] | None = None,
) -> TestClient:
    settings = Settings(
        database_url=f"sqlite:///{tmp_path / 'test.db'}",
        openai_api_key="sk-test",
        token_hash_pepper="test-pepper",
        allowed_models={"gpt-5.5", "gpt-5.6"},
        request_max_bytes=10_000,
        rate_limit_per_minute=rate_limit_per_minute,
        monthly_usage_limit_per_token=monthly_usage_limit_per_token,
        image_request_usage_units=image_request_usage_units,
        text_request_usage_units=text_request_usage_units,
        unlimited_token_labels=unlimited_token_labels or set(),
        invite_base_url="https://sasu.jp/sasu-invite#invite=",
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


def text_request() -> dict:
    return {"model": "gpt-5.6", "input": []}


def image_request() -> dict:
    return {
        "model": "gpt-5.6",
        "input": [
            {
                "role": "user",
                "content": [
                    {"type": "input_text", "text": "What does this say?"},
                    {"type": "input_image", "image_url": "data:image/jpeg;base64,abc"},
                ],
            }
        ],
    }


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
            json=text_request(),
        )
        assert response.status_code == 200
        assert response.json() == {"output_text": "ok"}
    finally:
        close_client(client)


def test_streams_openai_response_events_with_valid_app_token(tmp_path, monkeypatch) -> None:
    client = make_client(tmp_path)
    original_async_client = httpx.AsyncClient
    event_stream = (
        b'data: {"type":"response.output_text.delta","delta":"Hello"}\n\n'
        b'data: {"type":"response.completed"}\n\n'
    )

    def upstream_handler(request: httpx.Request) -> httpx.Response:
        assert request.url == "https://api.openai.com/v1/responses"
        assert b'"stream":true' in request.content
        return httpx.Response(
            200,
            headers={"content-type": "text/event-stream"},
            content=event_stream,
        )

    transport = httpx.MockTransport(upstream_handler)
    monkeypatch.setattr(
        "app.main.httpx.AsyncClient",
        lambda **_: original_async_client(transport=transport),
    )

    try:
        token = add_app_token(client)
        request_body = text_request()
        request_body["stream"] = True

        response = client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json=request_body,
        )

        assert response.status_code == 200
        assert response.content == event_stream
        assert response.headers["content-type"].startswith("text/event-stream")
    finally:
        close_client(client)


def test_rejects_revoked_app_token(tmp_path) -> None:
    client = make_client(tmp_path)
    try:
        token = add_app_token(client, revoked=True)
        response = client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json=text_request(),
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
            json=text_request(),
        )
        assert first_response.status_code == 200

        second_response = client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json=text_request(),
        )
        assert second_response.status_code == 429
    finally:
        close_client(client)


def test_monthly_usage_limits_text_requests_per_app_token(tmp_path, monkeypatch) -> None:
    client = make_client(tmp_path, monthly_usage_limit_per_token=1)
    try:
        token = add_app_token(client)

        async def fake_proxy(request_body, settings):
            return Response(content='{"output_text":"ok"}', media_type="application/json")

        monkeypatch.setattr("app.main._proxy_to_openai", fake_proxy)

        first_response = client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json=text_request(),
        )
        assert first_response.status_code == 200

        second_response = client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json=text_request(),
        )
        assert second_response.status_code == 429
        assert "Monthly hosted access limit reached" in second_response.json()["detail"]
    finally:
        close_client(client)


def test_monthly_usage_limit_can_be_disabled(tmp_path, monkeypatch) -> None:
    client = make_client(tmp_path, monthly_usage_limit_per_token=0)
    try:
        token = add_app_token(client)

        async def fake_proxy(request_body, settings):
            return Response(content='{"output_text":"ok"}', media_type="application/json")

        monkeypatch.setattr("app.main._proxy_to_openai", fake_proxy)

        for _ in range(3):
            response = client.post(
                "/v1/responses",
                headers={"Authorization": f"Bearer {token}"},
                json=text_request(),
            )
            assert response.status_code == 200
    finally:
        close_client(client)


def test_monthly_usage_limits_are_per_token(tmp_path, monkeypatch) -> None:
    client = make_client(tmp_path, monthly_usage_limit_per_token=1)
    try:
        first_token = add_app_token(client, label="first")
        second_token = add_app_token(client, label="second")

        async def fake_proxy(request_body, settings):
            return Response(content='{"output_text":"ok"}', media_type="application/json")

        monkeypatch.setattr("app.main._proxy_to_openai", fake_proxy)

        assert client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {first_token}"},
            json=text_request(),
        ).status_code == 200
        assert client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {first_token}"},
            json=text_request(),
        ).status_code == 429
        assert client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {second_token}"},
            json=text_request(),
        ).status_code == 200
    finally:
        close_client(client)


def test_image_requests_cost_more_monthly_units(tmp_path, monkeypatch) -> None:
    client = make_client(tmp_path, monthly_usage_limit_per_token=10, image_request_usage_units=10, text_request_usage_units=1)
    try:
        token = add_app_token(client)

        async def fake_proxy(request_body, settings):
            return Response(content='{"output_text":"ok"}', media_type="application/json")

        monkeypatch.setattr("app.main._proxy_to_openai", fake_proxy)

        assert client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json=image_request(),
        ).status_code == 200
        assert client.post(
            "/v1/responses",
            headers={"Authorization": f"Bearer {token}"},
            json=text_request(),
        ).status_code == 429
    finally:
        close_client(client)


def test_unlimited_token_labels_bypass_monthly_usage_limit(tmp_path, monkeypatch) -> None:
    client = make_client(tmp_path, monthly_usage_limit_per_token=1, unlimited_token_labels={"mom"})
    try:
        token = add_app_token(client, label="Mom")

        async def fake_proxy(request_body, settings):
            return Response(content='{"output_text":"ok"}', media_type="application/json")

        monkeypatch.setattr("app.main._proxy_to_openai", fake_proxy)

        for _ in range(3):
            assert client.post(
                "/v1/responses",
                headers={"Authorization": f"Bearer {token}"},
                json=image_request(),
            ).status_code == 200
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
            json=text_request(),
        )
        assert response.status_code == 429
        assert response.json() == {"error": {"message": "quota"}}
    finally:
        close_client(client)
