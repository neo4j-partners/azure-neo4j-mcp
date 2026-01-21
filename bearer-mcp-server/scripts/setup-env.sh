#!/bin/bash
#
# Bearer Token MCP Server - Environment Setup Script
#
# Reads configuration from an azure-ee-template deployment JSON file and
# populates the .env file with the necessary settings.
#
# Usage:
#   # Copy deployment file from azure-ee-template
#   cp /path/to/azure-ee-template/.deployments/standalone-v2025.json ./neo4j-deployment.json
#
#   # Run setup
#   ./scripts/setup-env.sh                    # Interactive mode
#   ./scripts/setup-env.sh --non-interactive  # Use defaults, no prompts
#   ./scripts/setup-env.sh --help             # Show help
#
# The script preserves existing credentials (AZURE_CLIENT_SECRET) if they exist.
#

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_SAMPLE="$PROJECT_ROOT/.env.sample"

# Default deployment JSON file names to look for
DEPLOYMENT_JSON_NAMES=(
    "neo4j-deployment.json"
    "standalone-v2025.json"
    "cluster-v2025.json"
    "deployment.json"
)

# Defaults
DEFAULT_RESOURCE_GROUP="neo4j-mcp-bearer-rg"
DEFAULT_LOCATION="eastus"
DEFAULT_NEO4J_DATABASE="neo4j"

# Path to azure-ee-template (for auto-discovery)
AZURE_EE_TEMPLATE_PATH="${AZURE_EE_TEMPLATE_PATH:-/Users/ryanknight/projects/neo4j-partners/azure-ee-template}"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo "INFO  $1"
}

log_success() {
    echo "OK    $1"
}

log_warn() {
    echo "WARN  $1"
}

log_error() {
    echo "ERROR $1" >&2
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get value from existing .env file
get_env_value() {
    local key="$1"
    if [[ -f "$ENV_FILE" ]]; then
        grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/^["'"'"']//;s/["'"'"']$//'
    fi
}

# Check if a value exists and is non-empty in .env
env_value_exists() {
    local key="$1"
    local value
    value=$(get_env_value "$key")
    [[ -n "$value" ]]
}

# Try to find Neo4j MCP repo in common locations
find_neo4j_mcp_repo() {
    local search_paths=(
        "$HOME/projects/mcp"
        "$HOME/mcp"
        "$HOME/neo4j-mcp"
        "../../../mcp"
        "../../mcp"
        "../mcp"
    )
    for path in "${search_paths[@]}"; do
        if [[ -d "$path" && -f "$path/Dockerfile" ]]; then
            echo "$(cd "$path" && pwd)"
            return
        fi
    done
    echo ""
}

# Find deployment JSON file
find_deployment_json() {
    # First, check project root for any of the default names
    for name in "${DEPLOYMENT_JSON_NAMES[@]}"; do
        if [[ -f "$PROJECT_ROOT/$name" ]]; then
            echo "$PROJECT_ROOT/$name"
            return
        fi
    done

    # Check azure-ee-template .deployments directory
    if [[ -d "$AZURE_EE_TEMPLATE_PATH/.deployments" ]]; then
        # Find the most recent deployment JSON
        local latest
        latest=$(ls -t "$AZURE_EE_TEMPLATE_PATH/.deployments"/*.json 2>/dev/null | head -1)
        if [[ -n "$latest" && -f "$latest" ]]; then
            echo "$latest"
            return
        fi
    fi

    echo ""
}

# =============================================================================
# Azure CLI Functions
# =============================================================================

check_azure_cli() {
    if ! command_exists az; then
        log_error "Azure CLI (az) is not installed."
        log_error "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure CLI."
        log_error "Run: az login"
        exit 1
    fi

    log_success "Azure CLI is installed and authenticated"
}

get_subscription_id() {
    az account show --query id -o tsv
}

get_subscription_name() {
    az account show --query name -o tsv
}

# =============================================================================
# Environment File Functions
# =============================================================================

init_env_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        if [[ -f "$ENV_SAMPLE" ]]; then
            log_info "Creating .env from .env.sample..."
            cp "$ENV_SAMPLE" "$ENV_FILE"
        else
            log_info "Creating new .env file..."
            touch "$ENV_FILE"
        fi
    else
        log_info "Using existing .env file"
    fi
}

set_env_value() {
    local key="$1"
    local value="$2"
    local comment="$3"

    # Escape special characters in value for sed
    local escaped_value
    escaped_value=$(echo "$value" | sed 's/[&/\]/\\&/g')

    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        # Update existing value
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s|^${key}=.*|${key}=${escaped_value}|" "$ENV_FILE"
        else
            sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$ENV_FILE"
        fi
    else
        # Add new value with optional comment
        if [[ -n "$comment" ]]; then
            echo "" >> "$ENV_FILE"
            echo "# $comment" >> "$ENV_FILE"
        fi
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

# =============================================================================
# Deployment JSON Parsing
# =============================================================================

parse_deployment_json() {
    local json_file="$1"

    if [[ ! -f "$json_file" ]]; then
        log_error "Deployment JSON file not found: $json_file"
        return 1
    fi

    if ! command_exists jq; then
        log_error "jq is required to parse deployment JSON"
        log_error "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
        exit 1
    fi

    log_info "Reading deployment configuration from: $json_file"

    # Extract connection details
    DEPLOY_NEO4J_URI=$(jq -r '.connection.neo4j_uri // empty' "$json_file")
    DEPLOY_NEO4J_USERNAME=$(jq -r '.connection.username // empty' "$json_file")
    DEPLOY_NEO4J_PASSWORD=$(jq -r '.connection.password // empty' "$json_file")

    # Extract M2M authentication details
    DEPLOY_M2M_ENABLED=$(jq -r '.m2m_auth.enabled // false' "$json_file")
    DEPLOY_TENANT_ID=$(jq -r '.m2m_auth.tenant_id // empty' "$json_file")
    DEPLOY_CLIENT_APP_ID=$(jq -r '.m2m_auth.client_app_id // empty' "$json_file")
    DEPLOY_AUDIENCE=$(jq -r '.m2m_auth.audience // empty' "$json_file")

    # Extract metadata
    DEPLOY_SCENARIO=$(jq -r '.scenario // empty' "$json_file")
    DEPLOY_RESOURCE_GROUP=$(jq -r '.resource_group // empty' "$json_file")

    log_success "Parsed deployment: $DEPLOY_SCENARIO"

    if [[ -n "$DEPLOY_NEO4J_URI" ]]; then
        log_info "  Neo4j URI: $DEPLOY_NEO4J_URI"
    fi

    if [[ "$DEPLOY_M2M_ENABLED" == "true" ]]; then
        log_info "  M2M Auth: enabled"
        log_info "  Tenant ID: $DEPLOY_TENANT_ID"
        log_info "  Client App: $DEPLOY_CLIENT_APP_ID"
    else
        log_warn "  M2M Auth: not enabled in deployment"
    fi
}

# =============================================================================
# Setup Functions
# =============================================================================

setup_azure_config() {
    log_info "Setting up Azure configuration..."

    # Subscription ID from Azure CLI
    local subscription_id
    subscription_id=$(get_subscription_id)
    local subscription_name
    subscription_name=$(get_subscription_name)

    log_info "Current subscription: $subscription_name ($subscription_id)"
    set_env_value "AZURE_SUBSCRIPTION_ID" "$subscription_id"
    log_success "Set AZURE_SUBSCRIPTION_ID=$subscription_id"

    # Resource Group
    local resource_group
    if env_value_exists "AZURE_RESOURCE_GROUP"; then
        resource_group=$(get_env_value "AZURE_RESOURCE_GROUP")
        log_info "Keeping existing AZURE_RESOURCE_GROUP=$resource_group"
    else
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            resource_group="$DEFAULT_RESOURCE_GROUP"
        else
            read -rp "Enter resource group name [$DEFAULT_RESOURCE_GROUP]: " resource_group
            resource_group="${resource_group:-$DEFAULT_RESOURCE_GROUP}"
        fi
        set_env_value "AZURE_RESOURCE_GROUP" "$resource_group"
        log_success "Set AZURE_RESOURCE_GROUP=$resource_group"
    fi

    # Location - try to extract from Neo4j URI if available
    local location
    if env_value_exists "AZURE_LOCATION"; then
        location=$(get_env_value "AZURE_LOCATION")
        log_info "Keeping existing AZURE_LOCATION=$location"
    else
        # Try to extract location from Neo4j URI (e.g., eastus2.cloudapp.azure.com)
        if [[ -n "$DEPLOY_NEO4J_URI" ]]; then
            local extracted_location
            extracted_location=$(echo "$DEPLOY_NEO4J_URI" | grep -oE '[a-z]+[0-9]?\.cloudapp\.azure\.com' | cut -d'.' -f1)
            if [[ -n "$extracted_location" ]]; then
                location="$extracted_location"
                log_info "Detected location from Neo4j URI: $location"
            fi
        fi

        if [[ -z "$location" ]]; then
            if [[ "$NON_INTERACTIVE" == "true" ]]; then
                location="$DEFAULT_LOCATION"
            else
                read -rp "Enter Azure location [$DEFAULT_LOCATION]: " location
                location="${location:-$DEFAULT_LOCATION}"
            fi
        fi

        set_env_value "AZURE_LOCATION" "$location"
        log_success "Set AZURE_LOCATION=$location"
    fi
}

setup_neo4j_config() {
    log_info "Setting up Neo4j configuration..."

    # NEO4J_URI - always update from deployment JSON if available
    if [[ -n "$DEPLOY_NEO4J_URI" ]]; then
        set_env_value "NEO4J_URI" "$DEPLOY_NEO4J_URI"
        log_success "Set NEO4J_URI from deployment"
    elif ! env_value_exists "NEO4J_URI"; then
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            log_warn "NEO4J_URI not set - configure manually"
        else
            read -rp "Neo4j URI: " neo4j_uri
            if [[ -n "$neo4j_uri" ]]; then
                set_env_value "NEO4J_URI" "$neo4j_uri"
                log_success "Set NEO4J_URI"
            fi
        fi
    else
        log_info "Keeping existing NEO4J_URI=$(get_env_value 'NEO4J_URI')"
    fi

    # NEO4J_DATABASE
    if ! env_value_exists "NEO4J_DATABASE"; then
        set_env_value "NEO4J_DATABASE" "$DEFAULT_NEO4J_DATABASE"
        log_success "Set NEO4J_DATABASE=$DEFAULT_NEO4J_DATABASE"
    else
        log_info "Keeping existing NEO4J_DATABASE=$(get_env_value 'NEO4J_DATABASE')"
    fi

    # Note: Bearer mode doesn't use NEO4J_USERNAME/PASSWORD for the MCP server
    # Native credentials remain in neo4j-deployment.json if needed for debugging
}

setup_m2m_config() {
    log_info "Setting up M2M authentication configuration..."

    if [[ "$DEPLOY_M2M_ENABLED" != "true" ]]; then
        log_warn "M2M authentication not enabled in deployment"
        log_warn "Bearer token auth requires M2M to be configured in Neo4j"
        log_warn "Re-deploy Neo4j with M2M enabled, or configure manually"
        return
    fi

    # AZURE_TENANT_ID
    if [[ -n "$DEPLOY_TENANT_ID" ]]; then
        set_env_value "AZURE_TENANT_ID" "$DEPLOY_TENANT_ID"
        log_success "Set AZURE_TENANT_ID from deployment"
    fi

    # AZURE_CLIENT_ID
    if [[ -n "$DEPLOY_CLIENT_APP_ID" ]]; then
        set_env_value "AZURE_CLIENT_ID" "$DEPLOY_CLIENT_APP_ID"
        log_success "Set AZURE_CLIENT_ID from deployment"
    fi

    # AZURE_AUDIENCE
    if [[ -n "$DEPLOY_AUDIENCE" ]]; then
        set_env_value "AZURE_AUDIENCE" "$DEPLOY_AUDIENCE"
        log_success "Set AZURE_AUDIENCE from deployment"
    fi

    # AZURE_CLIENT_SECRET - preserve if exists, otherwise prompt
    if env_value_exists "AZURE_CLIENT_SECRET"; then
        log_info "Keeping existing AZURE_CLIENT_SECRET=********"
    else
        log_warn "AZURE_CLIENT_SECRET not set"
        log_info "The client secret was shown during azure-ee-template M2M setup"

        if [[ "$NON_INTERACTIVE" != "true" ]]; then
            echo ""
            read -rsp "Enter client secret (or press Enter to skip): " client_secret
            echo ""
            if [[ -n "$client_secret" ]]; then
                set_env_value "AZURE_CLIENT_SECRET" "$client_secret"
                log_success "Set AZURE_CLIENT_SECRET"
            else
                log_warn "AZURE_CLIENT_SECRET not set - you'll need to configure this manually"
                log_info "Find or regenerate in Azure Portal > App Registrations > $DEPLOY_CLIENT_APP_ID > Certificates & secrets"
            fi
        else
            log_warn "Configure AZURE_CLIENT_SECRET manually"
        fi
    fi
}

setup_neo4j_mcp_repo() {
    log_info "Setting up Neo4j MCP repository path..."

    if env_value_exists "NEO4J_MCP_REPO"; then
        local repo_path
        repo_path=$(get_env_value "NEO4J_MCP_REPO")
        if [[ -d "$repo_path" && -f "$repo_path/Dockerfile" ]]; then
            log_info "NEO4J_MCP_REPO already configured: $repo_path"
            return
        else
            log_warn "Configured NEO4J_MCP_REPO path does not exist or missing Dockerfile: $repo_path"
        fi
    fi

    # Try to find the repo automatically
    local found_repo
    found_repo=$(find_neo4j_mcp_repo)
    if [[ -n "$found_repo" ]]; then
        set_env_value "NEO4J_MCP_REPO" "$found_repo"
        log_success "Found and set NEO4J_MCP_REPO=$found_repo"
        return
    fi

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        log_warn "NEO4J_MCP_REPO not found - configure manually"
        log_warn "Clone from: https://github.com/neo4j/mcp"
        return
    fi

    echo ""
    log_info "Neo4j MCP server repository not found."
    log_info "Clone from: https://github.com/neo4j/mcp"
    read -rp "Enter path to Neo4j MCP repository: " repo_path

    if [[ -n "$repo_path" && -d "$repo_path" ]]; then
        set_env_value "NEO4J_MCP_REPO" "$repo_path"
        log_success "Set NEO4J_MCP_REPO=$repo_path"
    else
        log_warn "NEO4J_MCP_REPO not set - configure manually"
    fi
}

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
Bearer Token MCP Server - Environment Setup Script

Reads configuration from an azure-ee-template deployment JSON file and
populates the .env file with the necessary settings for bearer token authentication.

USAGE:
    ./scripts/setup-env.sh [OPTIONS]

OPTIONS:
    --non-interactive    Use defaults without prompting
    --file <path>        Specify deployment JSON file path
    --help               Show this help message

SETUP STEPS:
    1. Deploy Neo4j with azure-ee-template (with M2M enabled):
       cd /path/to/azure-ee-template
       uv run neo4j-deploy deploy --scenario standalone-v2025

    2. Copy deployment file to bearer-mcp-server:
       cp .deployments/standalone-v2025.json /path/to/bearer-mcp-server/neo4j-deployment.json

    3. Run this setup script:
       ./scripts/setup-env.sh

DEPLOYMENT JSON:
    The script looks for deployment JSON in these locations:
    - ./neo4j-deployment.json (recommended)
    - ./standalone-v2025.json
    - ./cluster-v2025.json
    - ./deployment.json
    - $AZURE_EE_TEMPLATE_PATH/.deployments/*.json (auto-discovery)

BEHAVIOR:
    - Azure subscription ID is updated from current az context
    - Neo4j URI and M2M config are read from deployment JSON
    - AZURE_CLIENT_SECRET is NEVER overwritten if it exists
    - NEO4J_MCP_REPO is auto-discovered or prompted

EXAMPLE:
    # Copy deployment and run setup
    cp ~/azure-ee-template/.deployments/standalone-v2025.json ./neo4j-deployment.json
    ./scripts/setup-env.sh

    # Then deploy
    ./scripts/deploy.sh

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse arguments
    NON_INTERACTIVE="false"
    DEPLOYMENT_FILE=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive)
                NON_INTERACTIVE="true"
                shift
                ;;
            --file)
                DEPLOYMENT_FILE="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo ""
    echo "======================================================================"
    echo "Bearer Token MCP Server - Environment Setup"
    echo "======================================================================"
    echo ""

    # Check prerequisites
    check_azure_cli

    # Find deployment JSON
    if [[ -z "$DEPLOYMENT_FILE" ]]; then
        DEPLOYMENT_FILE=$(find_deployment_json)
    fi

    if [[ -z "$DEPLOYMENT_FILE" || ! -f "$DEPLOYMENT_FILE" ]]; then
        echo ""
        log_warn "No deployment JSON file found."
        echo ""
        log_info "To use this setup script:"
        log_info "  1. Deploy Neo4j with azure-ee-template (with M2M enabled)"
        log_info "  2. Copy the deployment file:"
        log_info "     cp /path/to/azure-ee-template/.deployments/standalone-v2025.json ./neo4j-deployment.json"
        log_info "  3. Run this script again"
        echo ""

        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            log_error "Cannot continue without deployment JSON in non-interactive mode"
            exit 1
        fi

        read -rp "Continue with manual configuration? [y/N]: " continue_manual
        if [[ "$continue_manual" != "y" && "$continue_manual" != "Y" ]]; then
            exit 0
        fi
    else
        # Parse the deployment JSON
        parse_deployment_json "$DEPLOYMENT_FILE"
    fi

    echo ""

    # Initialize .env file
    init_env_file

    echo ""

    # Setup each section
    setup_azure_config

    echo ""

    setup_neo4j_config

    echo ""

    setup_m2m_config

    echo ""

    setup_neo4j_mcp_repo

    echo ""
    echo "======================================================================"
    echo "Setup Complete"
    echo "======================================================================"
    echo ""
    log_success "Environment file: $ENV_FILE"
    echo ""

    # Show summary of what needs manual configuration
    local needs_manual=false

    if ! env_value_exists "NEO4J_URI"; then
        log_warn "NEO4J_URI needs to be configured manually"
        needs_manual=true
    fi

    if ! env_value_exists "AZURE_CLIENT_SECRET"; then
        log_warn "AZURE_CLIENT_SECRET needs to be configured manually"
        needs_manual=true
    fi

    if ! env_value_exists "NEO4J_MCP_REPO"; then
        log_warn "NEO4J_MCP_REPO needs to be configured manually"
        needs_manual=true
    fi

    if [[ "$needs_manual" == "true" ]]; then
        echo ""
        log_info "Edit $ENV_FILE to complete configuration"
    else
        log_success "All required settings are configured!"
        echo ""
        log_info "Next steps:"
        log_info "  1. Review settings: cat $ENV_FILE"
        log_info "  2. Deploy: ./scripts/deploy.sh"
    fi

    echo ""
}

main "$@"
