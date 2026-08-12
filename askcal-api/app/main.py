import asyncio
import contextlib
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.config import get_settings
from app.core.errors import AskcalError, http_exception_handler, askcal_error_handler
from app.routers import (
    auth,
    calendar,
    closing_time,
    digest,
    inbox,
    me,
    routines,
    settings as settings_router,
    tasks,
    today,
    tracks,
)
from app.llm.registry import classifier_configured, classifier_unavailable_reason
from app.services.sync import sync_loop

logger = logging.getLogger("askcal")


@asynccontextmanager
async def lifespan(app: FastAPI):
    s = get_settings()
    # Log, don't raise: an unclassifiable inbox is degraded, not dead — ingestion,
    # tasks and the calendar all still work. But it has to be *visible*, because
    # the failure mode otherwise is mail that silently never gets ranked.
    if not classifier_configured():
        logger.error(
            "LLM provider %r is not usable — mail will be ingested but never classified.",
            s.llm_provider,
        )
    if s.jwt_secret == "change-me":
        logger.error("ASKCAL_JWT_SECRET is still the default — tokens are forgeable.")

    task = asyncio.create_task(sync_loop()) if s.sync_enabled else None
    yield
    if task:
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task


app = FastAPI(title="Askcal API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_exception_handler(AskcalError, askcal_error_handler)
app.add_exception_handler(StarletteHTTPException, http_exception_handler)

app.include_router(auth.router)
app.include_router(today.router)
app.include_router(inbox.router)
app.include_router(tracks.router)
app.include_router(tasks.router)
app.include_router(calendar.router)
app.include_router(closing_time.router)
app.include_router(digest.router)
app.include_router(routines.router)
app.include_router(settings_router.router)
app.include_router(me.router)


@app.get("/health", tags=["meta"])
async def health() -> dict:
    """Includes classifier state so a deploy is verifiable without shelling in."""
    reason = classifier_unavailable_reason()
    body = {
        "status": "ok",
        "llm_provider": get_settings().llm_provider,
        "classifier_configured": reason is None,
    }
    # Only present when something is wrong, so a healthy deploy stays terse and
    # an unhealthy one says what to fix without shelling into the VM.
    if reason is not None:
        body["classifier_detail"] = reason
    return body
