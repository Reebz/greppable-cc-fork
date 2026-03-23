#!/usr/bin/env bash
# gdl-verify.sh — Semantic validation for GDL artifacts
# Checks @PATH and @D references against the filesystem.
# Read-only — reports issues but never modifies files.
# Usage: gdl-verify.sh [--project-root=DIR] FILE...
#        gdl-verify.sh [--project-root=DIR] --all DIR
# Note: -e (errexit) intentionally omitted — we accumulate errors and report at end (matches gdl-lint.sh)
set -uo pipefail

usage() {
  echo "Usage: gdl-verify.sh [OPTIONS] FILE..."
  echo "       gdl-verify.sh [OPTIONS] --all DIR"
  echo ""
  echo "Validate GDL artifact references against the filesystem."
  echo "Read-only — reports orphaned references, never modifies files."
  echo ""
  echo "Options:"
  echo "  --project-root=DIR  Project root for resolving paths (default: git root)"
  echo "  --all DIR           Scan all .gdlc and .gdls files in DIR"
  echo "  -h, --help          Show this help"
  echo ""
  echo "Checks:"
  echo "  GDLC: @PATH file refs, @D module directory paths"
  echo "  GDLS: @PATH file refs"
  echo ""
  echo "Exit codes:"
  echo "  0  All references valid"
  echo "  1  Orphaned references found"
}

PROJECT_ROOT=""
ALL_MODE=false
ALL_DIR=""
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root=*) PROJECT_ROOT="${1#--project-root=}"; shift ;;
    --all) ALL_MODE=true; [[ $# -lt 2 ]] && { echo "Error: --all requires a directory argument" >&2; exit 1; }; ALL_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="$(pwd)"
fi

_tmp_cleanup=""
trap '[[ -n "$_tmp_cleanup" ]] && rm -f "$_tmp_cleanup"' EXIT

if [[ "$ALL_MODE" == "true" ]]; then
  # Portable: use temp file instead of process substitution
  _tmp_cleanup=$(mktemp)
  find "$ALL_DIR" -type f \( -name '*.gdlc' -o -name '*.gdls' \) 2>/dev/null | sort > "$_tmp_cleanup"
  while IFS= read -r f; do
    FILES+=("$f")
  done < "$_tmp_cleanup"
  rm -f "$_tmp_cleanup"
  _tmp_cleanup=""
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  if [[ "$ALL_MODE" == "true" ]]; then
    echo "No .gdlc or .gdls files found in $ALL_DIR"
    exit 0
  fi
  echo "Error: no files specified" >&2
  usage >&2
  exit 1
fi

errors=0

verify_file() {
  local file="$1"
  # Guard: skip if file doesn't exist
  if [[ ! -f "$file" ]]; then
    echo "Error: file not found: $file. Check path or run: ls *.gdl*" >&2
    errors=$((errors + 1))
    return
  fi
  local line_num=0
  local ext="${file##*.}"

  while IFS= read -r line; do
    line_num=$((line_num + 1))
    case "$line" in
      @PATH\ *)
        local ref_path="${line#@PATH }"
        ref_path=$(echo "$ref_path" | cut -d'|' -f1 | sed 's/[[:space:]]*$//')
        if [[ ! -e "$PROJECT_ROOT/$ref_path" ]]; then
          echo "  Error: $file:$line_num: @PATH $ref_path (not found)" >&2
          errors=$((errors + 1))
        fi
        ;;
      @D\ *)
        # Only check @D module paths in GDLC files
        if [[ "$ext" == "gdlc" ]]; then
          local mod_path
          mod_path=$(echo "$line" | sed 's/^@D //' | cut -d'|' -f1 | sed 's/[[:space:]]*$//')
          if [[ -n "$mod_path" && ! -d "$PROJECT_ROOT/$mod_path" && ! -f "$PROJECT_ROOT/$mod_path" ]]; then
            echo "  Error: $file:$line_num: @D $mod_path (directory not found)" >&2
            errors=$((errors + 1))
          fi
        fi
        ;;
    esac
  done < "$file"
}

for file in "${FILES[@]}"; do
  verify_file "$file"
done

if [[ $errors -eq 0 ]]; then
  echo "All references valid."
  exit 0
else
  echo "" >&2
  echo "Found $errors orphaned reference(s)." >&2
  exit 1
fi
