"""One-off maintenance scripts.

Run inside the API container with `exec`, not `run`: the image's entrypoint
ignores the command it is given and starts uvicorn, so `docker compose run`
would launch a second server instead of the script.

    docker compose -f docker-compose.prod.yml -f docker-compose.subscription.yml \
        exec api uv run python -m app.scripts.<name>
"""
