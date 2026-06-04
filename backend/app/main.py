from __future__ import annotations

import json
from contextlib import asynccontextmanager
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import Settings
from .db import Database
from .models import AppToken, Invite, utc_now
from .schemas import RedeemInviteRequest, RedeemInviteResponse
from .security import hash_secret, make_app_token

OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses"


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


def get_db(request: Request) -> Iterator[Session]:
    yield from request.app.state.database.session()


def _require_backend_secret(settings: Settings) -> None:
    if not settings.token_hash_pepper:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="TOKEN_HASH_PEPPER is not configured.",
        )


def _require_openai_key(settings: Settings) -> None:
    if not settings.openai_api_key:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="OPENAI_API_KEY is not configured.",
        )


def _is_expired(expires_at: datetime | None) -> bool:
    if expires_at is None:
        return False
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return expires_at <= utc_now()


def _bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing access token.")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid access token.")
    return token


def _require_app_token(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> AppToken:
    _require_backend_secret(settings)
    token = _bearer_token(authorization)
    token_hash = hash_secret(token, settings.token_hash_pepper)
    app_token = db.scalar(select(AppToken).where(AppToken.token_hash == token_hash))
    if app_token is None or app_token.revoked_at is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid access token.")

    _enforce_rate_limit(app_token, settings)
    now = utc_now()
    app_token.last_used_at = now
    app_token.request_count += 1
    db.commit()
    db.refresh(app_token)
    return app_token


def _enforce_rate_limit(app_token: AppToken, settings: Settings) -> None:
    now = utc_now()
    window_started_at = app_token.rate_window_started_at
    if window_started_at is None:
        app_token.rate_window_started_at = now
        app_token.rate_window_request_count = 1
        return

    if window_started_at.tzinfo is None:
        window_started_at = window_started_at.replace(tzinfo=timezone.utc)

    if now - window_started_at >= timedelta(minutes=1):
        app_token.rate_window_started_at = now
        app_token.rate_window_request_count = 1
        return

    if app_token.rate_window_request_count >= settings.rate_limit_per_minute:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Rate limit exceeded.")

    app_token.rate_window_request_count += 1


def _validate_model(request_body: dict, settings: Settings) -> None:
    model = request_body.get("model")
    if not isinstance(model, str) or model not in settings.allowed_models:
        allowed = ", ".join(sorted(settings.allowed_models))
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Model is not allowed. Allowed: {allowed}")


async def _proxy_to_openai(request_body: dict, settings: Settings) -> Response:
    _require_openai_key(settings)
    async with httpx.AsyncClient(timeout=httpx.Timeout(180.0, connect=10.0)) as client:
        upstream = await client.post(
            OPENAI_RESPONSES_URL,
            headers={
                "Authorization": f"Bearer {settings.openai_api_key}",
                "Content-Type": "application/json",
            },
            json=request_body,
        )

    content_type = upstream.headers.get("content-type", "application/json")
    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        media_type=content_type,
    )


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    database = Database(settings.database_url)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        database.create_all()
        yield

    app = FastAPI(title="Sasu Invite Backend", lifespan=lifespan)
    app.state.settings = settings
    app.state.database = database

    @app.get("/health")
    def health() -> dict[str, bool]:
        return {"ok": True}

    @app.post("/v1/invites/redeem", response_model=RedeemInviteResponse)
    def redeem_invite(
        payload: RedeemInviteRequest,
        settings: Settings = Depends(get_settings),
        db: Session = Depends(get_db),
    ) -> RedeemInviteResponse:
        _require_backend_secret(settings)
        code_hash = hash_secret(payload.code, settings.token_hash_pepper)
        invite = db.scalar(select(Invite).where(Invite.code_hash == code_hash).with_for_update())
        if (
            invite is None
            or invite.revoked_at is not None
            or invite.redeemed_at is not None
            or _is_expired(invite.expires_at)
        ):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired invite.")

        access_token = make_app_token()
        app_token = AppToken(
            label=invite.label,
            token_hash=hash_secret(access_token, settings.token_hash_pepper),
        )
        db.add(app_token)
        db.flush()

        invite.redeemed_at = utc_now()
        invite.redeemed_token_id = app_token.id
        db.commit()

        return RedeemInviteResponse(access_token=access_token, label=invite.label)

    @app.post("/v1/responses")
    async def responses_proxy(
        request: Request,
        _: AppToken = Depends(_require_app_token),
        settings: Settings = Depends(get_settings),
    ) -> Response:
        body = await request.body()
        if len(body) > settings.request_max_bytes:
            raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="Request body is too large.")

        try:
            request_body = json.loads(body)
        except json.JSONDecodeError:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Request body must be valid JSON.")

        if not isinstance(request_body, dict):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Request body must be a JSON object.")

        _validate_model(request_body, settings)
        return await _proxy_to_openai(request_body, settings)

    return app


app = create_app()
