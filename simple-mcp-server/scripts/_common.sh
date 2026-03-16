#!/bin/bash
#
# Shared helpers for multi-deployment env file support
#
# Source this file AFTER setting PROJECT_ROOT.
# Then call: resolve_env_file [env_arg]
#
# Sets:
#   ENV_FILE        - absolute path to the .env file
#   MCP_ACCESS_FILE - absolute path to the corresponding MCP_ACCESS JSON file
#
# Naming convention:
#   .env           -> MCP_ACCESS.json
#   .env.movies    -> MCP_ACCESS.movies.json
#   .env.healthcare -> MCP_ACCESS.healthcare.json

resolve_env_file() {
    local env_arg="${1:-.env}"
    local project_root="${PROJECT_ROOT:-.}"

    # Resolve to absolute path if relative
    if [[ "$env_arg" != /* ]]; then
        ENV_FILE="$project_root/$env_arg"
    else
        ENV_FILE="$env_arg"
    fi

    # Derive MCP_ACCESS_FILE from env filename
    local env_basename
    env_basename=$(basename "$ENV_FILE")
    local suffix="${env_basename#.env}"

    if [[ -z "$suffix" ]]; then
        MCP_ACCESS_FILE="$project_root/MCP_ACCESS.json"
    else
        # ".movies" -> "movies"
        suffix="${suffix#.}"
        MCP_ACCESS_FILE="$project_root/MCP_ACCESS.${suffix}.json"
    fi
}
