#!/usr/bin/env bash
# session-context.sh — Builds SessionStart prompt from config + artifact scan
# Source this file; do not execute directly.
# Functions: gdl_find_root, gdl_config_val, gdl_scan_artifacts, gdl_scan_rules, gdl_metrics_oneliner, gdl_build_prompt, gdl_memory_enabled, gdl_welcome_banner, gdl_session_context

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
# Returns: "gdl:N,gdls:N,gdlc:N,gdld:N,gdlm:N,gdlu:N,total:N" or "total:0"
gdl_scan_artifacts() {
  local root="$1"
  [[ ! -d "$root" ]] && echo "total:0" && return 0

  local total=0
  local counts=""
  for ext in gdl gdls gdlc gdla gdld gdlm gdlu; do
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

# Scan for rules.gdl and return its contents for injection
# Usage: gdl_scan_rules <project_dir>
# Returns: formatted rules block or empty
gdl_scan_rules() {
  local project_dir="$1"
  local rules_file="${project_dir}/rules.gdl"

  [[ ! -f "$rules_file" ]] && return 0

  # Collect matching lines into an accumulator
  local has_rules=false
  local rule_lines=""
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" != @rule\|* ]] && continue
    has_rules=true
    rule_lines="${rule_lines}${line}
"
  done < "$rules_file"

  [[ "$has_rules" == "false" ]] && return 0

  printf '\n\n## Active Rules (from rules.gdl)\n\n'
  printf 'When editing files, apply these rules based on scope match:\n\n'
  printf '%s' "$rule_lines"
  printf '\nBefore writing or editing code, check which rules match the target file'\''s path.\n'
  printf 'Violations of severity:error must be fixed. severity:warn should be flagged.\n'
}

# Build a one-liner metrics summary from sessions.gdl
# Usage: gdl_metrics_oneliner <gdl_root_abs>
# Returns: formatted one-liner or empty
gdl_metrics_oneliner() {
  local gdl_root="$1"
  local metrics_file="${gdl_root}/metrics/sessions.gdl"
  [[ ! -f "$metrics_file" ]] && return 0
  [[ ! -s "$metrics_file" ]] && return 0

  local sessions avg_tc gdl_rate mem_count
  sessions=$(grep -c '^@metric' "$metrics_file" 2>/dev/null) || sessions=0
  (( sessions == 0 )) && return 0

  avg_tc=$(awk -F'|' '/^@metric/{n++;for(i=2;i<=NF;i++){split($i,kv,":");if(kv[1]=="tool_calls")s+=kv[2]}}END{if(n>0)printf "%.0f",s/n}' "$metrics_file") || avg_tc=0

  gdl_rate=$(awk -F'|' '/^@metric/{n++;for(i=2;i<=NF;i++){split($i,kv,":");if(kv[1]=="gdl_refs"&&kv[2]+0>0)g++}}END{if(n>0)printf "%.0f",g/n*100}' "$metrics_file") || gdl_rate=0

  local mem_dir="${gdl_root}/memory/active"
  mem_count=0
  if [[ -d "$mem_dir" ]] && ls "$mem_dir"/*.gdlm >/dev/null 2>&1; then
    mem_count=$(grep -ch '^@memory' "$mem_dir"/*.gdlm 2>/dev/null | awk '{s+=$1}END{print s+0}') || mem_count=0
  fi

  echo "greppable: ${sessions} sessions tracked · avg ${avg_tc} tool calls/session · ${mem_count} memories · ${gdl_rate}% GDL reference rate"
}

# Check if memory capture is enabled via config cascade
# Usage: gdl_memory_enabled [project_dir]
# Returns: 0 if enabled, 1 if not
gdl_memory_enabled() {
  local project_dir="${1:-.}"
  local global_config="$HOME/.claude/greppable.local.md"
  local project_config="${project_dir}/.claude/greppable.local.md"
  local val=""
  [[ -f "$global_config" ]] && val=$(gdl_config_val "$global_config" "memory")
  if [[ -f "$project_config" ]]; then
    local pv
    pv=$(gdl_config_val "$project_config" "memory")
    [[ -n "$pv" ]] && val="$pv"
  fi
  [[ "$val" == "true" ]]
}

# Extract scope hints from GDL artifacts for session-start prompt
# Usage: gdl_artifact_hints <gdl_root> <format>
# Returns: semicolon-separated scope hints (e.g., "auth, api, parsers")
gdl_artifact_hints() {
  local root="$1" fmt="$2"
  [[ ! -d "$root" ]] && return 0

  case "$fmt" in
    gdlc)
      # Extract unique @D module prefixes (last path component)
      # Note: paste -sd',' uses single-char delimiter (BSD paste treats multi-char as alternating)
      find "$root" -maxdepth 3 -name "*.gdlc" 2>/dev/null \
        | head -20 \
        | while read -r f; do grep '^@D ' "$f" 2>/dev/null; done \
        | sed 's/^@D //' | cut -d'|' -f1 | awk -F'/' '{print $NF}' \
        | sort -u | head -5 | paste -sd',' - | sed 's/,/, /g' || true
      ;;
    gdlm)
      # Extract recent memory subjects (use find, not glob — avoids bash 3.x nullglob issue)
      find "$root/memory/active" -name '*.gdlm' -maxdepth 1 2>/dev/null \
        | head -20 \
        | while read -r f; do grep '^@memory' "$f" 2>/dev/null; done \
        | grep -o 'subject:[^|]*' | sed 's/subject://' \
        | tail -5 | paste -sd';' - | sed 's/;/; /g' || true
      ;;
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
# Only checks bridge-generated formats: .gdlc, .gdls, .gdla
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
  local bridge_formats="gdlc gdls gdla"

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
          gdlc) bridge_hint="src2gdlc.sh" ;;
          gdls) bridge_hint="db2gdls.sh, sql2gdls.sh, or prisma2gdls.sh" ;;
          gdla) bridge_hint="openapi2gdla.sh or graphql2gdla.sh" ;;
        esac
        stale_lines="${stale_lines}\n  ${fname} - generated ${gen_date} (${age_days} days ago), refresh with ${bridge_hint}"
      fi
    done <<< "$file_list"
  done

  [[ -z "$stale_lines" ]] && return 0
  # Use printf '%s' (not echo -e) so \n stays literal — the outer echo -e in gdl_build_prompt expands it
  printf '%s' "**Stale artifacts detected:**${stale_lines}\nRun /greppable:discover to regenerate all, or run the specific bridge command above."
}

# Build the dynamic prompt based on artifacts
# Usage: gdl_build_prompt <artifact_summary> <enabled> [gdl_root_abs] [memory]
# Requires: PLUGIN_ROOT env var (set by hooks that source this file)
# Returns: prompt string for hookSpecificOutput, or empty if disabled
gdl_build_prompt() {
  local artifacts="$1" enabled="$2"
  local gdl_root_abs="${3:-}" memory="${4:-}"

  # Quick exit if disabled
  [[ "$enabled" != "true" && "$enabled" != "" ]] && return 0
  # If no artifacts, nothing to inject
  [[ -z "$artifacts" || "$artifacts" == "total:0" ]] && return 0

  local prompt="[GDL]"

  prompt="$prompt\n\nActive artifacts in this project:"
  # Parse artifact summary into readable lines
  local OLD_IFS="$IFS"
  IFS=','
  for pair in $artifacts; do
    local ext="${pair%%:*}"
    local count="${pair##*:}"
    [[ "$ext" == "total" ]] && continue
    local label=""
    case "$ext" in
      gdl)  label="structured data" ;;
      gdls) label="schema maps" ;;
      gdlc) label="code maps" ;;
      gdla) label="API contracts" ;;
      gdld) label="architecture diagrams" ;;
      gdlm) label="agent memory" ;;
      gdlu) label="document indexes" ;;
    esac
    prompt="$prompt\n- .${ext}: ${count} file(s) (${label})"
    # Add scope hints if available
    if [[ -n "$gdl_root_abs" ]]; then
      local hints
      hints=$(gdl_artifact_hints "$gdl_root_abs" "$ext") || true
      if [[ -n "$hints" ]]; then
        prompt="$prompt — ${hints}"
      fi
    fi
  done
  IFS="$OLD_IFS"

  # Inject using-greppable skill content as guarantee layer (single source of truth)
  local skill_file="${PLUGIN_ROOT:-}/skills/using-greppable/SKILL.md"
  if [[ -f "$skill_file" ]]; then
    local skill_body=""
    local in_frontmatter=0
    local past_frontmatter=0
    while IFS= read -r line; do
      if [[ "$line" == "---" ]]; then
        if [[ $in_frontmatter -eq 1 ]]; then
          past_frontmatter=1
          in_frontmatter=0
          continue
        elif [[ $past_frontmatter -eq 0 ]]; then
          in_frontmatter=1
          continue
        fi
      fi
      if [[ $past_frontmatter -eq 1 ]]; then
        skill_body="$skill_body\n$line"
      fi
    done < "$skill_file"
    if [[ -n "$skill_body" ]]; then
      prompt="$prompt\n$skill_body"
    fi
  fi

  # Append metrics one-liner if available
  if [[ -n "$gdl_root_abs" ]]; then
    local metrics_line
    metrics_line=$(gdl_metrics_oneliner "$gdl_root_abs") || true
    if [[ -n "$metrics_line" ]]; then
      prompt="$prompt\n\n$metrics_line"
    fi
  fi

  # Staleness warnings for bridge-generated artifacts
  if [[ -n "$gdl_root_abs" ]]; then
    local staleness_warning
    staleness_warning=$(gdl_staleness_check "$gdl_root_abs") || true
    if [[ -n "$staleness_warning" ]]; then
      prompt="$prompt\n\n$staleness_warning"
    fi
  fi

  # Append memory pointer if memory is enabled (content accessed via skills, not injected)
  if [[ "$memory" == "true" ]] && [[ -n "$gdl_root_abs" ]]; then
    local mem_dir="${gdl_root_abs}/memory/active"
    if [[ -d "$mem_dir" ]] && ls "$mem_dir"/*.gdlm >/dev/null 2>&1; then
      local mem_count
      mem_count=$(grep -hc '^@memory' "$mem_dir"/*.gdlm 2>/dev/null | awk '{s+=$1} END {print s+0}') || mem_count=0
      if (( mem_count > 0 )); then
        prompt="$prompt\n\nAgent memory: ${mem_count} records in memory/active/*.gdlm — consult before implementation decisions or when investigating past choices."
      fi
    fi
  fi

  # Check memory record count for compaction nudge
  if [[ "$memory" == "true" ]] && [[ -n "$gdl_root_abs" ]]; then
    local mem_dir="${gdl_root_abs}/memory/active"
    if [[ -d "$mem_dir" ]] && ls "$mem_dir"/*.gdlm >/dev/null 2>&1; then
      local mem_count
      mem_count=$(grep -h '^@memory' "$mem_dir"/*.gdlm 2>/dev/null | wc -l | tr -d ' ') || mem_count=0
      if (( mem_count > 200 )); then
        prompt="$prompt\n\n**Memory compaction recommended** — active memory has $mem_count records (threshold: 200). Run \`gdlm-compact.sh\` to archive aging records."
      fi
    fi
  fi

  echo -e "$prompt"
}

# Plain-text ASCII welcome banner for first-run detection
# No ANSI codes — output goes into additionalContext for Claude to display
# Usage: gdl_welcome_banner
gdl_welcome_banner() {
  cat <<'BANNER'
$ grep -rn "greppable" /dev/universe

 ██████╗ ██████╗ ███████╗██████╗ ██████╗  █████╗ ██████╗ ██╗     ███████╗
██╔════╝ ██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║     ██╔════╝
██║  ███╗██████╔╝█████╗  ██████╔╝██████╔╝███████║██████╔╝██║     █████╗
██║   ██║██╔══██╗██╔══╝  ██╔═══╝ ██╔═══╝ ██╔══██║██╔══██╗██║     ██╔══╝
╚██████╔╝██║  ██║███████╗██║     ██║     ██║  ██║██████╔╝███████╗███████╗
 ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝     ╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝
                                                                        .ai

 1 match · the grep-native language for agentic systems

Welcome! Run /greppable:onboard to get started.
BANNER
}

# Main entry point: read config, scan artifacts, build prompt
# Usage: gdl_session_context [project_dir]
# Outputs: prompt string, welcome banner (first-run), or empty
gdl_session_context() {
  local project_dir="${1:-.}"

  # Read config: project wins over global
  local global_config="$HOME/.claude/greppable.local.md"
  local project_config="${project_dir}/.claude/greppable.local.md"

  local enabled="" gdl_root="" discovery_auto_prompt="" memory=""

  # Global defaults
  if [[ -f "$global_config" ]]; then
    enabled=$(gdl_config_val "$global_config" "enabled")
    gdl_root=$(gdl_config_val "$global_config" "gdl_root")
    discovery_auto_prompt=$(gdl_config_val "$global_config" "discovery_auto_prompt")
    memory=$(gdl_config_val "$global_config" "memory")
  fi

  # Project overrides
  if [[ -f "$project_config" ]]; then
    local v
    v=$(gdl_config_val "$project_config" "enabled")
    [[ -n "$v" ]] && enabled="$v"
    v=$(gdl_config_val "$project_config" "gdl_root")
    [[ -n "$v" ]] && gdl_root="$v"
    v=$(gdl_config_val "$project_config" "discovery_auto_prompt")
    [[ -n "$v" ]] && discovery_auto_prompt="$v"
    v=$(gdl_config_val "$project_config" "memory")
    [[ -n "$v" ]] && memory="$v"
  fi

  # Default gdl_root
  [[ -z "$gdl_root" ]] && gdl_root="docs/gdl"

  # Scan for artifacts (always, even without config)
  local artifacts
  artifacts=$(gdl_scan_artifacts "${project_dir}/${gdl_root}")

  # If no config AND no artifacts → first run check
  if [[ -z "$enabled" && ("$artifacts" == "total:0" || -z "$artifacts") ]]; then
    local marker="$HOME/.claude/.greppable-welcomed"
    if [[ ! -f "$marker" ]]; then
      gdl_welcome_banner
      mkdir -p "$HOME/.claude" 2>/dev/null || true
      touch "$marker" 2>/dev/null || true
    fi
    return 0
  fi

  # If artifacts found but no config, enable by default
  if [[ -z "$enabled" && "$artifacts" != "total:0" ]]; then
    enabled="true"
  fi

  # If explicitly disabled, exit
  [[ "$enabled" == "false" ]] && return 0

  # Build prompt
  local gdl_root_abs="${project_dir}/${gdl_root}"
  local prompt
  prompt=$(gdl_build_prompt "$artifacts" "$enabled" "$gdl_root_abs" "$memory")

  [[ -z "$prompt" ]] && return 0

  # Append rules if rules.gdl exists
  local rules_block
  rules_block=$(gdl_scan_rules "$project_dir") || true
  if [[ -n "$rules_block" ]]; then
    prompt="${prompt}${rules_block}"
  fi

  echo "$prompt"
}

