#!/bin/bash
# Show MCP server logs
#
# Usage:
#   ./scripts/logs.sh          # Show last 100 logs
#   ./scripts/logs.sh 50       # Show last 50 logs

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../.env"

# Match deploy.sh pattern - default to "dev" if not set
ENVIRONMENT="${ENVIRONMENT:-dev}"
BASE_NAME="${BASE_NAME:-neo4jmcp}"
LIMIT=${1:-100}

az containerapp logs show \
    --name "${BASE_NAME}-app-${ENVIRONMENT}" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --tail "$LIMIT"
