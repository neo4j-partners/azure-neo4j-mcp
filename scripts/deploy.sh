#!/bin/bash
#
# Neo4j MCP Server - Azure Deployment Script
#
# Deploys the Neo4j MCP server to Azure Container Apps with API key authentication.
# Uses an Nginx sidecar for API key validation and proxying to the MCP server.
#
# Usage:
#   ./scripts/deploy.sh                    # Full deployment
#   ./scripts/deploy.sh redeploy           # Rebuild containers, update credentials, and redeploy
#   ./scripts/deploy.sh lint               # Lint Bicep templates
#   ./scripts/deploy.sh infra              # Deploy infrastructure only
#   ./scripts/deploy.sh status             # Show deployment status
#   ./scripts/deploy.sh test               # Run test client
#   ./scripts/deploy.sh cleanup            # Delete all resources
#   ./scripts/deploy.sh help               # Show help
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

# Get MCP server version from git commit
get_mcp_version() {
    if [[ -n "${NEO4J_MCP_REPO:-}" ]] && [[ -d "$NEO4J_MCP_REPO/.git" ]]; then
        local commit_short
        local commit_date
        commit_short=$(git -C "$NEO4J_MCP_REPO" rev-parse --short HEAD 2>/dev/null)
        commit_date=$(git -C "$NEO4J_MCP_REPO" log -1 --format=%cs 2>/dev/null)
        if [[ -n "$commit_short" && -n "$commit_date" ]]; then
            echo "${commit_date}-${commit_short}"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# Load environment variables from .env file
load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found at $ENV_FILE"
        log_error "Copy .env.sample to .env and configure your settings"
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
    NEO4J_DATABASE="${NEO4J_DATABASE:-neo4j}"
}

# Validate required environment variables
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
}

# Validate Neo4j configuration (for full deployment)
validate_neo4j_env() {
    local missing=()

    [[ -z "${NEO4J_URI:-}" ]] && missing+=("NEO4J_URI")
    [[ -z "${NEO4J_USERNAME:-}" ]] && missing+=("NEO4J_USERNAME")
    [[ -z "${NEO4J_PASSWORD:-}" ]] && missing+=("NEO4J_PASSWORD")
    [[ -z "${MCP_API_KEY:-}" ]] && missing+=("MCP_API_KEY")

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

    # Set the subscription explicitly
    if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
        az account set --subscription "$AZURE_SUBSCRIPTION_ID" 2>/dev/null || {
            log_error "Failed to set subscription: $AZURE_SUBSCRIPTION_ID"
            exit 1
        }
        log_success "Azure subscription set: $AZURE_SUBSCRIPTION_ID"
    fi

    # Docker (for build/push commands)
    if ! command_exists docker; then
        log_warn "Docker not installed - build/push commands will not work"
    else
        log_success "Docker installed"
    fi

    # jq (for parsing JSON outputs)
    if ! command_exists jq; then
        log_warn "jq not installed - status output may be limited"
    else
        log_success "jq installed"
    fi

    # Bicep
    if ! az bicep version >/dev/null 2>&1; then
        log_info "Installing Bicep CLI..."
        az bicep install
    fi
    log_success "Bicep CLI available"
}

# =============================================================================
# Bicep Linting
# =============================================================================

lint_bicep() {
    log_step "Linting Bicep templates"

    local lint_output
    local lint_exit_code=0

    # Lint main.bicep (which includes all modules)
    lint_output=$(az bicep lint --file "$INFRA_DIR/main.bicep" 2>&1) || lint_exit_code=$?

    # Check for errors (warnings are ok)
    if echo "$lint_output" | grep -q "Error"; then
        log_error "Bicep linting failed:"
        echo "$lint_output" | grep -E "(Error|Warning)" | head -20
        exit 1
    fi

    # Show warnings but don't fail
    if echo "$lint_output" | grep -q "Warning"; then
        log_warn "Bicep linting warnings:"
        echo "$lint_output" | grep "Warning" | head -10
    else
        log_success "Bicep templates passed linting"
    fi
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
# Docker Build (internal helper)
# =============================================================================

do_build() {
    log_step "Building Docker images"

    # Check for Neo4j MCP repo
    if [[ -z "${NEO4J_MCP_REPO:-}" ]]; then
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

    # Get version from MCP repo git commit
    MCP_VERSION=$(get_mcp_version)
    log_info "MCP Server version: $MCP_VERSION"

    # Build MCP server image (tag with version and latest)
    log_info "Building Neo4j MCP Server image..."
    docker buildx build \
        --platform linux/amd64 \
        --tag neo4j-mcp-server:${MCP_VERSION} \
        --tag neo4j-mcp-server:latest \
        --load \
        "$NEO4J_MCP_REPO"
    log_success "MCP Server image built: neo4j-mcp-server:${MCP_VERSION}"

    # Build auth proxy image (use same version tag for consistency)
    log_info "Building auth proxy image..."
    docker buildx build \
        --platform linux/amd64 \
        --tag mcp-auth-proxy:${MCP_VERSION} \
        --tag mcp-auth-proxy:latest \
        --load \
        "${SCRIPT_DIR}/nginx"
    log_success "Auth proxy image built: mcp-auth-proxy:${MCP_VERSION}"
}

# =============================================================================
# Docker Push (internal helper)
# =============================================================================

do_push() {
    log_step "Pushing Docker images to ACR"

    local acr_name
    acr_name=$(get_acr_name)

    if [[ -z "$acr_name" ]]; then
        log_error "Cannot determine ACR name. Deploy foundation infrastructure first."
        exit 1
    fi

    local acr_server="${acr_name}.azurecr.io"

    # Ensure MCP_VERSION is set (should be set by do_build)
    if [[ -z "${MCP_VERSION:-}" ]]; then
        MCP_VERSION=$(get_mcp_version)
    fi

    # Login to ACR
    log_info "Logging in to ACR: $acr_name"
    az acr login --name "$acr_name"

    # Tag and push MCP server image (both versioned and latest)
    log_info "Pushing Neo4j MCP Server image (version: $MCP_VERSION)..."
    docker tag neo4j-mcp-server:${MCP_VERSION} "${acr_server}/neo4j-mcp-server:${MCP_VERSION}"
    docker tag neo4j-mcp-server:${MCP_VERSION} "${acr_server}/neo4j-mcp-server:latest"
    docker push "${acr_server}/neo4j-mcp-server:${MCP_VERSION}"
    docker push "${acr_server}/neo4j-mcp-server:latest"
    log_success "MCP Server image pushed: ${MCP_VERSION}"

    # Tag and push auth proxy image (both versioned and latest)
    log_info "Pushing auth proxy image..."
    docker tag mcp-auth-proxy:${MCP_VERSION} "${acr_server}/mcp-auth-proxy:${MCP_VERSION}"
    docker tag mcp-auth-proxy:${MCP_VERSION} "${acr_server}/mcp-auth-proxy:latest"
    docker push "${acr_server}/mcp-auth-proxy:${MCP_VERSION}"
    docker push "${acr_server}/mcp-auth-proxy:latest"
    log_success "Auth proxy image pushed: ${MCP_VERSION}"
}

# =============================================================================
# Redeploy (build, push, update container app)
# =============================================================================

cmd_redeploy() {
    log_step "Redeploying container images"

    validate_neo4j_env

    # Get infrastructure info
    local acr_name
    acr_name=$(get_acr_name)

    if [[ -z "$acr_name" ]]; then
        log_error "Cannot determine ACR name. Run full deployment first: ./scripts/deploy.sh"
        exit 1
    fi

    local acr_server="${acr_name}.azurecr.io"

    # Step 1: Build images (sets MCP_VERSION)
    log_info "Step 1: Building container images..."
    do_build

    # Step 2: Push to ACR
    log_info "Step 2: Pushing images to ACR..."
    do_push

    # Step 3: Update Key Vault secrets
    log_info "Step 3: Updating credentials in Key Vault..."
    update_keyvault_secrets

    # Step 4: Update container app to use new images
    log_info "Step 4: Updating container app..."

    local app_name="${BASE_NAME:-neo4jmcp}-app-${ENVIRONMENT:-dev}"
    local mcp_image="${acr_server}/neo4j-mcp-server:${MCP_VERSION}"
    local proxy_image="${acr_server}/mcp-auth-proxy:${MCP_VERSION}"

    log_info "Deploying MCP server version: $MCP_VERSION"

    # Check if container app exists
    if ! az containerapp show --name "$app_name" --resource-group "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
        log_error "Container app '$app_name' not found. Run full deployment first: ./scripts/deploy.sh"
        exit 1
    fi

    # Update the MCP server container with the new image
    # Container name must match what's defined in infra/modules/container-app.bicep
    az containerapp update \
        --name "$app_name" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --container-name mcp-server \
        --image "$mcp_image" \
        --output none

    # Update the auth proxy container with the new image
    # Container name must match what's defined in infra/modules/container-app.bicep
    az containerapp update \
        --name "$app_name" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --container-name auth-proxy \
        --image "$proxy_image" \
        --output none

    log_success "Container app updated with version: $MCP_VERSION"

    # Generate access file (includes version info)
    generate_mcp_access

    echo ""
    log_success "Redeploy complete!"
    echo ""
    log_info "Deployed version: $MCP_VERSION"
    log_info "Test with: ./scripts/deploy.sh test"
    echo ""
}

# =============================================================================
# Infrastructure Deployment
# =============================================================================

deploy_foundation() {
    log_step "Deploying foundation infrastructure (ACR, Key Vault, etc.)"

    validate_neo4j_env
    lint_bicep

    # Export environment variables for bicepparam to read
    # Use placeholder images first to create ACR
    export MCP_SERVER_IMAGE="mcr.microsoft.com/hello-world:latest"
    export AUTH_PROXY_IMAGE="mcr.microsoft.com/hello-world:latest"

    # Get deployer's principal ID for Key Vault write access
    export DEPLOYER_PRINCIPAL_ID
    DEPLOYER_PRINCIPAL_ID=$(get_deployer_principal_id)
    log_info "Deployer principal ID: $DEPLOYER_PRINCIPAL_ID"

    # Deploy with placeholder images first to create ACR
    az deployment group create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --template-file "$INFRA_DIR/main.bicep" \
        --parameters "$INFRA_DIR/main.bicepparam" \
        --name "neo4j-mcp-foundation-$(date +%Y%m%d%H%M%S)" \
        --output none

    log_success "Foundation infrastructure deployed"
}

cmd_infra() {
    log_step "Deploying full infrastructure"

    ensure_resource_group
    validate_neo4j_env
    lint_bicep

    # Get ACR name
    local acr_name
    acr_name=$(get_acr_name)

    # Export environment variables for bicepparam to read
    export MCP_SERVER_IMAGE="mcr.microsoft.com/hello-world:latest"
    export AUTH_PROXY_IMAGE="mcr.microsoft.com/hello-world:latest"

    if [[ -n "$acr_name" ]]; then
        local acr_server="${acr_name}.azurecr.io"
        export MCP_SERVER_IMAGE="${acr_server}/neo4j-mcp-server:${IMAGE_TAG}"
        export AUTH_PROXY_IMAGE="${acr_server}/mcp-auth-proxy:${IMAGE_TAG}"
    else
        log_warn "ACR not found - using placeholder images"
    fi

    # Get deployer's principal ID for Key Vault write access
    export DEPLOYER_PRINCIPAL_ID
    DEPLOYER_PRINCIPAL_ID=$(get_deployer_principal_id)

    log_info "Deploying to resource group: $AZURE_RESOURCE_GROUP"
    log_info "Location: $AZURE_LOCATION"
    log_info "MCP Server image: $MCP_SERVER_IMAGE"
    log_info "Auth proxy image: $AUTH_PROXY_IMAGE"
    log_info "Deployer principal ID: $DEPLOYER_PRINCIPAL_ID"

    # Deploy Bicep template (parameters read from environment via bicepparam)
    az deployment group create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --template-file "$INFRA_DIR/main.bicep" \
        --parameters "$INFRA_DIR/main.bicepparam" \
        --name "neo4j-mcp-deploy-$(date +%Y%m%d%H%M%S)"

    log_success "Infrastructure deployed"

    # Generate access file
    generate_mcp_access
}

# =============================================================================
# Get Deployment Outputs
# =============================================================================

get_deployment_output() {
    local output_name="$1"
    local deployment_name
    deployment_name=$(az deployment group list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[?contains(name, 'neo4j-mcp')].name | [0]" \
        --output tsv 2>/dev/null || echo "")

    if [[ -n "$deployment_name" ]]; then
        az deployment group show \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --name "$deployment_name" \
            --query "properties.outputs.${output_name}.value" \
            --output tsv 2>/dev/null || echo ""
    fi
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

get_keyvault_name() {
    # First try to read from MCP_ACCESS.json
    if [[ -f "$MCP_ACCESS_FILE" ]] && command_exists jq; then
        local kv_name
        kv_name=$(jq -r '.keyVaultName // empty' "$MCP_ACCESS_FILE" 2>/dev/null)
        if [[ -n "$kv_name" ]]; then
            echo "$kv_name"
            return
        fi
    fi
    # Fallback: query Azure
    az keyvault list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[0].name" \
        --output tsv 2>/dev/null || echo ""
}

get_deployer_principal_id() {
    az ad signed-in-user show --query id -o tsv 2>/dev/null || echo ""
}

update_keyvault_secrets() {
    log_step "Updating Key Vault secrets"

    local kv_name
    kv_name=$(get_keyvault_name)

    if [[ -z "$kv_name" ]]; then
        log_error "Key Vault not found. Run full deployment first."
        exit 1
    fi

    log_info "Updating secrets in Key Vault: $kv_name"

    az keyvault secret set --vault-name "$kv_name" --name "neo4j-uri" --value "$NEO4J_URI" --output none
    az keyvault secret set --vault-name "$kv_name" --name "neo4j-username" --value "$NEO4J_USERNAME" --output none
    az keyvault secret set --vault-name "$kv_name" --name "neo4j-password" --value "$NEO4J_PASSWORD" --output none
    az keyvault secret set --vault-name "$kv_name" --name "neo4j-database" --value "$NEO4J_DATABASE" --output none
    az keyvault secret set --vault-name "$kv_name" --name "mcp-api-key" --value "$MCP_API_KEY" --output none

    log_success "Key Vault secrets updated"
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

    # Check if resource group exists
    if ! az group show --name "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warn "Resource group does not exist"
        return
    fi

    # List resources
    echo "Resources:"
    az resource list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[].{Name:name, Type:type}" \
        --output table

    echo ""

    # Get deployment outputs
    local deployment_name
    deployment_name=$(az deployment group list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[?contains(name, 'neo4j-mcp')].name | [0]" \
        --output tsv 2>/dev/null || echo "")

    if [[ -n "$deployment_name" ]]; then
        echo "Deployment Outputs ($deployment_name):"
        az deployment group show \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --name "$deployment_name" \
            --query "properties.outputs" \
            --output table 2>/dev/null || log_warn "Could not fetch outputs"
    fi

    # Container App status
    local app_url
    app_url=$(get_container_app_url)
    if [[ -n "$app_url" ]]; then
        echo ""
        echo "Container App URL: https://$app_url"
        echo "MCP Endpoint: https://$app_url/mcp"
    fi

    echo ""
}

# =============================================================================
# Test
# =============================================================================

cmd_test() {
    log_step "Running test client"

    # Check for Python
    if ! command_exists python3; then
        log_error "Python 3 is required for the test client"
        exit 1
    fi

    # Check for test client
    local test_client="$PROJECT_ROOT/client/test_client.py"
    if [[ ! -f "$test_client" ]]; then
        log_error "Test client not found at $test_client"
        exit 1
    fi

    # Run test client
    cd "$PROJECT_ROOT"
    python3 "$test_client"

    log_success "Tests completed"
}

# =============================================================================
# Generate MCP Access File
# =============================================================================

generate_mcp_access() {
    log_step "Generating MCP_ACCESS.json"

    local app_url
    app_url=$(get_container_app_url)

    local kv_name
    kv_name=$(az keyvault list --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[0].name" --output tsv 2>/dev/null || echo "")

    if [[ -z "$app_url" ]]; then
        log_warn "Container App URL not available yet"
        return
    fi

    # Ensure MCP_VERSION is set
    if [[ -z "${MCP_VERSION:-}" ]]; then
        MCP_VERSION=$(get_mcp_version)
    fi

    local deployed_at
    deployed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$MCP_ACCESS_FILE" << EOF
{
  "version": {
    "mcp_server": "${MCP_VERSION}",
    "deployed_at": "${deployed_at}"
  },
  "endpoint": "https://${app_url}",
  "keyVaultName": "${kv_name}",
  "mcp_path": "/mcp",
  "api_key": "${MCP_API_KEY}",
  "transport": "streamable-http",
  "authentication": {
    "type": "api_key",
    "header": "Authorization",
    "prefix": "Bearer",
    "alternative_header": "X-API-Key"
  },
  "example_curl": "curl -X POST 'https://${app_url}/mcp' -H 'Authorization: Bearer YOUR_API_KEY' -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"tools/list\",\"id\":1}'",
  "mcp_client_config": {
    "mcpServers": {
      "neo4j": {
        "url": "https://${app_url}/mcp",
        "transport": {
          "type": "streamable-http",
          "options": {
            "headers": {
              "Authorization": "Bearer YOUR_API_KEY"
            }
          }
        }
      }
    }
  }
}
EOF

    log_success "Generated MCP_ACCESS.json"
    log_info "Endpoint: https://${app_url}/mcp"
    log_info "Version: ${MCP_VERSION}"
}

# =============================================================================
# Version Info
# =============================================================================

cmd_version() {
    log_step "Version Information"

    # Show local MCP repo version
    local local_version
    local_version=$(get_mcp_version)
    echo ""
    echo "Local MCP repo version: $local_version"

    if [[ -n "${NEO4J_MCP_REPO:-}" ]] && [[ -d "$NEO4J_MCP_REPO/.git" ]]; then
        local commit_msg
        commit_msg=$(git -C "$NEO4J_MCP_REPO" log -1 --format="%s" 2>/dev/null)
        echo "  Latest commit: $commit_msg"
    fi

    # Show deployed version from MCP_ACCESS.json
    echo ""
    if [[ -f "$MCP_ACCESS_FILE" ]] && command_exists jq; then
        local deployed_version
        local deployed_at
        deployed_version=$(jq -r '.version.mcp_server // "unknown"' "$MCP_ACCESS_FILE" 2>/dev/null)
        deployed_at=$(jq -r '.version.deployed_at // "unknown"' "$MCP_ACCESS_FILE" 2>/dev/null)
        echo "Deployed version: $deployed_version"
        echo "  Deployed at: $deployed_at"

        # Compare versions
        echo ""
        if [[ "$local_version" == "$deployed_version" ]]; then
            log_success "Local and deployed versions match"
        else
            log_warn "Version mismatch: local=$local_version, deployed=$deployed_version"
            log_info "Run './scripts/deploy.sh redeploy' to update"
        fi
    else
        log_warn "MCP_ACCESS.json not found or jq not installed"
        log_info "Run './scripts/deploy.sh' to deploy"
    fi

    echo ""
}

# =============================================================================
# Cleanup
# =============================================================================

cmd_cleanup() {
    log_step "Cleanup"

    log_warn "This will delete ALL resources in resource group: $AZURE_RESOURCE_GROUP"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled"
        return
    fi

    log_info "Deleting resource group..."
    az group delete \
        --name "$AZURE_RESOURCE_GROUP" \
        --yes \
        --no-wait

    log_success "Resource group deletion initiated (running in background)"
    log_info "Note: Key Vault will be soft-deleted and recoverable for 7 days"

    # Clean up local files
    if [[ -f "$MCP_ACCESS_FILE" ]]; then
        rm -f "$MCP_ACCESS_FILE"
        log_info "Removed MCP_ACCESS.json"
    fi
}

# =============================================================================
# Full Deployment
# =============================================================================

cmd_deploy() {
    log_step "Full Deployment"

    validate_neo4j_env

    # Step 1: Ensure resource group
    ensure_resource_group

    # Step 2: Deploy foundation infrastructure (creates ACR)
    log_info "Phase 1: Deploying foundation infrastructure..."
    deploy_foundation

    # Step 3: Build Docker images
    log_info "Phase 2: Building container images..."
    do_build

    # Step 4: Push to ACR
    log_info "Phase 3: Pushing images to ACR..."
    do_push

    # Step 5: Deploy full infrastructure with correct images
    log_info "Phase 4: Deploying container app..."
    cmd_infra

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
    (none)            Full deployment (infra + build + push + deploy)
    redeploy          Rebuild containers, update credentials, and redeploy
    version           Show local and deployed version info
    lint              Lint Bicep templates (also runs automatically before deploy)
    infra             Deploy Bicep infrastructure only
    status            Show deployment status and outputs
    test              Run test client to validate deployment
    cleanup           Delete all resources and clean up
    help              Show this help message

ARCHITECTURE:
    The deployment creates two containers in a single Container App:
    - Auth Proxy (Nginx): Validates API keys, proxies to MCP server
    - MCP Server: Handles MCP protocol requests to Neo4j

    Traffic flow: Internet -> Ingress -> Auth Proxy -> MCP Server -> Neo4j

PREREQUISITES:
    - Azure CLI installed and authenticated (az login)
    - Docker with buildx support
    - .env file configured (copy from .env.sample)
    - Neo4j MCP repository cloned (NEO4J_MCP_REPO in .env)

EXAMPLES:
    # Full deployment (first time)
    ./scripts/deploy.sh

    # Rebuild and redeploy after code changes
    ./scripts/deploy.sh redeploy

    # Check version info (local vs deployed)
    ./scripts/deploy.sh version

    # Check deployment status
    ./scripts/deploy.sh status

    # Run tests
    ./scripts/deploy.sh test

    # Clean up resources
    ./scripts/deploy.sh cleanup

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local command="${1:-deploy}"

    # Load environment (except for help)
    if [[ "$command" != "help" && "$command" != "--help" && "$command" != "-h" ]]; then
        load_env
        validate_env
        check_prerequisites
    fi

    case "$command" in
        deploy|"")
            cmd_deploy
            ;;
        redeploy)
            cmd_redeploy
            ;;
        version)
            cmd_version
            ;;
        lint)
            lint_bicep
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
