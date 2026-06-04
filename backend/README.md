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
http://sasu.jp/#invite=sasu_inv_...
```

If you lose the printed URL, create a new invite.

## Heroku

Create an app and add Heroku Postgres, then set config vars:

```bash
heroku config:set OPENAI_API_KEY=sk-... --app <heroku-app>
heroku config:set TOKEN_HASH_PEPPER="$(python -c 'import secrets; print(secrets.token_urlsafe(48))')" --app <heroku-app>
heroku config:set INVITE_BASE_URL="http://sasu.jp/#invite=" --app <heroku-app>
heroku config:set ALLOWED_MODELS="gpt-5.5" --app <heroku-app>
```

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
