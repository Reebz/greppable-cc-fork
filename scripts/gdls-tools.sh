#!/usr/bin/env bash
# GDLS Tools - Bash helpers for schema navigation and relationship lookup
# Source this file: source scripts/gdls-tools.sh

# 1. gdls_columns - Extract column lines for a table
# Usage: gdls_columns <TABLE> [file]
gdls_columns() {
  local table="${1:-}"
  local file="${2:-}"
  if [[ -z "$table" ]]; then
    echo "Usage: gdls_columns <TABLE> [file.gdls]" >&2
    return 1
  fi
  if [[ -n "$file" ]]; then
    awk -v tbl="$table" '
      /^@T / && $0 ~ "^@T " tbl "\\|" { found=1; next }
      /^@/ { if (found) exit }
      found && /\|/ { print }
    ' "$file"
  else
    cat -- *.gdls 2>/dev/null | awk -v tbl="$table" '
      /^@T / && $0 ~ "^@T " tbl "\\|" { found=1; next }
      /^@/ { if (found) exit }
      found && /\|/ { print }
    '
  fi
}

# 2. gdls_fks - FK columns and their @R targets for a table
# Usage: gdls_fks <TABLE> [file]
gdls_fks() {
  local table="${1:-}"
  local file="${2:-}"
  if [[ -z "$table" ]]; then
    echo "Usage: gdls_fks <TABLE> [file.gdls]" >&2
    return 1
  fi
  # Get FK columns
  local fk_cols
  fk_cols=$(gdls_columns "$table" "$file" | grep "|FK|") || true
  if [[ -z "$fk_cols" ]]; then
    return 0
  fi
  # For each FK column, find matching @R record
  while IFS= read -r col_line; do
    local col_name
    col_name=$(echo "$col_line" | cut -d'|' -f1)
    local r_line
    if [[ -n "$file" ]]; then
      r_line=$(grep -F "@R ${table}.${col_name} -> " "$file" 2>/dev/null || true)
    else
      r_line=$(grep -F "@R ${table}.${col_name} -> " *.gdls 2>/dev/null || true)
    fi
    if [[ -n "$r_line" ]]; then
      echo "${col_line} => ${r_line}"
    else
      echo "${col_line}"
    fi
  done <<< "$fk_cols"
}

# 3. gdls_reverse_fk - What references this table?
# Usage: gdls_reverse_fk <TABLE> [file]
gdls_reverse_fk() {
  local table="${1:-}"
  local file="${2:-}"
  if [[ -z "$table" ]]; then
    echo "Usage: gdls_reverse_fk <TABLE> [file.gdls]" >&2
    return 1
  fi
  if [[ -n "$file" ]]; then
    grep "^@R " "$file" 2>/dev/null | grep -F -- "-> ${table}." || true
  else
    grep "^@R " *.gdls 2>/dev/null | grep -F -- "-> ${table}." || true
  fi
}

# 4. gdls_equivalents - Cross-system mappings for a table
# Usage: gdls_equivalents <TABLE> [file]
gdls_equivalents() {
  local table="${1:-}"
  local file="${2:-}"
  if [[ -z "$table" ]]; then
    echo "Usage: gdls_equivalents <TABLE> [file.gdls]" >&2
    return 1
  fi
  if [[ -n "$file" ]]; then
    grep "^@R " "$file" 2>/dev/null | grep -F "$table" | grep -F "|equivalent|" || true
  else
    grep "^@R " *.gdls 2>/dev/null | grep -F "$table" | grep -F "|equivalent|" || true
  fi
}

# 5. gdls_domain - Which domain contains a table?
# Usage: gdls_domain <TABLE> [file]
gdls_domain() {
  local table="${1:-}"
  local file="${2:-}"
  if [[ -z "$table" ]]; then
    echo "Usage: gdls_domain <TABLE> [file.gdls]" >&2
    return 1
  fi
  if [[ -n "$file" ]]; then
    awk -v tbl="$table" '
      /^@D / { domain=$0 }
      /^@T / && $0 ~ "^@T " tbl "\\|" { print domain; exit }
    ' "$file"
  else
    cat -- *.gdls 2>/dev/null | awk -v tbl="$table" '
      /^@D / { domain=$0 }
      /^@T / && $0 ~ "^@T " tbl "\\|" { print domain; exit }
    '
  fi
}

# 6. gdls_path - Find traversal paths between two entities
# Usage: gdls_path <FROM> <TO> [file]
gdls_path() {
  local from="${1:-}"
  local to="${2:-}"
  local file="${3:-}"
  if [[ -z "$from" || -z "$to" ]]; then
    echo "Usage: gdls_path <FROM> <TO> [file.gdls]" >&2
    return 1
  fi
  if [[ -n "$file" ]]; then
    grep "^@PATH " "$file" 2>/dev/null | grep -F "$from" | grep -F "$to" || true
  else
    grep "^@PATH " *.gdls 2>/dev/null | grep -F "$from" | grep -F "$to" || true
  fi
}

# 7. gdls_enums - Enum values for a table (or all enums)
# Usage: gdls_enums <TABLE> [file]
gdls_enums() {
  local table="${1:-}"
  local file="${2:-}"
  if [[ -z "$table" ]]; then
    echo "Usage: gdls_enums <TABLE> [file.gdls]" >&2
    return 1
  fi
  if [[ -n "$file" ]]; then
    grep "^@E " "$file" 2>/dev/null | grep -F "${table}." || true
  else
    grep "^@E " *.gdls 2>/dev/null | grep -F "${table}." || true
  fi
}

echo "GDLS tools loaded. Available: gdls_columns, gdls_fks, gdls_reverse_fk, gdls_equivalents, gdls_domain, gdls_path, gdls_enums"
