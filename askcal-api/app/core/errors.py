"""Error shape shared by every endpoint, per references/api-contracts.md:

    { "error": "GMAIL_DISCONNECTED", "message": "Gmail auth expired", "code": 401 }
"""

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class AskcalError(Exception):
    def __init__(self, code: int, error: str, message: str):
        self.code = code
        self.error = error
        self.message = message


async def askcal_error_handler(request: Request, exc: AskcalError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.code,
        content={"error": exc.error, "message": exc.message, "code": exc.code},
    )


_HTTP_ERROR_KEYS = {
    401: "AUTH_EXPIRED",
    404: "NOT_FOUND",
    429: "RATE_LIMITED",
    503: "SERVICE_UNAVAILABLE",
}


async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    error = _HTTP_ERROR_KEYS.get(exc.status_code, "SERVER_ERROR")
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": error, "message": str(exc.detail), "code": exc.status_code},
    )
