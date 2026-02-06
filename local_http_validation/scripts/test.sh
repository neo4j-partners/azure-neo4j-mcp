#!/bin/bash
# =============================================================================
# Run HTTP Mode Validation Tests
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

# Colors
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}INFO${NC} $1"; }

# Load environment if exists
if [[ -f "$ENV_FILE" ]]; then
    log_info "Loading environment from $ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
fi

# Set default endpoint
export MCP_ENDPOINT="${MCP_ENDPOINT:-http://localhost:8080}"

log_info "Testing MCP endpoint: $MCP_ENDPOINT"
log_info ""

# Run the test script with uv
cd "$PROJECT_ROOT"
uv run test_http_mode.py "$@"
