#!/usr/bin/env bash
# gdl-diff.sh — Semantic diff for GDL format files
# Usage: gdl-diff.sh <file-v1> <file-v2>
#        gdl-diff.sh <file> <git-ref>
# Note: -e (errexit) intentionally omitted; grep returns 1 on no-match which is expected
set -uo pipefail

# Source portable comm helper
SCRIPT_DIR_DIFF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_DIFF/lib/portability.sh"

TMP_CLEANUP=""
trap '[[ -n "$TMP_CLEANUP" ]] && rm -f "$TMP_CLEANUP"' EXIT

file1="${1:-}"
file2="${2:-}"

if [[ -z "$file1" || -z "$file2" ]]; then
  echo "Usage: gdl-diff.sh <file-v1> <file-v2>" >&2
  echo "       gdl-diff.sh <file> <git-ref>" >&2
  exit 1
fi

# Detect format from file extension
get_format() {
  case "$1" in
    *.gdls) echo "gdls" ;;
    *.gdlc) echo "gdlc" ;;
    *.gdld) echo "gdld" ;;
    *.gdlm) echo "gdlm" ;;
    *.gdlu) echo "gdlu" ;;
    *.gdla) echo "gdla" ;;
    *.gdl)  echo "gdl" ;;
    *) echo "unknown" ;;
  esac
}

# Extract a key:value field from a pipe-delimited line
_diff_extract_field() {
  local line="$1" key="$2"
  echo "$line" | sed 's/\\|/@@P@@/g' | awk -F'|' -v k="$key" '{
    for (i=1; i<=NF; i++) {
      idx = index($i, ":")
      if (idx > 0) {
        fk = substr($i, 1, idx-1)
        gsub(/^@[a-z]*/, "", fk)
        if (fk == k) { v = substr($i, idx+1); gsub(/@@P@@/, "|", v); print v; exit }
      }
    }
  }'
}

# Git ref mode: if file2 is not a file, treat it as a git ref
if [[ ! -f "$file2" ]]; then
  tmp_old=$(mktemp)
  TMP_CLEANUP="$tmp_old"
  # Get the file relative to repo root for git show
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  if [[ -n "$repo_root" ]]; then
    # Pure bash relpath: get absolute path then strip repo root prefix
    abs_path="$(cd "$(dirname "$file1")" && pwd)/$(basename "$file1")"
    rel_path="${abs_path#"$repo_root"/}"
    git_err=""
    git_err=$(git show "${file2}:${rel_path}" 2>&1 >"$tmp_old") || {
      echo "Error: Cannot retrieve '$rel_path' at ref '$file2': $git_err" >&2
      exit 1
    }
    # Swap: old version = git ref, new version = current file
    actual_v1="$tmp_old"
    actual_v2="$file1"
  else
    echo "Error: Not in a git repository, cannot use git ref mode" >&2
    exit 1
  fi
else
  actual_v1="$file1"
  actual_v2="$file2"
fi

format=$(get_format "$file1")
changes=0

# === GDLS diff ===
diff_gdls() {
  local v1="$1" v2="$2"

  # Parse tables and columns from a GDLS file into a flat string
  _parse_gdls() {
    local file="$1"
    local current_table=""
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      case "$line" in
        @T\ *)
          current_table=$(echo "$line" | cut -d'|' -f1 | sed 's/^@T //')
          echo "TABLE:$current_table"
          ;;
        @D\ *|@R\ *|@PATH\ *|@E\ *|@META\ *) ;;
        *)
          if [[ -n "$current_table" ]]; then
            local col_name col_type col_rest
            col_name=$(echo "$line" | cut -d'|' -f1)
            col_type=$(echo "$line" | cut -d'|' -f2)
            col_rest=$(echo "$line" | cut -d'|' -f3-)
            echo "COL:${current_table}.${col_name}=${col_type}|${col_rest}"
          fi
          ;;
      esac
    done < "$file"
  }

  local v1_data v2_data
  v1_data=$(_parse_gdls "$v1")
  v2_data=$(_parse_gdls "$v2")

  # Compare tables
  local v1_tables v2_tables
  v1_tables=$(echo "$v1_data" | grep "^TABLE:" | sed 's/^TABLE://' | sort || true)
  v2_tables=$(echo "$v2_data" | grep "^TABLE:" | sed 's/^TABLE://' | sort || true)

  # Added tables
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if ! echo "$v1_tables" | grep -qxF "$t"; then
      echo "  ADDED table: $t"
      changes=$((changes + 1))
      # Show columns of added table
      echo "$v2_data" | grep "^COL:${t}\." | sed 's/^COL:/    + /'
    fi
  done <<< "$v2_tables"

  # Removed tables
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if ! echo "$v2_tables" | grep -qxF "$t"; then
      echo "  REMOVED table: $t"
      changes=$((changes + 1))
    fi
  done <<< "$v1_tables"

  # Changed columns in shared tables
  local shared_tables
  shared_tables=$(_gdl_comm_sorted -12 "$v1_tables" "$v2_tables" || true)
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    local v1_cols v2_cols
    v1_cols=$(echo "$v1_data" | grep "^COL:${t}\." | sort || true)
    v2_cols=$(echo "$v2_data" | grep "^COL:${t}\." | sort || true)

    # Added columns
    while IFS= read -r col_line; do
      [[ -z "$col_line" ]] && continue
      local col_key
      col_key=$(echo "$col_line" | cut -d'=' -f1)
      if ! echo "$v1_cols" | grep -qF "$col_key="; then
        local col_name
        col_name=$(echo "$col_key" | sed "s/^COL:${t}\\.//")
        echo "  ADDED column: $t.$col_name"
        changes=$((changes + 1))
      fi
    done <<< "$v2_cols"

    # Removed columns
    while IFS= read -r col_line; do
      [[ -z "$col_line" ]] && continue
      local col_key
      col_key=$(echo "$col_line" | cut -d'=' -f1)
      if ! echo "$v2_cols" | grep -qF "$col_key="; then
        local col_name
        col_name=$(echo "$col_key" | sed "s/^COL:${t}\\.//")
        echo "  REMOVED column: $t.$col_name"
        changes=$((changes + 1))
      fi
    done <<< "$v1_cols"

    # Changed columns (same name, different definition)
    while IFS= read -r col_line; do
      [[ -z "$col_line" ]] && continue
      local col_key col_val
      col_key=$(echo "$col_line" | cut -d'=' -f1)
      col_val=$(echo "$col_line" | cut -d'=' -f2-)
      # Find matching column in v1
      local v1_match
      v1_match=$(echo "$v1_cols" | grep "^${col_key}=" || true)
      if [[ -n "$v1_match" ]]; then
        local v1_val
        v1_val=$(echo "$v1_match" | cut -d'=' -f2-)
        if [[ "$col_val" != "$v1_val" ]]; then
          local col_name
          col_name=$(echo "$col_key" | sed "s/^COL:${t}\\.//")
          echo "  CHANGED column: $t.$col_name"
          echo "    - $v1_val"
          echo "    + $col_val"
          changes=$((changes + 1))
        fi
      fi
    done <<< "$v2_cols"
  done <<< "$shared_tables"
}

# === GDL/GDLM/GDLU diff (key-value records keyed by id) ===
diff_records() {
  local v1="$1" v2="$2"

  # Parse records into id<TAB>full_line pairs (tab separator avoids = in IDs)
  _parse_records() {
    local file="$1"
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      local id_val
      id_val=$(_diff_extract_field "$line" "id")
      if [[ -n "$id_val" ]]; then
        printf '%s\t%s\n' "$id_val" "$line"
      fi
    done < "$file"
  }

  local v1_data v2_data
  v1_data=$(_parse_records "$v1")
  v2_data=$(_parse_records "$v2")

  local v1_ids v2_ids
  v1_ids=$(echo "$v1_data" | cut -d'	' -f1 | sort || true)
  v2_ids=$(echo "$v2_data" | cut -d'	' -f1 | sort || true)

  # Added records
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! echo "$v1_ids" | grep -qxF "$id"; then
      local new_line
      new_line=$(echo "$v2_data" | grep "^${id}	" | head -1 | cut -d'	' -f2- || true)
      echo "  ADDED [$id]: $new_line"
      changes=$((changes + 1))
    fi
  done <<< "$v2_ids"

  # Removed records
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! echo "$v2_ids" | grep -qxF "$id"; then
      local old_line
      old_line=$(echo "$v1_data" | grep "^${id}	" | head -1 | cut -d'	' -f2- || true)
      echo "  REMOVED [$id]: $old_line"
      changes=$((changes + 1))
    fi
  done <<< "$v1_ids"

  # Changed records (same ID, different content)
  local shared_ids
  shared_ids=$(_gdl_comm_sorted -12 "$v1_ids" "$v2_ids" || true)
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    local v1_line v2_line
    v1_line=$(echo "$v1_data" | grep "^${id}	" | head -1 | cut -d'	' -f2- || true)
    v2_line=$(echo "$v2_data" | grep "^${id}	" | head -1 | cut -d'	' -f2- || true)
    if [[ "$v1_line" != "$v2_line" ]]; then
      echo "  CHANGED [$id]:"
      # Show field-level diff
      local v1_fields v2_fields
      v1_fields=$(echo "$v1_line" | sed 's/\\|/@@P@@/g' | tr '|' '\n')
      v2_fields=$(echo "$v2_line" | sed 's/\\|/@@P@@/g' | tr '|' '\n')
      while IFS= read -r f2; do
        f2=$(echo "$f2" | sed 's/@@P@@/|/g')
        [[ -z "$f2" ]] && continue
        local f2_key f2_val
        f2_key=$(echo "$f2" | cut -d':' -f1)
        f2_val=$(echo "$f2" | cut -d':' -f2-)
        # Find same key in v1
        local f1_match
        f1_match=$(echo "$v1_fields" | sed 's/@@P@@/|/g' | grep "^${f2_key}:" | head -1 || true)
        if [[ -n "$f1_match" ]]; then
          local f1_val
          f1_val=$(echo "$f1_match" | cut -d':' -f2-)
          if [[ "$f1_val" != "$f2_val" ]]; then
            echo "    $f2_key: $f1_val -> $f2_val"
          fi
        else
          echo "    + $f2"
        fi
      done <<< "$v2_fields"
      changes=$((changes + 1))
    fi
  done <<< "$shared_ids"
}

# === GDLA diff (positional API contract format) ===
diff_gdla() {
  local v1="$1" v2="$2"

  _parse_gdla() {
    local file="$1"
    local current_schema=""
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      case "$line" in
        @S\ *)
          current_schema=$(echo "$line" | sed 's/\\|/@@P@@/g' | cut -d'|' -f1 | sed 's/^@S //')
          echo "SCHEMA:$current_schema"
          ;;
        @EP\ *)
          current_schema=""
          local ep_id ep_rest
          ep_id=$(echo "$line" | sed 's/\\|/@@P@@/g' | cut -d'|' -f1 | sed 's/^@EP //')
          ep_rest=$(echo "$line" | sed 's/\\|/@@P@@/g' | cut -d'|' -f2- | sed 's/@@P@@/|/g')
          echo "EP:${ep_id}=${ep_rest}"
          ;;
        @D\ *|@R\ *|@PATH\ *|@AUTH\ *|@ENUM\ *|@P\ *)
          current_schema=""
          ;;
        " "*)
          if [[ -n "$current_schema" ]]; then
            local field_name field_rest
            field_name=$(echo "$line" | sed 's/^ //' | cut -d'|' -f1)
            field_rest=$(echo "$line" | sed 's/^ //' | cut -d'|' -f2-)
            echo "FIELD:${current_schema}.${field_name}=${field_rest}"
          fi
          ;;
      esac
    done < "$file"
  }

  local v1_data v2_data
  v1_data=$(_parse_gdla "$v1")
  v2_data=$(_parse_gdla "$v2")

  # Compare schemas
  local v1_schemas v2_schemas
  v1_schemas=$(echo "$v1_data" | grep "^SCHEMA:" | sed 's/^SCHEMA://' | sort || true)
  v2_schemas=$(echo "$v2_data" | grep "^SCHEMA:" | sed 's/^SCHEMA://' | sort || true)

  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    if ! echo "$v1_schemas" | grep -qxF "$s"; then
      echo "  ADDED schema: $s"
      changes=$((changes + 1))
      echo "$v2_data" | grep "^FIELD:${s}\." | sed 's/^FIELD:/    + /'
    fi
  done <<< "$v2_schemas"

  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    if ! echo "$v2_schemas" | grep -qxF "$s"; then
      echo "  REMOVED schema: $s"
      changes=$((changes + 1))
    fi
  done <<< "$v1_schemas"

  # Compare fields in shared schemas
  local shared_schemas
  shared_schemas=$(_gdl_comm_sorted -12 "$v1_schemas" "$v2_schemas" || true)
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    local v1_fields v2_fields
    v1_fields=$(echo "$v1_data" | grep "^FIELD:${s}\." | sort || true)
    v2_fields=$(echo "$v2_data" | grep "^FIELD:${s}\." | sort || true)

    # Added fields
    while IFS= read -r field_line; do
      [[ -z "$field_line" ]] && continue
      local field_key
      field_key=$(echo "$field_line" | cut -d'=' -f1)
      if ! echo "$v1_fields" | grep -qF "$field_key="; then
        local field_name
        field_name=$(echo "$field_key" | sed "s/^FIELD:${s}\\.//")
        echo "  ADDED field: $s.$field_name"
        changes=$((changes + 1))
      fi
    done <<< "$v2_fields"

    # Removed fields
    while IFS= read -r field_line; do
      [[ -z "$field_line" ]] && continue
      local field_key
      field_key=$(echo "$field_line" | cut -d'=' -f1)
      if ! echo "$v2_fields" | grep -qF "$field_key="; then
        local field_name
        field_name=$(echo "$field_key" | sed "s/^FIELD:${s}\\.//")
        echo "  REMOVED field: $s.$field_name"
        changes=$((changes + 1))
      fi
    done <<< "$v1_fields"

    # Changed fields
    while IFS= read -r field_line; do
      [[ -z "$field_line" ]] && continue
      local field_key field_val
      field_key=$(echo "$field_line" | cut -d'=' -f1)
      field_val=$(echo "$field_line" | cut -d'=' -f2-)
      local v1_match
      v1_match=$(echo "$v1_fields" | grep "^${field_key}=" | head -1 || true)
      if [[ -n "$v1_match" ]]; then
        local v1_val
        v1_val=$(echo "$v1_match" | cut -d'=' -f2-)
        if [[ "$field_val" != "$v1_val" ]]; then
          local field_name
          field_name=$(echo "$field_key" | sed "s/^FIELD:${s}\\.//")
          echo "  CHANGED field: $s.$field_name"
          echo "    - $v1_val"
          echo "    + $field_val"
          changes=$((changes + 1))
        fi
      fi
    done <<< "$v2_fields"
  done <<< "$shared_schemas"

  # Compare endpoints
  local v1_eps v2_eps
  v1_eps=$(echo "$v1_data" | grep "^EP:" | sort || true)
  v2_eps=$(echo "$v2_data" | grep "^EP:" | sort || true)

  while IFS= read -r ep_line; do
    [[ -z "$ep_line" ]] && continue
    local ep_key
    ep_key=$(echo "$ep_line" | cut -d'=' -f1)
    if ! echo "$v1_eps" | grep -qF "$ep_key="; then
      echo "  ADDED endpoint: ${ep_key#EP:}"
      changes=$((changes + 1))
    fi
  done <<< "$v2_eps"

  while IFS= read -r ep_line; do
    [[ -z "$ep_line" ]] && continue
    local ep_key
    ep_key=$(echo "$ep_line" | cut -d'=' -f1)
    if ! echo "$v2_eps" | grep -qF "$ep_key="; then
      echo "  REMOVED endpoint: ${ep_key#EP:}"
      changes=$((changes + 1))
    fi
  done <<< "$v1_eps"

  # Compare changed endpoints
  local shared_ep_keys
  shared_ep_keys=$(_gdl_comm_sorted -12 "$(echo "$v1_eps" | cut -d'=' -f1 | sort)" "$(echo "$v2_eps" | cut -d'=' -f1 | sort)" || true)
  while IFS= read -r ep_key; do
    [[ -z "$ep_key" ]] && continue
    local v1_val v2_val
    v1_val=$(echo "$v1_eps" | grep "^${ep_key}=" | head -1 | cut -d'=' -f2-)
    v2_val=$(echo "$v2_eps" | grep "^${ep_key}=" | head -1 | cut -d'=' -f2-)
    if [[ "$v1_val" != "$v2_val" ]]; then
      echo "  CHANGED endpoint: ${ep_key#EP:}"
      echo "    - $v1_val"
      echo "    + $v2_val"
      changes=$((changes + 1))
    fi
  done <<< "$shared_ep_keys"
}

# === GDLC v2 diff (file-level) ===
diff_gdlc() {
  local v1="$1" v2="$2"

  # Extract @F file paths from each version
  local v1_files v2_files
  v1_files=$(grep "^@F " "$v1" 2>/dev/null | cut -d'|' -f1 | sed 's/^@F //' | sort || true)
  v2_files=$(grep "^@F " "$v2" 2>/dev/null | cut -d'|' -f1 | sed 's/^@F //' | sort || true)

  # Added files
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if ! echo "$v1_files" | grep -qxF "$f"; then
      echo "  ADDED file: $f"
      changes=$((changes + 1))
    fi
  done <<< "$v2_files"

  # Removed files
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if ! echo "$v2_files" | grep -qxF "$f"; then
      echo "  REMOVED file: $f"
      changes=$((changes + 1))
    fi
  done <<< "$v1_files"

  # Changed files (same path, different content)
  local shared_files
  shared_files=$(_gdl_comm_sorted -12 "$v1_files" "$v2_files" || true)
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    local v1_line v2_line
    v1_line=$(grep -F "@F ${f}|" "$v1" 2>/dev/null | head -1 || true)
    v2_line=$(grep -F "@F ${f}|" "$v2" 2>/dev/null | head -1 || true)
    if [[ "$v1_line" != "$v2_line" ]]; then
      echo "  CHANGED file: $f"
      echo "    - $v1_line"
      echo "    + $v2_line"
      changes=$((changes + 1))
    fi
  done <<< "$shared_files"
}

# === Dispatch ===
echo "Comparing $file1 vs $file2 ($format)..."

case "$format" in
  gdls) diff_gdls "$actual_v1" "$actual_v2" ;;
  gdlc) diff_gdlc "$actual_v1" "$actual_v2" ;;
  gdla) diff_gdla "$actual_v1" "$actual_v2" ;;
  gdl|gdlm|gdlu) diff_records "$actual_v1" "$actual_v2" ;;
  *)
    echo "Unsupported format for diff: $format" >&2
    exit 1
    ;;
esac

if (( changes == 0 )); then
  echo "No changes detected."
fi
