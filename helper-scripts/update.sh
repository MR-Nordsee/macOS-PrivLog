#!/bin/bash

# Resolve the absolute directory path of this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Activate the virtual environment
source "$SCRIPT_DIR/api/bin/activate"

# List outdated packages in the virtual environment
pip list --outdated

# Upgrade the basic modules
pip install --upgrade pydantic
pip install --upgrade fastapi
pip install --upgrade aiosqlite
pip install --upgrade uvicorn

# Write the changes to the requirements. Please test before publish.
pip freeze > "$SCRIPT_DIR/requirements.txt"

# if you want a fresh start do this
# SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# VENV_DIR="$SCRIPT_DIR/api"
# python3 -m venv "$VENV_DIR"
# source "$SCRIPT_DIR/api/bin/activate"
# pip install pydantic fastapi aiosqlite uvicorn
# pip freeze > "$SCRIPT_DIR/requirements.txt"