#!/usr/bin/env bash
# GDLA Tools - Bash helpers for API contract navigation
# Source this file: source scripts/gdla-tools.sh

# 1. gdla_endpoints - List @EP endpoint records
# Usage: gdla_endpoints [--method=GET] [file.gdla]
gdla_endpoints() {
  local method=""
  local file=""
  for arg in "$@"; do
    case "$arg" in
      --method=*) method="${arg#--method=}" ;;
      *) file="$arg" ;;
    esac
  done
  if [[ -n "$method" ]]; then
    if [[ -n "$file" ]]; then
      grep "^@EP ${method} " "$file" 2>/dev/null || true
    else
      grep "^@EP ${method} " -- *.gdla 2>/dev/null || true
    fi
  else
    if [[ -n "$file" ]]; then
      grep "^@EP " "$file" 2>/dev/null || true
    else
      grep "^@EP " -- *.gdla 2>/dev/null || true
    fi
  fi
}

# 2. gdla_params - Extract @P parameters for a specific endpoint
# Usage: gdla_params "METHOD /path" [file.gdla]
gdla_params() {
  local endpoint="${1:-}"
  local file="${2:-}"
  if [[ -z "$endpoint" ]]; then
    echo "Usage: gdla_params \"METHOD /path\" [file.gdla]" >&2
    return 1
  fi
  if [[ -n "$file" ]]; then
    awk -v ep="$endpoint" '
      /^@EP / { found = (index($0, "@EP " ep "|") == 1 || $0 == "@EP " ep); next }
      /^@P / && found { print; next }
      /^@[A-Z]/ { if (found) exit; found = 0 }
    ' "$file"
  else
    cat -- *.gdla 2>/dev/null | awk -v ep="$endpoint" '
      /^@EP / { found = (index($0, "@EP " ep "|") == 1 || $0 == "@EP " ep); next }
      /^@P / && found { print; next }
      /^@[A-Z]/ { if (found) exit; found = 0 }
    '
  fi
}

# 3. gdla_schemas - List @S schema records
# Usage: gdla_schemas [file.gdla]
gdla_schemas() {
  local file="${1:-}"
  if [[ -n "$file" ]]; then
    grep "^@S " "$file" 2>/dev/null || true
  else
    grep "^@S " -- *.gdla 2>/dev/null || true
  fi
}

# 4. gdla_schema_fields - Extract indented fields for a specific schema
# Usage: gdla_schema_fields <SchemaName> [file.gdla]
gdla_schema_fields() {
  local schema="${1:-}"
  local file="${2:-}"
  if [[ -z "$schema" ]]; then
    echo "Usage: gdla_schema_fields <SchemaName> [file.gdla]" >&2
    return 1
  fi
  if [[ -n "$file" ]]; then
    awk -v s="$schema" '
      /^@S / && $0 ~ "^@S " s "\\|" { found=1; next }
      /^@[A-Z]/ { if (found) exit; found=0 }
      found && /^ / { print }
    ' "$file"
  else
    cat -- *.gdla 2>/dev/null | awk -v s="$schema" '
      /^@S / && $0 ~ "^@S " s "\\|" { found=1; next }
      /^@[A-Z]/ { if (found) exit; found=0 }
      found && /^ / { print }
    '
  fi
}

# 5. gdla_auth - List @AUTH records
# Usage: gdla_auth [file.gdla]
gdla_auth() {
  local file="${1:-}"
  if [[ -n "$file" ]]; then
    grep "^@AUTH " "$file" 2>/dev/null || true
  else
    grep "^@AUTH " -- *.gdla 2>/dev/null || true
  fi
}

# 6. gdla_by_auth - Find endpoints that require a specific auth scheme
# Usage: gdla_by_auth <scheme> [file.gdla]
gdla_by_auth() {
  local scheme="${1:-}"
  local file="${2:-}"
  if [[ -z "$scheme" ]]; then
    echo "Usage: gdla_by_auth <scheme> [file.gdla]" >&2
    return 1
  fi
  if [[ -n "$file" ]]; then
    grep "^@EP " "$file" 2>/dev/null | grep "|${scheme}$" || true
  else
    grep "^@EP " -- *.gdla 2>/dev/null | grep "|${scheme}$" || true
  fi
}

# 7. gdla_relationships - List @R records
# Usage: gdla_relationships [file.gdla]
gdla_relationships() {
  local file="${1:-}"
  if [[ -n "$file" ]]; then
    grep "^@R " "$file" 2>/dev/null || true
  else
    grep "^@R " -- *.gdla 2>/dev/null || true
  fi
}

# 8. gdla_paths - List @PATH records
# Usage: gdla_paths [file.gdla]
gdla_paths() {
  local file="${1:-}"
  if [[ -n "$file" ]]; then
    grep "^@PATH " "$file" 2>/dev/null || true
  else
    grep "^@PATH " -- *.gdla 2>/dev/null || true
  fi
}

echo "GDLA tools loaded. Available: gdla_endpoints, gdla_params, gdla_schemas, gdla_schema_fields, gdla_auth, gdla_by_auth, gdla_relationships, gdla_paths"
