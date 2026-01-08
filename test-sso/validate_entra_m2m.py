#!/usr/bin/env python3
"""
Validate Azure Entra ID M2M (Client Credentials) Setup.

This script tests that your Azure Entra ID app registration is correctly
configured for M2M authentication by:

1. Acquiring an access token using Client Credentials flow
2. Validating the token cryptographically (signature, expiration, issuer, audience)
3. Displaying decoded claims for debugging

This isolates Entra configuration issues from Neo4j Aura SSO issues.

Usage:
    uv run python validate_entra_m2m.py

References:
    - MSAL Python: https://learn.microsoft.com/en-us/entra/msal/python/advanced/client-credentials
    - Token Validation: https://pypi.org/project/azure-ad-verify-token/
    - JWT Validation: https://www.voitanos.io/blog/validating-entra-id-generated-oauth-tokens/
"""

import base64
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import jwt
import msal
import requests
from dotenv import load_dotenv

load_dotenv()


class ValidationResult:
    """Track validation results."""

    def __init__(self):
        self.checks = []
        self.passed = 0
        self.failed = 0

    def check(self, name: str, passed: bool, details: str = ""):
        status = "PASS" if passed else "FAIL"
        self.checks.append((name, status, details))
        if passed:
            self.passed += 1
        else:
            self.failed += 1

    def print_summary(self):
        print(f"\n{'='*60}")
        print("VALIDATION SUMMARY")
        print(f"{'='*60}")
        for name, status, details in self.checks:
            symbol = "[OK]" if status == "PASS" else "[X]"
            print(f"  {symbol} {name}")
            if details and status == "FAIL":
                print(f"      {details}")
        print(f"\nTotal: {self.passed} passed, {self.failed} failed")
        return self.failed == 0


def load_config() -> dict:
    """Load configuration from APP_REGISTRATION.json if available."""
    config_file = Path(__file__).parent.parent / "APP_REGISTRATION.json"
    if config_file.exists():
        with open(config_file) as f:
            return json.load(f)
    return {}


def get_jwks_uri(tenant_id: str) -> str:
    """Get the JWKS URI from OpenID configuration."""
    openid_config_url = (
        f"https://login.microsoftonline.com/{tenant_id}/v2.0/"
        ".well-known/openid-configuration"
    )
    response = requests.get(openid_config_url, timeout=10)
    response.raise_for_status()
    return response.json()["jwks_uri"]


def get_public_keys(jwks_uri: str) -> dict:
    """Fetch public keys from JWKS endpoint."""
    response = requests.get(jwks_uri, timeout=10)
    response.raise_for_status()
    return response.json()


def decode_token_unverified(token: str) -> tuple[dict, dict]:
    """Decode token without verification (for inspection only)."""
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("Invalid JWT format - expected 3 parts")

    def decode_part(part: str) -> dict:
        padding = 4 - len(part) % 4
        if padding != 4:
            part += "=" * padding
        decoded = base64.urlsafe_b64decode(part)
        return json.loads(decoded)

    header = decode_part(parts[0])
    payload = decode_part(parts[1])
    return header, payload


def validate_token_cryptographically(
    token: str,
    tenant_id: str,
    client_id: str,
    result: ValidationResult,
) -> dict | None:
    """
    Validate token using Azure's JWKS public keys.

    This verifies:
    - Signature (using RSA public key from JWKS)
    - Expiration (exp claim)
    - Issuer (iss claim)
    - Audience (aud claim)
    """
    try:
        # Get JWKS URI and public keys
        jwks_uri = get_jwks_uri(tenant_id)
        result.check("Fetch OpenID configuration", True)

        jwks = get_public_keys(jwks_uri)
        result.check("Fetch JWKS public keys", True)

        # Decode header to get key ID
        header, _ = decode_token_unverified(token)
        kid = header.get("kid")
        if not kid:
            result.check("Token has key ID (kid)", False, "No 'kid' in token header")
            return None
        result.check("Token has key ID (kid)", True)

        # Find the matching key
        matching_key = None
        for key in jwks.get("keys", []):
            if key.get("kid") == kid:
                matching_key = key
                break

        if not matching_key:
            result.check(
                "Find matching public key",
                False,
                f"No key found for kid={kid}",
            )
            return None
        result.check("Find matching public key", True)

        # Build the public key
        from jwt.algorithms import RSAAlgorithm

        public_key = RSAAlgorithm.from_jwk(json.dumps(matching_key))
        result.check("Build RSA public key", True)

        # For M2M tokens, audience is the Application ID URI
        expected_audience = f"api://{client_id}"

        # Azure issues tokens with different issuers depending on version:
        # - v1.0: https://sts.windows.net/{tenant_id}/
        # - v2.0: https://login.microsoftonline.com/{tenant_id}/v2.0
        valid_issuers = [
            f"https://sts.windows.net/{tenant_id}/",  # v1.0
            f"https://login.microsoftonline.com/{tenant_id}/v2.0",  # v2.0
        ]

        # Validate the token
        try:
            payload = jwt.decode(
                token,
                public_key,
                algorithms=["RS256"],
                audience=expected_audience,
                issuer=valid_issuers,  # PyJWT accepts list of valid issuers
            )
            actual_issuer = payload.get("iss", "unknown")
            result.check("Verify signature (RS256)", True)
            result.check("Verify expiration (exp)", True)
            result.check(f"Verify issuer (iss)", True)
            result.check(f"Verify audience (aud={expected_audience})", True)
            return payload

        except jwt.ExpiredSignatureError:
            result.check("Verify expiration (exp)", False, "Token has expired")
        except jwt.InvalidAudienceError as e:
            result.check("Verify audience (aud)", False, str(e))
        except jwt.InvalidIssuerError as e:
            result.check("Verify issuer (iss)", False, str(e))
        except jwt.InvalidSignatureError:
            result.check("Verify signature (RS256)", False, "Signature mismatch")
        except jwt.DecodeError as e:
            result.check("Decode token", False, str(e))

        return None

    except requests.RequestException as e:
        result.check("Fetch JWKS", False, f"Network error: {e}")
        return None
    except Exception as e:
        result.check("Token validation", False, f"Unexpected error: {e}")
        return None


def acquire_m2m_token(
    tenant_id: str,
    client_id: str,
    client_secret: str,
    result: ValidationResult,
) -> str | None:
    """Acquire access token using Client Credentials flow."""
    authority = f"https://login.microsoftonline.com/{tenant_id}"

    try:
        app = msal.ConfidentialClientApplication(
            client_id,
            authority=authority,
            client_credential=client_secret,
        )
        result.check("Create MSAL ConfidentialClientApplication", True)
    except Exception as e:
        result.check(
            "Create MSAL ConfidentialClientApplication",
            False,
            str(e),
        )
        return None

    # M2M scope: api://{client_id}/.default
    # This requires Application ID URI to be configured
    scopes = [f"api://{client_id}/.default"]

    try:
        token_result = app.acquire_token_for_client(scopes=scopes)
    except Exception as e:
        result.check("Call acquire_token_for_client", False, str(e))
        return None

    if "error" in token_result:
        error = token_result.get("error", "")
        error_desc = token_result.get("error_description", "")

        # Check for specific errors
        if "AADSTS650053" in error_desc or "invalid_resource" in error.lower():
            result.check(
                "Acquire M2M token",
                False,
                "Application ID URI not configured. "
                "Go to Azure Portal > App registrations > Expose an API > "
                "Add Application ID URI (api://{client_id})",
            )
        elif "AADSTS7000215" in error_desc:
            result.check(
                "Acquire M2M token",
                False,
                "Invalid client secret. Create a new secret in Azure Portal.",
            )
        elif "AADSTS700016" in error_desc:
            result.check(
                "Acquire M2M token",
                False,
                f"Application not found in tenant. Check client_id: {client_id}",
            )
        else:
            result.check(
                "Acquire M2M token",
                False,
                f"{error}: {error_desc[:100]}",
            )
        return None

    access_token = token_result.get("access_token")
    if not access_token:
        result.check("Acquire M2M token", False, "No access_token in response")
        return None

    result.check("Acquire M2M token", True)
    return access_token


def print_token_claims(token: str):
    """Print decoded token claims for debugging."""
    try:
        header, payload = decode_token_unverified(token)

        print(f"\n{'='*60}")
        print("TOKEN HEADER")
        print(f"{'='*60}")
        print(f"  alg: {header.get('alg', 'N/A')}")
        print(f"  typ: {header.get('typ', 'N/A')}")
        print(f"  kid: {header.get('kid', 'N/A')}")

        print(f"\n{'='*60}")
        print("TOKEN CLAIMS")
        print(f"{'='*60}")

        # Standard claims
        print(f"  iss (issuer):     {payload.get('iss', 'N/A')}")
        print(f"  aud (audience):   {payload.get('aud', 'N/A')}")
        print(f"  sub (subject):    {payload.get('sub', 'N/A')}")

        # Time claims
        iat = payload.get("iat")
        exp = payload.get("exp")
        nbf = payload.get("nbf")

        if iat:
            iat_dt = datetime.fromtimestamp(iat, tz=timezone.utc)
            print(f"  iat (issued at):  {iat_dt.isoformat()}")
        if exp:
            exp_dt = datetime.fromtimestamp(exp, tz=timezone.utc)
            now = datetime.now(tz=timezone.utc)
            remaining = exp_dt - now
            print(f"  exp (expires):    {exp_dt.isoformat()} ({remaining} remaining)")
        if nbf:
            nbf_dt = datetime.fromtimestamp(nbf, tz=timezone.utc)
            print(f"  nbf (not before): {nbf_dt.isoformat()}")

        # Azure-specific claims
        print(f"\n  azp (client):     {payload.get('azp', 'N/A')}")
        print(f"  azpacr:           {payload.get('azpacr', 'N/A')}")
        print(f"  oid (object ID):  {payload.get('oid', 'N/A')}")
        print(f"  tid (tenant ID):  {payload.get('tid', 'N/A')}")

        # Authorization claims (important for Neo4j)
        roles = payload.get("roles", [])
        scp = payload.get("scp", "")
        print(f"\n  roles:            {roles if roles else 'None'}")
        print(f"  scp (scopes):     {scp if scp else 'None'}")

        # Version
        print(f"\n  ver (version):    {payload.get('ver', 'N/A')}")

    except Exception as e:
        print(f"  Error decoding token: {e}")


def main():
    config = load_config()

    tenant_id = os.environ.get("AZURE_TENANT_ID") or config.get("tenantId")
    client_id = os.environ.get("AZURE_CLIENT_ID") or config.get("clientId")
    client_secret = os.environ.get("AZURE_CLIENT_SECRET")

    print(f"\n{'='*60}")
    print("Azure Entra ID M2M (Client Credentials) Validation")
    print(f"{'='*60}")
    print("\nThis script validates your Entra M2M setup independently")
    print("of Neo4j to isolate configuration issues.\n")

    # Check required config
    missing = []
    if not tenant_id:
        missing.append("AZURE_TENANT_ID")
    if not client_id:
        missing.append("AZURE_CLIENT_ID")
    if not client_secret or client_secret == "<PASTE_SECRET_VALUE_HERE>":
        missing.append("AZURE_CLIENT_SECRET")

    if missing:
        print("ERROR: Missing required configuration:")
        for m in missing:
            print(f"  - {m}")
        print("\nRun ./scripts/deploy.sh app-registration first,")
        print("then create a client secret in Azure Portal.")
        sys.exit(1)

    print(f"Tenant ID:  {tenant_id}")
    print(f"Client ID:  {client_id}")
    print(f"Scope:      api://{client_id}/.default")

    result = ValidationResult()

    # Step 1: Acquire token
    print(f"\n{'='*60}")
    print("STEP 1: Token Acquisition")
    print(f"{'='*60}")

    access_token = acquire_m2m_token(tenant_id, client_id, client_secret, result)

    if not access_token:
        result.print_summary()
        print("\nToken acquisition failed. Fix the issues above before")
        print("testing Neo4j Aura SSO.")
        sys.exit(1)

    print(f"\nToken acquired: {access_token[:50]}...")
    print(f"Token length: {len(access_token)} characters")

    # Step 2: Display claims
    print_token_claims(access_token)

    # Step 3: Cryptographic validation
    print(f"\n{'='*60}")
    print("STEP 2: Cryptographic Validation")
    print(f"{'='*60}")

    validated_payload = validate_token_cryptographically(
        access_token,
        tenant_id,
        client_id,
        result,
    )

    # Summary
    all_passed = result.print_summary()

    if all_passed:
        print(f"\n{'='*60}")
        print("SUCCESS - Entra M2M Setup is Correct")
        print(f"{'='*60}")
        print("\nYour Azure Entra ID M2M configuration is valid:")
        print("  - Token acquired successfully")
        print("  - Signature verified with Azure's public key")
        print("  - Issuer and audience claims are correct")
        print("  - Token has not expired")
        print("\nIf Neo4j Aura still rejects this token, the issue is")
        print("with Aura's SSO support for M2M tokens, not your Entra setup.")
        print("\nSee SUPPORT.md for the email to Neo4j support.")
    else:
        print(f"\n{'='*60}")
        print("VALIDATION FAILED")
        print(f"{'='*60}")
        print("\nFix the issues above before testing Neo4j Aura SSO.")
        sys.exit(1)


if __name__ == "__main__":
    main()
