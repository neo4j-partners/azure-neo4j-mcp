#!/bin/bash
#
# Bearer Token MCP Server - Azure Cleanup Script
#
# Deletes all Azure resources created by the deployment.
#
# Usage:
#   ./scripts/cleanup.sh              # Fast cleanup (no prompts)
#   ./scripts/cleanup.sh --wait       # Wait and purge Key Vault
#   ./scripts/cleanup.sh --interactive # Prompt before deleting
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

load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found at $ENV_FILE"
        log_error "Nothing to clean up"
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

    if [[ -f "$MCP_ACCESS_FILE" ]]; then
        rm -f "$MCP_ACCESS_FILE"
        log_success "Removed MCP_ACCESS.json"
        cleaned=true
    fi

    if [[ -f "$PROJECT_ROOT/infra/main.json" ]]; then
        rm -f "$PROJECT_ROOT/infra/main.json"
        log_success "Removed infra/main.json"
        cleaned=true
    fi

    if [[ "$cleaned" == "false" ]]; then
        log_info "No local files to clean"
    fi
}

cleanup_azure_resources() {
    log_step "Cleaning up Azure resources"

    if ! command_exists az; then
        log_error "Azure CLI (az) is not installed"
        exit 1
    fi

    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure CLI. Run: az login"
        exit 1
    fi

    if [[ -n "$AZURE_SUBSCRIPTION_ID" ]]; then
        az account set --subscription "$AZURE_SUBSCRIPTION_ID" 2>/dev/null || {
            log_error "Failed to set subscription: $AZURE_SUBSCRIPTION_ID"
            exit 1
        }
    fi

    # Get Key Vault name before deleting resource group (for purging)
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

    if ! az group show --name "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
        log_info "Resource group '$AZURE_RESOURCE_GROUP' does not exist"
        log_info "Nothing to clean up in Azure"
        return
    fi

    echo ""
    log_warn "This will DELETE the following Azure resources:"
    echo ""
    echo "  Resource Group: $AZURE_RESOURCE_GROUP"
    echo "  Subscription:   $AZURE_SUBSCRIPTION_ID"
    if [[ -n "$kv_name" ]]; then
        echo "  Key Vault:      $kv_name"
    fi
    echo ""

    log_info "Resources in group:"
    az resource list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "[].{Name:name, Type:type}" \
        --output table 2>/dev/null || true

    echo ""

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

    if [[ -n "$kv_name" && "$NO_WAIT" != "true" ]]; then
        log_info "Waiting for deletion to complete (required to purge Key Vault)..."
        az group delete \
            --name "$AZURE_RESOURCE_GROUP" \
            --yes

        log_success "Resource group deleted"
        purge_keyvault "$kv_name" "$kv_location"
    elif [[ "$NO_WAIT" == "true" ]]; then
        az group delete \
            --name "$AZURE_RESOURCE_GROUP" \
            --yes \
            --no-wait

        log_success "Resource group deletion initiated (running in background)"
        log_info "Check status: az group show -n $AZURE_RESOURCE_GROUP"
        if [[ -n "$kv_name" ]]; then
            log_warn "Key Vault '$kv_name' will be soft-deleted (auto-purges after 7 days)"
            log_info "To purge now: az keyvault purge --name $kv_name --location $kv_location"
        fi
    else
        az group delete \
            --name "$AZURE_RESOURCE_GROUP" \
            --yes

        log_success "Resource group deleted"
    fi
}

purge_keyvault() {
    local kv_name="$1"
    local kv_location="$2"

    if [[ -z "$kv_name" ]]; then
        return
    fi

    log_info "Purging Key Vault: $kv_name"
    sleep 2

    if az keyvault purge --name "$kv_name" --location "$kv_location" 2>/dev/null; then
        log_success "Key Vault '$kv_name' purged"
    else
        log_warn "Could not purge Key Vault '$kv_name' (may already be purged)"
    fi
}

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
Bearer Token MCP Server - Azure Cleanup Script

Deletes all Azure resources created by the deployment.
Default behavior: fast cleanup (no prompts, no waiting).

USAGE:
    ./scripts/cleanup.sh [OPTIONS]

OPTIONS:
    --interactive   Prompt for confirmation before deleting
    --wait          Wait for deletion and purge Key Vault immediately
    --local-only    Only clean local generated files
    --help          Show this help message

EXAMPLES:
    # Fast cleanup (default)
    ./scripts/cleanup.sh

    # Interactive with prompts
    ./scripts/cleanup.sh --interactive

    # Wait and purge Key Vault
    ./scripts/cleanup.sh --wait

    # Only clean local files
    ./scripts/cleanup.sh --local-only

WHAT GETS DELETED:
    Azure Resources:
      - Container App
      - Container Apps Environment
      - Key Vault (soft-deleted, purged with --wait)
      - Log Analytics Workspace

    Local Files:
      - MCP_ACCESS.json

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    FORCE="true"
    NO_WAIT="true"
    LOCAL_ONLY="false"

    for arg in "$@"; do
        case "$arg" in
            --force|-f)
                FORCE="true"
                ;;
            --interactive|-i)
                FORCE="false"
                ;;
            --no-wait|-n)
                NO_WAIT="true"
                ;;
            --wait|-w)
                NO_WAIT="false"
                ;;
            --local-only|-l)
                LOCAL_ONLY="true"
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
    echo "Bearer Token MCP Server - Cleanup"
    echo "======================================================================"

    load_env

    if [[ "$LOCAL_ONLY" == "true" ]]; then
        cleanup_local_files
    else
        cleanup_azure_resources
        cleanup_local_files
    fi

    echo ""
    echo "======================================================================"
    log_success "Cleanup complete"
    echo "======================================================================"
    echo ""
}

main "$@"
