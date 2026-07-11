# Sasu Invite Backend

FastAPI service for invite-only Sasu access. It redeems one-time invite links for app access tokens, then proxies Sasu requests to OpenAI with the server-side API key.

## Local Setup

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export OPENAI_API_KEY=sk-...
export TOKEN_HASH_PEPPER="$(python -c 'import secrets; print(secrets.token_urlsafe(48))')"
uvicorn app.main:app --reload
```

By default, local development uses `sqlite:///./sasu-backend.db`.

## Create An Invite

```bash
cd backend
python scripts/create_invite.py mom
```

The command stores only a hash of the one-time invite code and prints a link like:

```text
https://sasu.jp/sasu-invite#invite=sasu_inv_...
```

If you lose the printed URL, create a new invite.

## Heroku

Create an app and add Heroku Postgres, then set config vars:

```bash
heroku config:set OPENAI_API_KEY=sk-... --app <heroku-app>
heroku config:set TOKEN_HASH_PEPPER="$(python -c 'import secrets; print(secrets.token_urlsafe(48))')" --app <heroku-app>
heroku config:set INVITE_BASE_URL="https://sasu.jp/sasu-invite#invite=" --app <heroku-app>
heroku config:set ALLOWED_MODELS="gpt-5.5" --app <heroku-app>
heroku config:set MONTHLY_USAGE_LIMIT_PER_TOKEN=600 --app <heroku-app>
heroku config:set IMAGE_REQUEST_USAGE_UNITS=10 --app <heroku-app>
heroku config:set TEXT_REQUEST_USAGE_UNITS=1 --app <heroku-app>
heroku config:set UNLIMITED_TOKEN_LABELS="mom,dad" --app <heroku-app>
```

## Monthly Usage Limits

Hosted invite access is capped per token so the beta can stay within budget. The
default is 600 usage units per calendar month per token. Screenshot/image
requests cost 10 units, while text-only requests cost 1 unit, so the default
allows roughly 60 image requests or 600 text-only translations.

Set `MONTHLY_USAGE_LIMIT_PER_TOKEN=0` to disable the monthly limit globally. Set
`UNLIMITED_TOKEN_LABELS` to a comma-separated list of invite labels that should
not be capped, for example friends and family tokens. The limit uses a separate
`token_monthly_usage` table, which startup `create_all()` creates without
altering existing invite/token tables.

## Usage Reporting

Run a quick usage report locally:

```bash
cd backend
python scripts/usage_report.py
```

Run it against production on Heroku:

```bash
heroku run python scripts/usage_report.py --app <heroku-app>
```

Useful options:

```bash
python scripts/usage_report.py --month 2026-06 --active-days 14 --limit 30
```

The report shows active tokens, recently active tokens, redeemed/open invites,
tracked all-time usage units by default, and top token labels by usage. Pass
`--month YYYY-MM` to report a single calendar month. For budget alerting, start
with OpenAI project/key spend alerts and use this report for user-level follow-up.

Deploy this subdirectory from the monorepo:

```bash
git subtree push --prefix backend heroku main
```

Create production invites with:

```bash
heroku run python scripts/create_invite.py mom --app <heroku-app>
```

## Privacy

The backend receives the same request body the app would otherwise send directly to OpenAI, including screenshots or clipboard text when the user asks Sasu for help. Do not log request bodies, prompts, screenshots, clipboard text, or model responses.
