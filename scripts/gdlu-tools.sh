#!/usr/bin/env bash
# GDLU Tools - Bash helpers for unstructured content index querying
# Source this file: source scripts/gdlu-tools.sh

# Internal helper: extract a field value from a GDLU key-value record
# Handles escaped pipes and colons (same logic as _gdld_get_field)
_gdlu_get_field() {
  local record="$1"
  local key="$2"
  echo "$record" | sed 's/\\|/@@PIPE@@/g' | awk -F'|' -v key="$key" '
  {
    for (i=1; i<=NF; i++) {
      idx = index($i, ":")
      if (idx > 0) {
        k = substr($i, 1, idx-1)
        v = substr($i, idx+1)
        gsub(/^@/, "", k)
        if (k == key) {
          gsub(/\\\\/, "@@BACKSLASH@@", v)
          gsub(/@@PIPE@@/, "|", v)
          gsub(/\\:/, ":", v)
          gsub(/@@BACKSLASH@@/, "\\", v)
          print v
          exit
        }
      }
    }
  }'
}

# 1. gdlu_sources - List source documents, optionally filtered
# Usage: gdlu_sources [--type=TYPE] [--signal=SIGNAL] [--format=FMT] <file.gdlu>
gdlu_sources() {
  local type_filter="" signal_filter="" format_filter="" file=""
  for arg in "$@"; do
    case "$arg" in
      --type=*) type_filter="${arg#--type=}" ;;
      --signal=*) signal_filter="${arg#--signal=}" ;;
      --format=*) format_filter="${arg#--format=}" ;;
      *) file="$arg" ;;
    esac
  done
  if [[ -z "$file" ]]; then
    echo "Usage: gdlu_sources [--type=TYPE] [--signal=SIGNAL] [--format=FMT] <file.gdlu>" >&2
    return 1
  fi
  local lines
  lines=$(grep "^@source" "$file" 2>/dev/null) || true
  if [[ -z "$lines" ]]; then return 0; fi
  while IFS= read -r line; do
    if [[ -n "$type_filter" ]]; then
      local t; t=$(_gdlu_get_field "$line" "type")
      case ",$t," in *",$type_filter,"*) ;; *) continue ;; esac
    fi
    if [[ -n "$signal_filter" ]]; then
      local s; s=$(_gdlu_get_field "$line" "signal")
      [[ "$s" == "$signal_filter" ]] || continue
    fi
    if [[ -n "$format_filter" ]]; then
      local f; f=$(_gdlu_get_field "$line" "format")
      [[ "$f" == "$format_filter" ]] || continue
    fi
    local id; id=$(_gdlu_get_field "$line" "id")
    local path; path=$(_gdlu_get_field "$line" "path")
    local summary; summary=$(_gdlu_get_field "$line" "summary")
    echo "$id|$path|$summary"
  done <<< "$lines"
}

# 2. gdlu_sections - List sections for a given source ID
# Usage: gdlu_sections <SOURCE_ID> <file.gdlu>
gdlu_sections() {
  local source_id="${1:-}"
  local file="${2:-}"
  if [[ -z "$source_id" || -z "$file" ]]; then
    echo "Usage: gdlu_sections <SOURCE_ID> <file.gdlu>" >&2
    return 1
  fi
  local lines
  lines=$(grep "^@section" "$file" 2>/dev/null) || true
  if [[ -z "$lines" ]]; then return 0; fi
  while IFS= read -r line; do
    local src; src=$(_gdlu_get_field "$line" "source")
    [[ "$src" == "$source_id" ]] || continue
    local id; id=$(_gdlu_get_field "$line" "id")
    local loc; loc=$(_gdlu_get_field "$line" "loc")
    local title; title=$(_gdlu_get_field "$line" "title")
    echo "$id|$loc|$title"
  done <<< "$lines"
}

# 3. gdlu_extracts - List extractions, filtered by source, kind, or key
# Usage: gdlu_extracts [SOURCE_ID] [--kind=KIND] [--key=KEY] <file.gdlu>
gdlu_extracts() {
  local source_id="" kind_filter="" key_filter="" file=""
  for arg in "$@"; do
    case "$arg" in
      --kind=*) kind_filter="${arg#--kind=}" ;;
      --key=*) key_filter="${arg#--key=}" ;;
      --*) ;; # ignore unknown flags
      *)
        if [[ -z "$file" && -f "$arg" ]]; then
          file="$arg"
        elif [[ -z "$source_id" ]]; then
          source_id="$arg"
        else
          file="$arg"
        fi
        ;;
    esac
  done
  if [[ -z "$file" ]]; then
    echo "Usage: gdlu_extracts [SOURCE_ID] [--kind=KIND] [--key=KEY] <file.gdlu>" >&2
    return 1
  fi
  local lines
  lines=$(grep "^@extract" "$file" 2>/dev/null) || true
  if [[ -z "$lines" ]]; then return 0; fi
  while IFS= read -r line; do
    if [[ -n "$source_id" ]]; then
      local src; src=$(_gdlu_get_field "$line" "source")
      [[ "$src" == "$source_id" ]] || continue
    fi
    if [[ -n "$kind_filter" ]]; then
      local k; k=$(_gdlu_get_field "$line" "kind")
      [[ "$k" == "$kind_filter" ]] || continue
    fi
    if [[ -n "$key_filter" ]]; then
      local ky; ky=$(_gdlu_get_field "$line" "key")
      [[ "$ky" == "$key_filter" ]] || continue
    fi
    local id; id=$(_gdlu_get_field "$line" "id")
    local kind; kind=$(_gdlu_get_field "$line" "kind")
    local key; key=$(_gdlu_get_field "$line" "key")
    local value; value=$(_gdlu_get_field "$line" "value")
    echo "$id|$kind|$key|$value"
  done <<< "$lines"
}

# 4. gdlu_refs - Show cross-references for a source
# Usage: gdlu_refs <SOURCE_ID> <file.gdlu>
gdlu_refs() {
  local source_id="${1:-}"
  local file="${2:-}"
  if [[ -z "$source_id" || -z "$file" ]]; then
    echo "Usage: gdlu_refs <SOURCE_ID> <file.gdlu>" >&2
    return 1
  fi
  local lines
  lines=$(grep "^@source" "$file" 2>/dev/null) || true
  if [[ -z "$lines" ]]; then return 0; fi
  while IFS= read -r line; do
    local id; id=$(_gdlu_get_field "$line" "id")
    [[ "$id" == "$source_id" ]] || continue
    local refs; refs=$(_gdlu_get_field "$line" "refs")
    if [[ -n "$refs" ]]; then
      echo "$refs" | tr ',' '\n'
    fi
  done <<< "$lines"
}

echo "GDLU Tools loaded. Available: gdlu_sources, gdlu_sections, gdlu_extracts, gdlu_refs"
