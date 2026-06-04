from __future__ import annotations

import os
from dataclasses import dataclass


def _get_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return int(value)


def _get_allowed_models() -> set[str]:
    raw_value = os.environ.get("ALLOWED_MODELS", "gpt-5.5")
    return {model.strip() for model in raw_value.split(",") if model.strip()}


def _database_url() -> str:
    url = os.environ.get("DATABASE_URL", "sqlite:///./sasu-backend.db")
    if url.startswith("postgres://"):
        return "postgresql+psycopg://" + url.removeprefix("postgres://")
    if url.startswith("postgresql://"):
        return "postgresql+psycopg://" + url.removeprefix("postgresql://")
    return url


@dataclass(frozen=True)
class Settings:
    database_url: str
    openai_api_key: str
    token_hash_pepper: str
    allowed_models: set[str]
    request_max_bytes: int
    rate_limit_per_minute: int
    invite_base_url: str

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            database_url=_database_url(),
            openai_api_key=os.environ.get("OPENAI_API_KEY", ""),
            token_hash_pepper=os.environ.get("TOKEN_HASH_PEPPER", ""),
            allowed_models=_get_allowed_models(),
            request_max_bytes=_get_int("REQUEST_MAX_BYTES", 6_000_000),
            rate_limit_per_minute=_get_int("RATE_LIMIT_PER_MINUTE", 20),
            invite_base_url=os.environ.get("INVITE_BASE_URL", "http://sasu.jp/#invite="),
        )
