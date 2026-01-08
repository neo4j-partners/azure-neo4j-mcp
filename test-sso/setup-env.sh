#!/bin/bash
#
# Setup test-sso/.env from APP_REGISTRATION.json and root .env
#
# This script reads:
#   - Azure Entra configuration from APP_REGISTRATION.json
#   - Neo4j URI and test user credentials from root .env
# And creates test-sso/.env for the SSO test scripts.
#
# Usage:
#   ./setup-env.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ROOT_ENV="$PROJECT_ROOT/.env"
APP_REG_FILE="$PROJECT_ROOT/APP_REGISTRATION.json"

# Colors for output
log_info() { echo -e "\033[0;34mINFO\033[0m  $1"; }
log_success() { echo -e "\033[0;32mOK\033[0m    $1"; }
log_warn() { echo -e "\033[0;33mWARN\033[0m  $1"; }
log_error() { echo -e "\033[0;31mERROR\033[0m $1" >&2; }

# Check for jq
if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed"
    log_error "Install with: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

# Check for APP_REGISTRATION.json
if [[ ! -f "$APP_REG_FILE" ]]; then
    log_error "APP_REGISTRATION.json not found at: $APP_REG_FILE"
    log_error "Run './scripts/deploy.sh app-registration' first"
    exit 1
fi

log_info "Reading from APP_REGISTRATION.json..."

# Extract values from APP_REGISTRATION.json
TENANT_ID=$(jq -r '.azure_app_registration.tenant_id // empty' "$APP_REG_FILE")
CLIENT_ID=$(jq -r '.neo4j_aura_sso.client_id // empty' "$APP_REG_FILE")
CLIENT_SECRET=$(jq -r '.neo4j_aura_sso.client_secret // empty' "$APP_REG_FILE")

if [[ -z "$TENANT_ID" || -z "$CLIENT_ID" ]]; then
    log_error "Could not extract tenant_id or client_id from APP_REGISTRATION.json"
    exit 1
fi

# Check if client secret is still placeholder
if [[ "$CLIENT_SECRET" == "<PASTE_SECRET_VALUE_HERE>" ]]; then
    log_warn "Client secret is still a placeholder in APP_REGISTRATION.json"
    log_warn "Create a secret in Azure Portal and update APP_REGISTRATION.json first"
    CLIENT_SECRET=""
fi

# Load values from root .env
ROOT_NEO4J_URI=""
ROOT_USERNAME=""
ROOT_PASSWORD=""

if [[ -f "$ROOT_ENV" ]]; then
    log_info "Reading from root .env..."
    ROOT_NEO4J_URI=$(grep -E "^NEO4J_URI=" "$ROOT_ENV" 2>/dev/null | cut -d'=' -f2- || echo "")
    ROOT_USERNAME=$(grep -E "^AZURE_TEST_USERNAME=" "$ROOT_ENV" 2>/dev/null | cut -d'=' -f2- || echo "")
    ROOT_PASSWORD=$(grep -E "^AZURE_TEST_PASSWORD=" "$ROOT_ENV" 2>/dev/null | cut -d'=' -f2- || echo "")
fi

# Load existing test-sso/.env values as fallback
EXISTING_NEO4J_URI=""
EXISTING_USERNAME=""
EXISTING_PASSWORD=""
EXISTING_CLIENT_SECRET=""

if [[ -f "$ENV_FILE" ]]; then
    log_info "Found existing test-sso/.env, checking for values..."
    EXISTING_NEO4J_URI=$(grep -E "^NEO4J_URI=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo "")
    EXISTING_USERNAME=$(grep -E "^AZURE_USERNAME=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo "")
    EXISTING_PASSWORD=$(grep -E "^AZURE_PASSWORD=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo "")
    EXISTING_CLIENT_SECRET=$(grep -E "^AZURE_CLIENT_SECRET=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo "")
fi

# Priority: root .env > existing test-sso/.env > placeholder
# NEO4J_URI
if [[ -n "$ROOT_NEO4J_URI" ]]; then
    NEO4J_URI="$ROOT_NEO4J_URI"
elif [[ -n "$EXISTING_NEO4J_URI" && "$EXISTING_NEO4J_URI" != "neo4j+s://xxxxxxxx.databases.neo4j.io" ]]; then
    NEO4J_URI="$EXISTING_NEO4J_URI"
else
    NEO4J_URI="neo4j+s://xxxxxxxx.databases.neo4j.io"
fi

# Username
if [[ -n "$ROOT_USERNAME" ]]; then
    USERNAME="$ROOT_USERNAME"
elif [[ -n "$EXISTING_USERNAME" && "$EXISTING_USERNAME" != "user@yourtenant.onmicrosoft.com" && "$EXISTING_USERNAME" != "neo4j-test-user@yourtenant.onmicrosoft.com" ]]; then
    USERNAME="$EXISTING_USERNAME"
else
    USERNAME="neo4j-test-user@yourtenant.onmicrosoft.com"
fi

# Password
if [[ -n "$ROOT_PASSWORD" ]]; then
    PASSWORD="$ROOT_PASSWORD"
elif [[ -n "$EXISTING_PASSWORD" && "$EXISTING_PASSWORD" != "your-password" ]]; then
    PASSWORD="$EXISTING_PASSWORD"
else
    PASSWORD="your-password"
fi

# Client secret: prefer APP_REGISTRATION.json, fall back to existing
if [[ -n "$CLIENT_SECRET" ]]; then
    FINAL_CLIENT_SECRET="$CLIENT_SECRET"
elif [[ -n "$EXISTING_CLIENT_SECRET" && "$EXISTING_CLIENT_SECRET" != "your-client-secret-value" ]]; then
    FINAL_CLIENT_SECRET="$EXISTING_CLIENT_SECRET"
    log_info "Using existing client secret from test-sso/.env"
else
    FINAL_CLIENT_SECRET="your-client-secret-value"
fi

# Write the test-sso/.env file
cat > "$ENV_FILE" << EOF
# Azure Entra SSO Test Configuration
# Generated from APP_REGISTRATION.json and root .env on $(date)

# Neo4j Aura connection
NEO4J_URI=$NEO4J_URI

# Azure Entra configuration (from APP_REGISTRATION.json)
AZURE_TENANT_ID=$TENANT_ID
AZURE_CLIENT_ID=$CLIENT_ID

# Client secret - create manually in Azure Portal if not set:
# 1. Go to App registrations > [your app] > Certificates & secrets
# 2. Click "New client secret"
# 3. Copy the secret VALUE (not the ID)
AZURE_CLIENT_SECRET=$FINAL_CLIENT_SECRET

# Test user credentials (from root .env AZURE_TEST_USERNAME/PASSWORD)
# Create with: ./scripts/create-user.sh
AZURE_USERNAME=$USERNAME
AZURE_PASSWORD=$PASSWORD
EOF

log_success "Created test-sso/.env"
echo ""
echo "Configuration:"
echo "  AZURE_TENANT_ID:  $TENANT_ID"
echo "  AZURE_CLIENT_ID:  $CLIENT_ID"
echo "  NEO4J_URI:        $NEO4J_URI"
echo "  AZURE_USERNAME:   $USERNAME"
echo ""

# Check what still needs to be configured
missing=()

if [[ "$NEO4J_URI" == "neo4j+s://xxxxxxxx.databases.neo4j.io" ]]; then
    missing+=("NEO4J_URI (set in root .env)")
fi

if [[ "$FINAL_CLIENT_SECRET" == "your-client-secret-value" ]]; then
    missing+=("AZURE_CLIENT_SECRET (update APP_REGISTRATION.json)")
fi

if [[ "$USERNAME" == "neo4j-test-user@yourtenant.onmicrosoft.com" ]]; then
    missing+=("AZURE_TEST_USERNAME (run ./scripts/create-user.sh)")
fi

if [[ "$PASSWORD" == "your-password" ]]; then
    missing+=("AZURE_TEST_PASSWORD (run ./scripts/create-user.sh)")
fi

if [[ ${#missing[@]} -gt 0 ]]; then
    log_warn "Still need to configure:"
    for var in "${missing[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "Then re-run: ./setup-env.sh"
else
    log_success "All values configured! Run:"
    echo "  uv run python test_sso.py"
fi
