from __future__ import annotations

import json
from contextlib import asynccontextmanager
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from typing import Optional

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response, status
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import Settings
from .db import Database
from .models import AppToken, Invite, TokenMonthlyUsage, utc_now
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


def _is_expired(expires_at: Optional[datetime]) -> bool:
    if expires_at is None:
        return False
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return expires_at <= utc_now()


def _bearer_token(authorization: Optional[str]) -> str:
    if not authorization:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing access token.")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid access token.")
    return token


def _require_app_token(
    authorization: Optional[str] = Header(default=None),
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


def _current_month_key(now: datetime) -> str:
    return now.strftime("%Y-%m")


def _next_month_start(now: datetime) -> datetime:
    year = now.year + (1 if now.month == 12 else 0)
    month = 1 if now.month == 12 else now.month + 1
    return datetime(year, month, 1, tzinfo=timezone.utc)


def _enforce_monthly_limit(app_token: AppToken, settings: Settings, db: Session, usage_units: int) -> None:
    if settings.monthly_usage_limit_per_token <= 0:
        return

    if app_token.label.strip().lower() in settings.unlimited_token_labels:
        return

    now = utc_now()
    month_key = _current_month_key(now)
    usage = db.scalar(
        select(TokenMonthlyUsage).where(
            TokenMonthlyUsage.app_token_id == app_token.id,
            TokenMonthlyUsage.month_key == month_key,
        )
    )

    if usage is None:
        usage = TokenMonthlyUsage(app_token_id=app_token.id, month_key=month_key)
        db.add(usage)
        db.flush()

    if usage.usage_units + usage_units > settings.monthly_usage_limit_per_token:
        reset_date = _next_month_start(now).date().isoformat()
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Monthly hosted access limit reached. Your limit resets on {reset_date}.",
        )

    usage.usage_units += usage_units
    usage.updated_at = now


def _contains_input_image(value: object) -> bool:
    if isinstance(value, dict):
        if value.get("type") == "input_image" or "image_url" in value:
            return True
        return any(_contains_input_image(child) for child in value.values())

    if isinstance(value, list):
        return any(_contains_input_image(child) for child in value)

    return False


def _request_usage_units(request_body: dict, settings: Settings) -> int:
    if _contains_input_image(request_body):
        return max(settings.image_request_usage_units, 0)
    return max(settings.text_request_usage_units, 0)


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
    client = httpx.AsyncClient(timeout=httpx.Timeout(180.0, connect=10.0))
    upstream_request = client.build_request(
        "POST",
        OPENAI_RESPONSES_URL,
        headers={
            "Authorization": f"Bearer {settings.openai_api_key}",
            "Content-Type": "application/json",
        },
        json=request_body,
    )
    upstream = await client.send(upstream_request, stream=True)
    content_type = upstream.headers.get("content-type", "application/json")

    if request_body.get("stream") is True and 200 <= upstream.status_code < 300:
        async def stream_body():
            try:
                async for chunk in upstream.aiter_bytes():
                    yield chunk
            finally:
                await upstream.aclose()
                await client.aclose()

        return StreamingResponse(
            stream_body(),
            status_code=upstream.status_code,
            media_type=content_type,
        )

    content = await upstream.aread()
    await upstream.aclose()
    await client.aclose()
    return Response(
        content=content,
        status_code=upstream.status_code,
        media_type=content_type,
    )


def create_app(settings: Optional[Settings] = None) -> FastAPI:
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
        app_token: AppToken = Depends(_require_app_token),
        settings: Settings = Depends(get_settings),
        db: Session = Depends(get_db),
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
        _enforce_monthly_limit(app_token, settings, db, _request_usage_units(request_body, settings))
        db.commit()
        return await _proxy_to_openai(request_body, settings)

    return app


app = create_app()
