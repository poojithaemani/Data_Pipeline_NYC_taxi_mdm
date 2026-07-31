# =================================================================
# services/database/config.py
#
# Description:
# This script is responsible for loading the application's
# configuration settings. It uses python-dotenv to load environment
# variables from a .env file, making them available throughout the app.
#
# A class-based approach is used for organization and clarity.
# =================================================================

import os
from dotenv import load_dotenv

# Load environment variables from a .env file in the project root.
# The find_dotenv() function will automatically search for the .env file.
from dotenv import find_dotenv
load_dotenv(find_dotenv())

class _Settings:
    """
    A simple class to hold and expose configuration settings.
    This provides a single, consistent object (`settings`) for other
    modules to import from.
    """
    DB_USER: str = os.getenv("DB_USER", "default_user")
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "default_password")
    DB_HOST: str = os.getenv("DB_HOST", "localhost")
    DB_PORT: int = int(os.getenv("DB_PORT", 5432))
    DB_NAME: str = os.getenv("DB_NAME", "default_db")

# Create a single instance of the settings to be imported by other modules.
settings = _Settings()
