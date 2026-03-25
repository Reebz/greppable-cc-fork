#!/usr/bin/env bash
# pre-rules-check.sh — PreToolUse hook: inject matching rules.gdl records before Edit/Write
# Reads tool_input from stdin JSON, finds matching @rule records for the target file.
# Exits 0 immediately when: no rules.gdl exists, no matching rules, or non-source files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source shared helpers (provides gdl_extract_file_path, gdl_json_hook_output, gdl_find_root)
source "$PLUGIN_ROOT/lib/session-context.sh"

# Read hook input from stdin
INPUT=$(cat)

# Extract file path from tool_input
FILE=$(gdl_extract_file_path "$INPUT")

# No file path — skip
[[ -z "$FILE" ]] && exit 0

# Skip GDL files themselves (handled by post-gdl-lint)
case "$FILE" in
    *.gdl|*.gdls|*.gdlc|*.gdla|*.gdlm|*.gdld|*.gdlu) exit 0 ;;
esac

# Find project root (same resolution as session-start)
PROJECT_ROOT=$(gdl_find_root "$(dirname "$FILE" 2>/dev/null || echo ".")") || exit 0

# Check for rules.gdl — exit silently if none
RULES_FILE="${PROJECT_ROOT}/rules.gdl"
[[ ! -f "$RULES_FILE" ]] && exit 0

# Source gdl-tools for gdl_rules_for_file (suppress load banner)
source "$PLUGIN_ROOT/scripts/gdl-tools.sh" >/dev/null 2>&1

# Make file path relative to project root for scope matching
REL_PATH="${FILE#"${PROJECT_ROOT}/"}"

# Find matching rules
matching=$(gdl_rules_for_file "$REL_PATH" "$RULES_FILE" 2>/dev/null) || true

# No matching rules — exit silently
[[ -z "$matching" ]] && exit 0

# Count matching rules
rule_count=$(echo "$matching" | wc -l | tr -d ' ')

# Build context with the matching rules
ctx="[GDL Rules] ${rule_count} rule(s) apply to ${REL_PATH}:"$'\n'"${matching}"

# Output hookSpecificOutput JSON (bash escaping — no jq dependency)
gdl_json_hook_output "PreToolUse" "$ctx"
