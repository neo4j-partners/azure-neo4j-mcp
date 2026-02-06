#!/bin/bash
# =============================================================================
# Bearer Token MCP Server - Azure Deployment Script
# =============================================================================
#
# Deploys the Neo4j MCP Server to Azure Container Apps with native bearer token
# authentication. Uses the official Neo4j MCP Docker image from Docker Hub
# (docker.io/mcp/neo4j) - no local build or ACR required.
#
# Usage:
#   ./scripts/deploy.sh                    # Full deployment
#   ./scripts/deploy.sh redeploy           # Update container image
#   ./scripts/deploy.sh lint               # Lint Bicep templates
#   ./scripts/deploy.sh status             # Show deployment status
#   ./scripts/deploy.sh logs               # Show container logs
#
# Prerequisites:
#   - Azure CLI installed and authenticated (az login)
#   - Neo4j Enterprise with OIDC configured (for bearer auth)
#
# Environment Variables (from .env file):
#   Required:
#     - AZURE_SUBSCRIPTION_ID: Azure subscription ID
#     - AZURE_RESOURCE_GROUP: Resource group name
#     - AZURE_LOCATION: Azure region (e.g., eastus)
#     - NEO4J_URI: Neo4j connection URI (e.g., neo4j+s://xxx.databases.neo4j.io)
#   Optional:
#     - NEO4J_DATABASE: Database name (default: neo4j)
#     - BASE_NAME: Resource naming prefix (default: neo4jmcp)
#     - ENVIRONMENT: Environment name (default: dev)
#     - MCP_SERVER_IMAGE: Container image override (default: docker.io/mcp/neo4j:latest)
#
# =============================================================================

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$PROJECT_ROOT/infra"
ENV_FILE="$PROJECT_ROOT/.env"
MCP_ACCESS_FILE="$PROJECT_ROOT/MCP_ACCESS.json"

# Default container image
DEFAULT_MCP_IMAGE="docker.io/mcp/neo4j:latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}INFO${NC} $1"; }
log_success() { echo -e "${GREEN}SUCCESS${NC} $1"; }
log_warning() { echo -e "${YELLOW}WARNING${NC} $1"; }
log_error() { echo -e "${RED}ERROR${NC} $1"; }

# =============================================================================
# Environment Loading
# =============================================================================

load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found at $ENV_FILE"
        log_error "Copy .env.sample to .env and configure your settings"
        exit 1
    fi

    log_info "Loading environment from $ENV_FILE"
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a

    # Set defaults for optional variables
    NEO4J_DATABASE="${NEO4J_DATABASE:-neo4j}"
    BASE_NAME="${BASE_NAME:-neo4jmcp}"
    ENVIRONMENT="${ENVIRONMENT:-dev}"
    NEO4J_READ_ONLY="${NEO4J_READ_ONLY:-true}"
    CORS_ALLOWED_ORIGINS="${CORS_ALLOWED_ORIGINS:-}"
    MCP_SERVER_IMAGE="${MCP_SERVER_IMAGE:-$DEFAULT_MCP_IMAGE}"
}

validate_env() {
    local missing=()

    [[ -z "${AZURE_SUBSCRIPTION_ID:-}" ]] && missing+=("AZURE_SUBSCRIPTION_ID")
    [[ -z "${AZURE_RESOURCE_GROUP:-}" ]] && missing+=("AZURE_RESOURCE_GROUP")
    [[ -z "${AZURE_LOCATION:-}" ]] && missing+=("AZURE_LOCATION")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing[@]}"; do
            log_error "  - $var"
        done
        exit 1
    fi

    log_success "Azure environment validated"
}

validate_neo4j_env() {
    if [[ -z "${NEO4J_URI:-}" ]]; then
        log_error "Missing required variable: NEO4J_URI"
        log_error "Set NEO4J_URI to your Neo4j connection string (e.g., neo4j+s://xxx.databases.neo4j.io)"
        exit 1
    fi

    # Bearer mode requires Neo4j Enterprise with OIDC - warn user
    log_warning "Bearer authentication requires Neo4j Enterprise with OIDC configured"
    log_warning "Ensure your Neo4j instance supports bearer token authentication"

    log_success "Neo4j environment validated"
}

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check Azure login
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run: az login"
        exit 1
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Install with: brew install jq (macOS) or apt-get install jq (Linux)"
        exit 1
    fi

    # Check Bicep
    if ! az bicep version &> /dev/null; then
        log_info "Installing Bicep CLI..."
        az bicep install
    fi

    log_success "All prerequisites met"
}

# =============================================================================
# Bicep Linting
# =============================================================================

lint_bicep() {
    log_info "Linting Bicep templates..."

    if az bicep lint --file "$INFRA_DIR/main.bicep"; then
        log_success "Bicep templates are valid"
    else
        log_error "Bicep linting failed"
        exit 1
    fi
}

# =============================================================================
# Infrastructure Deployment
# =============================================================================

deploy_infrastructure() {
    local deploy_container_app="${1:-true}"

    log_info "Deploying infrastructure to Azure..."
    log_info "Container image: $MCP_SERVER_IMAGE"

    # Set Azure subscription
    az account set --subscription "$AZURE_SUBSCRIPTION_ID"

    # Create resource group if needed
    if ! az group show --name "$AZURE_RESOURCE_GROUP" &> /dev/null; then
        log_info "Creating resource group: $AZURE_RESOURCE_GROUP"
        az group create \
            --name "$AZURE_RESOURCE_GROUP" \
            --location "$AZURE_LOCATION" \
            --tags project=neo4j-mcp-server-bearer environment="$ENVIRONMENT"
    fi

    # Get deployer principal ID for Key Vault access
    local deployer_principal_id
    deployer_principal_id=$(az ad signed-in-user show --query id --output tsv 2>/dev/null || echo "")
    export DEPLOYER_PRINCIPAL_ID="$deployer_principal_id"

    # Deploy Bicep templates
    if [[ "$deploy_container_app" == "true" ]]; then
        log_info "Deploying all resources (including container app)..."
    else
        log_info "Deploying foundation only (no container app)..."
    fi

    local deployment_name="bearer-mcp-deploy-$(date +%Y%m%d%H%M%S)"

    az deployment group create \
        --name "$deployment_name" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --template-file "$INFRA_DIR/main.bicep" \
        --parameters "$INFRA_DIR/main.bicepparam" \
        --parameters deployContainerApp="$deploy_container_app" \
        --output none

    log_success "Infrastructure deployed successfully"
}

# =============================================================================
# Generate MCP Access Configuration
# =============================================================================

generate_mcp_access() {
    log_info "Generating MCP access configuration..."

    # Get Container App URL
    local container_app_name
    container_app_name=$(az containerapp list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[?contains(name, '-b-')].name | [0]" \
        --output tsv)

    if [[ -z "$container_app_name" ]]; then
        log_warning "Container App not found. MCP_ACCESS.json not generated."
        return
    fi

    local fqdn
    fqdn=$(az containerapp show \
        --name "$container_app_name" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "properties.configuration.ingress.fqdn" \
        --output tsv)

    local endpoint="https://$fqdn"

    # Generate MCP_ACCESS.json for bearer authentication
    cat > "$MCP_ACCESS_FILE" << EOF
{
  "version": {
    "mcp_server_image": "$MCP_SERVER_IMAGE",
    "deployed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "auth_mode": "bearer-token"
  },
  "endpoint": "$endpoint",
  "mcp_path": "/mcp",
  "transport": "streamable-http",
  "authentication": {
    "type": "bearer_token",
    "description": "Obtain JWT from your identity provider (Entra ID, Okta, etc.)",
    "header": "Authorization",
    "prefix": "Bearer",
    "requirements": [
      "Neo4j Enterprise with OIDC configured",
      "Identity provider registered application",
      "Valid JWT with appropriate claims"
    ]
  },
  "identity_providers": {
    "azure_entra_id": {
      "token_endpoint": "https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token",
      "scope": "api://{app-id}/.default"
    },
    "okta": {
      "token_endpoint": "https://{domain}.okta.com/oauth2/default/v1/token",
      "scope": "neo4j"
    }
  },
  "example_curl": "curl -X POST '$endpoint/mcp' -H 'Authorization: Bearer \$TOKEN' -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"tools/list\",\"id\":1}'",
  "mcp_client_config": {
    "mcpServers": {
      "neo4j-bearer": {
        "url": "$endpoint/mcp",
        "transport": {
          "type": "streamable-http",
          "options": {
            "headers": {
              "Authorization": "Bearer \${TOKEN}"
            }
          }
        }
      }
    }
  }
}
EOF

    log_success "Generated $MCP_ACCESS_FILE"
    log_info "Endpoint: $endpoint/mcp"
    log_info "Authentication: Bearer token (obtain from your identity provider)"
}

# =============================================================================
# Status and Logs
# =============================================================================

show_status() {
    log_info "Checking deployment status..."

    # Check resource group
    if ! az group show --name "$AZURE_RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group not found: $AZURE_RESOURCE_GROUP"
        return
    fi

    # List resources
    log_info "Resources in $AZURE_RESOURCE_GROUP:"
    az resource list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table

    # Container App status
    local container_app_name
    container_app_name=$(az containerapp list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[?contains(name, '-b-')].name | [0]" \
        --output tsv 2>/dev/null || echo "")

    if [[ -n "$container_app_name" ]]; then
        log_info "Container App: $container_app_name"
        az containerapp show \
            --name "$container_app_name" \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --query "{Name:name, Status:properties.provisioningState, URL:properties.configuration.ingress.fqdn, Replicas:properties.template.scale}" \
            --output table
    fi
}

show_logs() {
    local lines="${1:-100}"

    local container_app_name
    container_app_name=$(az containerapp list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[?contains(name, '-b-')].name | [0]" \
        --output tsv 2>/dev/null || echo "")

    if [[ -z "$container_app_name" ]]; then
        log_error "Container App not found"
        exit 1
    fi

    log_info "Fetching logs for $container_app_name (last $lines lines)..."
    az containerapp logs show \
        --name "$container_app_name" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --container mcp-server \
        --tail "$lines"
}

# =============================================================================
# Commands
# =============================================================================

cmd_deploy() {
    log_info "Starting deployment..."
    log_info "Using container image: $MCP_SERVER_IMAGE"

    check_prerequisites
    validate_env
    validate_neo4j_env
    lint_bicep

    # Single-phase deployment - no build/push needed
    deploy_infrastructure "true"

    # Generate access configuration
    generate_mcp_access

    log_success "Deployment complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Configure your identity provider (Entra ID, Okta, etc.)"
    log_info "  2. Ensure Neo4j is configured for OIDC authentication"
    log_info "  3. Obtain a JWT token from your identity provider"
    log_info "  4. Test with: curl -H 'Authorization: Bearer \$TOKEN' \$(cat MCP_ACCESS.json | jq -r '.endpoint')/mcp"
}

cmd_redeploy() {
    log_info "Starting redeploy..."
    log_info "Using container image: $MCP_SERVER_IMAGE"

    check_prerequisites
    validate_env
    validate_neo4j_env

    # Check if container app exists
    local container_app_name
    container_app_name=$(az containerapp list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[?contains(name, '-b-')].name | [0]" \
        --output tsv 2>/dev/null || echo "")

    if [[ -n "$container_app_name" ]]; then
        # Container app exists - update the image
        log_info "Updating existing Container App: $container_app_name"
        az containerapp update \
            --name "$container_app_name" \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --container-name mcp-server \
            --image "$MCP_SERVER_IMAGE" \
            --output none
    else
        # Container app doesn't exist - deploy via Bicep
        log_info "Container App not found - deploying via Bicep..."
        deploy_infrastructure "true"
    fi

    generate_mcp_access
    log_success "Redeploy complete!"
}

cmd_lint() {
    lint_bicep
}

cmd_status() {
    load_env
    validate_env
    show_status
}

cmd_logs() {
    load_env
    validate_env
    show_logs "${1:-100}"
}

cmd_test() {
    log_info "Running bearer token authentication test..."

    # Check for MCP_ACCESS.json or endpoint
    if [[ ! -f "$MCP_ACCESS_FILE" ]]; then
        log_error "MCP_ACCESS.json not found. Run deploy first."
        exit 1
    fi

    # Check for required auth environment variables
    local has_token="${MCP_BEARER_TOKEN:-}"
    local has_azure_creds="false"

    if [[ -n "${AZURE_TENANT_ID:-}" && -n "${AZURE_CLIENT_ID:-}" && -n "${AZURE_CLIENT_SECRET:-}" ]]; then
        has_azure_creds="true"
    fi

    if [[ -z "$has_token" && "$has_azure_creds" != "true" ]]; then
        log_error "No authentication configured."
        log_error "Set one of:"
        log_error "  - MCP_BEARER_TOKEN (direct token)"
        log_error "  - AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET (Azure Entra ID)"
        exit 1
    fi

    # Get endpoint from MCP_ACCESS.json
    local endpoint
    endpoint=$(jq -r '.endpoint' "$MCP_ACCESS_FILE")
    export MCP_ENDPOINT="$endpoint"

    log_info "Testing endpoint: $endpoint"

    # Run the test client with uv (dependencies declared inline via PEP 723)
    uv run "$PROJECT_ROOT/client/test_bearer_client.py"
}

# =============================================================================
# Main
# =============================================================================

print_usage() {
    cat << EOF
Bearer Token MCP Server - Azure Deployment

Usage: $0 [command] [options]

Commands:
  deploy      Full deployment (default)
  redeploy    Update container image
  test        Run bearer token authentication test
  lint        Lint Bicep templates
  status      Show deployment status
  logs [N]    Show last N container logs (default: 100)
  help        Show this help message

Container Image:
  Default: $DEFAULT_MCP_IMAGE
  Override: Set MCP_SERVER_IMAGE in .env

Examples:
  $0                    # Full deployment
  $0 redeploy           # Update to latest image
  $0 test               # Test bearer auth
  $0 logs 50            # Show last 50 log lines
  $0 status             # Check deployment status

Environment:
  Configure settings in .env file (copy from .env.sample)

EOF
}

main() {
    cd "$PROJECT_ROOT"

    local command="${1:-deploy}"

    case "$command" in
        deploy)
            load_env
            cmd_deploy
            ;;
        redeploy)
            load_env
            cmd_redeploy
            ;;
        test)
            load_env
            cmd_test
            ;;
        lint)
            cmd_lint
            ;;
        status)
            cmd_status
            ;;
        logs)
            cmd_logs "${2:-100}"
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            log_error "Unknown command: $command"
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
