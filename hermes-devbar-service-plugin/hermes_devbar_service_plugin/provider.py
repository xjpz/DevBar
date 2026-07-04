"""Shared service-token validation helpers for DevBar's Hermes plugin."""

from __future__ import annotations

import hmac
import logging
import math
import os
from collections import Counter
from typing import Optional

logger = logging.getLogger(__name__)

ENV_TOKEN = "HERMES_DEVBAR_SERVICE_TOKEN"
DEFAULT_MIN_TOKEN_CHARS = 43
MIN_DISTINCT_CHARS = 16
MIN_SHANNON_BITS = 128.0


def _shannon_bits(value: str) -> float:
    if not value:
        return 0.0
    counts = Counter(value)
    length = len(value)
    per_char = -sum((count / length) * math.log2(count / length) for count in counts.values())
    return per_char * length


def assess_token_strength(token: str, min_chars: int = DEFAULT_MIN_TOKEN_CHARS) -> Optional[str]:
    if not token:
        return "token is empty"
    if len(token) < min_chars:
        return f"token too short: {len(token)} chars (need >= {min_chars})"
    distinct = len(set(token))
    if distinct < MIN_DISTINCT_CHARS:
        return f"token has only {distinct} distinct characters (need >= {MIN_DISTINCT_CHARS})"
    bits = _shannon_bits(token)
    if bits < MIN_SHANNON_BITS:
        return f"token entropy too low: {bits:.0f} bits (need >= {MIN_SHANNON_BITS:.0f})"
    return None


def service_token_from_env() -> str:
    token = os.environ.get(ENV_TOKEN, "").strip()
    reason = assess_token_strength(token)
    if reason is not None:
        raise ValueError(f"DevBar service token rejected: {reason}")
    return token


def service_token_matches(presented: str, expected: str) -> bool:
    if not presented or not expected:
        return False
    return hmac.compare_digest(presented.encode("utf-8"), expected.encode("utf-8"))
