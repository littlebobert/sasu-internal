#!/usr/bin/env python
from __future__ import annotations

import argparse
import sys
from datetime import timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import func, select

from app.config import Settings
from app.db import Database
from app.models import AppToken, Invite, TokenMonthlyUsage, utc_now


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Show Sasu backend usage by app token.")
    parser.add_argument("--month", help="Month to report as YYYY-MM. Defaults to the current UTC month.")
    parser.add_argument("--active-days", type=int, default=30, help="Window for recently active tokens. Default: 30.")
    parser.add_argument("--limit", type=int, default=20, help="Number of top tokens to show. Default: 20.")
    return parser.parse_args()


def month_key() -> str:
    return utc_now().strftime("%Y-%m")


def main() -> None:
    args = parse_args()
    settings = Settings.from_env()
    database = Database(settings.database_url)
    database.create_all()

    report_month = args.month or month_key()
    active_since = utc_now() - timedelta(days=args.active_days)

    with database.session_local() as db:
        active_tokens = db.scalar(
            select(func.count()).select_from(AppToken).where(AppToken.revoked_at.is_(None))
        )
        recently_active_tokens = db.scalar(
            select(func.count())
            .select_from(AppToken)
            .where(AppToken.revoked_at.is_(None), AppToken.last_used_at >= active_since)
        )
        redeemed_invites = db.scalar(
            select(func.count()).select_from(Invite).where(Invite.redeemed_at.is_not(None))
        )
        open_invites = db.scalar(
            select(func.count())
            .select_from(Invite)
            .where(Invite.redeemed_at.is_(None), Invite.revoked_at.is_(None))
        )

        total_usage_units = db.scalar(
            select(func.coalesce(func.sum(TokenMonthlyUsage.usage_units), 0)).where(
                TokenMonthlyUsage.month_key == report_month
            )
        )

        print(f"Sasu usage report for {report_month}")
        print()
        print(f"Active tokens: {active_tokens or 0}")
        print(f"Recently active tokens ({args.active_days}d): {recently_active_tokens or 0}")
        print(f"Redeemed invites: {redeemed_invites or 0}")
        print(f"Open invites: {open_invites or 0}")
        print(f"Monthly usage units: {total_usage_units or 0}")
        print(f"Monthly usage limit per token: {settings.monthly_usage_limit_per_token}")
        if settings.unlimited_token_labels:
            print(f"Unlimited labels: {', '.join(sorted(settings.unlimited_token_labels))}")
        print()
        print("Top tokens by monthly usage:")

        rows = db.execute(
            select(
                AppToken.label,
                AppToken.request_count,
                AppToken.last_used_at,
                TokenMonthlyUsage.usage_units,
            )
            .join(TokenMonthlyUsage, TokenMonthlyUsage.app_token_id == AppToken.id)
            .where(TokenMonthlyUsage.month_key == report_month)
            .order_by(TokenMonthlyUsage.usage_units.desc(), AppToken.last_used_at.desc().nullslast())
            .limit(args.limit)
        ).all()

        if not rows:
            print("  No usage for this month yet.")
            return

        for label, lifetime_requests, last_used_at, usage_units in rows:
            last_used = last_used_at.isoformat() if last_used_at else "never"
            unlimited_marker = " (unlimited)" if label.strip().lower() in settings.unlimited_token_labels else ""
            print(
                f"  {label}{unlimited_marker}: "
                f"{usage_units} units this month, "
                f"{lifetime_requests} lifetime requests, "
                f"last used {last_used}"
            )


if __name__ == "__main__":
    main()
