#!/usr/bin/env bash
# post-gdl-lint.sh — PostToolUse hook: auto-lint GDL files after Edit/Write
# Reads tool_input from stdin JSON, checks if file is *.gdl*, runs lint if so.
# Exits 0 immediately for non-GDL files (sub-millisecond).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source shared helpers (provides gdl_extract_file_path, gdl_json_hook_output)
source "$PLUGIN_ROOT/lib/session-context.sh"

# Read hook input from stdin
INPUT=$(cat)

# Extract file path from tool_input
FILE=$(gdl_extract_file_path "$INPUT")

# No file path — skip (shouldn't happen for Edit/Write but be safe)
[[ -z "$FILE" ]] && exit 0

# Only act on GDL files
case "$FILE" in
    *.gdl|*.gdls|*.gdlc|*.gdla|*.gdlm|*.gdld|*.gdlu) ;;
    *) exit 0 ;;
esac

# File must exist (Edit might have failed)
[[ ! -f "$FILE" ]] && exit 0

# Run lint and capture output for JSON response
lint_output=$(bash "$PLUGIN_ROOT/scripts/gdl-lint.sh" "$FILE" 2>&1) || true

if [[ -n "$lint_output" ]]; then
    ctx="GDL lint results for ${FILE##*/}:"$'\n'"${lint_output}"
    gdl_json_hook_output "PostToolUse" "$ctx"
else
    exit 0
fi
