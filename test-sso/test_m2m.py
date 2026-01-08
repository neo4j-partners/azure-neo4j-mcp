#!/usr/bin/env python3
"""
Test Neo4j Aura SSO with Azure Entra ID using M2M (Client Credentials) flow.

This script authenticates as an APPLICATION (not a user) using client credentials,
then attempts to connect to Neo4j Aura with the resulting access token.

No user account or password is required - only the app registration's client secret.

Usage:
    # After setup-env.sh populates .env with client credentials:
    uv run python test_m2m.py
"""

import json
import os
import sys
from pathlib import Path

import msal
from dotenv import load_dotenv
from neo4j import GraphDatabase, bearer_auth

load_dotenv()


def load_config() -> dict:
    """Load configuration from APP_REGISTRATION.json if available."""
    config_file = Path(__file__).parent.parent / "APP_REGISTRATION.json"
    if config_file.exists():
        with open(config_file) as f:
            return json.load(f)
    return {}


def get_m2m_token(
    tenant_id: str,
    client_id: str,
    client_secret: str,
) -> dict:
    """
    Get an access token using Client Credentials (M2M) flow.

    This flow authenticates the APPLICATION itself, not a user.
    No user interaction or credentials required.
    """
    authority = f"https://login.microsoftonline.com/{tenant_id}"

    app = msal.ConfidentialClientApplication(
        client_id,
        authority=authority,
        client_credential=client_secret,
    )

    # For M2M, we request the .default scope using the Application ID URI
    # This matches the pattern from: https://github.com/neo4j-field/entraid-programmatic-sso
    # The api:// prefix references the Application ID URI configured in "Expose an API"
    scopes = [f"api://{client_id}/.default"]

    result = app.acquire_token_for_client(scopes=scopes)

    if "error" in result:
        error = result.get('error')
        error_desc = result.get('error_description', '')

        print(f"Authentication failed: {error}")
        print(f"Error description: {error_desc}")

        # Provide specific guidance for common errors
        if "AADSTS650053" in error_desc or "invalid_resource" in error.lower():
            print("\n" + "=" * 60)
            print("APPLICATION ID URI NOT CONFIGURED")
            print("=" * 60)
            print("\nThe scope 'api://{client_id}/.default' requires an Application ID URI.")
            print("\nTo fix this in Azure Portal:")
            print("  1. Go to App registrations > [your app] > Expose an API")
            print("  2. Click 'Add' next to Application ID URI")
            print("  3. Accept the default: api://{client_id}")
            print("  4. Save and retry this test")

        return result

    return result


def decode_jwt_payload(token: str) -> dict:
    """Decode JWT payload without verification (for debugging only)."""
    import base64
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("Invalid JWT format")

    payload = parts[1]
    padding = 4 - len(payload) % 4
    if padding != 4:
        payload += "=" * padding

    decoded = base64.urlsafe_b64decode(payload)
    return json.loads(decoded)


def main():
    config = load_config()

    neo4j_uri = os.environ.get("NEO4J_URI")
    if not neo4j_uri:
        print("Error: NEO4J_URI not set in .env")
        sys.exit(1)

    tenant_id = os.environ.get("AZURE_TENANT_ID") or config.get("tenantId")
    client_id = os.environ.get("AZURE_CLIENT_ID") or config.get("clientId")
    client_secret = os.environ.get("AZURE_CLIENT_SECRET")

    if not tenant_id or not client_id:
        print("Error: Azure Entra configuration not found.")
        print("Run ./scripts/deploy.sh app-registration first")
        sys.exit(1)

    if not client_secret or client_secret == "<PASTE_SECRET_VALUE_HERE>":
        print("Error: AZURE_CLIENT_SECRET not set")
        print("Create a client secret in Azure Portal and update APP_REGISTRATION.json")
        sys.exit(1)

    print(f"\n{'='*60}")
    print("Neo4j Aura SSO Test - M2M (Client Credentials) Flow")
    print(f"{'='*60}\n")

    print(f"Neo4j URI:  {neo4j_uri}")
    print(f"Tenant ID:  {tenant_id}")
    print(f"Client ID:  {client_id}")
    print(f"\nThis test authenticates as an APPLICATION, not a user.\n")

    print("Step 1: Acquiring token with Client Credentials flow...")
    result = get_m2m_token(tenant_id, client_id, client_secret)

    if "error" in result:
        print(f"\nM2M authentication failed - see error details above.")
        sys.exit(1)

    access_token = result.get("access_token")
    if not access_token:
        print("Error: No access token in response")
        print(f"Response: {json.dumps(result, indent=2)}")
        sys.exit(1)

    print(f"Token type: Access Token (M2M)")
    print(f"Expires in: {result.get('expires_in', 'N/A')} seconds")
    print(f"Got token: {access_token[:50]}...\n")

    # Decode and show token claims
    print("Step 2: Inspecting token claims...")
    try:
        claims = decode_jwt_payload(access_token)
        print(f"  iss: {claims.get('iss', 'N/A')}")
        print(f"  aud: {claims.get('aud', 'N/A')}")
        print(f"  sub: {claims.get('sub', 'N/A')}")
        print(f"  roles: {claims.get('roles', 'N/A')}")
        print(f"  scp: {claims.get('scp', 'N/A')}")
        print()
    except Exception as e:
        print(f"  Could not decode token: {e}\n")

    print("Step 3: Connecting to Neo4j Aura with bearer auth...")
    try:
        driver = GraphDatabase.driver(neo4j_uri, auth=bearer_auth(access_token))

        with driver.session() as session:
            result = session.run(
                "CALL dbms.components() YIELD name, versions, edition "
                "RETURN name, versions[0] as version, edition"
            )
            record = result.single()
            print(f"Connected to: {record['name']} {record['version']} ({record['edition']})\n")

            print("Step 4: Getting user information...")
            result = session.run("CALL dbms.showCurrentUser()")
            record = result.single()
            print(f"Logged in as: {record['username']}")
            print(f"Roles: {', '.join(record['roles'])}\n")

            print("Step 5: Running test query...")
            result = session.run(
                "RETURN 'Hello from M2M authentication!' as greeting, datetime() as timestamp"
            )
            record = result.single()
            print(f"Result: {record['greeting']} (at {record['timestamp']})\n")

        driver.close()

        print(f"{'='*60}")
        print("SUCCESS! M2M authentication working correctly.")
        print(f"{'='*60}")
        print("\nThis means:")
        print("  - No user account needed for authentication")
        print("  - The MCP server can use this same flow")
        print("  - AI agents authenticate as applications, not users")

    except Exception as e:
        print(f"\nFailed to connect to Neo4j: {e}")
        print(f"\n{'='*60}")
        print("M2M CONNECTION FAILED")
        print(f"{'='*60}")
        print("\nPossible causes:")
        print("  1. Neo4j Aura SSO may not support M2M/Client Credentials for driver connections")
        print("  2. The app registration needs additional configuration:")
        print("     - Expose an API with Application ID URI")
        print("     - Define app roles that map to Neo4j roles")
        print("  3. Neo4j Aura SSO configuration may need role mapping for the app")
        print("\nThe access token was issued successfully, but Neo4j rejected it.")
        print("This suggests Neo4j Aura may only support user-based SSO, not M2M.")
        sys.exit(1)


if __name__ == "__main__":
    main()
