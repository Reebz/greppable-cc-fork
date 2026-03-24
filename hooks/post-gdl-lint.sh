#!/usr/bin/env bash
# post-gdl-lint.sh — PostToolUse hook: auto-lint GDL files after Edit/Write
# Reads tool_input from stdin JSON, checks if file is *.gdl*, runs lint if so.
# Exits 0 immediately for non-GDL files (sub-millisecond).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Read hook input from stdin
INPUT=$(cat)

# Extract file path from tool_input (|| true guards against missing jq or malformed JSON)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

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
    # Build full context string then escape for JSON
    ctx="GDL lint results for ${FILE##*/}:"$'\n'"${lint_output}"
    # jq handles all control-char escaping
    jq -n --arg ctx "$ctx" '{
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $ctx
      }
    }'
else
    exit 0
fi
