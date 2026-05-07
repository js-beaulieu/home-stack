#!/usr/bin/env python3
"""
Bootstrap a permanent Keycloak admin user in the master realm and remove the
temporary bootstrap admin created by KC_BOOTSTRAP_ADMIN_*.

Idempotent: if the permanent admin can already authenticate the script exits 0
without touching anything.

Pass --print-user-id to suppress informational output to stdout and instead
print only the permanent admin UUID.  Info messages are redirected to stderr so
they still appear in the terminal.  Useful for capturing the UUID in a shell
command substitution for `tofu import`.
"""
import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request


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


def http_json(url: str, *, method: str = "GET", headers=None, body=None):
    request = urllib.request.Request(url, method=method)
    for key, value in (headers or {}).items():
        request.add_header(key, value)
    if body is not None:
        request.add_header("Content-Type", "application/json")
        request.data = json.dumps(body).encode("utf-8")
    with urllib.request.urlopen(request) as response:
        payload = response.read().decode("utf-8")
        return response.status, json.loads(payload) if payload else None


def find_user_id(base_url: str, headers: dict, username: str) -> str | None:
    query = urllib.parse.urlencode({"username": username, "exact": "true"})
    _, users = http_json(f"{base_url}/admin/realms/master/users?{query}", headers=headers)
    return users[0]["id"] if users else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--bootstrap-username", required=True)
    parser.add_argument("--bootstrap-password", required=True)
    parser.add_argument("--permanent-username", required=True)
    parser.add_argument("--permanent-password", required=True)
    parser.add_argument(
        "--print-user-id",
        action="store_true",
        help="Print only the permanent admin UUID to stdout; redirect info to stderr.",
    )
    args = parser.parse_args()

    # When --print-user-id is set, informational messages go to stderr so that
    # command substitution ($(...)) captures only the UUID.
    info = sys.stderr if args.print_user_id else sys.stdout
    base_url = args.base_url

    # 1. Check whether the permanent admin already exists.
    try:
        get_token(base_url, args.permanent_username, args.permanent_password)
        info.write(f"Permanent admin '{args.permanent_username}' already exists — nothing to do.\n")
    except urllib.error.HTTPError as exc:
        if exc.code not in (400, 401):
            sys.stderr.write(f"Unexpected error checking permanent admin: {exc}\n")
            return exc.code

        info.write(
            f"Permanent admin '{args.permanent_username}' not found."
            " Bootstrapping via temporary admin...\n"
        )

        # 2. Authenticate with bootstrap credentials.
        try:
            bootstrap_token = get_token(
                base_url, args.bootstrap_username, args.bootstrap_password
            )
        except urllib.error.HTTPError as exc:
            sys.stderr.write(
                f"Failed to authenticate with bootstrap credentials: {exc}\n"
                + exc.read().decode("utf-8")
                + "\n"
            )
            return exc.code

        headers = {"Authorization": f"Bearer {bootstrap_token}"}

        try:
            # 3. Create the permanent admin user.
            http_json(
                f"{base_url}/admin/realms/master/users",
                method="POST",
                headers=headers,
                body={
                    "username": args.permanent_username,
                    "enabled": True,
                    "emailVerified": True,
                    "credentials": [
                        {
                            "type": "password",
                            "value": args.permanent_password,
                            "temporary": False,
                        }
                    ],
                },
            )

            # 4. Look up the new user's ID.
            permanent_user_id = find_user_id(base_url, headers, args.permanent_username)
            if not permanent_user_id:
                sys.stderr.write("Could not find permanent admin user after creation.\n")
                return 1

            # 5. Fetch the master realm composite 'admin' role.
            _, admin_role = http_json(
                f"{base_url}/admin/realms/master/roles/admin", headers=headers
            )

            # 6. Assign the role to the permanent admin.
            http_json(
                f"{base_url}/admin/realms/master/users/{permanent_user_id}/role-mappings/realm",
                method="POST",
                headers=headers,
                body=[{"id": admin_role["id"], "name": admin_role["name"]}],
            )
            info.write(
                f"Permanent admin '{args.permanent_username}' created"
                " and assigned the 'admin' role.\n"
            )

            # 7. Delete the bootstrap admin.
            bootstrap_user_id = find_user_id(base_url, headers, args.bootstrap_username)
            if bootstrap_user_id:
                http_json(
                    f"{base_url}/admin/realms/master/users/{bootstrap_user_id}",
                    method="DELETE",
                    headers=headers,
                )
                info.write(f"Bootstrap admin '{args.bootstrap_username}' deleted.\n")
            else:
                info.write(
                    f"Bootstrap admin '{args.bootstrap_username}' not found — already deleted.\n"
                )

        except urllib.error.HTTPError as exc:
            sys.stderr.write(exc.read().decode("utf-8") + "\n")
            return exc.code

    # When --print-user-id is set we need a token to look up the UUID.
    # Authenticate as the permanent admin (guaranteed to exist at this point).
    if args.print_user_id:
        try:
            perm_token = get_token(base_url, args.permanent_username, args.permanent_password)
            perm_headers = {"Authorization": f"Bearer {perm_token}"}
            user_id = find_user_id(base_url, perm_headers, args.permanent_username)
            if not user_id:
                sys.stderr.write("Could not look up permanent admin user ID.\n")
                return 1
            print(user_id)
        except urllib.error.HTTPError as exc:
            sys.stderr.write(f"Failed to look up permanent admin user ID: {exc}\n")
            return exc.code

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
