#!/usr/bin/env bash
# session-start.sh — GDL SessionStart hook
# Reads config, scans artifacts, outputs JSON for Claude Code
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the context builder
source "$PLUGIN_ROOT/lib/session-context.sh"

# Resolve the project root (walks up to find .claude/greppable.local.md or git root)
PROJECT_ROOT=$(gdl_find_root ".")

# Build context for the resolved project root
prompt=$(gdl_session_context "$PROJECT_ROOT" 2>/dev/null) || true

# If no prompt to inject, exit cleanly
if [[ -z "$prompt" ]]; then
  exit 0
fi

# Output hookSpecificOutput JSON (jq handles all control-char escaping)
jq -n --arg ctx "$prompt" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
