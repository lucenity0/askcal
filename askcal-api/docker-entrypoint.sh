#!/bin/sh
# Apply any pending schema migrations, then start the API.
set -e

echo "[entrypoint] running database migrations..."
alembic upgrade head

echo "[entrypoint] starting uvicorn..."
# --workers 1 is deliberate: the Gmail sync loop runs in-process via the app
# lifespan (app/main.py). More than one worker would run duplicate sync loops.
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 1
