#!/usr/bin/env python3
"""
Test Neo4j Aura SSO with Azure Entra ID.

This script authenticates with Azure Entra using MSAL (Microsoft Authentication Library),
then uses the resulting ID token to connect to Neo4j Aura with bearer authentication.

Usage:
    cp .env.sample .env
    # Edit .env with your configuration
    uv run python test_sso.py
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


def get_entra_token(
    tenant_id: str,
    client_id: str,
    client_secret: str,
    username: str,
    password: str,
) -> str:
    """
    Get an ID token from Azure Entra using ROPC (Resource Owner Password Credentials) flow.

    Note: ROPC is used here for testing purposes. In production, use interactive
    flows or managed identities.
    """
    authority = f"https://login.microsoftonline.com/{tenant_id}"

    # Create a confidential client application
    app = msal.ConfidentialClientApplication(
        client_id,
        authority=authority,
        client_credential=client_secret,
    )

    # Use ROPC flow to get tokens
    # The scopes request openid for ID token
    scopes = ["openid", "profile", "email", "User.Read"]

    result = app.acquire_token_by_username_password(
        username=username,
        password=password,
        scopes=scopes,
    )

    if "error" in result:
        print(f"Authentication failed: {result.get('error')}")
        print(f"Error description: {result.get('error_description')}")
        sys.exit(1)

    # Return the ID token for Neo4j bearer auth
    id_token = result.get("id_token")
    if not id_token:
        print("Error: No ID token in response")
        print(f"Response keys: {list(result.keys())}")
        sys.exit(1)

    print(f"Token type: ID Token")
    print(f"Expires in: {result.get('expires_in', 'N/A')} seconds")

    return id_token


class Neo4jSsoTest:
    """Test Neo4j connection using SSO bearer authentication."""

    def __init__(self, uri: str, token: str):
        self.driver = GraphDatabase.driver(uri, auth=bearer_auth(token))

    def close(self):
        self.driver.close()

    def verify_connection(self) -> dict:
        """Verify the connection and return database info."""
        with self.driver.session() as session:
            result = session.run(
                "CALL dbms.components() YIELD name, versions, edition "
                "RETURN name, versions[0] as version, edition"
            )
            record = result.single()
            return {
                "name": record["name"],
                "version": record["version"],
                "edition": record["edition"],
            }

    def run_test_query(self, message: str = "Hello from Azure Entra SSO!") -> str:
        """Run a simple test query."""
        with self.driver.session() as session:
            result = session.execute_read(
                lambda tx: tx.run(
                    "RETURN $message as greeting, datetime() as timestamp",
                    message=message
                ).single()
            )
            return f"{result['greeting']} (at {result['timestamp']})"

    def get_user_info(self) -> dict:
        """Get current user information from the database."""
        with self.driver.session() as session:
            result = session.run("CALL dbms.showCurrentUser()")
            record = result.single()
            return {
                "username": record["username"],
                "roles": list(record["roles"]),
            }


def main():
    # Load JSON config as fallback
    config = load_config()

    # Load from .env (primary) with JSON fallback
    neo4j_uri = os.environ.get("NEO4J_URI")
    if not neo4j_uri:
        print("Error: NEO4J_URI not set in .env")
        print("Run: cp .env.sample .env && edit .env")
        sys.exit(1)

    # Azure Entra configuration - .env takes priority over JSON
    tenant_id = os.environ.get("AZURE_TENANT_ID") or config.get("tenantId")
    client_id = os.environ.get("AZURE_CLIENT_ID") or config.get("clientId")
    client_secret = os.environ.get("AZURE_CLIENT_SECRET")

    if not tenant_id or not client_id:
        print("Error: Azure Entra configuration not found.")
        print("Run ./scripts/deploy.sh app-registration first,")
        print("or set AZURE_TENANT_ID and AZURE_CLIENT_ID in .env")
        sys.exit(1)

    if not client_secret:
        print("Error: AZURE_CLIENT_SECRET not set in .env")
        print("Create a client secret in Azure Portal:")
        print("  1. Go to App registrations > [your app] > Certificates & secrets")
        print("  2. Create a new client secret")
        print("  3. Copy the secret VALUE to .env as AZURE_CLIENT_SECRET")
        sys.exit(1)

    # User credentials
    username = os.environ.get("AZURE_USERNAME")
    password = os.environ.get("AZURE_PASSWORD")

    if not username or not password:
        print("Error: No user credentials found.")
        print("Set AZURE_USERNAME and AZURE_PASSWORD in .env")
        sys.exit(1)

    print(f"\n{'='*50}")
    print("Neo4j Aura SSO Test with Azure Entra ID")
    print(f"{'='*50}\n")

    print(f"Neo4j URI: {neo4j_uri}")
    print(f"Tenant ID: {tenant_id}")
    print(f"Client ID: {client_id}")
    print(f"Username: {username}\n")

    print("Step 1: Authenticating with Azure Entra...")
    token = get_entra_token(tenant_id, client_id, client_secret, username, password)
    print(f"Got ID token: {token[:50]}...\n")

    print("Step 2: Connecting to Neo4j Aura with bearer auth...")
    tester = Neo4jSsoTest(neo4j_uri, token)

    try:
        print("Step 3: Verifying connection...")
        db_info = tester.verify_connection()
        print(f"Connected to: {db_info['name']} {db_info['version']} ({db_info['edition']})\n")

        print("Step 4: Getting user information...")
        user_info = tester.get_user_info()
        print(f"Logged in as: {user_info['username']}")
        print(f"Roles: {', '.join(user_info['roles'])}\n")

        print("Step 5: Running test query...")
        greeting = tester.run_test_query()
        print(f"Result: {greeting}\n")

        print(f"{'='*50}")
        print("SUCCESS! SSO authentication working correctly.")
        print(f"{'='*50}")

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
    finally:
        tester.close()


if __name__ == "__main__":
    main()
