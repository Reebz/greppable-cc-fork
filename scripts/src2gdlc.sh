#!/usr/bin/env bash
# src2gdlc.sh — Extract source code to GDLC v2 file-level index (multi-language)
# Usage: src2gdlc.sh <directory|file> [--output=FILE] [--recursive] [--lang=NAME] [--ignore-file=PATH]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC2GDLC_DIR="$SCRIPT_DIR/src2gdlc"

if ! command -v node &>/dev/null; then
    echo "Error: node is required. Install Node.js." >&2
    exit 1
fi

if [[ ! -d "$SRC2GDLC_DIR/node_modules" ]]; then
    echo "Installing src2gdlc dependencies..." >&2
    (cd "$SRC2GDLC_DIR" && npm install --silent) || {
        echo "Error: npm install failed in $SRC2GDLC_DIR" >&2
        exit 1
    }
fi

node "$SRC2GDLC_DIR/index.js" "$@"
