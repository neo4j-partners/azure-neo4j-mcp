#!/usr/bin/env python3
"""
Debug script to inspect JWT token claims from Azure Entra.
This helps troubleshoot Neo4j Aura SSO authentication issues.
"""

import base64
import json
import os
import sys

from dotenv import load_dotenv

load_dotenv()

# Import the auth function from test_sso
from test_sso import get_entra_token, load_config


def decode_jwt_payload(token: str) -> dict:
    """Decode JWT payload without verification (for debugging only)."""
    # JWT is header.payload.signature
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("Invalid JWT format")

    # Decode payload (add padding if needed)
    payload = parts[1]
    padding = 4 - len(payload) % 4
    if padding != 4:
        payload += "=" * padding

    decoded = base64.urlsafe_b64decode(payload)
    return json.loads(decoded)


def decode_jwt_header(token: str) -> dict:
    """Decode JWT header without verification (for debugging only)."""
    parts = token.split(".")
    header = parts[0]
    padding = 4 - len(header) % 4
    if padding != 4:
        header += "=" * padding

    decoded = base64.urlsafe_b64decode(header)
    return json.loads(decoded)


def main():
    # Load configuration
    config = load_config()

    tenant_id = os.environ.get("AZURE_TENANT_ID") or config.get("tenantId")
    client_id = os.environ.get("AZURE_CLIENT_ID") or config.get("clientId")
    client_secret = os.environ.get("AZURE_CLIENT_SECRET")
    username = os.environ.get("AZURE_USERNAME")
    password = os.environ.get("AZURE_PASSWORD")

    if not all([tenant_id, client_id, client_secret, username, password]):
        print("Error: Missing configuration. Check .env file.")
        print("\nRequired variables:")
        print("  AZURE_TENANT_ID")
        print("  AZURE_CLIENT_ID")
        print("  AZURE_CLIENT_SECRET")
        print("  AZURE_USERNAME")
        print("  AZURE_PASSWORD")
        sys.exit(1)

    print("=" * 60)
    print("JWT Token Debug - Azure Entra ID")
    print("=" * 60)
    print(f"\nTenant ID: {tenant_id}")
    print(f"Client ID: {client_id}")
    print(f"Username: {username}")

    print("\nGetting token from Azure Entra...")
    token = get_entra_token(tenant_id, client_id, client_secret, username, password)

    print("\n" + "=" * 60)
    print("JWT HEADER")
    print("=" * 60)
    header = decode_jwt_header(token)
    print(json.dumps(header, indent=2))

    print("\n" + "=" * 60)
    print("JWT PAYLOAD (Claims)")
    print("=" * 60)
    payload = decode_jwt_payload(token)
    print(json.dumps(payload, indent=2))

    # Analysis
    print("\n" + "=" * 60)
    print("ANALYSIS FOR NEO4J SSO")
    print("=" * 60)

    # Determine token type
    is_v2 = "ver" in payload and payload["ver"] == "2.0"
    print(f"\n1. Token Version: {'v2.0' if is_v2 else 'v1.0'}")

    print(f"\n2. Issuer (iss): {payload.get('iss', 'NOT FOUND')}")
    if is_v2:
        expected_issuer = f"https://login.microsoftonline.com/{tenant_id}/v2.0"
    else:
        expected_issuer = f"https://sts.windows.net/{tenant_id}/"

    if payload.get("iss") == expected_issuer:
        print(f"   [OK] Matches expected: {expected_issuer}")
    else:
        print(f"   [INFO] Expected: {expected_issuer}")
        print(f"   [INFO] Actual: {payload.get('iss')}")

    print(f"\n3. Audience (aud): {payload.get('aud', 'NOT FOUND')}")
    if payload.get("aud") == client_id:
        print("   [OK] Matches client_id")
    else:
        print(f"   [INFO] Should match client_id: {client_id}")

    print(f"\n4. Subject (sub): {payload.get('sub', 'NOT FOUND')}")

    print(f"\n5. Email: {payload.get('email', payload.get('preferred_username', 'NOT FOUND'))}")

    print(f"\n6. Name: {payload.get('name', 'NOT FOUND')}")

    # Groups claim (if configured in app registration)
    groups = payload.get("groups", [])
    print(f"\n7. Groups: {groups if groups else 'NOT FOUND'}")
    if not groups:
        print("   [INFO] Groups claim not present.")
        print("   To enable groups in token:")
        print("   1. Go to Azure Portal > App registrations > [your app]")
        print("   2. Token configuration > Add groups claim")
        print("   3. Select 'Security groups' or 'Groups assigned to the application'")

    # Roles claim (app roles)
    roles = payload.get("roles", [])
    print(f"\n8. App Roles: {roles if roles else 'NOT FOUND'}")
    if not roles:
        print("   [INFO] Roles claim not present.")
        print("   App roles are configured in the App manifest under 'appRoles'")

    print(f"\n9. Token expiration (exp): {payload.get('exp', 'NOT FOUND')}")

    print(f"\n10. Token issued at (iat): {payload.get('iat', 'NOT FOUND')}")

    # Recommendations
    print("\n" + "=" * 60)
    print("TROUBLESHOOTING RECOMMENDATIONS")
    print("=" * 60)

    issues = []

    if not groups and not roles:
        issues.append(
            "- Neither groups nor roles claims are present in the token.\n"
            "  Neo4j Aura SSO may require groups or roles for authorization.\n"
            "  Configure groups claim in Token configuration in Azure Portal."
        )

    if not payload.get("email") and not payload.get("preferred_username"):
        issues.append(
            "- No email or preferred_username claim found.\n"
            "  Ensure the app has the 'email' and 'profile' scopes."
        )

    if not issues:
        issues.append(
            "- Token claims look correct. Check Neo4j Aura SSO configuration:\n"
            "  1. Verify the Discovery URI is correct\n"
            "  2. Check that the instance has SSO enabled\n"
            "  3. Verify the Client ID matches in Neo4j Aura\n"
            "  4. Try logging in via the Neo4j Browser with SSO"
        )

    for issue in issues:
        print(issue)
        print()

    # Print useful configuration values for Neo4j Aura
    print("=" * 60)
    print("NEO4J AURA SSO CONFIGURATION VALUES")
    print("=" * 60)
    print(f"\nClient ID: {client_id}")
    print(f"Discovery URI: https://login.microsoftonline.com/{tenant_id}/v2.0/.well-known/openid-configuration")
    print("\nNote: Client Secret must be created manually in Azure Portal")


if __name__ == "__main__":
    main()
