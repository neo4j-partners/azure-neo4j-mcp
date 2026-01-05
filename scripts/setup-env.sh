#!/bin/bash
#
# Neo4j MCP Server - Environment Setup Script
#
# Populates the .env file with Azure configuration from the current az CLI context.
# Preserves existing Neo4j settings if they exist.
# Generates a random MCP API key if not already set.
#
# Usage:
#   ./scripts/setup-env.sh                    # Interactive mode
#   ./scripts/setup-env.sh --non-interactive  # Use defaults, no prompts
#   ./scripts/setup-env.sh --help             # Show help
#

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_SAMPLE="$PROJECT_ROOT/.env.sample"

# Defaults
DEFAULT_RESOURCE_GROUP="neo4j-mcp-demo-rg"
DEFAULT_LOCATION="eastus"
DEFAULT_NEO4J_DATABASE="neo4j"
DEFAULT_NEO4J_USERNAME="neo4j"
DEFAULT_NEO4J_MCP_REPO="/Users/ryanknight/projects/mcp"

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

# Generate a random API key (32 bytes, base64 encoded = 44 chars)
generate_api_key() {
    if command_exists openssl; then
        openssl rand -base64 32
    elif [[ -f /dev/urandom ]]; then
        head -c 32 /dev/urandom | base64
    else
        # Fallback: use $RANDOM (less secure but works everywhere)
        echo "$(date +%s%N)$RANDOM$RANDOM$RANDOM" | sha256sum | head -c 44
    fi
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

# =============================================================================
# Azure CLI Functions
# =============================================================================

# Check Azure CLI is installed and logged in
check_azure_cli() {
    if ! command_exists az; then
        log_error "Azure CLI (az) is not installed."
        log_error "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check if logged in
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure CLI."
        log_error "Run: az login"
        exit 1
    fi

    log_success "Azure CLI is installed and authenticated"
}

# Get current subscription ID
get_subscription_id() {
    az account show --query id -o tsv
}

# Get current subscription name
get_subscription_name() {
    az account show --query name -o tsv
}

# Get list of available locations
get_locations() {
    az account list-locations --query "[].name" -o tsv | sort
}

# Validate location exists
validate_location() {
    local location="$1"
    az account list-locations --query "[?name=='$location'].name" -o tsv | grep -q "$location"
}

# =============================================================================
# Environment File Functions
# =============================================================================

# Create .env file from sample if it doesn't exist
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

# Update or add a value in .env file
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
# Main Setup Functions
# =============================================================================

setup_azure_config() {
    log_info "Setting up Azure configuration..."

    # Subscription ID
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

    # Location
    local location
    if env_value_exists "AZURE_LOCATION"; then
        location=$(get_env_value "AZURE_LOCATION")
        log_info "Keeping existing AZURE_LOCATION=$location"
    else
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            location="$DEFAULT_LOCATION"
        else
            echo ""
            log_info "Common Azure regions: eastus, westus2, westeurope, northeurope, southeastasia"
            read -rp "Enter Azure location [$DEFAULT_LOCATION]: " location
            location="${location:-$DEFAULT_LOCATION}"

            # Validate location
            if ! validate_location "$location"; then
                log_warn "Location '$location' may not be valid. Continuing anyway."
            fi
        fi
        set_env_value "AZURE_LOCATION" "$location"
        log_success "Set AZURE_LOCATION=$location"
    fi
}

setup_neo4j_config() {
    log_info "Setting up Neo4j configuration..."

    # Check if Neo4j settings already exist
    local has_neo4j_uri has_neo4j_password
    has_neo4j_uri=$(env_value_exists "NEO4J_URI" && echo "true" || echo "false")
    has_neo4j_password=$(env_value_exists "NEO4J_PASSWORD" && echo "true" || echo "false")

    if [[ "$has_neo4j_uri" == "true" && "$has_neo4j_password" == "true" ]]; then
        log_info "Neo4j settings already configured - preserving existing values"
        log_info "  NEO4J_URI=$(get_env_value 'NEO4J_URI')"
        log_info "  NEO4J_DATABASE=$(get_env_value 'NEO4J_DATABASE')"
        log_info "  NEO4J_USERNAME=$(get_env_value 'NEO4J_USERNAME')"
        log_info "  NEO4J_PASSWORD=********"
        return
    fi

    log_warn "Neo4j settings not fully configured"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        log_warn "Running in non-interactive mode - Neo4j settings must be configured manually"
        # Set defaults for database and username if not present
        if ! env_value_exists "NEO4J_DATABASE"; then
            set_env_value "NEO4J_DATABASE" "$DEFAULT_NEO4J_DATABASE"
        fi
        if ! env_value_exists "NEO4J_USERNAME"; then
            set_env_value "NEO4J_USERNAME" "$DEFAULT_NEO4J_USERNAME"
        fi
        return
    fi

    echo ""
    log_info "Enter your Neo4j database connection details:"
    echo ""

    # NEO4J_URI
    if ! env_value_exists "NEO4J_URI"; then
        read -rp "Neo4j URI (e.g., neo4j+s://xxx.databases.neo4j.io): " neo4j_uri
        if [[ -n "$neo4j_uri" ]]; then
            set_env_value "NEO4J_URI" "$neo4j_uri"
            log_success "Set NEO4J_URI"
        else
            log_warn "NEO4J_URI not set - you'll need to configure this manually"
        fi
    fi

    # NEO4J_DATABASE
    if ! env_value_exists "NEO4J_DATABASE"; then
        read -rp "Neo4j database name [$DEFAULT_NEO4J_DATABASE]: " neo4j_database
        neo4j_database="${neo4j_database:-$DEFAULT_NEO4J_DATABASE}"
        set_env_value "NEO4J_DATABASE" "$neo4j_database"
        log_success "Set NEO4J_DATABASE=$neo4j_database"
    fi

    # NEO4J_USERNAME
    if ! env_value_exists "NEO4J_USERNAME"; then
        read -rp "Neo4j username [$DEFAULT_NEO4J_USERNAME]: " neo4j_username
        neo4j_username="${neo4j_username:-$DEFAULT_NEO4J_USERNAME}"
        set_env_value "NEO4J_USERNAME" "$neo4j_username"
        log_success "Set NEO4J_USERNAME=$neo4j_username"
    fi

    # NEO4J_PASSWORD
    if ! env_value_exists "NEO4J_PASSWORD"; then
        read -rsp "Neo4j password: " neo4j_password
        echo ""
        if [[ -n "$neo4j_password" ]]; then
            set_env_value "NEO4J_PASSWORD" "$neo4j_password"
            log_success "Set NEO4J_PASSWORD=********"
        else
            log_warn "NEO4J_PASSWORD not set - you'll need to configure this manually"
        fi
    fi
}

setup_mcp_api_key() {
    log_info "Setting up MCP API key..."

    if env_value_exists "MCP_API_KEY"; then
        log_info "MCP_API_KEY already configured - preserving existing value"
        return
    fi

    # Generate a new random API key
    local api_key
    api_key=$(generate_api_key)

    set_env_value "MCP_API_KEY" "$api_key"
    log_success "Generated new MCP_API_KEY"
    log_info "API Key: $api_key"
}

setup_neo4j_mcp_repo() {
    log_info "Setting up Neo4j MCP repository path..."

    if env_value_exists "NEO4J_MCP_REPO"; then
        local repo_path
        repo_path=$(get_env_value "NEO4J_MCP_REPO")
        if [[ -d "$repo_path" ]]; then
            log_info "NEO4J_MCP_REPO already configured: $repo_path"
            return
        else
            log_warn "Configured NEO4J_MCP_REPO path does not exist: $repo_path"
        fi
    fi

    # Check if default path exists
    if [[ -d "$DEFAULT_NEO4J_MCP_REPO" ]]; then
        set_env_value "NEO4J_MCP_REPO" "$DEFAULT_NEO4J_MCP_REPO"
        log_success "Set NEO4J_MCP_REPO=$DEFAULT_NEO4J_MCP_REPO"
        return
    fi

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        log_warn "NEO4J_MCP_REPO not found - you'll need to configure this manually"
        log_warn "Clone from: https://github.com/neo4j/mcp"
        return
    fi

    echo ""
    log_info "Neo4j MCP server repository not found at default location."
    log_info "Clone from: https://github.com/neo4j/mcp"
    read -rp "Enter path to Neo4j MCP repository: " repo_path

    if [[ -n "$repo_path" && -d "$repo_path" ]]; then
        set_env_value "NEO4J_MCP_REPO" "$repo_path"
        log_success "Set NEO4J_MCP_REPO=$repo_path"
    else
        log_warn "NEO4J_MCP_REPO not set - you'll need to configure this manually"
    fi
}

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
Neo4j MCP Server - Environment Setup Script

Populates the .env file with Azure configuration from the current az CLI context.
Preserves existing Neo4j settings if they exist.
Generates a random MCP API key if not already set.

USAGE:
    ./scripts/setup-env.sh [OPTIONS]

OPTIONS:
    --non-interactive    Use defaults without prompting
    --help               Show this help message

EXAMPLES:
    # Interactive mode (prompts for Neo4j settings)
    ./scripts/setup-env.sh

    # Non-interactive mode (uses defaults, skips Neo4j prompts)
    ./scripts/setup-env.sh --non-interactive

BEHAVIOR:
    - Azure subscription ID is always updated from current az context
    - Resource group and location use defaults if not set
    - Neo4j settings are NEVER overwritten if they already exist
    - MCP_API_KEY is generated only if not already set

PREREQUISITES:
    - Azure CLI installed and authenticated (az login)
    - Neo4j database credentials (for interactive mode)

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse arguments
    NON_INTERACTIVE="false"
    for arg in "$@"; do
        case "$arg" in
            --non-interactive)
                NON_INTERACTIVE="true"
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $arg"
                show_help
                exit 1
                ;;
        esac
    done

    echo ""
    echo "======================================================================"
    echo "Neo4j MCP Server - Environment Setup"
    echo "======================================================================"
    echo ""

    # Check prerequisites
    check_azure_cli

    # Initialize .env file
    init_env_file

    echo ""

    # Setup each section
    setup_azure_config

    echo ""

    setup_neo4j_config

    echo ""

    setup_mcp_api_key

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

    if ! env_value_exists "NEO4J_PASSWORD"; then
        log_warn "NEO4J_PASSWORD needs to be configured manually"
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
