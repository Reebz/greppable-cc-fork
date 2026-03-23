#!/usr/bin/env bash
# GDLC Tools v2 - Bash helpers for file-level code index navigation
# Source this file: source scripts/gdlc-tools.sh

# 1. gdlc_files - List @F file records, optionally filtered by directory
# Usage: gdlc_files [DIR_PREFIX] [file.gdlc]
gdlc_files() {
  local dir_prefix="${1:-}"
  local file="${2:-}"
  if [[ -n "$dir_prefix" ]]; then
    # Anchor dir_prefix to path boundary (/) so "scripts" won't match "scripts-utils"
    if [[ -n "$file" ]]; then
      grep "^@F ${dir_prefix}/" "$file" 2>/dev/null || true
    else
      cat -- *.gdlc 2>/dev/null | grep "^@F ${dir_prefix}/" || true
    fi
  else
    if [[ -n "$file" ]]; then
      grep "^@F " "$file" 2>/dev/null || true
    else
      cat -- *.gdlc 2>/dev/null | grep "^@F " || true
    fi
  fi
}

# 2. gdlc_exports - Find files exporting a symbol (exact match in exports field)
# Usage: gdlc_exports <SYMBOL> [file.gdlc]
gdlc_exports() {
  local symbol="${1:-}"
  local file="${2:-}"
  if [[ -z "$symbol" ]]; then
    echo "Usage: gdlc_exports <SYMBOL> [file.gdlc]" >&2
    return 1
  fi
  # Exact match in comma-separated exports field (3rd pipe field).
  if [[ -n "$file" ]]; then
    grep "^@F " "$file" 2>/dev/null | awk -F'|' -v sym="$symbol" '{
      n=split($3,a,","); for(i=1;i<=n;i++){gsub(/^ +| +$/,"",a[i]); if(a[i]==sym){print;break}}
    }'
  else
    cat -- *.gdlc 2>/dev/null | grep "^@F " | awk -F'|' -v sym="$symbol" '{
      n=split($3,a,","); for(i=1;i<=n;i++){gsub(/^ +| +$/,"",a[i]); if(a[i]==sym){print;break}}
    }'
  fi
}

# 3. gdlc_imports - Find files that import a module (exact match in imports field)
# Usage: gdlc_imports <MODULE> [file.gdlc]
gdlc_imports() {
  local module="${1:-}"
  local file="${2:-}"
  if [[ -z "$module" ]]; then
    echo "Usage: gdlc_imports <MODULE> [file.gdlc]" >&2
    return 1
  fi
  # Exact match in comma-separated imports field (4th pipe field).
  if [[ -n "$file" ]]; then
    grep "^@F " "$file" 2>/dev/null | awk -F'|' -v mod="$module" '{
      n=split($4,a,","); for(i=1;i<=n;i++){gsub(/^ +| +$/,"",a[i]); if(a[i]==mod){print;break}}
    }'
  else
    cat -- *.gdlc 2>/dev/null | grep "^@F " | awk -F'|' -v mod="$module" '{
      n=split($4,a,","); for(i=1;i<=n;i++){gsub(/^ +| +$/,"",a[i]); if(a[i]==mod){print;break}}
    }'
  fi
}

# 4. gdlc_dirs - List all @D directory records
# Usage: gdlc_dirs [file.gdlc]
gdlc_dirs() {
  local file="${1:-}"
  if [[ -n "$file" ]]; then
    grep "^@D " "$file" 2>/dev/null || true
  else
    cat -- *.gdlc 2>/dev/null | grep "^@D " || true
  fi
}

# 5. gdlc_lang - List @F records for a specific language (exact match on 2nd field)
# Usage: gdlc_lang <LANG> [file.gdlc]
gdlc_lang() {
  local lang="${1:-}"
  local file="${2:-}"
  if [[ -z "$lang" ]]; then
    echo "Usage: gdlc_lang <LANG> [file.gdlc]" >&2
    return 1
  fi
  # Exact match on 2nd pipe field (lang) — 'ts' must NOT match 'tsx'
  if [[ -n "$file" ]]; then
    grep "^@F " "$file" 2>/dev/null | awk -F'|' -v lang="$lang" '$2 == lang'
  else
    cat -- *.gdlc 2>/dev/null | grep "^@F " | awk -F'|' -v lang="$lang" '$2 == lang'
  fi
}

echo "GDLC tools v2 loaded. Available: gdlc_files, gdlc_exports, gdlc_imports, gdlc_dirs, gdlc_lang"
