#!/bin/bash
#
# Create Azure AD Test User for SSO Testing
#
# Creates an Azure AD user for testing SSO authentication with Neo4j Aura.
# Generates a random password and updates test-sso/.env with the credentials.
#
# Usage:
#   ./scripts/create-user.sh                    # Uses AZURE_USERNAME from test-sso/.env
#   ./scripts/create-user.sh testuser           # Creates testuser@{tenant}.onmicrosoft.com
#   ./scripts/create-user.sh user@domain.com    # Creates user with specific UPN
#
# Note: The created user will NOT have MFA enabled, suitable for ROPC flow testing.
#       For production, users authenticate interactively via browser.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_ENV="$PROJECT_ROOT/.env"
ROOT_ENV_SAMPLE="$PROJECT_ROOT/.env.sample"

# Colors for output
log_info() { echo -e "\033[0;34mINFO\033[0m  $1"; }
log_success() { echo -e "\033[0;32mOK\033[0m    $1"; }
log_warn() { echo -e "\033[0;33mWARN\033[0m  $1"; }
log_error() { echo -e "\033[0;31mERROR\033[0m $1" >&2; }

# Check Azure CLI
if ! command -v az &> /dev/null; then
    log_error "Azure CLI (az) is not installed"
    log_error "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    log_error "Not logged in to Azure CLI. Run: az login"
    exit 1
fi

# Get tenant domain
get_tenant_domain() {
    az rest --method GET --url "https://graph.microsoft.com/v1.0/organization" \
        --query "value[0].verifiedDomains[?isDefault].name | [0]" \
        --output tsv 2>/dev/null || echo ""
}

# Generate a random password (20 chars, meets Azure AD complexity requirements)
generate_password() {
    # Ensure password has: uppercase, lowercase, number, special char
    local upper=$(LC_ALL=C tr -dc 'A-Z' < /dev/urandom | head -c 4)
    local lower=$(LC_ALL=C tr -dc 'a-z' < /dev/urandom | head -c 8)
    local number=$(LC_ALL=C tr -dc '0-9' < /dev/urandom | head -c 4)
    local special=$(LC_ALL=C tr -dc '@#$%&*!' < /dev/urandom | head -c 2)
    # Combine and shuffle
    echo "${upper}${lower}${number}${special}" | fold -w1 | shuf | tr -d '\n'
}

# Load username from root .env if it exists
load_existing_username() {
    if [[ -f "$ROOT_ENV" ]]; then
        grep -E "^AZURE_TEST_USERNAME=" "$ROOT_ENV" 2>/dev/null | cut -d'=' -f2- || echo ""
    fi
}

# Update or add a value in .env file
update_env_value() {
    local file="$1"
    local key="$2"
    local value="$3"

    if grep -q "^${key}=" "$file" 2>/dev/null; then
        # Update existing value (macOS and Linux compatible)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^${key}=.*|${key}=${value}|" "$file"
        else
            sed -i "s|^${key}=.*|${key}=${value}|" "$file"
        fi
    else
        # Add new value
        echo "${key}=${value}" >> "$file"
    fi
}

# Main
main() {
    local username_arg="${1:-}"
    local display_name="${2:-}"

    log_info "Azure AD Test User Creation"
    echo ""

    # Get tenant domain
    local tenant_domain
    tenant_domain=$(get_tenant_domain)

    if [[ -z "$tenant_domain" ]]; then
        log_error "Could not determine tenant domain. Ensure you're logged in with sufficient permissions."
        exit 1
    fi

    log_info "Tenant domain: $tenant_domain"

    # Determine username
    local username=""

    if [[ -n "$username_arg" ]]; then
        # Username provided as argument
        if [[ "$username_arg" == *"@"* ]]; then
            username="$username_arg"
        else
            username="${username_arg}@${tenant_domain}"
        fi
    else
        # Try to load from .env
        username=$(load_existing_username)

        if [[ -z "$username" || "$username" == "user@yourtenant.onmicrosoft.com" ]]; then
            # Generate a default username
            username="neo4j-test-user@${tenant_domain}"
        fi
    fi

    # Determine display name
    if [[ -z "$display_name" ]]; then
        # Extract from username (part before @)
        local local_part="${username%%@*}"
        display_name=$(echo "$local_part" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
    fi

    log_info "Username (UPN): $username"
    log_info "Display name: $display_name"
    echo ""

    # Check if user already exists
    local existing_user
    existing_user=$(az ad user show --id "$username" --query "id" --output tsv 2>/dev/null || echo "")

    if [[ -n "$existing_user" ]]; then
        log_warn "User already exists: $username"
        echo ""
        read -p "Reset password and update .env? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled"
            exit 0
        fi

        # Generate new password and reset
        local password
        password=$(generate_password)

        log_info "Resetting password..."
        az ad user update \
            --id "$username" \
            --password "$password" \
            --force-change-password-next-sign-in false \
            --output none

        log_success "Password reset"
    else
        # Create new user
        local password
        password=$(generate_password)

        log_info "Creating user..."
        az ad user create \
            --display-name "$display_name" \
            --user-principal-name "$username" \
            --password "$password" \
            --force-change-password-next-sign-in false \
            --output none

        log_success "User created"
    fi

    # Ensure root .env exists
    if [[ ! -f "$ROOT_ENV" ]]; then
        if [[ -f "$ROOT_ENV_SAMPLE" ]]; then
            cp "$ROOT_ENV_SAMPLE" "$ROOT_ENV"
            log_info "Created .env from sample"
        else
            touch "$ROOT_ENV"
        fi
    fi

    # Update root .env with credentials
    update_env_value "$ROOT_ENV" "AZURE_TEST_USERNAME" "$username"
    update_env_value "$ROOT_ENV" "AZURE_TEST_PASSWORD" "$password"

    log_success "Updated .env with credentials"

    echo ""
    echo "=============================================="
    echo "Test User Created"
    echo "=============================================="
    echo ""
    echo "  Username: $username"
    echo "  Password: $password"
    echo ""
    echo "Credentials saved to: .env"
    echo ""
    echo "Next steps:"
    echo "  1. Ensure APP_REGISTRATION.json has the client secret"
    echo "  2. Run: cd test-sso && ./setup-env.sh"
    echo "  3. Run: uv run python test_sso.py"
    echo ""

    # Warn about MFA
    log_warn "This user has no MFA. For testing ROPC flow only."
    log_warn "Production SSO uses interactive browser authentication."
}

main "$@"
