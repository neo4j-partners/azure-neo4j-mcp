#!/bin/bash
#
# Neo4j MCP Server - Azure Cleanup Script
#
# Deletes all Azure resources created by the deployment.
# Can also clean up local generated files.
#
# Usage:
#   ./scripts/cleanup.sh              # Interactive cleanup
#   ./scripts/cleanup.sh --force      # Skip confirmation prompts
#   ./scripts/cleanup.sh --local-only # Only clean local files
#   ./scripts/cleanup.sh --help       # Show help
#

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
MCP_ACCESS_FILE="$PROJECT_ROOT/MCP_ACCESS.json"

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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Load environment variables from .env file
load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found at $ENV_FILE"
        log_error "Nothing to clean up or run ./scripts/setup-env.sh first"
        exit 1
    fi

    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
}

# =============================================================================
# Cleanup Functions
# =============================================================================

cleanup_local_files() {
    log_step "Cleaning up local generated files"

    local cleaned=false

    # MCP_ACCESS.json
    if [[ -f "$MCP_ACCESS_FILE" ]]; then
        rm -f "$MCP_ACCESS_FILE"
        log_success "Removed MCP_ACCESS.json"
        cleaned=true
    fi

    # Any generated ARM templates
    if [[ -f "$PROJECT_ROOT/infra/main.json" ]]; then
        rm -f "$PROJECT_ROOT/infra/main.json"
        log_success "Removed infra/main.json"
        cleaned=true
    fi

    # Docker build cache (optional)
    if [[ "$CLEAN_DOCKER" == "true" ]] && command_exists docker; then
        log_info "Cleaning Docker build cache..."
        docker builder prune -f 2>/dev/null || true
        log_success "Cleaned Docker build cache"
        cleaned=true
    fi

    if [[ "$cleaned" == "false" ]]; then
        log_info "No local files to clean"
    fi
}

cleanup_azure_resources() {
    log_step "Cleaning up Azure resources"

    # Check Azure CLI
    if ! command_exists az; then
        log_error "Azure CLI (az) is not installed"
        exit 1
    fi

    # Check if logged in
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure CLI"
        log_error "Run: az login"
        exit 1
    fi

    # Set subscription
    if [[ -n "$AZURE_SUBSCRIPTION_ID" ]]; then
        az account set --subscription "$AZURE_SUBSCRIPTION_ID" 2>/dev/null || {
            log_error "Failed to set subscription: $AZURE_SUBSCRIPTION_ID"
            exit 1
        }
    fi

    # Get Key Vault name before deleting resource group (for purging later)
    local kv_name=""
    local kv_location=""
    if az group show --name "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
        kv_name=$(az keyvault list \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --query "[0].name" \
            --output tsv 2>/dev/null || echo "")
        if [[ -n "$kv_name" ]]; then
            kv_location=$(az keyvault show \
                --name "$kv_name" \
                --resource-group "$AZURE_RESOURCE_GROUP" \
                --query "location" \
                --output tsv 2>/dev/null || echo "")
        fi
    fi

    # Check if resource group exists
    if ! az group show --name "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
        log_info "Resource group '$AZURE_RESOURCE_GROUP' does not exist"
        log_info "Nothing to clean up in Azure"
        # Still check for soft-deleted Key Vaults to purge
        purge_deleted_keyvaults
        return
    fi

    # Show what will be deleted
    echo ""
    log_warn "This will DELETE the following Azure resources:"
    echo ""
    echo "  Resource Group: $AZURE_RESOURCE_GROUP"
    echo "  Subscription:   $AZURE_SUBSCRIPTION_ID"
    if [[ -n "$kv_name" ]]; then
        echo "  Key Vault:      $kv_name (will be purged)"
    fi
    echo ""

    # List resources in the group
    log_info "Resources in group:"
    az resource list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[].{Name:name, Type:type}" \
        --output table 2>/dev/null || true

    echo ""

    # Confirm unless --force
    if [[ "$FORCE" != "true" ]]; then
        log_warn "This action cannot be undone!"
        echo ""
        read -rp "Type 'delete' to confirm: " confirm
        if [[ "$confirm" != "delete" ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi

    echo ""
    log_info "Deleting resource group: $AZURE_RESOURCE_GROUP"

    # If we have a Key Vault, we need to wait to purge it
    # Otherwise, respect the --no-wait flag
    if [[ -n "$kv_name" ]]; then
        log_info "Waiting for deletion to complete (required to purge Key Vault)..."
        az group delete \
            --name "$AZURE_RESOURCE_GROUP" \
            --yes

        log_success "Resource group deleted"

        # Purge Key Vault
        purge_keyvault "$kv_name" "$kv_location"
    elif [[ "$NO_WAIT" == "true" ]]; then
        az group delete \
            --name "$AZURE_RESOURCE_GROUP" \
            --yes \
            --no-wait

        log_success "Resource group deletion initiated (running in background)"
        log_info "Check status: az group show -n $AZURE_RESOURCE_GROUP"
    else
        az group delete \
            --name "$AZURE_RESOURCE_GROUP" \
            --yes

        log_success "Resource group deleted"
    fi

    # Check for any soft-deleted Key Vaults to purge
    purge_deleted_keyvaults
}

purge_keyvault() {
    local kv_name="$1"
    local kv_location="$2"

    log_info "Purging Key Vault: $kv_name"

    # Wait a moment for soft-delete to register
    sleep 2

    if az keyvault purge --name "$kv_name" --location "$kv_location" 2>/dev/null; then
        log_success "Key Vault '$kv_name' purged"
    else
        log_warn "Could not purge Key Vault '$kv_name' (may not be soft-deleted or already purged)"
    fi
}

purge_deleted_keyvaults() {
    log_step "Checking for soft-deleted Key Vaults to purge"

    # List soft-deleted Key Vaults
    local deleted_vaults
    deleted_vaults=$(az keyvault list-deleted \
        --query "[?contains(name, 'kv')].{name:name, location:properties.location}" \
        --output tsv 2>/dev/null || echo "")

    if [[ -z "$deleted_vaults" ]]; then
        log_info "No soft-deleted Key Vaults found"
        return
    fi

    echo ""
    log_warn "Found soft-deleted Key Vaults:"
    az keyvault list-deleted \
        --query "[?contains(name, 'kv')].{Name:name, Location:properties.location}" \
        --output table 2>/dev/null || true

    echo ""

    if [[ "$FORCE" != "true" ]]; then
        read -rp "Purge all soft-deleted Key Vaults? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log_info "Skipping Key Vault purge"
            return
        fi
    fi

    # Purge each vault
    while IFS=$'\t' read -r name location; do
        if [[ -n "$name" && -n "$location" ]]; then
            log_info "Purging: $name in $location"
            az keyvault purge --name "$name" --location "$location" 2>/dev/null || \
                log_warn "Failed to purge $name"
        fi
    done <<< "$deleted_vaults"

    log_success "Soft-deleted Key Vaults purged"
}

cleanup_acr_images() {
    log_step "Cleaning up ACR images"

    # Get ACR name
    local acr_name
    acr_name=$(az acr list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[0].name" \
        --output tsv 2>/dev/null || echo "")

    if [[ -z "$acr_name" ]]; then
        log_info "No ACR found in resource group"
        return
    fi

    log_info "Found ACR: $acr_name"

    # List repositories
    local repos
    repos=$(az acr repository list --name "$acr_name" --output tsv 2>/dev/null || echo "")

    if [[ -z "$repos" ]]; then
        log_info "No images in ACR"
        return
    fi

    echo "Images to delete:"
    echo "$repos" | while read -r repo; do
        echo "  - $repo"
    done

    if [[ "$FORCE" != "true" ]]; then
        read -rp "Delete all images? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log_info "Skipping ACR image cleanup"
            return
        fi
    fi

    echo "$repos" | while read -r repo; do
        log_info "Deleting repository: $repo"
        az acr repository delete \
            --name "$acr_name" \
            --repository "$repo" \
            --yes 2>/dev/null || true
    done

    log_success "ACR images cleaned up"
}

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
Neo4j MCP Server - Azure Cleanup Script

Deletes all Azure resources created by the deployment.

USAGE:
    ./scripts/cleanup.sh [OPTIONS]

OPTIONS:
    --force         Skip all confirmation prompts
    --no-wait       Don't wait for deletion (faster, but can't purge Key Vault)
    --local-only    Only clean local generated files (no Azure changes)
    --images-only   Only clean ACR images (keep infrastructure)
    --docker        Also clean Docker build cache
    --help          Show this help message

EXAMPLES:
    # Interactive cleanup (prompts for confirmation)
    ./scripts/cleanup.sh

    # Force cleanup without prompts (waits for completion)
    ./scripts/cleanup.sh --force

    # Only clean local files
    ./scripts/cleanup.sh --local-only

    # Clean ACR images but keep infrastructure
    ./scripts/cleanup.sh --images-only

    # Fast cleanup without waiting (won't purge Key Vault)
    ./scripts/cleanup.sh --force --no-wait

WHAT GETS DELETED:
    Azure Resources (in resource group):
      - Container App (if deployed)
      - Container Apps Environment
      - Azure Container Registry
      - Key Vault (soft-deleted then PURGED - permanent deletion)
      - Log Analytics Workspace
      - Managed Identity
      - All role assignments

    Key Vault Purging:
      - Key Vaults are soft-deleted by Azure by default
      - This script PURGES them (permanent deletion)
      - Allows reusing the same Key Vault name immediately
      - Also offers to purge any previously soft-deleted Key Vaults

    Local Files:
      - MCP_ACCESS.json
      - infra/main.json (if generated)

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse arguments
    FORCE="false"
    NO_WAIT="false"
    LOCAL_ONLY="false"
    IMAGES_ONLY="false"
    CLEAN_DOCKER="false"

    for arg in "$@"; do
        case "$arg" in
            --force|-f)
                FORCE="true"
                ;;
            --no-wait|-n)
                NO_WAIT="true"
                ;;
            --local-only|-l)
                LOCAL_ONLY="true"
                ;;
            --images-only|-i)
                IMAGES_ONLY="true"
                ;;
            --docker|-d)
                CLEAN_DOCKER="true"
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $arg"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done

    echo ""
    echo "======================================================================"
    echo "Neo4j MCP Server - Cleanup"
    echo "======================================================================"

    # Load environment
    load_env

    # Execute cleanup based on options
    if [[ "$LOCAL_ONLY" == "true" ]]; then
        cleanup_local_files
    elif [[ "$IMAGES_ONLY" == "true" ]]; then
        cleanup_acr_images
    else
        # Full cleanup
        cleanup_local_files
        cleanup_azure_resources
    fi

    echo ""
    echo "======================================================================"
    log_success "Cleanup complete"
    echo "======================================================================"
    echo ""
}

main "$@"
