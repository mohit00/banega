"""Error envelope used by every endpoint: {code, message_en, message_hi, details}."""

from __future__ import annotations

from typing import Any

import structlog
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm.exc import StaleDataError
from starlette.exceptions import HTTPException as StarletteHTTPException

log = structlog.get_logger(__name__)


class AppError(Exception):
    status_code: int = 400
    code: str = "bad_request"
    message_en: str = "Something went wrong."
    message_hi: str = "Kuch gadbad ho gayi."

    def __init__(
        self,
        code: str | None = None,
        message_en: str | None = None,
        message_hi: str | None = None,
        *,
        status_code: int | None = None,
        details: dict[str, Any] | None = None,
    ) -> None:
        self.code = code or self.code
        self.message_en = message_en or self.message_en
        self.message_hi = message_hi or self.message_hi
        if status_code is not None:
            self.status_code = status_code
        self.details = details or {}
        # Extra top-level keys for the body (e.g. ``allowed`` on invalid_transition).
        self.extra: dict[str, Any] = {}
        super().__init__(self.message_en)


class NotFound(AppError):
    status_code = 404
    code = "not_found"
    message_en = "Not found."
    message_hi = "Ye nahi mila."


class Unauthorized(AppError):
    status_code = 401
    code = "unauthorized"
    message_en = "Please log in again."
    message_hi = "Kripya dobara login kijiye."


class Forbidden(AppError):
    status_code = 403
    code = "forbidden"
    message_en = "You are not allowed to do this."
    message_hi = "Aapko iski anumati nahi hai."


class Conflict(AppError):
    status_code = 409
    code = "conflict"
    message_en = "This conflicts with the current state."
    message_hi = "Ye abhi ki sthiti se mel nahi khaata."


class PreconditionFailed(AppError):
    status_code = 412
    code = "version_mismatch"
    message_en = "This was changed by someone else. Refresh and try again."
    message_hi = "Ise kisi aur ne badal diya. Refresh karke dobara koshish kijiye."


class Gone(AppError):
    status_code = 410
    code = "gone"
    message_en = "This is no longer available."
    message_hi = "Ye ab uplabdh nahi hai."


class TooManyRequests(AppError):
    status_code = 429
    code = "rate_limited"
    message_en = "Too many attempts. Please try again later."
    message_hi = "Bahut zyada koshish. Thodi der baad try kijiye."


def error_body(
    code: str, message_en: str, message_hi: str, details: dict[str, Any] | None = None
) -> dict[str, Any]:
    return {
        "code": code,
        "message_en": message_en,
        "message_hi": message_hi,
        "details": details or {},
    }


_HTTP_CODES: dict[int, tuple[str, str, str]] = {
    401: ("unauthorized", "Please log in again.", "Kripya dobara login kijiye."),
    403: ("forbidden", "You are not allowed to do this.", "Aapko iski anumati nahi hai."),
    404: ("not_found", "Not found.", "Ye nahi mila."),
    405: ("method_not_allowed", "Method not allowed.", "Ye tarika allowed nahi hai."),
}


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(_: Request, exc: AppError) -> JSONResponse:
        body = error_body(exc.code, exc.message_en, exc.message_hi, exc.details)
        for key, value in exc.extra.items():
            body.setdefault(key, value)
        return JSONResponse(status_code=exc.status_code, content=body)

    @app.exception_handler(StaleDataError)
    async def _stale(_: Request, exc: StaleDataError) -> JSONResponse:
        # Optimistic lock lost (Ticket/Menu.version): somebody else wrote first.
        return JSONResponse(
            status_code=409,
            content=error_body(
                "version_conflict",
                "This was changed by someone else. Refresh and try again.",
                "Ise kisi aur ne badal diya. Refresh karke dobara koshish kijiye.",
            ),
        )

    @app.exception_handler(IntegrityError)
    async def _integrity(_: Request, exc: IntegrityError) -> JSONResponse:
        # A unique / FK constraint lost a race the service checks did not see (two requests
        # at once): the database is the last line, the client gets a retryable 409.
        log.warning("integrity_conflict", error=str(exc.orig)[:300])
        return JSONResponse(
            status_code=409,
            content=error_body(
                "conflict",
                "This conflicts with a change made at the same time. Refresh and try again.",
                "Ye usi samay hue badlav se takraata hai. Refresh karke dobara koshish kijiye.",
            ),
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code, en, hi = _HTTP_CODES.get(
            exc.status_code, ("http_error", str(exc.detail), str(exc.detail))
        )
        return JSONResponse(
            status_code=exc.status_code,
            content=error_body(code, en, hi),
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        errors = [
            {"loc": list(e.get("loc", [])), "msg": e.get("msg"), "type": e.get("type")}
            for e in exc.errors()
        ]
        return JSONResponse(
            status_code=422,
            content=error_body(
                "validation_error",
                "Some fields are invalid.",
                "Kuch jaankari sahi nahi hai.",
                {"errors": errors},
            ),
        )

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, exc: Exception) -> JSONResponse:
        log.exception("unhandled_error", error=str(exc))
        return JSONResponse(
            status_code=500,
            content=error_body("internal_error", "Something went wrong.", "Kuch gadbad ho gayi."),
        )
