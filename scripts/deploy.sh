#!/bin/bash
#
# Neo4j MCP Server - Azure Deployment Script
#
# Deploys the Neo4j MCP server to Azure Container Apps.
# Mirrors the AWS deployment pattern with local Docker build.
#
# Usage:
#   ./scripts/deploy.sh              # Full deployment
#   ./scripts/deploy.sh build        # Build Docker image only
#   ./scripts/deploy.sh push         # Push image to ACR only
#   ./scripts/deploy.sh infra        # Deploy infrastructure only
#   ./scripts/deploy.sh status       # Show deployment status
#   ./scripts/deploy.sh test         # Run test client
#   ./scripts/deploy.sh cleanup      # Delete all resources
#   ./scripts/deploy.sh help         # Show help
#

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$PROJECT_ROOT/infra"
ENV_FILE="$PROJECT_ROOT/.env"
MCP_ACCESS_FILE="$PROJECT_ROOT/MCP_ACCESS.json"

# Default values (can be overridden by .env)
DEFAULT_RESOURCE_GROUP="neo4j-mcp-demo-rg"
DEFAULT_LOCATION="eastus"
DEFAULT_BASE_NAME="neo4jmcp"
DEFAULT_ENVIRONMENT="dev"
DEFAULT_IMAGE_TAG="latest"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "\033[0;34mINFO\033[0m  $1"
}

log_success() {
    echo -e "\033[0;32mOK\033[0m    $1"
}

log_warn() {
    echo -e "\033[0;33mWARN\033[0m  $1"
}

log_error() {
    echo -e "\033[0;31mERROR\033[0m $1" >&2
}

log_step() {
    echo ""
    echo -e "\033[1;36m==>\033[0m \033[1m$1\033[0m"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Load environment variables from .env file
load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found at $ENV_FILE"
        log_error "Run ./scripts/setup-env.sh to create it"
        exit 1
    fi

    # Export variables from .env file
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    # Set defaults for optional variables
    AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
    AZURE_LOCATION="${AZURE_LOCATION:-$DEFAULT_LOCATION}"
    BASE_NAME="${BASE_NAME:-$DEFAULT_BASE_NAME}"
    ENVIRONMENT="${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"
    IMAGE_TAG="${IMAGE_TAG:-$DEFAULT_IMAGE_TAG}"
}

# Validate required environment variables
validate_env() {
    local missing=()

    [[ -z "$AZURE_SUBSCRIPTION_ID" ]] && missing+=("AZURE_SUBSCRIPTION_ID")
    [[ -z "$AZURE_RESOURCE_GROUP" ]] && missing+=("AZURE_RESOURCE_GROUP")
    [[ -z "$AZURE_LOCATION" ]] && missing+=("AZURE_LOCATION")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing[@]}"; do
            log_error "  - $var"
        done
        log_error "Run ./scripts/setup-env.sh to configure"
        exit 1
    fi
}

# Validate Neo4j configuration (for full deployment)
validate_neo4j_env() {
    local missing=()

    [[ -z "$NEO4J_URI" ]] && missing+=("NEO4J_URI")
    [[ -z "$NEO4J_PASSWORD" ]] && missing+=("NEO4J_PASSWORD")
    [[ -z "$MCP_API_KEY" ]] && missing+=("MCP_API_KEY")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required Neo4j/MCP environment variables:"
        for var in "${missing[@]}"; do
            log_error "  - $var"
        done
        log_error "Edit $ENV_FILE to configure"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites"

    # Azure CLI
    if ! command_exists az; then
        log_error "Azure CLI (az) is not installed"
        log_error "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    log_success "Azure CLI installed"

    # Check if logged in
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure CLI"
        log_error "Run: az login"
        exit 1
    fi
    log_success "Azure CLI authenticated"

    # Docker (for build/push commands)
    if ! command_exists docker; then
        log_warn "Docker not installed - build/push commands will not work"
    else
        log_success "Docker installed"
    fi

    # Bicep
    if ! az bicep version >/dev/null 2>&1; then
        log_info "Installing Bicep CLI..."
        az bicep install
    fi
    log_success "Bicep CLI available"
}

# =============================================================================
# Resource Group Management
# =============================================================================

ensure_resource_group() {
    log_step "Ensuring resource group exists"

    if az group show --name "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
        log_success "Resource group '$AZURE_RESOURCE_GROUP' exists"
    else
        log_info "Creating resource group '$AZURE_RESOURCE_GROUP' in '$AZURE_LOCATION'..."
        az group create \
            --name "$AZURE_RESOURCE_GROUP" \
            --location "$AZURE_LOCATION" \
            --output none
        log_success "Resource group created"
    fi
}

# =============================================================================
# Docker Build
# =============================================================================

cmd_build() {
    log_step "Building Docker image"

    # Check for Neo4j MCP repo
    if [[ -z "$NEO4J_MCP_REPO" ]]; then
        log_error "NEO4J_MCP_REPO not set in .env"
        log_error "Set it to the path of the cloned https://github.com/neo4j/mcp repository"
        exit 1
    fi

    if [[ ! -d "$NEO4J_MCP_REPO" ]]; then
        log_error "NEO4J_MCP_REPO directory not found: $NEO4J_MCP_REPO"
        exit 1
    fi

    if [[ ! -f "$NEO4J_MCP_REPO/Dockerfile" ]]; then
        log_error "Dockerfile not found in $NEO4J_MCP_REPO"
        exit 1
    fi

    # Get ACR name from deployment outputs or generate it
    local acr_name
    acr_name=$(get_acr_name)

    if [[ -z "$acr_name" ]]; then
        log_error "Cannot determine ACR name. Deploy infrastructure first."
        exit 1
    fi

    local image_name="${acr_name}.azurecr.io/neo4j-mcp-server:${IMAGE_TAG}"

    log_info "Building image: $image_name"
    log_info "Source: $NEO4J_MCP_REPO"

    # Build for linux/amd64 (Azure Container Apps architecture)
    docker buildx build \
        --platform linux/amd64 \
        --tag "$image_name" \
        --load \
        "$NEO4J_MCP_REPO"

    log_success "Docker image built: $image_name"
}

# =============================================================================
# Docker Push
# =============================================================================

cmd_push() {
    log_step "Pushing Docker image to ACR"

    local acr_name
    acr_name=$(get_acr_name)

    if [[ -z "$acr_name" ]]; then
        log_error "Cannot determine ACR name. Deploy infrastructure first."
        exit 1
    fi

    local image_name="${acr_name}.azurecr.io/neo4j-mcp-server:${IMAGE_TAG}"

    # Login to ACR
    log_info "Logging in to ACR: $acr_name"
    az acr login --name "$acr_name"

    # Push image
    log_info "Pushing image: $image_name"
    docker push "$image_name"

    log_success "Image pushed to ACR"
}

# =============================================================================
# Infrastructure Deployment
# =============================================================================

cmd_infra() {
    log_step "Deploying Bicep infrastructure"

    ensure_resource_group

    log_info "Deploying to resource group: $AZURE_RESOURCE_GROUP"
    log_info "Location: $AZURE_LOCATION"
    log_info "Base name: $BASE_NAME"
    log_info "Environment: $ENVIRONMENT"

    # Deploy Bicep template
    az deployment group create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --template-file "$INFRA_DIR/main.bicep" \
        --parameters \
            location="$AZURE_LOCATION" \
            baseName="$BASE_NAME" \
            environment="$ENVIRONMENT" \
        --output none

    log_success "Infrastructure deployed"

    # Show outputs
    cmd_status
}

# =============================================================================
# Get Deployment Outputs
# =============================================================================

get_deployment_output() {
    local output_name="$1"
    az deployment group show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "main" \
        --query "properties.outputs.${output_name}.value" \
        --output tsv 2>/dev/null || echo ""
}

get_acr_name() {
    # Try to get from deployment outputs
    local acr_name
    acr_name=$(get_deployment_output "containerRegistryName")

    if [[ -z "$acr_name" ]]; then
        # Try to find ACR in resource group
        acr_name=$(az acr list \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --query "[0].name" \
            --output tsv 2>/dev/null || echo "")
    fi

    echo "$acr_name"
}

get_container_app_url() {
    az containerapp show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "${BASE_NAME}-app-${ENVIRONMENT}" \
        --query "properties.configuration.ingress.fqdn" \
        --output tsv 2>/dev/null || echo ""
}

# =============================================================================
# Status
# =============================================================================

cmd_status() {
    log_step "Deployment Status"

    echo ""
    echo "Resource Group: $AZURE_RESOURCE_GROUP"
    echo "Location: $AZURE_LOCATION"
    echo ""

    # Check if deployment exists
    if ! az deployment group show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "main" >/dev/null 2>&1; then
        log_warn "No deployment found in resource group"
        return
    fi

    echo "Deployment Outputs:"
    echo "-------------------"

    # Get all outputs
    local outputs
    outputs=$(az deployment group show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "main" \
        --query "properties.outputs" \
        --output json 2>/dev/null)

    if [[ -n "$outputs" && "$outputs" != "null" ]]; then
        echo "$outputs" | jq -r 'to_entries[] | "  \(.key): \(.value.value)"'
    else
        log_warn "No outputs available"
    fi

    # Check for Container App URL
    local app_url
    app_url=$(get_container_app_url)
    if [[ -n "$app_url" ]]; then
        echo ""
        echo "Container App URL: https://$app_url"
    fi

    echo ""
}

# =============================================================================
# Test
# =============================================================================

cmd_test() {
    log_step "Running test client"

    # Check if MCP_ACCESS.json exists
    if [[ ! -f "$MCP_ACCESS_FILE" ]]; then
        log_error "MCP_ACCESS.json not found"
        log_error "Deploy the full stack first, or create MCP_ACCESS.json manually"
        exit 1
    fi

    # Check for Python
    if ! command_exists python3; then
        log_error "Python 3 is required for the test client"
        exit 1
    fi

    # Check for test client
    local test_client="$PROJECT_ROOT/client/test_client.py"
    if [[ ! -f "$test_client" ]]; then
        log_error "Test client not found at $test_client"
        log_error "Test client will be implemented in Phase 6"
        exit 1
    fi

    # Run test client
    cd "$PROJECT_ROOT/client"
    python3 test_client.py

    log_success "Tests completed"
}

# =============================================================================
# Cleanup
# =============================================================================

cmd_cleanup() {
    log_step "Cleaning up Azure resources"

    echo ""
    log_warn "This will delete ALL resources in resource group: $AZURE_RESOURCE_GROUP"
    echo ""

    read -rp "Are you sure? Type 'yes' to confirm: " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi

    log_info "Deleting resource group: $AZURE_RESOURCE_GROUP"

    az group delete \
        --name "$AZURE_RESOURCE_GROUP" \
        --yes \
        --no-wait

    log_success "Resource group deletion initiated (running in background)"
    log_info "Use 'az group show -n $AZURE_RESOURCE_GROUP' to check status"

    # Clean up local files
    if [[ -f "$MCP_ACCESS_FILE" ]]; then
        rm -f "$MCP_ACCESS_FILE"
        log_info "Removed MCP_ACCESS.json"
    fi
}

# =============================================================================
# Generate MCP Access File
# =============================================================================

generate_mcp_access() {
    log_step "Generating MCP_ACCESS.json"

    local app_url
    app_url=$(get_container_app_url)

    if [[ -z "$app_url" ]]; then
        log_warn "Container App URL not available yet"
        return
    fi

    cat > "$MCP_ACCESS_FILE" << EOF
{
  "endpoint": "https://${app_url}",
  "api_key": "${MCP_API_KEY}",
  "transport": "http",
  "port": 443,
  "tools": [
    "get-schema",
    "read-cypher",
    "write-cypher",
    "list-gds-procedures"
  ],
  "example_request": {
    "method": "POST",
    "url": "https://${app_url}/mcp/v1/tools/call",
    "headers": {
      "Authorization": "Bearer ${MCP_API_KEY}",
      "Content-Type": "application/json"
    },
    "body": {
      "name": "get-schema",
      "arguments": {}
    }
  },
  "claude_desktop_config": {
    "mcpServers": {
      "neo4j": {
        "url": "https://${app_url}",
        "headers": {
          "Authorization": "Bearer ${MCP_API_KEY}"
        }
      }
    }
  }
}
EOF

    log_success "Generated MCP_ACCESS.json"
    log_info "Endpoint: https://${app_url}"
}

# =============================================================================
# Full Deployment
# =============================================================================

cmd_deploy() {
    log_step "Full Deployment"

    validate_neo4j_env

    # Step 1: Deploy infrastructure
    cmd_infra

    # Step 2: Build Docker image
    cmd_build

    # Step 3: Push to ACR
    cmd_push

    # Step 4: Generate access file
    generate_mcp_access

    echo ""
    log_success "Deployment complete!"
    echo ""
    log_info "Next steps:"
    log_info "  1. Test: ./scripts/deploy.sh test"
    log_info "  2. View access info: cat MCP_ACCESS.json"
    echo ""
}

# =============================================================================
# Help
# =============================================================================

cmd_help() {
    cat << 'EOF'
Neo4j MCP Server - Azure Deployment Script

USAGE:
    ./scripts/deploy.sh [COMMAND]

COMMANDS:
    (none)      Full deployment (infra + build + push)
    build       Build Docker image locally
    push        Push Docker image to ACR
    infra       Deploy Bicep infrastructure only
    status      Show deployment status and outputs
    test        Run test client to validate deployment
    cleanup     Delete all Azure resources
    help        Show this help message

PREREQUISITES:
    - Azure CLI installed and authenticated (az login)
    - Docker with buildx support
    - .env file configured (run ./scripts/setup-env.sh)
    - Neo4j MCP repository cloned (for build command)

EXAMPLES:
    # First time setup
    ./scripts/setup-env.sh
    ./scripts/deploy.sh

    # Deploy only infrastructure (Phase 1)
    ./scripts/deploy.sh infra

    # Check deployment status
    ./scripts/deploy.sh status

    # Clean up all resources
    ./scripts/deploy.sh cleanup

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local command="${1:-deploy}"

    # Load environment (except for help)
    if [[ "$command" != "help" ]]; then
        load_env
        validate_env
        check_prerequisites
    fi

    case "$command" in
        deploy|"")
            cmd_deploy
            ;;
        build)
            cmd_build
            ;;
        push)
            cmd_push
            ;;
        infra)
            cmd_infra
            ;;
        status)
            cmd_status
            ;;
        test)
            cmd_test
            ;;
        cleanup)
            cmd_cleanup
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
