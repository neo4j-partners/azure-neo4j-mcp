#!/bin/bash
# =============================================================================
# Stop Neo4j MCP Server Container
# =============================================================================

set -euo pipefail

CONTAINER_NAME="neo4j-mcp-http-test"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}INFO${NC} $1"; }
log_success() { echo -e "${GREEN}SUCCESS${NC} $1"; }
log_error() { echo -e "${RED}ERROR${NC} $1"; }

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Stopping container: $CONTAINER_NAME"
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    log_success "Container stopped and removed"
else
    log_info "Container not found: $CONTAINER_NAME"
fi
