"""DevBar service-token dashboard plugin for Hermes."""

from __future__ import annotations

import logging

logger = logging.getLogger(__name__)

TOKEN_ROUTE = "/api/plugins/devbar-service/ws-ticket"


def register(ctx) -> None:
    """Keep the backend plugin loadable on Hermes versions without token-provider hooks."""
    logger.info("devbar-service: dashboard API route available at %s", TOKEN_ROUTE)
