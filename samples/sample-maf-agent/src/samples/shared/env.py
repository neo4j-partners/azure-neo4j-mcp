# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license. See LICENSE.md file in the project root for full license information.

from __future__ import annotations

import json
import os


def get_env_file_path() -> str | None:
    """
    Get the path to the environment file to load.

    Priorities:
    1. If RUNNING_IN_PRODUCTION is set: returns None (uses system env vars)
    2. Checks for .env in samples/ directory (shared config)
    3. Checks for .env in sample-maf-agent/ (local config)
    4. Checks .azure/config.json to find the azd-managed .env

    Returns:
        Absolute path to the environment file, or None.
    """
    # In production, use system environment variables
    if os.getenv("RUNNING_IN_PRODUCTION"):
        return None

    # Get directory paths
    # shared/ -> samples_pkg (samples) -> src -> sample_root (sample-maf-agent) -> samples_dir
    current_dir = os.path.dirname(os.path.abspath(__file__))
    samples_pkg_dir = os.path.dirname(current_dir)  # src/samples
    src_dir = os.path.dirname(samples_pkg_dir)       # src
    sample_root = os.path.dirname(src_dir)           # sample-maf-agent/
    samples_dir = os.path.dirname(sample_root)       # samples/

    # Check for .env in samples/ directory (shared config - preferred)
    samples_env = os.path.join(samples_dir, '.env')
    if os.path.exists(samples_env):
        return samples_env

    # Check for .env in sample-maf-agent/ (local config)
    local_env = os.path.join(sample_root, '.env')
    if os.path.exists(local_env):
        return local_env

    # Fallback: Try to get path from samples/.azure/{environment}/.env (azd managed)
    try:
        config_path = os.path.join(samples_dir, '.azure', 'config.json')

        if os.path.exists(config_path):
            with open(config_path) as f:
                config = json.load(f)
                default_env = config.get('defaultEnvironment')

                if default_env:
                    env_file = os.path.join(samples_dir, '.azure', default_env, '.env')
                    if os.path.exists(env_file):
                        return env_file

    except Exception:
        pass

    return None
