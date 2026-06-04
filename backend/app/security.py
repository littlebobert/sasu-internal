from __future__ import annotations

import hashlib
import hmac
import secrets


INVITE_PREFIX = "sasu_inv_"
APP_TOKEN_PREFIX = "sasu_app_"


def make_invite_code() -> str:
    return f"{INVITE_PREFIX}{secrets.token_urlsafe(32)}"


def make_app_token() -> str:
    return f"{APP_TOKEN_PREFIX}{secrets.token_urlsafe(40)}"


def hash_secret(secret: str, pepper: str) -> str:
    return hmac.new(
        pepper.encode("utf-8"),
        secret.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def constant_time_equal(left: str, right: str) -> bool:
    return hmac.compare_digest(left, right)
