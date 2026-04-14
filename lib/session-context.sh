#!/usr/bin/env bash
# session-context.sh — Shared utilities for GDL hooks and commands
# Source this file; do not execute directly.
# Functions: gdl_find_root, gdl_config_val, gdl_scan_artifacts, gdl_artifact_hints, gdl_staleness_check, gdl_json_hook_output, gdl_extract_file_path

# Walk up from a directory to find the GDL project root.
# Priority: .claude/greppable.local.md > git root > given dir
# Usage: gdl_find_root [dir]
# Returns: absolute path to the project root
gdl_find_root() {
    local dir="${1:-$(pwd)}"
    dir="$(cd "$dir" 2>/dev/null && pwd)" || dir="$(pwd)"
    local check="$dir"
    while [[ "$check" != "/" ]]; do
        if [[ -f "$check/.claude/greppable.local.md" ]]; then
            echo "$check"; return 0
        fi
        check="$(dirname "$check")"
    done
    local git_root
    git_root=$(cd "$dir" && git rev-parse --show-toplevel 2>/dev/null) || true
    if [[ -n "$git_root" ]]; then echo "$git_root"; return 0; fi
    echo "$dir"
}

# Extract a value from YAML frontmatter in a .local.md file
# Usage: gdl_config_val <file> <key>
# Returns: value string, or empty if key not found
gdl_config_val() {
  local file="$1" key="$2"
  [[ ! -f "$file" ]] && return 0
  # Validate frontmatter: must have opening and closing ---
  local marker_count
  marker_count=$(grep -c '^---$' "$file" 2>/dev/null) || true
  (( marker_count < 2 )) && return 0
  # Extract between --- markers, find key, extract value with awk (safe from regex injection)
  local val
  val=$(sed -n '/^---$/,/^---$/p' "$file" \
    | awk -F': ' -v k="$key" '$1 == k { print substr($0, length(k)+3); exit }') || true
  [[ -z "$val" ]] && return 0
  # Trim leading/trailing whitespace, then strip surrounding quotes
  val=$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  val=$(echo "$val" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
  echo "$val"
}

# Scan a directory for GDL artifacts, return summary
# Usage: gdl_scan_artifacts <gdl_root>
# Returns: "gdl:N,gdls:N,gdld:N,total:N" or "total:0"
gdl_scan_artifacts() {
  local root="$1"
  [[ ! -d "$root" ]] && echo "total:0" && return 0

  local total=0
  local counts=""
  for ext in gdl gdls gdla gdld gdlu; do
    local n
    n=$(find "$root" -maxdepth 3 -name "*.${ext}" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | wc -l | tr -d ' ')
    if (( n > 0 )); then
      [[ -n "$counts" ]] && counts="${counts},"
      counts="${counts}${ext}:${n}"
      total=$((total + n))
    fi
  done

  if (( total == 0 )); then
    echo "total:0"
  else
    echo "${counts},total:${total}"
  fi
}

# Extract scope hints from GDL artifacts for prompt context
# Usage: gdl_artifact_hints <gdl_root> <format>
# Returns: semicolon-separated scope hints (e.g., "auth, api, parsers")
gdl_artifact_hints() {
  local root="$1" fmt="$2"
  [[ ! -d "$root" ]] && return 0

  case "$fmt" in
    gdld)
      # Extract diagram titles (use find, not ** globs — bash 3.x has no globstar)
      find "$root" -name '*.gdld' -type f 2>/dev/null \
        | head -20 \
        | while read -r f; do grep '^@diagram' "$f" 2>/dev/null; done \
        | grep -o 'title:[^|]*' | sed 's/title://' \
        | head -5 | paste -sd';' - | sed 's/;/; /g' || true
      ;;
    gdls)
      # Extract table names (use find, not ** globs)
      find "$root" -name '*.gdls' -type f 2>/dev/null \
        | head -20 \
        | while read -r f; do grep '^@T ' "$f" 2>/dev/null; done \
        | sed 's/^@T //' | cut -d'|' -f1 \
        | sort -u | head -5 | paste -sd',' - | sed 's/,/, /g' || true
      ;;
    gdla)
      # Extract endpoint paths (use find, not ** globs)
      find "$root" -name '*.gdla' -type f 2>/dev/null \
        | head -20 \
        | while read -r f; do grep '^@EP' "$f" 2>/dev/null; done \
        | grep -o 'path:[^|]*' | sed 's/path://' \
        | sort -u | head -5 | paste -sd',' - | sed 's/,/, /g' || true
      ;;
    *) return 0 ;;
  esac
}

# Check bridge-generated artifacts for staleness based on @VERSION generated: date
# Usage: gdl_staleness_check <gdl_root>
# Returns: formatted warning lines, or empty if nothing is stale
# Only checks bridge-generated formats: .gdls, .gdla
# @VERSION is always line 1 in bridge-generated files (all current bridges)
# Threshold: 14 days (hardcoded for alpha; add config post-alpha if needed)
# Uses string comparison on YYYY-MM-DD (lexicographically sortable) to avoid per-file date forks
# Age display uses Julian Day Number formula (pure shell arithmetic, no forks in loop)
gdl_staleness_check() {
  local root="$1"
  [[ ! -d "$root" ]] && return 0

  local threshold=14
  # Calculate cutoff date once (avoids per-file date forks)
  local cutoff_date
  cutoff_date=$(date -v-${threshold}d +%Y-%m-%d 2>/dev/null) || \
  cutoff_date=$(date -d "${threshold} days ago" +%Y-%m-%d 2>/dev/null) || return 0

  # Pre-compute today's JDN for age calculation (no forks inside the loop)
  local today_str
  today_str=$(date +%Y-%m-%d)
  local ty=$((10#${today_str:0:4})) tm=$((10#${today_str:5:2})) td=$((10#${today_str:8:2}))
  local today_jdn=$(( (1461 * (ty + 4800 + (tm - 14) / 12)) / 4 + (367 * (tm - 2 - 12 * ((tm - 14) / 12))) / 12 - (3 * ((ty + 4900 + (tm - 14) / 12) / 100)) / 4 + td - 32075 ))

  local stale_lines=""
  local bridge_formats="gdls gdla"

  for ext in $bridge_formats; do
    local file_list
    file_list=$(find "$root" -maxdepth 3 -name "*.${ext}" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -50) || true
    [[ -z "$file_list" ]] && continue

    while IFS= read -r artifact; do
      [[ -z "$artifact" ]] && continue
      # Read first line with bash builtin (no fork), extract date with =~ regex (no fork)
      local first_line=""
      read -r first_line < "$artifact" 2>/dev/null || continue
      [[ -z "$first_line" ]] && continue
      local gen_date=""
      if [[ "$first_line" =~ generated:([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        gen_date="${BASH_REMATCH[1]}"
      else
        continue
      fi

      # Validate month/day ranges (JDN formula assumes valid calendar dates)
      local mm="${gen_date:5:2}" dd="${gen_date:8:2}"
      (( 10#$mm < 1 || 10#$mm > 12 || 10#$dd < 1 || 10#$dd > 31 )) && continue

      # String comparison: stale if gen_date < cutoff_date (YYYY-MM-DD is lexicographically sortable)
      if [[ "$gen_date" < "$cutoff_date" ]]; then
        local fname="${artifact##*/}"
        # Compute age in days via Julian Day Number (pure arithmetic, no fork)
        local gy=$((10#${gen_date:0:4})) gm=$((10#${gen_date:5:2})) gd=$((10#${gen_date:8:2}))
        local gen_jdn=$(( (1461 * (gy + 4800 + (gm - 14) / 12)) / 4 + (367 * (gm - 2 - 12 * ((gm - 14) / 12))) / 12 - (3 * ((gy + 4900 + (gm - 14) / 12) / 100)) / 4 + gd - 32075 ))
        local age_days=$(( today_jdn - gen_jdn ))
        local bridge_hint=""
        case "$ext" in
          gdls) bridge_hint="db2gdls.sh, sql2gdls.sh, or prisma2gdls.sh" ;;
          gdla) bridge_hint="openapi2gdla.sh or graphql2gdla.sh" ;;
        esac
        stale_lines="${stale_lines}\n  ${fname} - generated ${gen_date} (${age_days} days ago), refresh with ${bridge_hint}"
      fi
    done <<< "$file_list"
  done

  [[ -z "$stale_lines" ]] && return 0
  # Use printf '%s' (not echo -e) so \n stays literal for callers to expand
  printf '%s' "**Stale artifacts detected:**${stale_lines}\nRun /greppable:discover to regenerate all, or run the specific bridge command above."
}

# Escape a string for JSON and wrap in hookSpecificOutput envelope.
# Usage: gdl_json_hook_output <event_name> <context_string>
# Outputs: JSON to stdout
gdl_json_hook_output() {
  local event="$1" ctx="$2"
  # Escape in strict order: backslash first, then the rest
  ctx="${ctx//\\/\\\\}"
  ctx="${ctx//\"/\\\"}"
  ctx="${ctx//$'\n'/\\n}"
  ctx="${ctx//$'\t'/\\t}"
  ctx="${ctx//$'\r'/\\r}"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$ctx"
}

# Extract file_path from Claude Code hook stdin JSON.
# Usage: gdl_extract_file_path <json_string>
# Returns: file path string, or empty if not found
# Note: grep exits 1 on no match. The || true prevents pipefail from
# propagating a non-zero exit to callers running under set -euo pipefail.
gdl_extract_file_path() {
  local input="$1"
  [[ -z "$input" ]] && return 0
  local match
  match=$(echo "$input" | grep -o '"file_path":"[^"]*"' 2>/dev/null | head -1) || true
  [[ -z "$match" ]] && return 0
  # Extract value, then unescape JSON backslash pairs (\\ -> \).
  # Matches jq -r behavior for file paths. No-op on macOS/Linux (no backslashes in paths).
  echo "$match" | sed 's/"file_path":"//;s/"$//' | sed 's/\\\\/\\/g'
}
