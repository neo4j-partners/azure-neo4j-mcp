# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license. See LICENSE.md file in the project root for full license information.

from __future__ import annotations

import logging
import os
import sys

# Module-level cached logger instance
_app_logger: logging.Logger | None = None

# Default logger name used across the application
DEFAULT_LOGGER_NAME = "azureaiapp"


def configure_logging(
    log_file_name: str | None = None,
    logger_name: str = DEFAULT_LOGGER_NAME,
) -> logging.Logger:
    """
    Configure and return a logger with both stream (stdout) and optional file handlers.

    Args:
        log_file_name: The path to the log file. If provided, logs will also be written to this file.
        logger_name: The name of the logger to configure.

    Returns:
        The configured logger instance.
    """
    logger = logging.getLogger(logger_name)

    # Only configure if no handlers exist (avoid duplicate handlers)
    if not logger.handlers:
        logger.setLevel(logging.INFO)

        # Stream handler (stdout)
        stream_handler = logging.StreamHandler(sys.stdout)
        stream_handler.setLevel(logging.INFO)
        stream_formatter = logging.Formatter(
            "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
        )
        stream_handler.setFormatter(stream_formatter)
        logger.addHandler(stream_handler)

        # File handler if a log file is specified
        if log_file_name:
            file_handler = logging.FileHandler(log_file_name)
            file_handler.setLevel(logging.INFO)
            file_formatter = logging.Formatter(
                "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
            )
            file_handler.setFormatter(file_formatter)
            logger.addHandler(file_handler)

    return logger


def get_logger() -> logging.Logger:
    """
    Get the application logger, initializing it if necessary.

    This is the preferred way to get a logger in application modules.
    It ensures consistent configuration and avoids duplicate handlers.

    Returns:
        The configured application logger.
    """
    global _app_logger
    if _app_logger is None:
        log_file = os.getenv("APP_LOG_FILE", "") or None
        _app_logger = configure_logging(log_file)
    return _app_logger
