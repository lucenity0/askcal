import asyncio
import contextlib
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
    inbox,
    me,
    routines,
    tasks,
    today,
    tracks,
)
from app.services.sync import sync_loop


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(sync_loop()) if get_settings().sync_enabled else None
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
app.include_router(routines.router)
app.include_router(me.router)


@app.get("/health", tags=["meta"])
async def health() -> dict:
    return {"status": "ok"}
