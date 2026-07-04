# Hermes DevBar Service Plugin

Hidden dashboard API for DevBar's playdev-server service credential.

It exposes:

```text
POST /api/plugins/devbar-service/ws-ticket
Authorization: Bearer <HERMES_DEVBAR_SERVICE_TOKEN>
```

The endpoint returns a single-use Hermes WebSocket ticket:

```json
{
  "ticket": "...",
  "ttl_seconds": 30
}
```

Configure a strong service token in the Hermes environment:

```bash
HERMES_DEVBAR_SERVICE_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
```

Install into a machine-installed Hermes checkout as a bundled dashboard plugin:

```bash
mkdir -p ~/.hermes/hermes-agent/plugins/devbar-service
cp -R hermes_devbar_service_plugin/* ~/.hermes/hermes-agent/plugins/devbar-service/
```

The dashboard auth gate must allow exactly this endpoint through so the plugin
can verify `Authorization: Bearer ...` itself:

```python
"/api/plugins/devbar-service/ws-ticket",
```

Add that path to `hermes_cli/dashboard_auth/public_paths.py`.
