#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting installation for BIDS2DataLad Web Interface..."

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo "❌ 'uv' is not installed. Please install it first: https://github.com/astral-sh/uv"
    echo "You can install it via: curl -LsSf https://astral-sh/uv/install.sh | sh"
    exit 1
fi

echo "📦 Setting up virtual environment with uv..."
uv venv

# Activate venv for the current script
source .venv/bin/activate

echo "📥 Installing dependencies..."
uv pip install \
    flask \
    waitress \
    psutil \
    "flask-socketio"

echo "✅ Environment setup complete!"
echo "To start the web interface, run:"
echo "  source .venv/bin/activate"
echo "  python server.py"
