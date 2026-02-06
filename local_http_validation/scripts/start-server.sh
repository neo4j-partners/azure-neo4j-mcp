#!/bin/bash
# =============================================================================
# Start Neo4j MCP Server in HTTP Mode (Local Docker)
# =============================================================================
# Pulls and runs the official mcp/neo4j Docker image with HTTP transport enabled
#
# IMPORTANT: In HTTP mode, the server does NOT use NEO4J_USERNAME/NEO4J_PASSWORD
# environment variables. Authentication is per-request via HTTP headers:
#   - Authorization: Bearer <token>  (for SSO/OIDC with Neo4j Enterprise)
#   - Authorization: Basic <base64>  (for username/password)
#
# The server passes credentials from the request directly to Neo4j.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

# Container settings
CONTAINER_NAME="neo4j-mcp-http-test"
IMAGE="mcp/neo4j"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}INFO${NC} $1"; }
log_success() { echo -e "${GREEN}SUCCESS${NC} $1"; }
log_warning() { echo -e "${YELLOW}WARNING${NC} $1"; }
log_error() { echo -e "${RED}ERROR${NC} $1"; }

# Load environment
if [[ -f "$ENV_FILE" ]]; then
    log_info "Loading environment from $ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
else
    log_warning ".env file not found, using defaults"
    log_warning "Copy .env.sample to .env and configure your Neo4j URI"
fi

# Set defaults - only URI and database needed for HTTP mode
# Authentication comes from per-request HTTP headers
NEO4J_URI="${NEO4J_URI:-bolt://host.docker.internal:7687}"
NEO4J_DATABASE="${NEO4J_DATABASE:-neo4j}"
MCP_HTTP_HOST="${MCP_HTTP_HOST:-0.0.0.0}"
MCP_HTTP_PORT="${MCP_HTTP_PORT:-8080}"

# Stop existing container if running
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Stopping existing container: $CONTAINER_NAME"
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# Pull latest image
log_info "Pulling latest image: $IMAGE"
docker pull "$IMAGE"

# Run container in HTTP mode
# NOTE: No NEO4J_USERNAME/NEO4J_PASSWORD - auth is per-request via HTTP headers
log_info "Starting container in HTTP mode..."
log_info "  NEO4J_URI: $NEO4J_URI"
log_info "  NEO4J_DATABASE: $NEO4J_DATABASE"
log_info "  HTTP Port: $MCP_HTTP_PORT"
log_info "  Auth: Per-request via Authorization header (Bearer or Basic)"

docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${MCP_HTTP_PORT}:${MCP_HTTP_PORT}" \
    -e "NEO4J_URI=$NEO4J_URI" \
    -e "NEO4J_DATABASE=$NEO4J_DATABASE" \
    -e "NEO4J_TRANSPORT_MODE=http" \
    -e "NEO4J_MCP_HTTP_HOST=$MCP_HTTP_HOST" \
    -e "NEO4J_MCP_HTTP_PORT=$MCP_HTTP_PORT" \
    -e "NEO4J_READ_ONLY=true" \
    -e "NEO4J_TELEMETRY=false" \
    "$IMAGE"

# Wait for container to start
log_info "Waiting for container to start..."
sleep 2

# Check if container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_success "Container started successfully!"
    log_info ""
    log_info "Container logs (last 20 lines):"
    docker logs "$CONTAINER_NAME" --tail 20
    log_info ""
    log_info "MCP endpoint should be available at: http://localhost:${MCP_HTTP_PORT}/mcp"
    log_info ""
    log_info "To view logs: docker logs -f $CONTAINER_NAME"
    log_info "To stop: ./scripts/stop-server.sh"
else
    log_error "Container failed to start!"
    log_error "Check logs: docker logs $CONTAINER_NAME"
    exit 1
fi
