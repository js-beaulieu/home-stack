#!/usr/bin/env python3
import json
import os
import sys
import urllib.parse

import requests


def assert_ok(name: str, condition: bool, detail: str) -> None:
    if not condition:
        raise RuntimeError(f"{name}: {detail}")
    print(f"PASS {name}: {detail}")


def main() -> int:
    session = requests.Session()

    health = session.get("http://tasks.localhost/api/health", timeout=10)
    assert_ok("public health", health.status_code == 200, f"status={health.status_code}")

    keycloak = session.get("http://auth.localhost/", timeout=10, allow_redirects=False)
    assert_ok("keycloak host", keycloak.status_code in {200, 302, 303}, f"status={keycloak.status_code}")

    discovery = session.get(
        "http://auth.localhost/realms/home-stack/.well-known/openid-configuration",
        timeout=10,
    )
    assert_ok("oidc discovery", discovery.status_code == 200, f"status={discovery.status_code}")
    discovery_json = discovery.json()
    assert_ok("issuer", discovery_json["issuer"] == "http://auth.localhost/realms/home-stack", discovery_json["issuer"])

    jwks = session.get(discovery_json["jwks_uri"], timeout=10)
    jwks_json = jwks.json()
    assert_ok("jwks", jwks.status_code == 200 and len(jwks_json.get("keys", [])) > 0, f"keys={len(jwks_json.get('keys', []))}")

    dcr_payload = {
        "client_name": "home-stack-local-dcr",
        "redirect_uris": ["https://claude.ai/api/mcp/auth_callback"],
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "token_endpoint_auth_method": "none",
        # "openid" is a protocol-level scope in Keycloak, not a named client scope;
        # the Keycloak DCR policy validates named scopes so openid must be omitted here.
        # Clients request openid (implicitly handled by Keycloak) at token-request time.
        "scope": "profile email",
    }
    dcr = session.post(
        "http://auth.localhost/realms/home-stack/clients-registrations/openid-connect",
        timeout=10,
        json=dcr_payload,
    )
    assert_ok("anonymous dcr", dcr.status_code in {201, 409}, f"status={dcr.status_code}")

    smoke_password = (
        os.environ.get("KEYCLOAK_SMOKE_PASSWORD")
        or read_env_file(".generated/local/home-stack.env").get("LOCAL_SMOKE_USER_PASSWORD")
        or ""
    )
    token = session.post(
        "http://auth.localhost/realms/home-stack/protocol/openid-connect/token",
        timeout=10,
        data={
            "grant_type": "password",
            "client_id": "home-stack-cli",
            "username": "local-smoke-user",
            "password": smoke_password,
            "scope": "openid profile email",
        },
    )
    token_json = token.json()
    assert_ok("token endpoint", token.status_code == 200 and "access_token" in token_json, f"status={token.status_code}")

    protected = session.get(
        "http://tasks.localhost/api/users/me",
        timeout=10,
        headers={"Authorization": f"Bearer {token_json['access_token']}"},
    )
    protected_json = protected.json()
    assert_ok("protected route", protected.status_code == 200, f"status={protected.status_code}")
    assert_ok("protected route user", protected_json.get("email") == "local-smoke-user@example.com", json.dumps(protected_json))

    private_app = session.get("http://private.localhost/", timeout=10, allow_redirects=False)
    location = private_app.headers.get("Location", "")
    assert_ok(
        "oauth2-proxy browser auth",
        private_app.status_code in {302, 303} and ("/oauth2/sign_in" in location or "openid-connect/auth" in location),
        f"status={private_app.status_code} location={location}",
    )

    return 0


def read_env_file(path: str) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                values[key] = value
    except FileNotFoundError:
        return values
    return values


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        sys.stderr.write(f"FAIL {exc}\n")
        raise
