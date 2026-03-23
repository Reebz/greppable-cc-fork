#!/usr/bin/env bash
# GDL Tools - Reference implementations for common GDL operations
# Source this file: source scripts/gdl-tools.sh

# Convert CSV to GDL
# Usage: csv2gdl <type> <file.csv>
csv2gdl() {
    local type="$1"
    local file="$2"
    if [[ -z "$type" || -z "$file" ]]; then
        echo "Usage: csv2gdl <type> <file.csv>" >&2
        return 1
    fi
    local header=$(head -1 "$file" | tr -d '\r')
    IFS=',' read -ra cols <<< "$header"
    tail -n +2 "$file" | while IFS=',' read -ra vals; do
        printf "@%s" "$type"
        for i in "${!cols[@]}"; do
            printf "|%s:%s" "${cols[$i]}" "${vals[$i]}"
        done
        printf "\n"
    done
}

# Describe a GDL file
# Usage: gdl_describe <file.gdl>
gdl_describe() {
    local file="$1"
    if [[ -z "$file" ]]; then
        echo "Usage: gdl_describe <file.gdl>" >&2
        return 1
    fi
    echo "=== Record Types ==="
    cut -d'|' -f1 "$file" | grep "^@" | sort | uniq -c | sort -rn
    echo ""
    echo "=== Sample Records ==="
    cut -d'|' -f1 "$file" | grep "^@" | sort -u | while read -r type; do
        echo "$type:"
        grep "^$type" "$file" | head -1 | tr '|' '\n' | tail -n +2 | sed 's/^/  /'
        echo ""
    done
}

# Get latest version of a record by ID
# Usage: gdl_latest <id> <file.gdl>
gdl_latest() {
    local id="$1"
    local file="$2"
    if [[ -z "$id" || -z "$file" ]]; then
        echo "Usage: gdl_latest <id> <file.gdl>" >&2
        return 1
    fi
    grep "id:$id" "$file" | tail -1
}

# List unique values for a field
# Usage: gdl_values <type> <field> <file.gdl>
gdl_values() {
    local type="$1"
    local field="$2"
    local file="$3"
    if [[ -z "$type" || -z "$field" || -z "$file" ]]; then
        echo "Usage: gdl_values <type> <field> <file.gdl>" >&2
        return 1
    fi
    grep "^@$type" "$file" | sed -n "s/.*${field}:\([^|]*\).*/\1/p" | sort -u
}

# Convert JSON or JSONL to GDL records
# Usage: json2gdl <type> <file.json|file.jsonl|->
# Supports: JSON arrays, JSONL (one object per line), stdin via -
json2gdl() {
    local type="${1:-}"
    local file="${2:-}"
    if [[ -z "$type" || -z "$file" ]]; then
        echo "Usage: json2gdl <type> <file.json|file.jsonl|->" >&2
        return 1
    fi

    local input
    if [[ "$file" == "-" ]]; then
        input=$(cat)
    elif [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file. Check path or ensure the file exists." >&2
        return 1
    else
        input=$(cat "$file")
    fi

    # Detect format: JSON array starts with [, JSONL has one object per line
    local jq_filter
    if echo "$input" | head -c 1 | grep -q '\['; then
        jq_filter='.[]'
    else
        jq_filter='.'
    fi

    echo "$input" | jq -r "$jq_filter"' | "@'"$type"'|" + (to_entries | map(
        .key + ":" + (
            .value | tostring
            | gsub("\\\\"; "\\\\")
            | gsub("\\|"; "\\|")
            | gsub(":"; "\\:")
            | gsub("\n"; "\\n")
            | gsub("\r"; "\\r")
            | gsub("\t"; "\\t")
        )
    ) | join("|"))'
}

# Search across all GDL-family layers for a topic
# Usage: gdl_about <topic> [base_dir] [--layer=LAYER] [--exclude-layer=LAYERS] [--summary] [--regex] [--ignore-case]
gdl_about() {
    local topic="${1:-}"
    if [[ -z "$topic" ]]; then
        echo "Usage: gdl_about <topic> [base_dir] [--layer=LAYER] [--exclude-layer=LAYERS] [--summary] [--regex] [--ignore-case]" >&2
        return 1
    fi

    local base="${2:-.}"
    local layer_filter=""
    local summary=false
    local regex_mode=false
    local ignore_case=false
    local exclude_layers=""

    # Parse flags from any position
    local args=()
    for arg in "$@"; do
        case "$arg" in
            --layer=*)
                layer_filter="${arg#--layer=}"
                if [[ ! "$layer_filter" =~ ^(gdls|gdlc|gdld|gdlm|gdl|gdlu|gdla)$ ]]; then
                    echo "Usage: gdl_about <topic> [base_dir] [--layer=LAYER] [--exclude-layer=LAYERS] [--summary] [--regex] [--ignore-case]" >&2
                    echo "Error: Invalid layer '$layer_filter'. Must be one of: gdl, gdls, gdlc, gdld, gdlm, gdlu, gdla" >&2
                    return 1
                fi
                ;;
            --summary) summary=true ;;
            --regex|-E) regex_mode=true ;;
            --ignore-case|-i) ignore_case=true ;;
            --exclude-layer=*)
                local excl="${arg#--exclude-layer=}"
                # Validate each comma-separated layer
                local IFS_OLD="$IFS"
                IFS=','
                for elyr in $excl; do
                    [[ -z "$elyr" ]] && continue  # Skip empty elements from trailing/double commas
                    if [[ ! "$elyr" =~ ^(gdls|gdlc|gdld|gdlm|gdl|gdlu|gdla)$ ]]; then
                        echo "Usage: gdl_about <topic> [base_dir] [--layer=LAYER] [--exclude-layer=LAYERS] [--summary] [--regex] [--ignore-case]" >&2
                        echo "Error: Invalid exclude layer '$elyr'. Must be one of: gdl, gdls, gdlc, gdld, gdlm, gdlu, gdla" >&2
                        IFS="$IFS_OLD"
                        return 1
                    fi
                done
                IFS="$IFS_OLD"
                exclude_layers=",$excl,"  # Wrap with commas for substring matching
                ;;
            *) args+=("$arg") ;;
        esac
    done

    # Re-extract positional args after flag parsing
    topic="${args[0]:-}"
    base="${args[1]:-.}"

    if [[ -z "$topic" ]]; then
        echo "Usage: gdl_about <topic> [base_dir] [--layer=LAYER] [--exclude-layer=LAYERS] [--summary] [--regex] [--ignore-case]" >&2
        return 1
    fi

    # Resolve version from plugin.json (printed on first match)
    local _gdl_version=""
    local _plugin_json=""
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ]]; then
        _plugin_json="${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
    else
        local _script_dir
        _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || true
        if [[ -n "$_script_dir" && -f "${_script_dir}/../.claude-plugin/plugin.json" ]]; then
            _plugin_json="${_script_dir}/../.claude-plugin/plugin.json"
        fi
    fi
    if [[ -n "$_plugin_json" ]]; then
        _gdl_version=$(grep '"version"' "$_plugin_json" 2>/dev/null | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/') || true
    fi

    local found_any=false

    # Search each layer
    local layers=("gdls" "gdla" "gdlc" "gdld" "gdlm" "gdl" "gdlu")
    for lyr in "${layers[@]}"; do
        # Skip if layer filter is set and doesn't match
        if [[ -n "$layer_filter" && "$layer_filter" != "$lyr" ]]; then
            continue
        fi

        # Skip if this layer is in the exclude list
        if [[ -n "$exclude_layers" && "$exclude_layers" == *",$lyr,"* ]]; then
            continue
        fi

        local grep_mode="-F"
        [[ "$regex_mode" == "true" ]] && grep_mode="-E"
        local grep_flags="-rn${grep_mode#-}"
        [[ "$ignore_case" == "true" ]] && grep_flags="${grep_flags}i"
        local matches
        matches=$(find "$base" -name "*.$lyr" -exec grep $grep_flags -- "$topic" {} + 2>/dev/null) || true

        if [[ -n "$matches" ]]; then
            if [[ "$found_any" == "false" && -n "$_gdl_version" ]]; then
                echo "# Greppable v${_gdl_version}"
                echo ""
            fi
            found_any=true
            local header
            header=$(echo "$lyr" | tr '[:lower:]' '[:upper:]')
            echo "## $header"
            if [[ "$summary" == "true" ]]; then
                local count
                count=$(echo "$matches" | wc -l | tr -d ' ')
                echo "  $count match(es)"
            else
                echo "$matches" | sed 's/^/  /'
            fi
            echo ""
        fi
    done

    if [[ "$found_any" == "false" ]]; then
        echo "No matches found for '$topic' in $base" >&2
        return 1
    fi
}

# Generate a new GDL record with auto-incremented ID
# Usage: gdl_new memory --agent=AGENT --subject=SUBJ --detail=TEXT --file=FILE [--type=TYPE] [--tags=TAGS] [--confidence=LEVEL] [--relates=IDS] [--anchor=ANCHOR] [--source=SRC] [--append]
#        gdl_new source --path=PATH --format=FMT --type=TYPE --summary=TEXT --file=FILE [--append]
gdl_new() {
    local record_type="${1:-}"
    if [[ -z "$record_type" ]]; then
        echo "Usage: gdl_new <memory|source> --agent=AGENT --subject=SUBJ --detail=TEXT --file=FILE" >&2
        return 1
    fi
    shift

    local agent="" subject="" detail="" file="" path_val="" format="" content_type="" summary="" append=false
    local mem_tags="" mem_confidence="" mem_relates="" mem_anchor="" mem_source=""
    for arg in "$@"; do
        case "$arg" in
            --agent=*) agent="${arg#--agent=}" ;;
            --subject=*) subject="${arg#--subject=}" ;;
            --detail=*) detail="${arg#--detail=}" ;;
            --file=*) file="${arg#--file=}" ;;
            --path=*) path_val="${arg#--path=}" ;;
            --format=*) format="${arg#--format=}" ;;
            --type=*) content_type="${arg#--type=}" ;;
            --summary=*) summary="${arg#--summary=}" ;;
            --tags=*) mem_tags="${arg#--tags=}" ;;
            --confidence=*) mem_confidence="${arg#--confidence=}" ;;
            --relates=*) mem_relates="${arg#--relates=}" ;;
            --anchor=*) mem_anchor="${arg#--anchor=}" ;;
            --source=*) mem_source="${arg#--source=}" ;;
            --append) append=true ;;
        esac
    done

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    case "$record_type" in
        memory)
            if [[ -z "$agent" ]]; then
                echo "Error: --agent is required. Use: gdl_new memory --agent=NAME --subject=\"...\" --detail=\"...\" --file=PATH" >&2
                return 1
            fi
            if [[ -z "$file" ]]; then
                echo "Error: --file is required. Use: gdl_new memory --agent=NAME --subject=\"...\" --detail=\"...\" --file=PATH" >&2
                return 1
            fi

            # Function to find max sequence for this agent (used inside and outside lock)
            _gdl_new_memory_gen() {
                local target_file="$1"
                local max_seq=0
                if [[ -s "$target_file" ]]; then
                    local pattern="id:M-${agent}-"
                    while IFS= read -r match; do
                        [[ -z "$match" ]] && continue
                        # Extract sequence number: M-{agent}-NNN
                        local seq_str
                        seq_str=$(echo "$match" | sed -n "s/.*id:M-${agent}-\([0-9][0-9]*\).*/\1/p")
                        if [[ -n "$seq_str" ]]; then
                            local seq_num=$((10#$seq_str))
                            if (( seq_num > max_seq )); then
                                max_seq=$seq_num
                            fi
                        fi
                    done <<< "$(grep "$pattern" "$target_file" 2>/dev/null || true)"
                fi
                local next_seq=$((max_seq + 1))
                printf "M-%s-%03d" "$agent" "$next_seq"
            }

            # Build record with optional fields
            _gdl_build_memory_record() {
                local id="$1"
                local record="@memory|id:$id|agent:$agent|subject:$subject"
                [[ -n "$content_type" ]] && record+="|type:$content_type"
                [[ -n "$mem_tags" ]] && record+="|tags:$mem_tags"
                record+="|detail:$detail"
                [[ -n "$mem_confidence" ]] && record+="|confidence:$mem_confidence"
                [[ -n "$mem_relates" ]] && record+="|relates:$mem_relates"
                [[ -n "$mem_anchor" ]] && record+="|anchor:$mem_anchor"
                [[ -n "$mem_source" ]] && record+="|source:$mem_source"
                record+="|ts:$ts"
                echo "$record"
            }

            if [[ "$append" == "true" ]]; then
                if [[ ! -f "$file" ]]; then
                    echo "Error: file '$file' does not exist (use touch to create first)" >&2
                    return 1
                fi
                local lockdir="$file.lock"
                local retries=0
                while ! mkdir "$lockdir" 2>/dev/null; do
                    retries=$((retries + 1))
                    if (( retries > 50 )); then
                        echo "Error: cannot acquire lock on '$file' after 5s" >&2
                        return 1
                    fi
                    sleep 0.1
                done
                local id
                id=$(_gdl_new_memory_gen "$file") || { rmdir "$lockdir" 2>/dev/null; return 1; }
                _gdl_build_memory_record "$id" >> "$file" || { rmdir "$lockdir" 2>/dev/null; return 1; }
                rmdir "$lockdir" 2>/dev/null
            else
                local id
                id=$(_gdl_new_memory_gen "$file")
                _gdl_build_memory_record "$id"
            fi
            ;;
        source)
            if [[ -z "$file" ]]; then
                echo "Error: --file is required. Use: gdl_new source --path=PATH --format=FMT --type=TYPE --summary=\"...\" --file=PATH" >&2
                return 1
            fi

            _gdl_new_source_gen() {
                local target_file="$1"
                local max_seq=0
                if [[ -s "$target_file" ]]; then
                    while IFS= read -r match; do
                        [[ -z "$match" ]] && continue
                        local seq_str
                        seq_str=$(echo "$match" | sed -n 's/.*id:U-\([0-9][0-9]*\).*/\1/p')
                        if [[ -n "$seq_str" ]]; then
                            local seq_num=$((10#$seq_str))
                            if (( seq_num > max_seq )); then
                                max_seq=$seq_num
                            fi
                        fi
                    done <<< "$(grep "^@source" "$target_file" 2>/dev/null || true)"
                fi
                local next_seq=$((max_seq + 1))
                printf "U-%03d" "$next_seq"
            }

            if [[ "$append" == "true" ]]; then
                if [[ ! -f "$file" ]]; then
                    echo "Error: file '$file' does not exist (use touch to create first)" >&2
                    return 1
                fi
                local lockdir="$file.lock"
                local retries=0
                while ! mkdir "$lockdir" 2>/dev/null; do
                    retries=$((retries + 1))
                    if (( retries > 50 )); then
                        echo "Error: cannot acquire lock on '$file' after 5s" >&2
                        return 1
                    fi
                    sleep 0.1
                done
                local id
                id=$(_gdl_new_source_gen "$file") || { rmdir "$lockdir" 2>/dev/null; return 1; }
                echo "@source|id:$id|path:$path_val|format:$format|type:$content_type|summary:$summary|ts:$ts" >> "$file" || { rmdir "$lockdir" 2>/dev/null; return 1; }
                rmdir "$lockdir" 2>/dev/null
            else
                local id
                id=$(_gdl_new_source_gen "$file")
                echo "@source|id:$id|path:$path_val|format:$format|type:$content_type|summary:$summary|ts:$ts"
            fi
            ;;
        *)
            echo "Usage: gdl_new <memory|source> ..." >&2
            return 1
            ;;
    esac
}

# Match @rule records from a rules file by scope glob against a file path
# Usage: gdl_rules_for_file <file_path> [rules_file]
# Returns: matching @rule lines, one per line
gdl_rules_for_file() {
  local file_path="${1:-}"
  local rules_file="${2:-rules.gdl}"

  if [[ -z "$file_path" ]]; then
    echo "Usage: gdl_rules_for_file <file_path> [rules_file]" >&2
    return 1
  fi

  [[ ! -f "$rules_file" ]] && return 0

  while IFS= read -r line; do
    # Skip comments and blank lines
    [[ -z "$line" || "$line" == \#* ]] && continue
    # Only process @rule records
    [[ "$line" != @rule\|* ]] && continue

    # Extract scope field
    local scope=""
    scope=$(echo "$line" | sed 's/\\|/@@PIPE@@/g' | awk -F'|' '{
      for (i=1; i<=NF; i++) {
        if (index($i, "scope:") == 1) { print substr($i, 7); exit }
      }
    }' | sed 's/@@PIPE@@/|/g')

    [[ -z "$scope" ]] && continue

    # Match scope glob against file path using bash pattern matching
    # Convert glob to a bash-compatible pattern:
    #   ** -> matches any path (use a regex approach)
    #   *  -> matches within a segment
    local match=false

    # Simple cases first
    if [[ "$scope" == "*" ]]; then
      match=true
    elif [[ "$scope" == *"**"* ]]; then
      # Convert glob with ** to regex: **/ -> (.*/)?, ** -> .*, * -> [^/]*, . -> \.
      # First escape regex metacharacters that aren't glob operators (* and .)
      # Use sentinel to avoid mangling ** when converting single *
      local pattern="$scope"
      pattern=$(echo "$pattern" | sed 's/[\\[(){}+?^$]/\\&/g' | sed 's/]/\\]/g')
      pattern=$(echo "$pattern" | sed 's/\./\\./g')
      # **/ must match zero-or-more path segments (src/**/foo matches src/foo AND src/bar/foo)
      pattern=$(echo "$pattern" | sed 's/\*\*\//@@DSTARSLASH@@/g')
      pattern=$(echo "$pattern" | sed 's/\*\*/@@DSTAR@@/g')
      pattern=$(echo "$pattern" | sed 's/\*/[^\/]*/g')
      pattern=$(echo "$pattern" | sed 's/@@DSTARSLASH@@/(.*\/)?/g')
      pattern=$(echo "$pattern" | sed 's/@@DSTAR@@/.*/g')
      pattern="^${pattern}$"
      if echo "$file_path" | grep -qE "$pattern"; then
        match=true
      fi
    else
      # Simple glob: *.ext or prefix*
      # Use bash built-in pattern matching via case
      # shellcheck disable=SC2254
      case "$file_path" in
        $scope) match=true ;;
        */$scope) match=true ;;
      esac
    fi

    if [[ "$match" == "true" ]]; then
      echo "$line"
    fi
  done < "$rules_file"
}

# Read .gdlignore and return patterns applicable to a given format
# Usage: gdl_ignore_patterns <format> [ignore_file]
# Returns: one pattern per line (prefixes stripped), only matching format + unprefixed
gdl_ignore_patterns() {
  local format="${1:-}"
  local ignore_file="${2:-.gdlignore}"

  if [[ -z "$format" ]]; then
    echo "Usage: gdl_ignore_patterns <format> [ignore_file]" >&2
    return 1
  fi

  [[ ! -f "$ignore_file" ]] && return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and blank lines
    [[ -z "$line" || "$line" == \#* ]] && continue
    # Strip trailing whitespace
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue

    # Check for format prefix (e.g. gdlc:pattern)
    if [[ "$line" == *:* ]] && [[ "$line" =~ ^(gdl[a-z]*): ]]; then
      local prefix="${BASH_REMATCH[1]}"
      local pattern="${line#"$prefix":}"
      # Strip leading whitespace from pattern (handles "gdlc: pattern/" with space)
      pattern="${pattern#"${pattern%%[![:space:]]*}"}"
      if [[ -n "$pattern" ]] && [[ "$prefix" == "$format" ]]; then
        echo "$pattern"
      fi
    else
      # No prefix — applies to all formats
      echo "$line"
    fi
  done < "$ignore_file"
}

# Check if a path should be excluded based on .gdlignore patterns
# Usage: gdl_should_exclude <path> <format> [ignore_file]
# Returns: 0 if path should be excluded, 1 if it should be kept
gdl_should_exclude() {
  local filepath="${1:-}"
  local format="${2:-}"
  local ignore_file="${3:-.gdlignore}"

  if [[ -z "$filepath" || -z "$format" ]]; then
    echo "Usage: gdl_should_exclude <path> <format> [ignore_file]" >&2
    return 1
  fi

  [[ ! -f "$ignore_file" ]] && return 1  # No ignore file = keep everything

  local patterns
  patterns=$(gdl_ignore_patterns "$format" "$ignore_file") || return 1
  [[ -z "$patterns" ]] && return 1  # No patterns = keep everything

  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue

    # Directory pattern (trailing /)
    if [[ "$pattern" == */ ]]; then
      local dir_name="${pattern%/}"
      if [[ "$dir_name" == /* ]]; then
        # Root-relative: only match at start of path
        dir_name="${dir_name#/}"
        if [[ "$filepath" == "$dir_name/"* ]]; then
          return 0
        fi
      elif [[ "$dir_name" == *"**"* ]] || [[ "$dir_name" == *"*"* ]] || [[ "$dir_name" == *"?"* ]]; then
        # Glob directory pattern — convert to regex
        local regex="$dir_name"
        regex=$(echo "$regex" | sed 's/[.[\^$()+{}]/\\&/g')
        regex=$(echo "$regex" | sed 's/]/\\]/g')
        regex=$(echo "$regex" | sed 's/|/\\|/g')
        regex=$(echo "$regex" | sed 's/\*\*/@@DSTAR@@/g')
        regex=$(echo "$regex" | sed 's/\*/[^\/]*/g')
        regex=$(echo "$regex" | sed 's/?/[^\/]/g')
        regex=$(echo "$regex" | sed 's/@@DSTAR@@/.*/g')
        if echo "$filepath" | grep -qE "(^|/)${regex}/"; then
          return 0
        fi
      else
        # Bare directory name — match anywhere in path (segment-boundary)
        if [[ "$filepath" == "$dir_name/"* ]] || [[ "$filepath" == *"/$dir_name/"* ]]; then
          return 0
        fi
      fi
    # File glob pattern (no trailing /)
    elif [[ "$pattern" == *"*"* ]] || [[ "$pattern" == *"?"* ]]; then
      local regex="$pattern"
      regex=$(echo "$regex" | sed 's/[.[\^$()+{}]/\\&/g')
      regex=$(echo "$regex" | sed 's/]/\\]/g')
      regex=$(echo "$regex" | sed 's/|/\\|/g')
      regex=$(echo "$regex" | sed 's/\*\*/@@DSTAR@@/g')
      regex=$(echo "$regex" | sed 's/\*/[^\/]*/g')
      regex=$(echo "$regex" | sed 's/?/[^\/]/g')
      regex=$(echo "$regex" | sed 's/@@DSTAR@@/.*/g')
      if [[ "$pattern" == /* ]]; then
        # Root-relative glob
        regex="${regex#\\}"
        regex="^${regex#/}$"
      else
        # Match anywhere
        regex="(^|/)${regex}$"
      fi
      if echo "$filepath" | grep -qE "$regex"; then
        return 0
      fi
    else
      # Plain filename pattern (no trailing /, no glob) — exact basename match
      local fname
      fname=$(basename "$filepath")
      if [[ "$pattern" == /* ]]; then
        # Root-relative: match exact path
        if [[ "$filepath" == "${pattern#/}" ]]; then
          return 0
        fi
      elif [[ "$fname" == "$pattern" ]]; then
        return 0
      fi
    fi
  done <<< "$patterns"

  return 1  # No pattern matched = keep
}

echo "GDL Tools loaded. Available: csv2gdl, json2gdl, gdl_describe, gdl_latest, gdl_values, gdl_about, gdl_new, gdl_rules_for_file, gdl_ignore_patterns, gdl_should_exclude"
