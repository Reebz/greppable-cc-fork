#!/usr/bin/env bash
# gdld2mermaid - Convert GDLD diagram files to Markdown with embedded Mermaid
#
# Usage: gdld2mermaid [OPTIONS] <file.gdld>
#
# Features:
#   - Flowchart diagrams (type: flow, pattern, concept, state, decision)
#   - Sequence diagrams with alt/else, par/and blocks
#   - Deployment diagrams with environments, nodes, instances
#   - @include file resolution with prefix and filtering
#   - --scenario application with inheritance
#   - --view filtering by tags, includes, excludes
#   - Context sections from GDLD-only records
#
# Requirements: bash 3.2+, awk (POSIX), sed, grep
# Tested on: macOS (bash 3.2), Linux (bash 4+)
#
# See: docs/plans/2026-02-02-gdld-to-mermaid-design.md

set -euo pipefail

# Default values
SCENARIO=""
VIEW=""
DIRECTION=""
OUTPUT=""
MMD=false
VALIDATE=false
QUIET=false

usage() {
    cat <<'EOF'
Usage: gdld2mermaid [OPTIONS] <file.gdld>

Convert GDLD diagram files to Markdown with embedded Mermaid diagrams.

Options:
  -s, --scenario=NAME    Apply scenario overrides (default: base diagram)
  -v, --view=NAME        Apply view filter (filter by tags, includes/excludes)
  -d, --direction=DIR    Override layout direction (TD, LR, RL, BT)
  -o, --output=FILE      Output file (default: <basename>.diagram.md)
  --mmd                  Also output standalone .mmd file
  --validate             Check diagram integrity without rendering
  -q, --quiet            Suppress warnings to stderr (errors still printed)
  -h, --help             Show this help

Examples:
  gdld2mermaid pipeline.gdld
  gdld2mermaid --scenario=production --mmd pipeline.gdld
  gdld2mermaid --view=security pipeline.gdld
  gdld2mermaid -o docs/pipeline.md pipeline.gdld
EOF
    exit 0
}

error() {
    echo "Error: $1" >&2
    exit 1
}

warn() {
    [[ "$QUIET" == "true" ]] || echo "Warning: $1" >&2
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--scenario)
            SCENARIO="$2"
            shift 2
            ;;
        --scenario=*)
            SCENARIO="${1#*=}"
            shift
            ;;
        -v|--view)
            VIEW="$2"
            shift 2
            ;;
        --view=*)
            VIEW="${1#*=}"
            shift
            ;;
        -d|--direction)
            DIRECTION="$2"
            shift 2
            ;;
        --direction=*)
            DIRECTION="${1#*=}"
            shift
            ;;
        -o|--output)
            OUTPUT="$2"
            shift 2
            ;;
        --output=*)
            OUTPUT="${1#*=}"
            shift
            ;;
        --mmd)
            MMD=true
            shift
            ;;
        --validate)
            VALIDATE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            error "Unknown option: $1. Run with -h for usage."
            ;;
        *)
            INPUT="$1"
            shift
            ;;
    esac
done

# Validate input file
if [[ -z "${INPUT:-}" ]]; then
    error "No input file specified. Use -h for help."
fi

if [[ ! -f "$INPUT" ]]; then
    error "File not found: $INPUT. Check path or run: ls *.gdld"
fi

# Set default output filename
if [[ -z "$OUTPUT" ]]; then
    OUTPUT="${INPUT%.gdld}.diagram.md"
fi

# === PARSING FUNCTIONS (using awk for bash 3 compatibility) ===

# Check if a field key exists in a GDLD record
# Usage: has_field "record" "key" && echo "exists"
has_field() {
    local record="$1"
    local key="$2"
    # Pre-process: replace \| with placeholder to avoid field splitting issues
    echo "$record" | sed 's/\\|/@@PIPE@@/g' | awk -F'|' -v key="$key" '
    BEGIN { found = 0 }
    {
        for (i=1; i<=NF; i++) {
            idx = index($i, ":")
            if (idx > 0) {
                k = substr($i, 1, idx-1)
                gsub(/^@/, "", k)
                if (k == key) { found = 1; exit }
            }
        }
    }
    END { exit (found ? 0 : 1) }'
}

# Get a field value from a GDLD record
# Usage: get_field "record" "key"
# Returns empty string if key not found or value is empty
get_field() {
    local record="$1"
    local key="$2"
    local result
    # Pre-process: replace \| with placeholder BEFORE splitting on |
    # This ensures escaped pipes don't break field splitting
    result=$(echo "$record" | sed 's/\\|/@@PIPE@@/g' | awk -F'|' -v key="$key" '
    {
        for (i=1; i<=NF; i++) {
            # Split field by first colon
            idx = index($i, ":")
            if (idx > 0) {
                k = substr($i, 1, idx-1)
                v = substr($i, idx+1)
                # Handle @ prefix on type field
                gsub(/^@/, "", k)
                if (k == key) {
                    # Unescape GDLD escapes
                    gsub(/\\\\/, "@@BACKSLASH@@", v)   # Temporarily replace \\ with placeholder
                    gsub(/@@PIPE@@/, "|", v)           # Restore escaped pipes
                    gsub(/\\:/, ":", v)                # Process \:
                    gsub(/@@BACKSLASH@@/, "\\", v)     # Restore backslashes
                    print v
                    exit
                }
            }
        }
    }') || {
        warn "Failed to parse field '$key' from record"
        echo ""
        return
    }
    echo "$result"
}

# Get @diagram metadata
get_diagram_line() {
    grep -m1 "^@diagram|" "$1" || true
}

# === INCLUDE RESOLUTION ===

# Track included files to detect circular includes
INCLUDED_FILES=()

# Check if file was already included
is_already_included() {
    local file="$1"
    local f
    # Handle empty array case
    [[ ${#INCLUDED_FILES[@]} -eq 0 ]] && return 1
    for f in "${INCLUDED_FILES[@]}"; do
        [[ "$f" == "$file" ]] && return 0
    done
    return 1
}

# Resolve @include directives and merge content
# Creates a temporary file with all includes resolved
# Usage: resolve_includes "input_file"
# Returns: path to resolved temporary file (caller must clean up)
resolve_includes() {
    local input_file="$1"
    local input_dir
    input_dir=$(dirname "$input_file")

    # Create temp file for resolved content
    local resolved_file
    resolved_file=$(mktemp)

    # Process line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "@include|"* ]]; then
            local inc_file
            inc_file=$(get_field "$line" "file")
            local inc_prefix
            inc_prefix=$(get_field "$line" "prefix")
            local inc_records
            inc_records=$(get_field "$line" "records")

            # Resolve relative path
            local inc_path
            if [[ "$inc_file" == /* ]]; then
                inc_path="$inc_file"
            else
                inc_path="$input_dir/$inc_file"
            fi

            # Check file exists
            if [[ ! -f "$inc_path" ]]; then
                warn "Include file not found: $inc_file (resolved to: $inc_path)"
                continue
            fi

            # Check for circular include
            local abs_path
            abs_path=$(cd "$(dirname "$inc_path")" && pwd)/$(basename "$inc_path")
            if is_already_included "$abs_path"; then
                warn "Circular include detected, skipping: $inc_file"
                continue
            fi
            INCLUDED_FILES+=("$abs_path")

            # Read included file, apply prefix, filter records
            while IFS= read -r inc_line || [[ -n "$inc_line" ]]; do
                # Skip @diagram from included files (only one diagram per output)
                [[ "$inc_line" == "@diagram|"* ]] && continue
                # Skip comments and empty lines
                [[ "$inc_line" == "#"* ]] && continue
                [[ -z "$inc_line" ]] && continue

                # Filter by record type if specified
                if [[ -n "$inc_records" ]]; then
                    local rec_type
                    rec_type=$(echo "$inc_line" | sed 's/^@\([^|]*\)|.*/\1/')
                    # Check if this record type is in the allowed list
                    if ! echo ",$inc_records," | grep -q ",$rec_type,"; then
                        continue
                    fi
                fi

                # Apply prefix to id, from, to, group, parent, node, env fields
                if [[ -n "$inc_prefix" ]]; then
                    # Escape sed metacharacters in prefix (\ first, then &, then /)
                    local safe_prefix
                    safe_prefix=$(printf '%s\n' "$inc_prefix" | sed -e 's/\\/\\\\/g' -e 's/[&]/\\&/g' -e 's/[/]/\\&/g')
                    inc_line=$(echo "$inc_line" | sed -E "
                        s/\|id:([^|]+)/|id:${safe_prefix}\1/g
                        s/\|from:([^|]+)/|from:${safe_prefix}\1/g
                        s/\|to:([^|]+)/|to:${safe_prefix}\1/g
                        s/\|group:([^|]+)/|group:${safe_prefix}\1/g
                        s/\|parent:([^|]+)/|parent:${safe_prefix}\1/g
                        s/\|node:([^|]+)/|node:${safe_prefix}\1/g
                        s/\|env:([^|]+)/|env:${safe_prefix}\1/g
                    ")
                fi

                echo "$inc_line" >> "$resolved_file"
            done < "$inc_path"
        else
            echo "$line" >> "$resolved_file"
        fi
    done < "$input_file"

    echo "$resolved_file"
}

# === COLLECTION FUNCTIONS ===
# Using indexed arrays (bash 3.2 compatible) with parallel array pattern

# Collect all @node records
# Sets: NODE_IDS[], NODE_LABELS[], NODE_SHAPES[], NODE_GROUPS[], NODE_STATUS[]
collect_nodes() {
    local file="$1"
    NODE_COUNT=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        NODE_IDS[$NODE_COUNT]=$(get_field "$line" "id")
        NODE_LABELS[$NODE_COUNT]=$(get_field "$line" "label")
        NODE_SHAPES[$NODE_COUNT]=$(get_field "$line" "shape")
        NODE_GROUPS[$NODE_COUNT]=$(get_field "$line" "group")
        NODE_STATUS[$NODE_COUNT]=$(get_field "$line" "status")
        NODE_TAGS[$NODE_COUNT]=$(get_field "$line" "tags")

        # Default label to id only if label key is not specified at all
        # (preserve explicitly empty labels)
        if ! has_field "$line" "label"; then
            NODE_LABELS[$NODE_COUNT]="${NODE_IDS[$NODE_COUNT]}"
        fi
        # Default shape to box if not specified
        if ! has_field "$line" "shape"; then
            NODE_SHAPES[$NODE_COUNT]="box"
        fi

        NODE_COUNT=$((NODE_COUNT + 1))
    done <<< "$(grep "^@node|" "$file" || true)"
}

# Collect all @edge records
# Sets: EDGE_FROM[], EDGE_TO[], EDGE_LABELS[], EDGE_STYLES[], EDGE_STATUS[], EDGE_BIDIR[]
collect_edges() {
    local file="$1"
    EDGE_COUNT=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        EDGE_FROM[$EDGE_COUNT]=$(get_field "$line" "from")
        EDGE_TO[$EDGE_COUNT]=$(get_field "$line" "to")
        EDGE_LABELS[$EDGE_COUNT]=$(get_field "$line" "label")
        EDGE_STYLES[$EDGE_COUNT]=$(get_field "$line" "style")
        EDGE_STATUS[$EDGE_COUNT]=$(get_field "$line" "status")
        EDGE_BIDIR[$EDGE_COUNT]=$(get_field "$line" "bidirectional")

        # Default style to solid
        if [[ -z "${EDGE_STYLES[$EDGE_COUNT]}" ]]; then
            EDGE_STYLES[$EDGE_COUNT]="solid"
        fi
        # Default bidir to false
        if [[ -z "${EDGE_BIDIR[$EDGE_COUNT]}" ]]; then
            EDGE_BIDIR[$EDGE_COUNT]="false"
        fi

        EDGE_COUNT=$((EDGE_COUNT + 1))
    done <<< "$(grep "^@edge|" "$file" || true)"
}

# Collect all @group records
# Sets: GROUP_IDS[], GROUP_LABELS[], GROUP_PARENTS[]
collect_groups() {
    local file="$1"
    GROUP_COUNT=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local gid
        gid=$(get_field "$line" "id")

        # Reject IDs containing commas (commas are used as list delimiters internally)
        if [[ "$gid" == *","* ]]; then
            echo "Error: Group ID '$gid' contains a comma — this is not supported; skipping" >&2
            continue
        fi

        GROUP_IDS[$GROUP_COUNT]="$gid"
        GROUP_LABELS[$GROUP_COUNT]=$(get_field "$line" "label")
        GROUP_PARENTS[$GROUP_COUNT]=$(get_field "$line" "parent")

        # Reject parent references containing commas
        if [[ "${GROUP_PARENTS[$GROUP_COUNT]}" == *","* ]]; then
            echo "Error: Group '$gid' parent '${GROUP_PARENTS[$GROUP_COUNT]}' contains a comma — this is not supported; clearing" >&2
            GROUP_PARENTS[$GROUP_COUNT]=""
        fi

        # Default label to id only if label key is not specified
        if ! has_field "$line" "label"; then
            GROUP_LABELS[$GROUP_COUNT]="${GROUP_IDS[$GROUP_COUNT]}"
        fi

        GROUP_COUNT=$((GROUP_COUNT + 1))
    done <<< "$(grep "^@group|" "$file" 2>/dev/null || true)"
}

# Collect deployment diagram records
# Sets: DEPLOY_ENV_IDS[], DEPLOY_ENV_LABELS[]
#       DEPLOY_NODE_IDS[], DEPLOY_NODE_LABELS[], DEPLOY_NODE_ENVS[], DEPLOY_NODE_PARENTS[]
#       DEPLOY_INST_IDS[], DEPLOY_INST_COMPS[], DEPLOY_INST_NODES[], DEPLOY_INST_COUNTS[]
#       INFRA_NODE_IDS[], INFRA_NODE_LABELS[], INFRA_NODE_PARENTS[]
collect_deployment() {
    local file="$1"

    # @deploy-env records
    DEPLOY_ENV_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        DEPLOY_ENV_IDS[$DEPLOY_ENV_COUNT]=$(get_field "$line" "id")
        DEPLOY_ENV_LABELS[$DEPLOY_ENV_COUNT]=$(get_field "$line" "label")
        if ! has_field "$line" "label"; then
            DEPLOY_ENV_LABELS[$DEPLOY_ENV_COUNT]="${DEPLOY_ENV_IDS[$DEPLOY_ENV_COUNT]}"
        fi
        DEPLOY_ENV_COUNT=$((DEPLOY_ENV_COUNT + 1))
    done <<< "$(grep "^@deploy-env|" "$file" 2>/dev/null || true)"

    # @deploy-node records
    DEPLOY_NODE_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        DEPLOY_NODE_IDS[$DEPLOY_NODE_COUNT]=$(get_field "$line" "id")
        DEPLOY_NODE_LABELS[$DEPLOY_NODE_COUNT]=$(get_field "$line" "label")
        DEPLOY_NODE_ENVS[$DEPLOY_NODE_COUNT]=$(get_field "$line" "env")
        DEPLOY_NODE_PARENTS[$DEPLOY_NODE_COUNT]=$(get_field "$line" "parent")
        if ! has_field "$line" "label"; then
            DEPLOY_NODE_LABELS[$DEPLOY_NODE_COUNT]="${DEPLOY_NODE_IDS[$DEPLOY_NODE_COUNT]}"
        fi
        DEPLOY_NODE_COUNT=$((DEPLOY_NODE_COUNT + 1))
    done <<< "$(grep "^@deploy-node|" "$file" 2>/dev/null || true)"

    # @deploy-instance records
    DEPLOY_INST_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        DEPLOY_INST_IDS[$DEPLOY_INST_COUNT]=$(get_field "$line" "id")
        DEPLOY_INST_COMPS[$DEPLOY_INST_COUNT]=$(get_field "$line" "component")
        DEPLOY_INST_NODES[$DEPLOY_INST_COUNT]=$(get_field "$line" "node")
        DEPLOY_INST_COUNTS[$DEPLOY_INST_COUNT]=$(get_field "$line" "instances")
        # Default instances to 1
        if [[ -z "${DEPLOY_INST_COUNTS[$DEPLOY_INST_COUNT]}" ]]; then
            DEPLOY_INST_COUNTS[$DEPLOY_INST_COUNT]="1"
        fi
        DEPLOY_INST_COUNT=$((DEPLOY_INST_COUNT + 1))
    done <<< "$(grep "^@deploy-instance|" "$file" 2>/dev/null || true)"

    # @infra-node records
    INFRA_NODE_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        INFRA_NODE_IDS[$INFRA_NODE_COUNT]=$(get_field "$line" "id")
        INFRA_NODE_LABELS[$INFRA_NODE_COUNT]=$(get_field "$line" "label")
        INFRA_NODE_PARENTS[$INFRA_NODE_COUNT]=$(get_field "$line" "node")
        if ! has_field "$line" "label"; then
            INFRA_NODE_LABELS[$INFRA_NODE_COUNT]="${INFRA_NODE_IDS[$INFRA_NODE_COUNT]}"
        fi
        INFRA_NODE_COUNT=$((INFRA_NODE_COUNT + 1))
    done <<< "$(grep "^@infra-node|" "$file" 2>/dev/null || true)"
}

# === CONTEXT COLLECTION ===
# Collect all context records for markdown sections

collect_context() {
    local file="$1"

    # @use-when records
    USE_WHEN_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        USE_WHEN_CONDITIONS[$USE_WHEN_COUNT]=$(get_field "$line" "condition")
        USE_WHEN_THRESHOLDS[$USE_WHEN_COUNT]=$(get_field "$line" "threshold")
        USE_WHEN_DETAILS[$USE_WHEN_COUNT]=$(get_field "$line" "detail")
        USE_WHEN_COUNT=$((USE_WHEN_COUNT + 1))
    done <<< "$(grep "^@use-when|" "$file" 2>/dev/null || true)"

    # @use-not records
    USE_NOT_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        USE_NOT_CONDITIONS[$USE_NOT_COUNT]=$(get_field "$line" "condition")
        USE_NOT_REASONS[$USE_NOT_COUNT]=$(get_field "$line" "reason")
        USE_NOT_COUNT=$((USE_NOT_COUNT + 1))
    done <<< "$(grep "^@use-not|" "$file" 2>/dev/null || true)"

    # @component records
    COMP_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        COMP_NAMES[$COMP_COUNT]=$(get_field "$line" "name")
        COMP_FILES[$COMP_COUNT]=$(get_field "$line" "file")
        COMP_DOES[$COMP_COUNT]=$(get_field "$line" "does")
        COMP_COUNT=$((COMP_COUNT + 1))
    done <<< "$(grep "^@component|" "$file" 2>/dev/null || true)"

    # @config records
    CONFIG_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        CONFIG_PARAMS[$CONFIG_COUNT]=$(get_field "$line" "param")
        CONFIG_VALUES[$CONFIG_COUNT]=$(get_field "$line" "value")
        CONFIG_NOTES[$CONFIG_COUNT]=$(get_field "$line" "note")
        CONFIG_COUNT=$((CONFIG_COUNT + 1))
    done <<< "$(grep "^@config|" "$file" 2>/dev/null || true)"

    # @gotcha records
    GOTCHA_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        GOTCHA_ISSUES[$GOTCHA_COUNT]=$(get_field "$line" "issue")
        GOTCHA_DETAILS[$GOTCHA_COUNT]=$(get_field "$line" "detail")
        GOTCHA_FIXES[$GOTCHA_COUNT]=$(get_field "$line" "fix")
        GOTCHA_COUNT=$((GOTCHA_COUNT + 1))
    done <<< "$(grep "^@gotcha|" "$file" 2>/dev/null || true)"

    # @recovery records
    RECOVERY_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        RECOVERY_ISSUES[$RECOVERY_COUNT]=$(get_field "$line" "issue")
        RECOVERY_MEANS[$RECOVERY_COUNT]=$(get_field "$line" "means")
        RECOVERY_FIXES[$RECOVERY_COUNT]=$(get_field "$line" "fix")
        RECOVERY_COUNT=$((RECOVERY_COUNT + 1))
    done <<< "$(grep "^@recovery|" "$file" 2>/dev/null || true)"

    # @entry records
    ENTRY_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ENTRY_CASES[$ENTRY_COUNT]=$(get_field "$line" "use-case")
        ENTRY_COMMANDS[$ENTRY_COUNT]=$(get_field "$line" "command")
        ENTRY_ENDPOINTS[$ENTRY_COUNT]=$(get_field "$line" "endpoint")
        ENTRY_COUNT=$((ENTRY_COUNT + 1))
    done <<< "$(grep "^@entry|" "$file" 2>/dev/null || true)"

    # @decision records
    DECISION_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        DECISION_IDS[$DECISION_COUNT]=$(get_field "$line" "id")
        DECISION_TITLES[$DECISION_COUNT]=$(get_field "$line" "title")
        DECISION_STATUS[$DECISION_COUNT]=$(get_field "$line" "status")
        DECISION_REASONS[$DECISION_COUNT]=$(get_field "$line" "reason")
        DECISION_COUNT=$((DECISION_COUNT + 1))
    done <<< "$(grep "^@decision|" "$file" 2>/dev/null || true)"

    # @note records
    NOTE_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        NOTE_CONTEXTS[$NOTE_COUNT]=$(get_field "$line" "context")
        NOTE_TEXTS[$NOTE_COUNT]=$(get_field "$line" "text")
        NOTE_COUNT=$((NOTE_COUNT + 1))
    done <<< "$(grep "^@note|" "$file" 2>/dev/null || true)"

    # @pattern records
    PATTERN_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        PATTERN_NAMES[$PATTERN_COUNT]=$(get_field "$line" "name")
        PATTERN_FILES[$PATTERN_COUNT]=$(get_field "$line" "file")
        PATTERN_FORS[$PATTERN_COUNT]=$(get_field "$line" "for")
        PATTERN_COUNT=$((PATTERN_COUNT + 1))
    done <<< "$(grep "^@pattern|" "$file" 2>/dev/null || true)"
}

# === SCENARIO SUPPORT ===

# Collect scenario definitions and modifications
# Sets: SCENARIO_IDS[], SCENARIO_INHERITS[], SCENARIO_LABELS[]
#       OVERRIDE_SCENARIOS[], OVERRIDE_TARGETS[], OVERRIDE_FIELDS[], OVERRIDE_VALUES[]
#       EXCLUDE_SCENARIOS[], EXCLUDE_TARGETS[]
collect_scenarios() {
    local file="$1"

    # @scenario records
    SCENARIO_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local sid
        sid=$(get_field "$line" "id")

        # Reject IDs containing commas
        if [[ "$sid" == *","* ]]; then
            echo "Error: Scenario ID '$sid' contains a comma — this is not supported; skipping" >&2
            continue
        fi

        SCENARIO_IDS[$SCENARIO_COUNT]="$sid"
        SCENARIO_INHERITS[$SCENARIO_COUNT]=$(get_field "$line" "inherits")
        SCENARIO_LABELS[$SCENARIO_COUNT]=$(get_field "$line" "label")

        # Reject inherits references containing commas
        if [[ "${SCENARIO_INHERITS[$SCENARIO_COUNT]}" == *","* ]]; then
            echo "Error: Scenario '$sid' inherits '${SCENARIO_INHERITS[$SCENARIO_COUNT]}' contains a comma — this is not supported; clearing" >&2
            SCENARIO_INHERITS[$SCENARIO_COUNT]=""
        fi
        SCENARIO_COUNT=$((SCENARIO_COUNT + 1))
    done <<< "$(grep "^@scenario|" "$file" 2>/dev/null || true)"

    # @override records
    OVERRIDE_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        OVERRIDE_SCENARIOS[$OVERRIDE_COUNT]=$(get_field "$line" "scenario")
        OVERRIDE_TARGETS[$OVERRIDE_COUNT]=$(get_field "$line" "target")
        OVERRIDE_FIELDS[$OVERRIDE_COUNT]=$(get_field "$line" "field")
        OVERRIDE_VALUES[$OVERRIDE_COUNT]=$(get_field "$line" "value")
        OVERRIDE_COUNT=$((OVERRIDE_COUNT + 1))
    done <<< "$(grep "^@override|" "$file" 2>/dev/null || true)"

    # @exclude records
    EXCLUDE_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        EXCLUDE_SCENARIOS[$EXCLUDE_COUNT]=$(get_field "$line" "scenario")
        EXCLUDE_TARGETS[$EXCLUDE_COUNT]=$(get_field "$line" "target")
        EXCLUDE_COUNT=$((EXCLUDE_COUNT + 1))
    done <<< "$(grep "^@exclude|" "$file" 2>/dev/null || true)"
}

# Get inheritance chain for a scenario (returns space-separated list from base to leaf)
get_scenario_chain() {
    local scenario="$1"
    local chain="$scenario"
    local current="$scenario"
    local max_depth=10
    local depth=0
    local visited=",$scenario,"

    while [[ -n "$current" ]] && ((depth < max_depth)); do
        local parent=""
        local s
        for ((s=0; s<SCENARIO_COUNT; s++)); do
            if [[ "${SCENARIO_IDS[$s]}" == "$current" ]]; then
                parent="${SCENARIO_INHERITS[$s]}"
                break
            fi
        done
        if [[ -z "$parent" ]]; then
            break
        fi
        if [[ "$visited" == *",$parent,"* ]]; then
            echo "Error: Circular scenario inheritance involving '$scenario'" >&2
            return 1
        fi
        visited="$visited$parent,"
        chain="$parent $chain"
        current="$parent"
        depth=$((depth + 1))
    done
    if ((depth >= max_depth)); then
        echo "Error: Scenario '$scenario' exceeds maximum inheritance depth ($depth); possible circular reference" >&2
        return 1
    fi
    echo "$chain"
}

# Validate scenario exists
validate_scenario() {
    local scenario="$1"
    local s
    for ((s=0; s<SCENARIO_COUNT; s++)); do
        [[ "${SCENARIO_IDS[$s]}" == "$scenario" ]] && return 0
    done
    return 1
}

# List available scenarios
list_scenarios() {
    local s
    echo "Available scenarios:"
    for ((s=0; s<SCENARIO_COUNT; s++)); do
        local label="${SCENARIO_LABELS[$s]}"
        if [[ -n "$label" ]]; then
            echo "  - ${SCENARIO_IDS[$s]} ($label)"
        else
            echo "  - ${SCENARIO_IDS[$s]}"
        fi
    done
}

# Apply scenario overrides and excludes to collected data
# Must be called after collect_nodes/edges/groups
apply_scenario() {
    local scenario="$1"
    local chain
    if ! chain=$(get_scenario_chain "$scenario"); then
        return 1
    fi

    local s o n e g target

    # Process each scenario in inheritance chain
    for s in $chain; do
        # Apply overrides for this scenario
        for ((o=0; o<OVERRIDE_COUNT; o++)); do
            if [[ "${OVERRIDE_SCENARIOS[$o]}" == "$s" ]]; then
                target="${OVERRIDE_TARGETS[$o]}"
                local field="${OVERRIDE_FIELDS[$o]}"
                local value="${OVERRIDE_VALUES[$o]}"

                # Find and update node
                for ((n=0; n<NODE_COUNT; n++)); do
                    if [[ "${NODE_IDS[$n]}" == "$target" ]]; then
                        case "$field" in
                            label)  NODE_LABELS[$n]="$value" ;;
                            shape)  NODE_SHAPES[$n]="$value" ;;
                            status) NODE_STATUS[$n]="$value" ;;
                        esac
                        break
                    fi
                done

                # Find and update edge (target is from:to format)
                for ((e=0; e<EDGE_COUNT; e++)); do
                    local edge_id="${EDGE_FROM[$e]}:${EDGE_TO[$e]}"
                    if [[ "$edge_id" == "$target" ]]; then
                        case "$field" in
                            label)  EDGE_LABELS[$e]="$value" ;;
                            style)  EDGE_STYLES[$e]="$value" ;;
                            status) EDGE_STATUS[$e]="$value" ;;
                        esac
                        break
                    fi
                done

                # Find and update group
                for ((g=0; g<GROUP_COUNT; g++)); do
                    if [[ "${GROUP_IDS[$g]}" == "$target" ]]; then
                        case "$field" in
                            label) GROUP_LABELS[$g]="$value" ;;
                        esac
                        break
                    fi
                done
            fi
        done
    done

    # Collect all excluded targets from inheritance chain
    local excluded_nodes=""
    for s in $chain; do
        for ((o=0; o<EXCLUDE_COUNT; o++)); do
            if [[ "${EXCLUDE_SCENARIOS[$o]}" == "$s" ]]; then
                excluded_nodes="$excluded_nodes ${EXCLUDE_TARGETS[$o]}"
            fi
        done
    done

    # Remove excluded nodes by marking them
    # We mark by clearing the ID (empty IDs are skipped in generation)
    for target in $excluded_nodes; do
        for ((n=0; n<NODE_COUNT; n++)); do
            if [[ "${NODE_IDS[$n]}" == "$target" ]]; then
                NODE_IDS[$n]=""
                break
            fi
        done

        # Also remove edges referencing excluded nodes
        for ((e=0; e<EDGE_COUNT; e++)); do
            if [[ "${EDGE_FROM[$e]}" == "$target" ]] || [[ "${EDGE_TO[$e]}" == "$target" ]]; then
                EDGE_FROM[$e]=""
                EDGE_TO[$e]=""
            fi
        done
    done
}

# === VIEW SUPPORT ===

# Collect view definitions
# Sets: VIEW_IDS[], VIEW_FILTERS[], VIEW_INCLUDES[], VIEW_EXCLUDES[], VIEW_LABELS[], VIEW_SCENARIOS[], VIEW_LEVELS[]
collect_views() {
    local file="$1"

    VIEW_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        VIEW_IDS[$VIEW_COUNT]=$(get_field "$line" "id")
        VIEW_FILTERS[$VIEW_COUNT]=$(get_field "$line" "filter")
        VIEW_INCLUDES[$VIEW_COUNT]=$(get_field "$line" "includes")
        VIEW_EXCLUDES[$VIEW_COUNT]=$(get_field "$line" "excludes")
        VIEW_LABELS[$VIEW_COUNT]=$(get_field "$line" "label")
        VIEW_SCENARIOS[$VIEW_COUNT]=$(get_field "$line" "scenario")
        VIEW_LEVELS[$VIEW_COUNT]=$(get_field "$line" "level")
        VIEW_COUNT=$((VIEW_COUNT + 1))
    done <<< "$(grep "^@view|" "$file" 2>/dev/null || true)"
}

# Validate view exists
validate_view() {
    local view="$1"
    local v
    for ((v=0; v<VIEW_COUNT; v++)); do
        [[ "${VIEW_IDS[$v]}" == "$view" ]] && return 0
    done
    return 1
}

# List available views
list_views() {
    local v
    echo "Available views:"
    for ((v=0; v<VIEW_COUNT; v++)); do
        local label="${VIEW_LABELS[$v]}"
        if [[ -n "$label" ]]; then
            echo "  - ${VIEW_IDS[$v]} ($label)"
        else
            echo "  - ${VIEW_IDS[$v]}"
        fi
    done
}

# Check if a node passes the tag filter
# Usage: node_passes_filter "node_tags" "filter_spec"
# filter_spec format: "tags:security" or "tags:security,tags:pii" (OR logic)
node_passes_filter() {
    local node_tags="$1"
    local filter_spec="$2"

    # No filter means all pass
    [[ -z "$filter_spec" ]] && return 0

    # Parse filter conditions (comma-separated, OR logic)
    local saved_IFS="$IFS"
    IFS=','
    local conditions=($filter_spec)
    IFS="$saved_IFS"
    local cond

    for cond in "${conditions[@]}"; do
        # Parse tags:value format
        if [[ "$cond" == tags:* ]]; then
            local required_tag="${cond#tags:}"
            # Check if node has this tag (node_tags is comma-separated)
            if echo ",$node_tags," | grep -q ",$required_tag,"; then
                return 0  # Match found
            fi
        fi
    done

    return 1  # No match
}

# Apply view filter to collected data
apply_view() {
    local view="$1"
    local v n e g

    # Find view definition
    local filter="" includes="" excludes="" level=""
    for ((v=0; v<VIEW_COUNT; v++)); do
        if [[ "${VIEW_IDS[$v]}" == "$view" ]]; then
            filter="${VIEW_FILTERS[$v]}"
            includes="${VIEW_INCLUDES[$v]}"
            excludes="${VIEW_EXCLUDES[$v]}"
            level="${VIEW_LEVELS[$v]}"
            # Check if view specifies a scenario
            local view_scenario="${VIEW_SCENARIOS[$v]}"
            if [[ -n "$view_scenario" ]] && [[ -z "$SCENARIO" ]]; then
                # Apply view's scenario if no CLI scenario specified
                if ! apply_scenario "$view_scenario"; then
                    return 1
                fi
            fi
            break
        fi
    done

    # Warn about unimplemented level feature
    if [[ -n "$level" ]]; then
        warn "View level:$level is not yet implemented (level filtering is a planned feature)"
    fi

    # Apply tag filter to nodes
    if [[ -n "$filter" ]]; then
        for ((n=0; n<NODE_COUNT; n++)); do
            [[ -z "${NODE_IDS[$n]}" ]] && continue  # Already excluded
            if ! node_passes_filter "${NODE_TAGS[$n]}" "$filter"; then
                NODE_IDS[$n]=""  # Mark as excluded
            fi
        done
    fi

    # Apply group excludes (with tree cascade to descendants)
    if [[ -n "$excludes" ]]; then
        local saved_IFS="$IFS"
        IFS=','
        local excluded_groups=($excludes)
        IFS="$saved_IFS"

        # Expand excludes list with all descendants
        local all_excluded=()
        local grp
        for grp in "${excluded_groups[@]}"; do
            all_excluded+=("$grp")
            local descs
            descs=$(get_group_descendants "$grp")
            local d
            for d in $descs; do
                all_excluded+=("$d")
            done
        done

        for grp in "${all_excluded[@]}"; do
            # Exclude all nodes in this group
            for ((n=0; n<NODE_COUNT; n++)); do
                if [[ "${NODE_GROUPS[$n]}" == "$grp" ]]; then
                    NODE_IDS[$n]=""
                fi
            done
            # Mark group as excluded
            for ((g=0; g<GROUP_COUNT; g++)); do
                if [[ "${GROUP_IDS[$g]}" == "$grp" ]]; then
                    GROUP_IDS[$g]=""
                fi
            done
        done
    fi

    # Apply group includes — keep only specified groups and their descendants
    if [[ -n "$includes" ]]; then
        local saved_IFS="$IFS"
        IFS=','
        local included_groups=($includes)
        IFS="$saved_IFS"

        # Expand includes list with all descendants
        local all_included=()
        local grp
        for grp in "${included_groups[@]}"; do
            all_included+=("$grp")
            local descs
            descs=$(get_group_descendants "$grp")
            local d
            for d in $descs; do
                all_included+=("$d")
            done
        done

        for ((n=0; n<NODE_COUNT; n++)); do
            [[ -z "${NODE_IDS[$n]}" ]] && continue  # Already excluded
            local keep=false
            local node_group="${NODE_GROUPS[$n]}"
            # Keep ungrouped nodes
            [[ -z "$node_group" ]] && keep=true
            # Check if in any included group (including descendants)
            local grp
            for grp in "${all_included[@]}"; do
                [[ "$node_group" == "$grp" ]] && keep=true && break
            done
            [[ "$keep" == "false" ]] && NODE_IDS[$n]=""
        done
        # Remove groups not in the expanded includes list
        for ((g=0; g<GROUP_COUNT; g++)); do
            [[ -z "${GROUP_IDS[$g]}" ]] && continue
            local grp_in_list=false
            local grp
            for grp in "${all_included[@]}"; do
                [[ "${GROUP_IDS[$g]}" == "$grp" ]] && grp_in_list=true && break
            done
            if [[ "$grp_in_list" == "false" ]]; then
                GROUP_IDS[$g]=""
            fi
        done
    fi

    # Suppress empty groups (no remaining nodes and no remaining child groups)
    local changed_groups=true
    while [[ "$changed_groups" == "true" ]]; do
        changed_groups=false
        for ((g=0; g<GROUP_COUNT; g++)); do
            [[ -z "${GROUP_IDS[$g]}" ]] && continue
            local gid="${GROUP_IDS[$g]}"
            local has_content=false
            # Check for remaining nodes in this group
            for ((n=0; n<NODE_COUNT; n++)); do
                if [[ -n "${NODE_IDS[$n]}" ]] && [[ "${NODE_GROUPS[$n]}" == "$gid" ]]; then
                    has_content=true
                    break
                fi
            done
            # Check for remaining child groups
            if [[ "$has_content" == "false" ]]; then
                local g2
                for ((g2=0; g2<GROUP_COUNT; g2++)); do
                    if [[ -n "${GROUP_IDS[$g2]}" ]] && [[ "${GROUP_PARENTS[$g2]}" == "$gid" ]]; then
                        has_content=true
                        break
                    fi
                done
            fi
            if [[ "$has_content" == "false" ]]; then
                GROUP_IDS[$g]=""
                changed_groups=true
            fi
        done
    done

    # Remove edges where either endpoint is excluded
    for ((e=0; e<EDGE_COUNT; e++)); do
        [[ -z "${EDGE_FROM[$e]}" ]] && continue
        local from_id="${EDGE_FROM[$e]}"
        local to_id="${EDGE_TO[$e]}"
        local from_exists=false
        local to_exists=false

        for ((n=0; n<NODE_COUNT; n++)); do
            [[ "${NODE_IDS[$n]}" == "$from_id" ]] && from_exists=true
            [[ "${NODE_IDS[$n]}" == "$to_id" ]] && to_exists=true
        done

        if [[ "$from_exists" == "false" ]] || [[ "$to_exists" == "false" ]]; then
            EDGE_FROM[$e]=""
            EDGE_TO[$e]=""
        fi
    done
}

# Generate context sections in markdown
generate_context_sections() {
    local i

    # When to Use
    if ((USE_WHEN_COUNT > 0)); then
        echo ""
        echo "## When to Use"
        echo ""
        for ((i=0; i<USE_WHEN_COUNT; i++)); do
            local line="- ${USE_WHEN_CONDITIONS[$i]}"
            [[ -n "${USE_WHEN_THRESHOLDS[$i]}" ]] && line+=" (${USE_WHEN_THRESHOLDS[$i]})"
            [[ -n "${USE_WHEN_DETAILS[$i]}" ]] && line+=" — ${USE_WHEN_DETAILS[$i]}"
            echo "$line"
        done
    fi

    # When NOT to Use
    if ((USE_NOT_COUNT > 0)); then
        echo ""
        echo "## When NOT to Use"
        echo ""
        for ((i=0; i<USE_NOT_COUNT; i++)); do
            local line="- ${USE_NOT_CONDITIONS[$i]}"
            [[ -n "${USE_NOT_REASONS[$i]}" ]] && line+=" — ${USE_NOT_REASONS[$i]}"
            echo "$line"
        done
    fi

    # Key Components
    if ((COMP_COUNT > 0)); then
        echo ""
        echo "## Key Components"
        echo ""
        echo "| Component | File | Responsibility |"
        echo "|-----------|------|----------------|"
        for ((i=0; i<COMP_COUNT; i++)); do
            echo "| ${COMP_NAMES[$i]} | \`${COMP_FILES[$i]}\` | ${COMP_DOES[$i]} |"
        done
    fi

    # Configuration
    if ((CONFIG_COUNT > 0)); then
        echo ""
        echo "## Configuration"
        echo ""
        echo "| Param | Value | Note |"
        echo "|-------|-------|------|"
        for ((i=0; i<CONFIG_COUNT; i++)); do
            echo "| ${CONFIG_PARAMS[$i]} | ${CONFIG_VALUES[$i]} | ${CONFIG_NOTES[$i]} |"
        done
    fi

    # Gotchas
    if ((GOTCHA_COUNT > 0)); then
        echo ""
        echo "## Gotchas"
        echo ""
        for ((i=0; i<GOTCHA_COUNT; i++)); do
            local line="- **${GOTCHA_ISSUES[$i]}** — ${GOTCHA_DETAILS[$i]}"
            [[ -n "${GOTCHA_FIXES[$i]}" ]] && line+=". Fix: ${GOTCHA_FIXES[$i]}"
            echo "$line"
        done
    fi

    # Recovery
    if ((RECOVERY_COUNT > 0)); then
        echo ""
        echo "## Recovery"
        echo ""
        for ((i=0; i<RECOVERY_COUNT; i++)); do
            echo "- **${RECOVERY_ISSUES[$i]}** — ${RECOVERY_MEANS[$i]}. Fix: ${RECOVERY_FIXES[$i]}"
        done
    fi

    # Entry Points
    if ((ENTRY_COUNT > 0)); then
        echo ""
        echo "## Entry Points"
        echo ""
        for ((i=0; i<ENTRY_COUNT; i++)); do
            local line="- **${ENTRY_CASES[$i]}**"
            [[ -n "${ENTRY_COMMANDS[$i]}" ]] && line+=": \`${ENTRY_COMMANDS[$i]}\`"
            [[ -n "${ENTRY_ENDPOINTS[$i]}" ]] && line+=": \`${ENTRY_ENDPOINTS[$i]}\`"
            echo "$line"
        done
    fi

    # Decisions
    if ((DECISION_COUNT > 0)); then
        echo ""
        echo "## Decisions"
        echo ""
        for ((i=0; i<DECISION_COUNT; i++)); do
            local line="- **${DECISION_IDS[$i]}** (${DECISION_STATUS[$i]}): ${DECISION_TITLES[$i]}"
            [[ -n "${DECISION_REASONS[$i]}" ]] && line+=" — ${DECISION_REASONS[$i]}"
            echo "$line"
        done
    fi

    # Notes
    if ((NOTE_COUNT > 0)); then
        echo ""
        echo "## Notes"
        echo ""
        for ((i=0; i<NOTE_COUNT; i++)); do
            echo "- **${NOTE_CONTEXTS[$i]}**: ${NOTE_TEXTS[$i]}"
        done
    fi

    # Related Patterns
    if ((PATTERN_COUNT > 0)); then
        echo ""
        echo "## Related Patterns"
        echo ""
        for ((i=0; i<PATTERN_COUNT; i++)); do
            local line="- ${PATTERN_NAMES[$i]}"
            [[ -n "${PATTERN_FORS[$i]}" ]] && line+=" (${PATTERN_FORS[$i]})"
            [[ -n "${PATTERN_FILES[$i]}" ]] && line+=" — \`${PATTERN_FILES[$i]}\`"
            echo "$line"
        done
    fi
}

# === MERMAID GENERATION ===

# Escape label for Mermaid (wrap in quotes, handle special characters)
escape_label() {
    local label="$1"
    # Replace special characters that can break Mermaid rendering
    # Order matters: & first to avoid double-escaping, then # before entities that contain #
    label="${label//&/&amp;}"         # & -> &amp;
    label="${label//\"/&quot;}"       # " -> &quot;
    label="${label//$'\n'/ }"         # newlines -> space
    label="${label//$'\r'/ }"         # carriage returns -> space
    label="${label//#/&#35;}"         # # -> HTML entity
    label="${label//|/&#124;}"        # | -> HTML entity (breaks edge label syntax; after # to avoid &#35; in entity)
    label="${label//\`/&#96;}"        # backticks -> HTML entity
    echo "\"$label\""
}

# Get Mermaid shape syntax for a node
# Usage: get_node_shape "id" "label" "shape" "status"
get_node_shape() {
    local id="$1"
    local label="$2"
    local shape="$3"
    local status="$4"
    local escaped
    escaped=$(escape_label "$label")

    local result
    case "$shape" in
        diamond)    result="${id}{${escaped}}" ;;
        stadium)    result="${id}([${escaped}])" ;;
        circle)     result="${id}((${escaped}))" ;;
        hexagon)    result="${id}{{${escaped}}}" ;;
        database)   result="${id}[(${escaped})]" ;;
        subroutine) result="${id}[[${escaped}]]" ;;
        *)          result="${id}[${escaped}]" ;;  # box default
    esac

    # Add status class if present
    if [[ -n "$status" ]]; then
        result="${result}:::${status}"
    fi

    echo "$result"
}

# Get Mermaid edge syntax
# Usage: get_edge_syntax "from" "to" "label" "style" "bidir"
get_edge_syntax() {
    local from="$1"
    local to="$2"
    local label="$3"
    local style="$4"
    local bidir="$5"

    local arrow
    if [[ "$bidir" == "true" ]]; then
        # Bidirectional arrows respect style
        case "$style" in
            dashed|dotted) arrow="<-.->" ;;
            thick)         arrow="<==>" ;;
            *)             arrow="<-->" ;;
        esac
    else
        case "$style" in
            dashed|dotted) arrow="-.->" ;;
            thick)         arrow="==>" ;;
            *)             arrow="-->" ;;
        esac
    fi

    if [[ -n "$label" ]]; then
        local escaped
        escaped=$(escape_label "$label")
        echo "${from} ${arrow}|${escaped}| ${to}"
    else
        echo "${from} ${arrow} ${to}"
    fi
}

# Check if group A is a direct child of group B
is_child_of() {
    local child_id="$1"
    local parent_id="$2"
    local g
    for ((g=0; g<GROUP_COUNT; g++)); do
        if [[ "${GROUP_IDS[$g]}" == "$child_id" ]]; then
            [[ "${GROUP_PARENTS[$g]}" == "$parent_id" ]]
            return $?
        fi
    done
    return 1
}

# Get all descendant group IDs for a given group (walks parent chain)
# Outputs space-separated list of descendant group IDs (not including the input group itself)
get_group_descendants() {
    local parent_id="$1"
    local descendants=""
    local changed=true
    local known=",$parent_id,"

    # Iteratively find all groups whose parent chain leads to parent_id
    while [[ "$changed" == "true" ]]; do
        changed=false
        local g
        for ((g=0; g<GROUP_COUNT; g++)); do
            [[ -z "${GROUP_IDS[$g]}" ]] && continue
            local gid="${GROUP_IDS[$g]}"
            local gparent="${GROUP_PARENTS[$g]}"
            # Skip if already known or no parent
            [[ -z "$gparent" ]] && continue
            [[ "$known" == *",$gid,"* ]] && continue
            # If parent is in known set, this is a descendant
            if [[ "$known" == *",$gparent,"* ]]; then
                known="$known$gid,"
                descendants="$descendants $gid"
                changed=true
            fi
        done
    done
    echo "$descendants"
}

# Recursively output a group and its nested subgroups
output_group() {
    local gid="$1"
    local indent="$2"
    local g i

    # Find this group's label
    local glabel=""
    for ((g=0; g<GROUP_COUNT; g++)); do
        if [[ "${GROUP_IDS[$g]}" == "$gid" ]]; then
            glabel="${GROUP_LABELS[$g]}"
            break
        fi
    done

    local escaped_label
    escaped_label=$(escape_label "$glabel")

    echo "${indent}subgraph ${gid}[${escaped_label}]"

    # Output nodes directly in this group
    for ((i=0; i<NODE_COUNT; i++)); do
        # Skip excluded nodes (empty ID)
        [[ -z "${NODE_IDS[$i]}" ]] && continue
        if [[ "${NODE_GROUPS[$i]}" == "$gid" ]]; then
            local node_syntax
            node_syntax=$(get_node_shape "${NODE_IDS[$i]}" "${NODE_LABELS[$i]}" "${NODE_SHAPES[$i]}" "${NODE_STATUS[$i]}")
            echo "${indent}    $node_syntax"
        fi
    done

    # Output child groups (nested subgraphs)
    for ((g=0; g<GROUP_COUNT; g++)); do
        # Skip excluded groups (empty ID)
        [[ -z "${GROUP_IDS[$g]}" ]] && continue
        if [[ "${GROUP_PARENTS[$g]}" == "$gid" ]]; then
            output_group "${GROUP_IDS[$g]}" "${indent}    "
        fi
    done

    echo "${indent}end"
}

# Generate Mermaid flowchart with nested subgraph support
generate_flowchart() {
    echo "flowchart $FINAL_DIRECTION"

    local i g

    # Output ungrouped nodes first
    for ((i=0; i<NODE_COUNT; i++)); do
        local node_id="${NODE_IDS[$i]}"
        # Skip excluded nodes (empty ID)
        [[ -z "$node_id" ]] && continue
        local group="${NODE_GROUPS[$i]}"
        if [[ -z "$group" ]]; then
            local node_syntax
            node_syntax=$(get_node_shape "$node_id" "${NODE_LABELS[$i]}" "${NODE_SHAPES[$i]}" "${NODE_STATUS[$i]}")
            echo "    $node_syntax"
        fi
    done

    # Output top-level groups and promoted orphans
    # A group is top-level if it has no parent, or its parent was excluded by view filtering
    # Child groups are handled recursively by output_group
    for ((g=0; g<GROUP_COUNT; g++)); do
        # Skip excluded groups (empty ID)
        [[ -z "${GROUP_IDS[$g]}" ]] && continue
        local parent="${GROUP_PARENTS[$g]}"
        if [[ -z "$parent" ]]; then
            output_group "${GROUP_IDS[$g]}" "    "
        else
            # Check if parent group still exists (not excluded by view)
            local parent_exists=false
            local g2
            for ((g2=0; g2<GROUP_COUNT; g2++)); do
                if [[ "${GROUP_IDS[$g2]}" == "$parent" ]]; then
                    parent_exists=true
                    break
                fi
            done
            # Promote to top-level if parent was excluded (Structurizr semantics)
            if [[ "$parent_exists" == "false" ]]; then
                output_group "${GROUP_IDS[$g]}" "    "
            fi
        fi
    done

    # Output edges (track actual edge index for linkStyle)
    for ((i=0; i<EDGE_COUNT; i++)); do
        # Skip excluded edges (empty from/to)
        [[ -z "${EDGE_FROM[$i]}" ]] && continue
        [[ -z "${EDGE_TO[$i]}" ]] && continue
        local edge_syntax
        edge_syntax=$(get_edge_syntax "${EDGE_FROM[$i]}" "${EDGE_TO[$i]}" "${EDGE_LABELS[$i]}" "${EDGE_STYLES[$i]}" "${EDGE_BIDIR[$i]}")
        echo "    $edge_syntax"
    done

    # Add link styles for edges with status (re-track for correct indices)
    local edge_index=0
    for ((i=0; i<EDGE_COUNT; i++)); do
        # Skip excluded edges
        [[ -z "${EDGE_FROM[$i]}" ]] && continue
        [[ -z "${EDGE_TO[$i]}" ]] && continue
        local status="${EDGE_STATUS[$i]}"
        if [[ "$status" == "deprecated" ]]; then
            echo "    linkStyle $edge_index stroke:#999,stroke-dasharray:5"
        elif [[ "$status" == "planned" ]]; then
            echo "    linkStyle $edge_index stroke:#69b,stroke-dasharray:2"
        fi
        edge_index=$((edge_index + 1))
    done
}

# === SEQUENCE DIAGRAM SUPPORT ===

# Collect sequence-specific records
collect_sequence() {
    local file="$1"

    # Participants
    PART_COUNT=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        PART_IDS[$PART_COUNT]=$(get_field "$line" "id")
        PART_LABELS[$PART_COUNT]=$(get_field "$line" "label")

        # Default label to id
        if ! has_field "$line" "label"; then
            PART_LABELS[$PART_COUNT]="${PART_IDS[$PART_COUNT]}"
        fi

        PART_COUNT=$((PART_COUNT + 1))
    done <<< "$(grep "^@participant|" "$file" 2>/dev/null || true)"

    # Sequence elements (order matters - read full file to preserve order)
    SEQ_COUNT=0
    while IFS= read -r line; do
        # Skip non-sequence records
        [[ "$line" != "@msg|"* ]] && [[ "$line" != "@block|"* ]] && \
        [[ "$line" != "@endblock"* ]] && [[ "$line" != "@seq-note|"* ]] && \
        [[ "$line" != "@else|"* ]] && [[ "$line" != "@and|"* ]] && continue

        # Determine record type
        local rec_type
        case "$line" in
            "@msg|"*)      rec_type="msg" ;;
            "@block|"*)    rec_type="block" ;;
            "@else|"*)     rec_type="else" ;;
            "@and|"*)      rec_type="and" ;;
            "@endblock"*)  rec_type="endblock" ;;
            "@seq-note|"*) rec_type="seq-note" ;;
        esac

        SEQ_REC_TYPES[$SEQ_COUNT]="$rec_type"
        SEQ_FROM[$SEQ_COUNT]=$(get_field "$line" "from")
        SEQ_TO[$SEQ_COUNT]=$(get_field "$line" "to")
        SEQ_LABELS[$SEQ_COUNT]=$(get_field "$line" "label")
        SEQ_MSG_TYPES[$SEQ_COUNT]=$(get_field "$line" "type")
        SEQ_ACTIVATE[$SEQ_COUNT]=$(get_field "$line" "activate")
        SEQ_DEACTIVATE[$SEQ_COUNT]=$(get_field "$line" "deactivate")
        SEQ_OVER[$SEQ_COUNT]=$(get_field "$line" "over")
        SEQ_TEXT[$SEQ_COUNT]=$(get_field "$line" "text")

        # Defaults
        [[ -z "${SEQ_MSG_TYPES[$SEQ_COUNT]}" ]] && SEQ_MSG_TYPES[$SEQ_COUNT]="request"
        [[ -z "${SEQ_ACTIVATE[$SEQ_COUNT]}" ]] && SEQ_ACTIVATE[$SEQ_COUNT]="false"
        [[ -z "${SEQ_DEACTIVATE[$SEQ_COUNT]}" ]] && SEQ_DEACTIVATE[$SEQ_COUNT]="false"

        SEQ_COUNT=$((SEQ_COUNT + 1))
    done < "$file"
}

# Generate Mermaid sequence diagram
generate_sequence() {
    echo "sequenceDiagram"

    local i

    # Participants
    for ((i=0; i<PART_COUNT; i++)); do
        echo "    participant ${PART_IDS[$i]} as ${PART_LABELS[$i]}"
    done

    # Messages and blocks
    for ((i=0; i<SEQ_COUNT; i++)); do
        local rec_type="${SEQ_REC_TYPES[$i]}"

        case "$rec_type" in
            msg)
                local from="${SEQ_FROM[$i]}"
                local to="${SEQ_TO[$i]}"
                local label="${SEQ_LABELS[$i]}"
                local msg_type="${SEQ_MSG_TYPES[$i]}"

                local arrow
                case "$msg_type" in
                    response)       arrow="-->>" ;;
                    async)          arrow="-)" ;;
                    async-response) arrow="--)" ;;
                    self)           to="$from"; arrow="->>" ;;
                    *)              arrow="->>" ;;
                esac

                echo "    ${from}${arrow}${to}: ${label}"

                [[ "${SEQ_ACTIVATE[$i]}" == "true" ]] && echo "    activate ${to}"
                [[ "${SEQ_DEACTIVATE[$i]}" == "true" ]] && echo "    deactivate ${from}"
                ;;
            block)
                local block_type="${SEQ_MSG_TYPES[$i]}"
                local block_label="${SEQ_LABELS[$i]}"
                # block type is stored in 'type' field for @block records
                [[ -z "$block_type" || "$block_type" == "request" ]] && block_type="opt"
                echo "    ${block_type} ${block_label}"
                ;;
            else)
                local else_label="${SEQ_LABELS[$i]}"
                echo "    else ${else_label}"
                ;;
            and)
                local and_label="${SEQ_LABELS[$i]}"
                echo "    and ${and_label}"
                ;;
            endblock)
                echo "    end"
                ;;
            seq-note)
                local over="${SEQ_OVER[$i]}"
                local text="${SEQ_TEXT[$i]}"
                echo "    note over ${over}: ${text}"
                ;;
        esac
    done
}

# === DEPLOYMENT DIAGRAM SUPPORT ===

# Generate Mermaid deployment diagram (rendered as flowchart with nested subgraphs)
generate_deployment() {
    echo "flowchart $FINAL_DIRECTION"

    local e n i inf

    # Output environments as top-level subgraphs
    for ((e=0; e<DEPLOY_ENV_COUNT; e++)); do
        local env_id="${DEPLOY_ENV_IDS[$e]}"
        local env_label
        env_label=$(escape_label "${DEPLOY_ENV_LABELS[$e]}")
        echo "    subgraph ${env_id}[${env_label}]"

        # Output deploy-nodes in this environment
        for ((n=0; n<DEPLOY_NODE_COUNT; n++)); do
            if [[ "${DEPLOY_NODE_ENVS[$n]}" == "$env_id" ]] && [[ -z "${DEPLOY_NODE_PARENTS[$n]}" ]]; then
                output_deploy_node "${DEPLOY_NODE_IDS[$n]}" "        "
            fi
        done

        echo "    end"
    done

    # Output edges
    for ((i=0; i<EDGE_COUNT; i++)); do
        # Skip excluded edges (empty from/to)
        [[ -z "${EDGE_FROM[$i]}" ]] && continue
        [[ -z "${EDGE_TO[$i]}" ]] && continue
        local edge_syntax
        edge_syntax=$(get_edge_syntax "${EDGE_FROM[$i]}" "${EDGE_TO[$i]}" "${EDGE_LABELS[$i]}" "${EDGE_STYLES[$i]}" "${EDGE_BIDIR[$i]}")
        echo "    $edge_syntax"
    done
}

# Recursively output a deploy-node and its contents
output_deploy_node() {
    local node_id="$1"
    local indent="$2"
    local n i inf

    # Find this node's label
    local node_label=""
    for ((n=0; n<DEPLOY_NODE_COUNT; n++)); do
        if [[ "${DEPLOY_NODE_IDS[$n]}" == "$node_id" ]]; then
            node_label="${DEPLOY_NODE_LABELS[$n]}"
            break
        fi
    done

    local escaped_label
    escaped_label=$(escape_label "$node_label")

    echo "${indent}subgraph ${node_id}[${escaped_label}]"

    # Output instances in this node
    for ((i=0; i<DEPLOY_INST_COUNT; i++)); do
        if [[ "${DEPLOY_INST_NODES[$i]}" == "$node_id" ]]; then
            local inst_id="${DEPLOY_INST_IDS[$i]}"
            local inst_label="${DEPLOY_INST_COMPS[$i]}"
            local inst_count="${DEPLOY_INST_COUNTS[$i]}"
            if [[ "$inst_count" != "1" ]]; then
                inst_label="${inst_label} (${inst_count} instances)"
            fi
            local escaped_inst
            escaped_inst=$(escape_label "$inst_label")
            echo "${indent}    ${inst_id}[${escaped_inst}]"
        fi
    done

    # Output infra-nodes in this node (subroutine shape)
    for ((inf=0; inf<INFRA_NODE_COUNT; inf++)); do
        if [[ "${INFRA_NODE_PARENTS[$inf]}" == "$node_id" ]]; then
            local infra_id="${INFRA_NODE_IDS[$inf]}"
            local infra_label
            infra_label=$(escape_label "${INFRA_NODE_LABELS[$inf]}")
            echo "${indent}    ${infra_id}[[${infra_label}]]"
        fi
    done

    # Output nested deploy-nodes
    for ((n=0; n<DEPLOY_NODE_COUNT; n++)); do
        if [[ "${DEPLOY_NODE_PARENTS[$n]}" == "$node_id" ]]; then
            output_deploy_node "${DEPLOY_NODE_IDS[$n]}" "${indent}    "
        fi
    done

    echo "${indent}end"
}

# === VALIDATION ===

validate_diagram() {
    local errors=0
    local warnings=0
    local g i n p s

    # Check for circular scenario inheritance
    for ((s=0; s<SCENARIO_COUNT; s++)); do
        local sid="${SCENARIO_IDS[$s]}"
        local inherits="${SCENARIO_INHERITS[$s]}"
        if [[ -n "$inherits" ]]; then
            local sc_depth=0
            local sc_current="$sid"
            local sc_visited=",$sid,"
            local sc_detected=false
            while [[ -n "$sc_current" ]] && ((sc_depth < 10)); do
                local sc_parent=""
                local ss
                for ((ss=0; ss<SCENARIO_COUNT; ss++)); do
                    if [[ "${SCENARIO_IDS[$ss]}" == "$sc_current" ]]; then
                        sc_parent="${SCENARIO_INHERITS[$ss]}"
                        break
                    fi
                done
                if [[ -z "$sc_parent" ]]; then
                    break
                fi
                if [[ "$sc_visited" == *",$sc_parent,"* ]]; then
                    echo "Error: Circular scenario inheritance involving '$sid'" >&2
                    errors=$((errors + 1))
                    sc_detected=true
                    break
                fi
                sc_visited="$sc_visited$sc_parent,"
                sc_current="$sc_parent"
                sc_depth=$((sc_depth + 1))
            done
            if [[ "$sc_detected" == "false" ]] && ((sc_depth >= 10)); then
                echo "Error: Scenario '$sid' exceeds maximum inheritance depth ($sc_depth); possible circular reference" >&2
                errors=$((errors + 1))
            fi
        fi
    done

    # Check for circular group parents
    for ((g=0; g<GROUP_COUNT; g++)); do
        local gid="${GROUP_IDS[$g]}"
        local parent="${GROUP_PARENTS[$g]}"

        if [[ -n "$parent" ]]; then
            # Check parent exists
            local found=false
            for ((p=0; p<GROUP_COUNT; p++)); do
                [[ "${GROUP_IDS[$p]}" == "$parent" ]] && found=true && break
            done
            if [[ "$found" == "false" ]]; then
                echo "Error: Group '$gid' references unknown parent '$parent'" >&2
                errors=$((errors + 1))
            fi
        fi
    done

    # Check nesting depth and circular references
    for ((g=0; g<GROUP_COUNT; g++)); do
        local gid="${GROUP_IDS[$g]}"
        local depth=0
        local current="$gid"
        local visited=",$gid,"
        local circular=false

        while [[ -n "$current" ]] && ((depth < 10)); do
            local parent=""
            for ((p=0; p<GROUP_COUNT; p++)); do
                if [[ "${GROUP_IDS[$p]}" == "$current" ]]; then
                    parent="${GROUP_PARENTS[$p]}"
                    break
                fi
            done
            if [[ -n "$parent" ]] && [[ "$visited" == *",$parent,"* ]]; then
                echo "Error: Circular group reference involving '$gid'" >&2
                errors=$((errors + 1))
                circular=true
                break
            fi
            if [[ -z "$parent" ]]; then
                break
            fi
            visited="$visited$parent,"
            current="$parent"
            depth=$((depth + 1))
        done

        if [[ "$circular" == "false" ]] && ((depth >= 10)); then
            warn "Group '$gid' exceeds maximum nesting depth ($depth); circular reference check may be incomplete"
            warnings=$((warnings + 1))
        elif [[ "$circular" == "false" ]] && ((depth > 4)); then
            warn "Deep nesting ($depth levels) for group '$gid' may render poorly"
            warnings=$((warnings + 1))
        fi
    done

    # Check edges reference valid nodes (skip for deployment diagrams which use different ID arrays)
    if [[ "$DIAGRAM_TYPE" != "deployment" ]]; then
        for ((i=0; i<EDGE_COUNT; i++)); do
            local from="${EDGE_FROM[$i]}"
            local to="${EDGE_TO[$i]}"

            local from_found=false
            local to_found=false
            for ((n=0; n<NODE_COUNT; n++)); do
                [[ "${NODE_IDS[$n]}" == "$from" ]] && from_found=true
                [[ "${NODE_IDS[$n]}" == "$to" ]] && to_found=true
            done

            [[ "$from_found" == "false" ]] && { warn "Edge references unknown node: $from"; warnings=$((warnings + 1)); }
            [[ "$to_found" == "false" ]] && { warn "Edge references unknown node: $to"; warnings=$((warnings + 1)); }
        done
    fi

    # Check for duplicate node IDs
    for ((i=0; i<NODE_COUNT; i++)); do
        local nid="${NODE_IDS[$i]}"
        for ((n=i+1; n<NODE_COUNT; n++)); do
            if [[ "${NODE_IDS[$n]}" == "$nid" ]]; then
                echo "Error: Duplicate node ID '$nid'" >&2
                errors=$((errors + 1))
            fi
        done
    done

    if ((errors > 0)); then
        echo "Validation failed with $errors error(s)"
        return 1
    fi

    if ((warnings > 0)); then
        echo "Validation passed with $warnings warning(s)"
    else
        echo "OK"
    fi
    return 0
}

# === MAIN LOGIC ===

# Resolve @include directives first
RESOLVED_INPUT=$(resolve_includes "$INPUT")
trap "rm -f '$RESOLVED_INPUT'" EXIT

DIAGRAM_LINE=$(get_diagram_line "$RESOLVED_INPUT")

if [[ -z "$DIAGRAM_LINE" ]]; then
    rm -f "$RESOLVED_INPUT"
    error "Not a valid GDLD file: no @diagram record found"
fi

# Extract diagram metadata
DIAGRAM_ID=$(get_field "$DIAGRAM_LINE" "id")
DIAGRAM_TYPE=$(get_field "$DIAGRAM_LINE" "type")
DIAGRAM_PURPOSE=$(get_field "$DIAGRAM_LINE" "purpose")
FILE_DIRECTION=$(get_field "$DIAGRAM_LINE" "direction")

# Determine direction: CLI > file > default
if [[ -n "$DIRECTION" ]]; then
    FINAL_DIRECTION="$DIRECTION"
elif [[ -n "$FILE_DIRECTION" ]]; then
    FINAL_DIRECTION="$FILE_DIRECTION"
else
    FINAL_DIRECTION="TD"
fi

# Default diagram type
DIAGRAM_TYPE="${DIAGRAM_TYPE:-flow}"

# Initialize arrays (bash 3.2 compatible)
NODE_IDS=()
NODE_LABELS=()
NODE_SHAPES=()
NODE_GROUPS=()
NODE_STATUS=()
NODE_TAGS=()
EDGE_FROM=()
EDGE_TO=()
EDGE_LABELS=()
EDGE_STYLES=()
EDGE_STATUS=()
EDGE_BIDIR=()
GROUP_IDS=()
GROUP_LABELS=()
GROUP_PARENTS=()

# Context arrays
USE_WHEN_CONDITIONS=()
USE_WHEN_THRESHOLDS=()
USE_WHEN_DETAILS=()
USE_NOT_CONDITIONS=()
USE_NOT_REASONS=()
COMP_NAMES=()
COMP_FILES=()
COMP_DOES=()
CONFIG_PARAMS=()
CONFIG_VALUES=()
CONFIG_NOTES=()
GOTCHA_ISSUES=()
GOTCHA_DETAILS=()
GOTCHA_FIXES=()
RECOVERY_ISSUES=()
RECOVERY_MEANS=()
RECOVERY_FIXES=()
ENTRY_CASES=()
ENTRY_COMMANDS=()
ENTRY_ENDPOINTS=()
DECISION_IDS=()
DECISION_TITLES=()
DECISION_STATUS=()
DECISION_REASONS=()
NOTE_CONTEXTS=()
NOTE_TEXTS=()
PATTERN_NAMES=()
PATTERN_FILES=()
PATTERN_FORS=()

# Sequence diagram arrays
PART_IDS=()
PART_LABELS=()
SEQ_REC_TYPES=()
SEQ_FROM=()
SEQ_TO=()
SEQ_LABELS=()
SEQ_MSG_TYPES=()
SEQ_ACTIVATE=()
SEQ_DEACTIVATE=()
SEQ_OVER=()
SEQ_TEXT=()

# Deployment diagram arrays
DEPLOY_ENV_IDS=()
DEPLOY_ENV_LABELS=()
DEPLOY_NODE_IDS=()
DEPLOY_NODE_LABELS=()
DEPLOY_NODE_ENVS=()
DEPLOY_NODE_PARENTS=()
DEPLOY_INST_IDS=()
DEPLOY_INST_COMPS=()
DEPLOY_INST_NODES=()
DEPLOY_INST_COUNTS=()
INFRA_NODE_IDS=()
INFRA_NODE_LABELS=()
INFRA_NODE_PARENTS=()

# Scenario arrays
SCENARIO_IDS=()
SCENARIO_INHERITS=()
SCENARIO_LABELS=()
OVERRIDE_SCENARIOS=()
OVERRIDE_TARGETS=()
OVERRIDE_FIELDS=()
OVERRIDE_VALUES=()
EXCLUDE_SCENARIOS=()
EXCLUDE_TARGETS=()

# View arrays
VIEW_IDS=()
VIEW_FILTERS=()
VIEW_INCLUDES=()
VIEW_EXCLUDES=()
VIEW_LABELS=()
VIEW_SCENARIOS=()
VIEW_LEVELS=()

# Collect elements based on diagram type
if [[ "$DIAGRAM_TYPE" == "sequence" ]]; then
    collect_sequence "$RESOLVED_INPUT"
    # Set flowchart counts to 0 for sequence diagrams (validation compatibility)
    NODE_COUNT=0
    EDGE_COUNT=0
    GROUP_COUNT=0
elif [[ "$DIAGRAM_TYPE" == "deployment" ]]; then
    collect_deployment "$RESOLVED_INPUT"
    collect_edges "$RESOLVED_INPUT"  # Edges still used for connections
    NODE_COUNT=0
    GROUP_COUNT=0
else
    collect_nodes "$RESOLVED_INPUT"
    collect_edges "$RESOLVED_INPUT"
    collect_groups "$RESOLVED_INPUT"
fi
collect_context "$RESOLVED_INPUT"

# Collect scenarios
collect_scenarios "$RESOLVED_INPUT"

# Validate --scenario if specified
if [[ -n "$SCENARIO" ]]; then
    if ! validate_scenario "$SCENARIO"; then
        echo "Error: Unknown scenario '$SCENARIO'" >&2
        list_scenarios >&2
        exit 1
    fi
fi

# Collect views
collect_views "$RESOLVED_INPUT"

# Validate --view if specified
if [[ -n "$VIEW" ]]; then
    if ! validate_view "$VIEW"; then
        echo "Error: Unknown view '$VIEW'" >&2
        list_views >&2
        exit 1
    fi
fi

# Apply scenario if specified
if [[ -n "$SCENARIO" ]]; then
    if ! apply_scenario "$SCENARIO"; then
        exit 1
    fi
fi

# Apply view if specified (after scenario)
if [[ -n "$VIEW" ]]; then
    if ! apply_view "$VIEW"; then
        exit 1
    fi
fi

# Warn if diagram has no content (check AFTER scenario/view filtering)
if [[ "$DIAGRAM_TYPE" == "sequence" ]]; then
    if ((PART_COUNT == 0)); then
        warn "Diagram has no participants"
    fi
elif [[ "$DIAGRAM_TYPE" == "deployment" ]]; then
    if ((DEPLOY_ENV_COUNT == 0)) && ((DEPLOY_NODE_COUNT == 0)); then
        warn "Diagram has no deployment environments or nodes"
    fi
else
    remaining_nodes=0
    for ((n=0; n<NODE_COUNT; n++)); do
        [[ -n "${NODE_IDS[$n]}" ]] && remaining_nodes=$((remaining_nodes + 1))
    done
    if ((remaining_nodes == 0)); then
        if ((NODE_COUNT > 0)); then
            warn "All nodes were excluded by scenario/view — diagram will be empty"
        else
            warn "Diagram has no nodes"
        fi
    fi
fi

# === OUTPUT GENERATION ===

# Handle validate-only mode
if [[ "$VALIDATE" == "true" ]]; then
    validate_diagram
    exit $?
fi

# Generate Mermaid content based on diagram type
case "$DIAGRAM_TYPE" in
    sequence)
        MERMAID_CONTENT=$(generate_sequence)
        ;;
    deployment)
        MERMAID_CONTENT=$(generate_deployment)
        ;;
    *)
        MERMAID_CONTENT=$(generate_flowchart)
        ;;
esac
CONTEXT_CONTENT=$(generate_context_sections)

# Get scenario label if applicable
SCENARIO_SUFFIX=""
if [[ -n "$SCENARIO" ]]; then
    for ((s=0; s<SCENARIO_COUNT; s++)); do
        if [[ "${SCENARIO_IDS[$s]}" == "$SCENARIO" ]]; then
            SCENARIO_SUFFIX=" (${SCENARIO_LABELS[$s]:-$SCENARIO})"
            break
        fi
    done
fi

# Write markdown output
cat > "$OUTPUT" <<EOF
# ${DIAGRAM_PURPOSE:-$DIAGRAM_ID}${SCENARIO_SUFFIX}

> ${DIAGRAM_PURPOSE:-Diagram}

## Diagram

\`\`\`mermaid
$MERMAID_CONTENT
\`\`\`
$CONTEXT_CONTENT
EOF

echo "Generated: $OUTPUT"

# Optionally write .mmd file
if [[ "$MMD" == "true" ]]; then
    MMD_FILE="${OUTPUT%.diagram.md}.mmd"
    echo "$MERMAID_CONTENT" > "$MMD_FILE"
    echo "Generated: $MMD_FILE"
fi
