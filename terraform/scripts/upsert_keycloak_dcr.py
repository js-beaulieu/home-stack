#!/usr/bin/env python3
import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request


POLICY_PROVIDER_TYPE = "org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy"
POLICIES = [
    {
        "name": "Trusted Hosts",
        "providerId": "trusted-hosts",
        "subType": "anonymous",
        "config": {
            "trusted-hosts": ["localhost", "claude.ai", "claude.com"],
            "host-sending-registration-request-must-match": ["false"],
            "client-uris-must-match": ["true"],
        },
    },
    {
        "name": "Allowed Registration Web Origins",
        "providerId": "registration-web-origins",
        "subType": "anonymous",
        "config": {
            "web-origins": ["https://claude.ai", "https://claude.com"],
        },
    },
]


def http_json(url: str, *, method: str = "GET", headers=None, body=None):
    request = urllib.request.Request(url, method=method)
    for key, value in (headers or {}).items():
      request.add_header(key, value)
    if body is not None:
      data = json.dumps(body).encode("utf-8")
      request.add_header("Content-Type", "application/json")
      request.data = data
    with urllib.request.urlopen(request) as response:
      payload = response.read().decode("utf-8")
      return response.status, json.loads(payload) if payload else None


def get_token(base_url: str, username: str, password: str) -> str:
    payload = urllib.parse.urlencode(
        {
            "grant_type": "password",
            "client_id": "admin-cli",
            "username": username,
            "password": password,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url}/realms/master/protocol/openid-connect/token",
        data=payload,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(request) as response:
        data = json.loads(response.read().decode("utf-8"))
    return data["access_token"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--realm", required=True)
    parser.add_argument("--admin-username", required=True)
    parser.add_argument("--admin-password", required=True)
    args = parser.parse_args()

    try:
        token = get_token(args.base_url, args.admin_username, args.admin_password)
        headers = {"Authorization": f"Bearer {token}"}
        _, components = http_json(f"{args.base_url}/admin/realms/{args.realm}/components", headers=headers)
        parent_id = components[0]["parentId"] if components else args.realm

        for policy in POLICIES:
            existing = next(
                (
                    item
                    for item in components
                    if item.get("providerType") == POLICY_PROVIDER_TYPE
                    and item.get("providerId") == policy["providerId"]
                    and item.get("subType") == policy["subType"]
                ),
                None,
            )
            body = {
                "name": policy["name"],
                "providerId": policy["providerId"],
                "providerType": POLICY_PROVIDER_TYPE,
                "parentId": parent_id,
                "subType": policy["subType"],
                "config": policy["config"],
            }
            if existing:
                body["id"] = existing["id"]
                http_json(
                    f"{args.base_url}/admin/realms/{args.realm}/components/{existing['id']}",
                    method="PUT",
                    headers=headers,
                    body=body,
                )
            else:
                http_json(
                    f"{args.base_url}/admin/realms/{args.realm}/components",
                    method="POST",
                    headers=headers,
                    body=body,
                )
    except urllib.error.HTTPError as exc:
        sys.stderr.write(exc.read().decode("utf-8"))
        return exc.code

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
