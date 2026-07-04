import os
import sys
import unittest
import asyncio
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

HERMES_SOURCE = Path("/private/tmp/hermes-agent-source")
if HERMES_SOURCE.exists():
    sys.path.insert(0, str(HERMES_SOURCE))


class DevBarServiceTokenTests(unittest.TestCase):
    def setUp(self):
        os.environ.pop("HERMES_DEVBAR_SERVICE_TOKEN", None)

    def test_service_token_matches_only_exact_high_entropy_token(self):
        from hermes_devbar_service_plugin.provider import (
            assess_token_strength,
            service_token_matches,
        )

        token = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
        self.assertIsNone(assess_token_strength(token))
        self.assertFalse(service_token_matches("wrong-token", token))
        self.assertTrue(service_token_matches(token, token))

    def test_service_token_from_env_rejects_weak_or_missing_token(self):
        from hermes_devbar_service_plugin.provider import service_token_from_env

        with self.assertRaises(ValueError):
            service_token_from_env()

        os.environ["HERMES_DEVBAR_SERVICE_TOKEN"] = "short"
        with self.assertRaises(ValueError):
            service_token_from_env()


class DevBarServiceApiTests(unittest.TestCase):
    def test_ws_ticket_endpoint_requires_bearer_token(self):
        from hermes_devbar_service_plugin.dashboard.plugin_api import issue_ws_ticket

        os.environ["HERMES_DEVBAR_SERVICE_TOKEN"] = (
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
        )
        request = SimpleNamespace(headers={})

        with self.assertRaises(Exception) as ctx:
            asyncio.run(issue_ws_ticket(request))
        self.assertEqual(getattr(ctx.exception, "status_code", None), 401)

    def test_ws_ticket_endpoint_mints_ticket_for_valid_bearer_token(self):
        from hermes_devbar_service_plugin.dashboard.plugin_api import issue_ws_ticket

        token = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
        os.environ["HERMES_DEVBAR_SERVICE_TOKEN"] = token
        request = SimpleNamespace(
            headers={"authorization": f"Bearer {token}"}
        )

        data = asyncio.run(issue_ws_ticket(request))

        self.assertEqual(data["ttl_seconds"], 30)
        self.assertTrue(data["ticket"])


if __name__ == "__main__":
    unittest.main()
