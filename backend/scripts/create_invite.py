#!/usr/bin/env python
from __future__ import annotations

import argparse
from datetime import timedelta

from sqlalchemy import select

from app.config import Settings
from app.db import Database
from app.models import Invite, utc_now
from app.security import hash_secret, make_invite_code


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a one-time Sasu invite link.")
    parser.add_argument("label", help="Human label for the invite, for example mom or garrett.")
    parser.add_argument("--expires-days", type=int, default=30, help="Invite expiration in days. Default: 30.")
    parser.add_argument("--base-url", help="Invite URL prefix. Defaults to INVITE_BASE_URL.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    settings = Settings.from_env()
    if not settings.token_hash_pepper:
        raise SystemExit("TOKEN_HASH_PEPPER must be set before creating invites.")

    database = Database(settings.database_url)
    database.create_all()

    code = make_invite_code()
    code_hash = hash_secret(code, settings.token_hash_pepper)
    expires_at = utc_now() + timedelta(days=args.expires_days) if args.expires_days > 0 else None

    with database.session_local() as db:
        existing = db.scalar(select(Invite).where(Invite.code_hash == code_hash))
        if existing is not None:
            raise SystemExit("Generated a duplicate invite code. Run the command again.")

        invite = Invite(label=args.label, code_hash=code_hash, expires_at=expires_at)
        db.add(invite)
        db.commit()

    base_url = args.base_url or settings.invite_base_url
    link = f"{base_url}{code}"
    print(f"Invite created for {args.label}:")
    print()
    print(link)
    print()
    print("This is the only time the plaintext invite code will be shown.")


if __name__ == "__main__":
    main()
