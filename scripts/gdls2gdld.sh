#!/usr/bin/env bash
# gdls2gdld.sh - Convert GDLS schema files to GDLD diagram format
# Usage: gdls2gdld.sh <schema.gdls> [schema2.gdls ...] [--id=DIAGRAM_ID] [--output=FILE]
set -euo pipefail

files=()
diagram_id=""
output_file=""

for arg in "$@"; do
    case "$arg" in
        --id=*) diagram_id="${arg#--id=}" ;;
        --output=*) output_file="${arg#--output=}" ;;
        -) files+=("$arg") ;;
        -*) ;;
        *) files+=("$arg") ;;
    esac
done

if [[ ${#files[@]} -eq 0 ]]; then
    echo "Usage: gdls2gdld.sh <schema.gdls> [schema2.gdls ...] [--id=DIAGRAM_ID] [--output=FILE]" >&2
    exit 1
fi

# Enforce single-stdin constraint
stdin_count=0
for file in "${files[@]}"; do
    [[ "$file" == "-" ]] && stdin_count=$((stdin_count + 1))
done
if [[ "$stdin_count" -gt 1 ]]; then
    echo "Error: stdin '-' can only be specified once" >&2
    exit 1
fi

# Validate all files exist
for file in "${files[@]}"; do
    if [[ "$file" != "-" && ! -f "$file" ]]; then
        echo "Error: File not found: $file. Check path or run: ls *.gdls" >&2
        exit 1
    fi
done

# Default diagram ID from first filename
if [[ -z "$diagram_id" ]]; then
    if [[ "${files[0]}" == "-" ]]; then
        diagram_id="schema-diagram"
    else
        diagram_id=$(basename "${files[0]}" .gdls | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    fi
fi

# Concatenate all inputs
input=""
for file in "${files[@]}"; do
    input+="$(cat "$file")"$'\n'
done

# If --output specified, redirect all output to a temp file for atomic write
if [[ -n "$output_file" ]]; then
    mkdir -p "$(dirname "$output_file")"
    _gdls2gdld_tmpout=$(mktemp "${output_file}.tmp.XXXXXX")
    exec 3>&1 1>"$_gdls2gdld_tmpout"
fi

# Emit diagram record
echo "@diagram|id:${diagram_id}|type:flow|purpose:Auto-generated from GDLS schema"

# Capitalize first letter of a string (Bash 3 compatible)
capitalize() {
    local str="$1"
    local first
    first=$(echo "$str" | cut -c1 | tr '[:lower:]' '[:upper:]')
    local rest
    rest=$(echo "$str" | cut -c2-)
    echo "${first}${rest}"
}

# Use a temp file for table->domain mappings (Bash 3 compatible, no assoc arrays)
tmpmap=$(mktemp)
trap "rm -f '$tmpmap' '${_gdls2gdld_tmpout:-}'" EXIT

current_domain=""

# First pass: emit groups and build table->domain mapping
while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" ]] && continue
    case "$line" in
        '#'*|'//'*) continue ;;
    esac

    if [[ "$line" =~ ^@D\ ([^|]+)\| ]]; then
        current_domain="${BASH_REMATCH[1]}"
        local_label="$(capitalize "$current_domain")"
        echo "@group|id:${current_domain}|label:${local_label}"
    elif [[ "$line" =~ ^@T\ ([^|]+)\| ]]; then
        local_table="${BASH_REMATCH[1]}"
        echo "${local_table}=${current_domain}" >> "$tmpmap"
    fi
done <<< "$input"

# Lookup domain for a table from the temp mapping file
lookup_domain() {
    local table="$1"
    local result
    result=$(grep "^${table}=" "$tmpmap" 2>/dev/null | head -1 | cut -d'=' -f2) || true
    echo "$result"
}

# Warn if no tables found
if ! echo "$input" | grep -q '^@T '; then
    echo "Warning: No @T table definitions found in input" >&2
fi

# Emit nodes for each table (in order of appearance)
while IFS= read -r table; do
    [[ -z "$table" ]] && continue
    local_group="$(lookup_domain "$table")"
    if [[ -n "$local_group" ]]; then
        echo "@node|id:${table}|label:${table}|group:${local_group}|shape:box"
    else
        echo "@node|id:${table}|label:${table}|shape:box"
    fi
done <<< "$(echo "$input" | grep '^@T ' | sed 's/^@T \([^|]*\)|.*/\1/' || true)"

# Emit edges from @R relationship records
# Format: @R SOURCE.COL -> TARGET.COL|type|description
# Skip cross-system relationships (contain : in table reference)
while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Extract source and target: @R TABLE.COL -> TABLE.COL|type|desc
    local_rel="${line#@R }"

    # Skip cross-system (contains colon in entity references)
    local_arrow_part="${local_rel%%|*}"
    if echo "$local_arrow_part" | grep -qF ':'; then
        continue
    fi

    # Parse: SOURCE_TABLE.SOURCE_COL -> TARGET_TABLE.TARGET_COL
    local_source="${local_arrow_part%% -> *}"
    local_target="${local_arrow_part##* -> }"

    local_src_table="${local_source%%.*}"
    local_src_col="${local_source##*.}"
    local_tgt_table="${local_target%%.*}"

    # Determine edge type from relationship type
    local_type_part=$(echo "$local_rel" | cut -d'|' -f2)
    local_edge_type="data"
    case "$local_type_part" in
        fk) local_edge_type="data" ;;
        equivalent) local_edge_type="flow" ;;
        feeds) local_edge_type="flow" ;;
        derives) local_edge_type="data" ;;
    esac

    echo "@edge|from:${local_src_table}|to:${local_tgt_table}|label:${local_src_col} (${local_type_part})|type:${local_edge_type}"
done <<< "$(echo "$input" | grep '^@R ' || true)"

# If --output specified, finalize atomic write
if [[ -n "$output_file" ]]; then
    exec 1>&3 3>&-
    mv "$_gdls2gdld_tmpout" "$output_file"
    echo "Wrote: $output_file" >&2
fi
