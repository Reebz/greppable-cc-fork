#!/usr/bin/env bash
# gdla2gdld.sh — Convert GDLA API contract files to GDLD diagram format
# Usage: gdla2gdld.sh <api.gdla> [--id=DIAGRAM_ID] [--output=FILE]
set -euo pipefail

file=""
diagram_id=""
output_file=""

for arg in "$@"; do
    case "$arg" in
        --id=*) diagram_id="${arg#--id=}" ;;
        --output=*) output_file="${arg#--output=}" ;;
        -*) ;;
        *) [[ -z "$file" ]] && file="$arg" ;;
    esac
done

if [[ -z "$file" ]]; then
    echo "Usage: gdla2gdld.sh <api.gdla> [--id=DIAGRAM_ID] [--output=FILE]" >&2
    exit 1
fi

if [[ "$file" != "-" && ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdla" >&2
    exit 1
fi

if [[ -z "$diagram_id" ]]; then
    if [[ "$file" == "-" ]]; then
        diagram_id="api-diagram"
    else
        diagram_id=$(basename "$file" .gdla | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    fi
fi

input=$(cat "$file")

# If --output specified, redirect all output to a temp file for atomic write
if [[ -n "$output_file" ]]; then
    mkdir -p "$(dirname "$output_file")"
    _gdla2gdld_tmpout=$(mktemp "${output_file}.tmp.XXXXXX")
    trap "rm -f '${_gdla2gdld_tmpout}'" EXIT
    exec 3>&1 1>"$_gdla2gdld_tmpout"
fi

echo "@diagram|id:${diagram_id}|type:flow|purpose:Auto-generated from GDLA API contract"

# Sanitize string for use as GDLD id
sanitize_id() {
    echo "$1" | tr '/. {}*?[]' '--------' | tr -s '-' | sed 's/-$//'
}

current_group=""
seen_edges=";"
has_auth=false

while IFS= read -r line; do
    line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    [[ -z "$line" || "$line" == \#* || "$line" == //* ]] && continue

    if [[ "$line" == "@D "* ]]; then
        # @D service-name|description|version|base-url → @group
        rest="${line#@D }"
        name=$(echo "$rest" | sed 's/\\|/@@P@@/g' | cut -d'|' -f1)
        group_id=$(sanitize_id "$name")
        current_group="$group_id"
        echo "@group|id:${group_id}|label:${name}"

    elif [[ "$line" == "@S "* ]]; then
        # @S SchemaName|description → @node shape:box
        rest="${line#@S }"
        name=$(echo "$rest" | sed 's/\\|/@@P@@/g' | cut -d'|' -f1)
        if [[ -n "$current_group" ]]; then
            echo "@node|id:${name}|label:${name}|group:${current_group}|shape:box"
        else
            echo "@node|id:${name}|label:${name}|shape:box"
        fi

    elif [[ "$line" == "@EP "* ]]; then
        # @EP METHOD /path|description|responses|auth → @node shape:diamond
        rest="${line#@EP }"
        method_path=$(echo "$rest" | sed 's/\\|/@@P@@/g' | cut -d'|' -f1)
        ep_id=$(sanitize_id "$method_path")
        if [[ -n "$current_group" ]]; then
            echo "@node|id:${ep_id}|label:${method_path}|group:${current_group}|shape:diamond"
        else
            echo "@node|id:${ep_id}|label:${method_path}|shape:diamond"
        fi

        # Extract response schema refs → edges from endpoint to schemas
        responses=$(echo "$rest" | sed 's/\\|/@@P@@/g' | cut -d'|' -f3)
        if [[ -n "$responses" ]]; then
            # Parse 200:Pet[],404:Error
            IFS=',' read -ra resp_parts <<< "$responses"
            for resp in "${resp_parts[@]}"; do
                schema_ref="${resp#*:}"
                # Strip array suffix and whitespace
                schema_ref="${schema_ref%\[\]}"
                schema_ref=$(echo "$schema_ref" | tr -d ' ')
                if [[ -n "$schema_ref" ]]; then
                    edge_key="${ep_id}|${schema_ref}|returns"
                    case "$seen_edges" in
                        *";${edge_key};"*) ;;
                        *)
                            seen_edges="${seen_edges}${edge_key};"
                            echo "@edge|from:${ep_id}|to:${schema_ref}|label:returns|type:data"
                            ;;
                    esac
                fi
            done
        fi

        # Extract auth ref → edge from endpoint to auth node
        auth=$(echo "$rest" | sed 's/\\|/@@P@@/g' | cut -d'|' -f4)
        auth=$(echo "$auth" | tr -d ' ')
        if [[ -n "$auth" ]]; then
            edge_key="${ep_id}|auth-${auth}|requires"
            case "$seen_edges" in
                *";${edge_key};"*) ;;
                *)
                    seen_edges="${seen_edges}${edge_key};"
                    echo "@edge|from:${ep_id}|to:auth-${auth}|label:requires|type:flow"
                    ;;
            esac
        fi

    elif [[ "$line" == "@AUTH "* ]]; then
        # @AUTH scheme|description|header → @node in auth group
        rest="${line#@AUTH }"
        scheme=$(echo "$rest" | sed 's/\\|/@@P@@/g' | cut -d'|' -f1)
        [[ -z "$scheme" ]] && continue
        has_auth=true
        echo "@node|id:auth-${scheme}|label:${scheme}|group:auth|shape:box"

    elif [[ "$line" == "@R "* ]]; then
        # @R Source -> Target|relationship|via field → @edge
        rest="${line#@R }"
        arrow=$(echo "$rest" | sed 's/\\|/@@P@@/g' | cut -d'|' -f1)
        reltype=$(echo "$rest" | sed 's/\\|/@@P@@/g' | cut -d'|' -f2 | tr -d ' ' | sed 's/@@P@@/\\|/g')
        src=$(echo "$arrow" | sed 's/ *->.*$//' | tr -d ' ')
        tgt=$(echo "$arrow" | sed 's/^.*-> *//' | tr -d ' ')
        [[ -z "$src" || -z "$tgt" ]] && continue
        edge_key="${src}|${tgt}|${reltype}"
        case "$seen_edges" in
            *";${edge_key};"*) ;;
            *)
                seen_edges="${seen_edges}${edge_key};"
                echo "@edge|from:${src}|to:${tgt}|label:${reltype}|type:data"
                ;;
        esac

    elif [[ "$line" == "@PATH "* ]]; then
        # @PATH A -> B -> C|via /path → chain of edges
        rest="${line#@PATH }"
        chain=$(echo "$rest" | sed 's/\\|/@@P@@/g' | cut -d'|' -f1)
        # Split chain on ->
        prev=""
        remaining="$chain"
        while [[ -n "$remaining" ]]; do
            node=$(echo "$remaining" | sed 's/ *->.*$//' | tr -d ' ')
            if [[ -n "$prev" && -n "$node" ]]; then
                edge_key="${prev}|${node}|traversal"
                case "$seen_edges" in
                    *";${edge_key};"*) ;;
                    *)
                        seen_edges="${seen_edges}${edge_key};"
                        echo "@edge|from:${prev}|to:${node}|label:traversal|type:flow"
                        ;;
                esac
            fi
            prev="$node"
            case "$remaining" in
                *" -> "*) remaining="${remaining#*-> }" ;;
                *) remaining="" ;;
            esac
        done
    fi
done <<< "$input"

# Emit auth group if any @AUTH was found
if [[ "$has_auth" == true ]]; then
    echo "@group|id:auth|label:Authentication"
fi

# If --output specified, finalize atomic write
if [[ -n "$output_file" ]]; then
    exec 1>&3 3>&-
    mv "$_gdla2gdld_tmpout" "$output_file"
    echo "Wrote: $output_file" >&2
fi
