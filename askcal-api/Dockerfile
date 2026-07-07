# Askcal API — production image.
# uv-based, matches the local toolchain (uv 0.11, Python 3.13).
FROM python:3.13-slim-bookworm

# uv binary, pinned to the same minor as local dev for reproducible installs.
COPY --from=ghcr.io/astral-sh/uv:0.11 /uv /bin/uv

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

# Install dependencies first, in their own layer, so source edits don't bust
# the (slow) dependency cache. --no-install-project skips building the app
# itself (there's no build backend — the source is run in place off WORKDIR).
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project --no-dev

# App source. .dockerignore keeps .venv/.env/caches out.
COPY . .
RUN chmod +x docker-entrypoint.sh

# Put the venv on PATH so alembic/uvicorn resolve without `uv run`.
ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000
ENTRYPOINT ["/app/docker-entrypoint.sh"]
