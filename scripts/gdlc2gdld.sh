#!/usr/bin/env bash
# gdlc2gdld.sh - Convert GDLC v2 code index to GDLD diagram format
# Usage: gdlc2gdld.sh <code.gdlc> [--id=DIAGRAM_ID] [--output=FILE]
set -euo pipefail

if [[ $# -lt 1 || "${1:-}" == "" ]]; then
    echo "Usage: gdlc2gdld.sh <code.gdlc> [--id=DIAGRAM_ID] [--output=FILE]" >&2
    exit 1
fi

file="${1:-}"
diagram_id=""
output_file=""

for arg in "$@"; do
    case "$arg" in
        --id=*) diagram_id="${arg#--id=}" ;;
        --output=*) output_file="${arg#--output=}" ;;
    esac
done

if [[ "$file" != "-" && ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdlc" >&2
    exit 1
fi

if [[ -z "$diagram_id" ]]; then
    if [[ "$file" == "-" ]]; then
        diagram_id="code-diagram"
    else
        diagram_id=$(basename "$file" .gdlc | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    fi
fi

input=$(cat "$file")

# Sanitize string for use as GDLD id (replace / and . with -)
sanitize_id() {
    echo "$1" | tr '/. ' '---' | tr -s '-'
}

# Pass 1: collect all file paths as newline-delimited string
# (bash 3.x compatible — no declare -a with initializers or +=)
all_fpaths=""
while IFS= read -r line; do
    line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    [[ -z "$line" || "$line" == \#* || "$line" == //* ]] && continue
    if [[ "$line" == "@F "* ]]; then
        fpath=$(echo "$line" | cut -d'|' -f1 | sed 's/^@F //')
        all_fpaths="${all_fpaths}${fpath}
"
    fi
done <<< "$input"

# Resolve import name to a sanitized node ID.
# Matches by basename (with or without extension) against all file paths.
resolve_import() {
    local import_name="$1"
    # Direct basename match (import name IS a basename with extension)
    while IFS= read -r fp; do
        [[ -z "$fp" ]] && continue
        local bn
        bn=$(basename "$fp")
        if [[ "$bn" == "$import_name" ]]; then
            sanitize_id "$fp"
            return
        fi
    done <<< "$all_fpaths"
    # Strip extension and match
    while IFS= read -r fp; do
        [[ -z "$fp" ]] && continue
        local bn
        bn=$(basename "$fp")
        local no_ext="${bn%.*}"
        if [[ "$no_ext" == "$import_name" ]]; then
            sanitize_id "$fp"
            return
        fi
    done <<< "$all_fpaths"
    # No match — external dependency, return empty
    echo ""
}

# Pass 2: emit diagram records
emit_diagram() {
    echo "@diagram|id:${diagram_id}|type:flow|purpose:Auto-generated from GDLC v2 code index"

    local current_group=""
    local seen_edges=";"

    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        [[ -z "$line" || "$line" == \#* || "$line" == //* ]] && continue

        if [[ "$line" == "@D "* ]]; then
            local rest="${line#@D }"
            local dpath="${rest%%|*}"
            local group_id
            group_id=$(sanitize_id "$dpath")
            current_group="$group_id"
            echo "@group|id:${group_id}|label:${dpath}"

        elif [[ "$line" == "@F "* ]]; then
            local fpath
            fpath=$(echo "$line" | cut -d'|' -f1 | sed 's/^@F //')
            local bname
            bname=$(basename "$fpath")
            local imports_field
            imports_field=$(echo "$line" | cut -d'|' -f4)

            local node_id
            node_id=$(sanitize_id "$fpath")
            if [[ -n "$current_group" ]]; then
                echo "@node|id:${node_id}|label:${bname}|group:${current_group}"
            else
                echo "@node|id:${node_id}|label:${bname}"
            fi

            # Emit edges for imports
            if [[ -n "$imports_field" ]]; then
                IFS=',' read -ra import_list <<< "$imports_field"
                local imp
                for imp in "${import_list[@]}"; do
                    imp=$(echo "$imp" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
                    [[ -z "$imp" ]] && continue
                    local target
                    target=$(resolve_import "$imp")
                    # Skip external dependencies (unresolved imports)
                    [[ -z "$target" ]] && continue
                    local edge_key="${node_id}|${target}"
                    case "$seen_edges" in
                        *";${edge_key};"*) ;;
                        *)
                            seen_edges="${seen_edges}${edge_key};"
                            echo "@edge|from:${node_id}|to:${target}|label:imports|type:data"
                            ;;
                    esac
                done
            fi
        fi
    done <<< "$input"
}

if [[ -n "$output_file" ]]; then
    tmpfile=$(mktemp "${output_file}.tmp.XXXXXX")
    emit_diagram > "$tmpfile" || { rm -f "$tmpfile"; exit 1; }
    mv "$tmpfile" "$output_file"
    echo "Wrote: $output_file" >&2
else
    emit_diagram
fi
