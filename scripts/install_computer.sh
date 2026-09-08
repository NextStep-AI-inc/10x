#!/bin/bash
# Builds tenx-computer and installs it where the app and MCP configs expect it.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="${TENX_INSTALL_DEST:-$HOME/Library/Application Support/10x}"
mkdir -p "$DEST"
(cd ComputerKit && swift build -c release)
cp "ComputerKit/.build/release/tenx-computer" "$DEST/tenx-computer"
echo "installed: $DEST/tenx-computer"
