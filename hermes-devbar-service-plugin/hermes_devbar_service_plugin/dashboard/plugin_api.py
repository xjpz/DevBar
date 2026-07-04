"""Hidden dashboard API for DevBar service-token ws-ticket minting."""

from __future__ import annotations

import sys
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
if str(PLUGIN_ROOT) not in sys.path:
    sys.path.insert(0, str(PLUGIN_ROOT))

try:
    from fastapi import APIRouter, HTTPException, Request
except Exception:  # Allows unit tests without FastAPI installed.
    class HTTPException(Exception):  # type: ignore[no-redef]
        def __init__(self, status_code: int, detail: str):
            super().__init__(detail)
            self.status_code = status_code
            self.detail = detail

    class Request:  # type: ignore[no-redef]
        pass

    class APIRouter:  # type: ignore[no-redef]
        def post(self, *_args, **_kwargs):
            return lambda fn: fn

from hermes_cli.dashboard_auth.ws_tickets import TTL_SECONDS, mint_ticket
from provider import service_token_from_env, service_token_matches

router = APIRouter()


def _bearer_token(request: Request) -> str:
    authorization = getattr(getattr(request, "headers", {}), "get", lambda _name, _default=None: "")(
        "authorization",
        "",
    )
    scheme, _, token = str(authorization).partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        return ""
    return token.strip()


@router.post("/ws-ticket")
async def issue_ws_ticket(request: Request) -> dict:
    try:
        expected_token = service_token_from_env()
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    if not service_token_matches(_bearer_token(request), expected_token):
        raise HTTPException(status_code=401, detail="invalid service token")

    ticket = mint_ticket(
        user_id="playdev-server",
        provider="devbar-service",
    )
    return {
        "ticket": ticket,
        "ttl_seconds": TTL_SECONDS,
    }
