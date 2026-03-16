#!/bin/bash
# Show MCP server logs
#
# Usage:
#   ./scripts/logs.sh                    # Show last 100 logs
#   ./scripts/logs.sh 50                 # Show last 50 logs
#   ./scripts/logs.sh --env .env.movies  # Show logs for a named deployment

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

# Parse --env flag and positional args
env_arg=""
LIMIT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)
            env_arg="${2:-}"
            shift 2
            ;;
        *)
            LIMIT="$1"
            shift
            ;;
    esac
done

resolve_env_file "${env_arg:-.env}"

# shellcheck source=/dev/null
source "$ENV_FILE"

# Match deploy.sh pattern - default to "dev" if not set
ENVIRONMENT="${ENVIRONMENT:-dev}"
BASE_NAME="${BASE_NAME:-neo4jmcp}"
LIMIT=${LIMIT:-100}

az containerapp logs show \
    --name "${BASE_NAME}-app-${ENVIRONMENT}" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --tail "$LIMIT"
