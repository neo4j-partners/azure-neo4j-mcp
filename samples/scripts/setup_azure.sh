#!/bin/bash
# Configure Azure region for Neo4j MCP samples
# Run this after: az login --use-device-code && azd auth login --use-device-code

set -e

ENV_FILE=".env"

# Function to clean stale Azure config from .env
clean_env_file() {
    if [ ! -f "$ENV_FILE" ]; then
        return
    fi

    if grep -qE '^(AZURE_|SERVICE_)' "$ENV_FILE" 2>/dev/null; then
        echo ""
        echo "Found existing Azure configuration in .env."

        if grep -qE '^NEO4J_' "$ENV_FILE" 2>/dev/null; then
            grep '^NEO4J_' "$ENV_FILE" > "$ENV_FILE.neo4j.tmp"
            grep '^MCP_' "$ENV_FILE" >> "$ENV_FILE.neo4j.tmp" 2>/dev/null || true

            cat > "$ENV_FILE" << 'EOF'
# Neo4j and MCP Connection (preserved)

EOF
            cat "$ENV_FILE.neo4j.tmp" >> "$ENV_FILE"
            rm -f "$ENV_FILE.neo4j.tmp"

            echo "Removed stale Azure config (Neo4j/MCP settings preserved)"
        else
            grep -vE '^(AZURE_|SERVICE_)' "$ENV_FILE" > "$ENV_FILE.tmp" || true
            mv "$ENV_FILE.tmp" "$ENV_FILE"
            echo "Cleaned stale Azure configuration"
        fi
    fi
}

echo ""
echo "Azure AI Foundry serverless models require one of these regions:"
echo "  1) East US 2 (eastus2) - Recommended"
echo "  2) Sweden Central (swedencentral)"
echo "  3) West US 2 (westus2)"
echo "  4) West US 3 (westus3)"
echo ""
read -p "Select a region [1-4] (default: 1): " choice
choice=${choice:-1}

case $choice in
    1) REGION="eastus2" ;;
    2) REGION="swedencentral" ;;
    3) REGION="westus2" ;;
    4) REGION="westus3" ;;
    *)
        echo "Invalid choice. Please enter 1-4."
        exit 1
        ;;
esac

clean_env_file

if [ -d ".azure" ]; then
    echo "Removing existing .azure directory..."
    rm -rf .azure
fi

echo "Initializing azd environment..."
azd init -e dev

azd env set AZURE_LOCATION "$REGION"

echo ""
echo "Azure configured: $REGION"
echo ""
echo "Ready to deploy! Run:"
echo "   azd up"
echo "   uv run python setup_env.py"
