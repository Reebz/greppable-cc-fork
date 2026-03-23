#!/usr/bin/env bash
# gdl-lint.sh — Validate GDL format files
# Usage: gdl-lint.sh <file.gdl[s|c|d|m|u|a]> [--strict]
#        gdl-lint.sh --all <directory> [--strict]
# Note: -e (errexit) intentionally omitted; we accumulate errors and report at end
set -uo pipefail

errors=0
warnings=0
ALL_GDLC_MODULES=""

err() { echo "  Error: $1" >&2; errors=$((errors + 1)); }
warn() { echo "  Warning: $1" >&2; warnings=$((warnings + 1)); }

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
    *.gdlignore) echo "gdlignore" ;;
    *) echo "unknown" ;;
  esac
}

# Extract a key:value field from a pipe-delimited line
_extract_field() {
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

# === GDL validation ===
lint_gdl() {
  local file="$1"
  local seen_ids=""
  local line_num=0

  while IFS= read -r line; do
    line_num=$((line_num + 1))
    # Skip comments and blank lines
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Must start with @type
    if [[ ! "$line" =~ ^@ ]]; then
      err "$file:$line_num: line does not start with @type"
      continue
    fi

    # Split on unescaped pipes, check each field has key:value
    local fields
    fields=$(echo "$line" | sed 's/\\|/@@PIPE@@/g' | tr '|' '\n' | tail -n +2)
    local has_colon_error=false
    while IFS= read -r field; do
      field=$(echo "$field" | sed 's/@@PIPE@@/|/g')
      [[ -z "$field" ]] && continue
      if [[ ! "$field" =~ : ]]; then
        has_colon_error=true
        err "$file:$line_num: missing colon in field '$field'"
      fi
    done <<< "$fields"

    # If any fields lack colons, likely unescaped pipe
    if [[ "$has_colon_error" == "true" ]]; then
      err "$file:$line_num: possible unescaped pipe (field(s) without key:value)"
    fi

    # Check for duplicate IDs
    local id_val
    id_val=$(_extract_field "$line" "id")
    if [[ -n "$id_val" ]]; then
      case "$seen_ids" in
        *"|$id_val|"*)
          err "$file:$line_num: duplicate id '$id_val'"
          ;;
      esac
      seen_ids="$seen_ids|$id_val|"
    fi

    # @rule-specific field validation
    if [[ "$line" == @rule\|* ]]; then
      local has_scope=false has_severity=false has_desc=false
      local severity_val=""
      local check_fields
      check_fields=$(echo "$line" | sed 's/\\|/@@PIPE@@/g' | tr '|' '\n' | tail -n +2)
      while IFS= read -r cf; do
        cf=$(echo "$cf" | sed 's/@@PIPE@@/|/g')
        [[ -z "$cf" ]] && continue
        case "$cf" in
          scope:*) has_scope=true ;;
          severity:*) has_severity=true; severity_val="${cf#severity:}" ;;
          desc:*) has_desc=true ;;
        esac
      done <<< "$check_fields"
      if [[ "$has_scope" == "false" ]]; then
        err "$file:$line_num: @rule missing required field 'scope'"
      fi
      if [[ "$has_severity" == "false" ]]; then
        err "$file:$line_num: @rule missing required field 'severity'"
      elif [[ -z "$severity_val" ]]; then
        err "$file:$line_num: @rule empty severity (must be error|warn|info)"
      else
        case "$severity_val" in
          error|warn|info) ;; # valid
          *) err "$file:$line_num: @rule invalid severity '$severity_val' (must be error|warn|info)" ;;
        esac
      fi
      if [[ "$has_desc" == "false" ]]; then
        err "$file:$line_num: @rule missing required field 'desc'"
      fi
    fi
  done < "$file"
}

# === GDLS validation ===
lint_gdls() {
  local file="$1"
  local tables=""
  local all_cols=""  # Flat string: "|TABLE.COLUMN|" entries (no eval needed)
  local external_tables="${2:-}"
  local external_cols="${3:-}"
  if [[ -n "$external_tables" ]]; then
    tables="$external_tables"
  fi
  if [[ -n "$external_cols" ]]; then
    all_cols="$external_cols"
  fi
  # Check for @FORMAT header (skip index files which use @META/@DOMAIN/@TABLES)
  local base_name
  base_name=$(basename "$file")
  if [[ "$base_name" != "_index.gdls" ]]; then
    local has_format_header=false
    while IFS= read -r fh_line; do
      [[ -z "$fh_line" ]] && continue
      [[ "$fh_line" == \#* ]] || break  # Stop at first non-comment, non-blank line
      case "$fh_line" in
        "# @FORMAT "*) has_format_header=true; break ;;
      esac
    done < "$file"
    if [[ "$has_format_header" == "false" ]]; then
      warn "$file: missing '# @FORMAT COLUMN|SQL_TYPE|NULLABLE|KEY|DESCRIPTION' header"
    fi
  fi

  local current_table=""
  local line_num=0

  # Pass 1: collect all table names and their columns
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    [[ -z "$line" || "$line" == \#* ]] && continue

    case "$line" in
      @T\ *)
        current_table=$(echo "$line" | cut -d'|' -f1 | sed 's/^@T //')
        tables="$tables|$current_table|"
        ;;
      @D\ *|@R\ *|@PATH\ *|@E\ *|@META\ *|@DOMAIN\ *|@TABLES\ *)
        current_table=""
        ;;
      *)
        if [[ -n "$current_table" ]]; then
          local col_name
          col_name=$(echo "$line" | cut -d'|' -f1)
          all_cols="$all_cols|${current_table}.${col_name}|"
        fi
        ;;
    esac
  done < "$file"

  # Pass 2: validate @R references
  line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    [[ -z "$line" || "$line" == \#* ]] && continue

    case "$line" in
      @R\ *)
        # Parse: @R source.col -> target.col|type|desc
        local ref_part
        ref_part=$(echo "$line" | cut -d'|' -f1 | sed 's/^@R //')
        local source_part target_part
        source_part=$(echo "$ref_part" | awk -F' -> ' '{print $1}')
        target_part=$(echo "$ref_part" | awk -F' -> ' '{print $2}')

        local source_table source_col target_table target_col
        source_table=$(echo "$source_part" | cut -d'.' -f1)
        source_col=$(echo "$source_part" | cut -d'.' -f2)
        target_table=$(echo "$target_part" | cut -d'.' -f1)
        target_col=$(echo "$target_part" | cut -d'.' -f2)

        # Check tables exist
        case "$tables" in
          *"|$source_table|"*) ;;
          *) err "$file:$line_num: @R references unknown table '$source_table'" ;;
        esac
        case "$tables" in
          *"|$target_table|"*) ;;
          *) err "$file:$line_num: @R references unknown table '$target_table'" ;;
        esac

        # Check columns exist (using flat string lookup)
        case "$tables" in
          *"|$source_table|"*)
            case "$all_cols" in
              *"|${source_table}.${source_col}|"*) ;;
              *) err "$file:$line_num: @R references unknown column '$source_table.$source_col'" ;;
            esac
            ;;
        esac
        case "$tables" in
          *"|$target_table|"*)
            case "$all_cols" in
              *"|${target_table}.${target_col}|"*) ;;
              *) err "$file:$line_num: @R references unknown column '$target_table.$target_col'" ;;
            esac
            ;;
        esac
        ;;
    esac
  done < "$file"
}

# === GDLC validation ===
# Check if a module name is a known external dependency.
# Returns 0 (true) ONLY for patterns that are definitely external.
# Returns 1 (false) for everything else — unknowns get validated against $modules/$all_modules.
_is_external_module() {
  local mod="$1"
  case "$mod" in
    node:*) return 0 ;;          # Node.js builtins
    @*) return 0 ;;              # Scoped npm packages
    *) return 1 ;;               # Unknown — validate it
  esac
}

lint_gdlc() {
  local file="$1"
  local line_num=0
  local file_count=0
  local desc_count=0

  # Check for v2 @FORMAT header
  local has_format_header=false
  while IFS= read -r fh_line; do
    [[ -z "$fh_line" ]] && continue
    [[ "$fh_line" == \#* ]] || break
    case "$fh_line" in
      "# @FORMAT PATH|LANG|EXPORTS|IMPORTS|DESCRIPTION") has_format_header=true; break ;;
      "# @FORMAT "*) warn "$file: unexpected @FORMAT header (expected v2: PATH|LANG|EXPORTS|IMPORTS|DESCRIPTION)" ;;
    esac
  done < "$file"
  if [[ "$has_format_header" == "false" ]]; then
    warn "$file: missing '# @FORMAT PATH|LANG|EXPORTS|IMPORTS|DESCRIPTION' header"
  fi

  # Validate records
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    [[ -z "$line" || "$line" == \#* ]] && continue

    case "$line" in
      @F\ *)
        file_count=$((file_count + 1))
        # Count UNESCAPED pipe characters (strip \| first, then count |):
        local pipe_count
        pipe_count=$(echo "$line" | sed 's/\\|//g' | tr -cd '|' | wc -c | tr -d ' ')
        # @F records need at least 4 unescaped pipes (5 fields): PATH|LANG|EXPORTS|IMPORTS|DESCRIPTION
        if [[ "$pipe_count" -lt 4 ]]; then
          err "$file:$line_num: @F record has $pipe_count pipe(s), expected at least 4 (PATH|LANG|EXPORTS|IMPORTS|DESCRIPTION)"
          continue
        fi
        # Check non-empty path
        local fpath
        fpath=$(echo "$line" | cut -d'|' -f1 | sed 's/^@F //')
        if [[ -z "$fpath" || "$fpath" == " " ]]; then
          err "$file:$line_num: @F record has empty file path"
        fi
        # Check valid language identifier
        local lang
        lang=$(echo "$line" | cut -d'|' -f2)
        case "$lang" in
          ts|tsx|js|jsx|py|go|java|rs|rb|c|cpp|cs|kt|swift|php|bash|sh) ;;
          *) err "$file:$line_num: @F record has unknown language '$lang' (valid: ts|tsx|js|jsx|py|go|java|rs|rb|c|cpp|cs|kt|swift|php|bash|sh)" ;;
        esac
        # Check description (for coverage reporting)
        local desc
        desc=$(echo "$line" | cut -d'|' -f5)
        if [[ -n "$desc" ]]; then
          desc_count=$((desc_count + 1))
        fi
        ;;
      @D\ *)
        local dpath
        dpath=$(echo "$line" | cut -d'|' -f1 | sed 's/^@D //')
        if [[ -z "$dpath" || "$dpath" == " " ]]; then
          err "$file:$line_num: @D record has empty directory path"
        fi
        ;;
      @T\ *|@R\ *|@PATH\ *|@E\ *)
        err "$file:$line_num: v1 record type detected ($(echo "$line" | cut -d' ' -f1)). GDLC v2 only supports @F and @D."
        ;;
      @*)
        local prefix
        prefix=$(echo "$line" | cut -d' ' -f1 | cut -d'|' -f1)
        case "$prefix" in
          @F|@D) ;; # already handled
          *) err "$file:$line_num: unrecognized record prefix '$prefix' (valid: @F, @D)" ;;
        esac
        ;;
    esac
  done < "$file"

  # Description coverage (informational)
  if [[ "$file_count" -gt 0 ]]; then
    echo "  Info: $file: $desc_count/$file_count files described ($(( desc_count * 100 / file_count ))%)" >&2
  fi
}

# === GDLD validation (delegate to gdld2mermaid.sh) ===
_gdld_profile_types() {
  case "$1" in
    flow) echo "|@diagram|@group|@node|@edge|@component|@config|@entry|@gotcha|@recovery|@pattern|@note|@use-when|@use-not|@decision|@scenario|@override|@exclude|@view|@include|" ;;
    sequence) echo "|@diagram|@participant|@msg|@block|@endblock|@seq-note|@gotcha|@note|@scenario|@override|@exclude|@view|@include|" ;;
    deployment) echo "|@diagram|@deploy-env|@deploy-node|@deploy-instance|@infra-node|@node|@edge|@note|@scenario|@override|@exclude|@view|@include|" ;;
    knowledge) echo "|@diagram|@gotcha|@recovery|@decision|@pattern|@use-when|@use-not|@note|@node|@edge|@scenario|@override|@exclude|@view|@include|" ;;
    *) echo "" ;;  # Unknown profile — skip validation
  esac
}

lint_gdld() {
  local file="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local gdld2mermaid="$script_dir/gdld2mermaid.sh"

  # --- Profile validation pass ---
  local profile=""
  local diagram_line
  diagram_line=$(grep "^@diagram" "$file" 2>/dev/null | head -1) || true
  if [[ -n "$diagram_line" ]]; then
    profile=$(_extract_field "$diagram_line" "profile")
  fi

  if [[ -n "$profile" ]]; then
    local allowed
    allowed=$(_gdld_profile_types "$profile")
    if [[ -n "$allowed" ]]; then
      local pline_num=0
      while IFS= read -r pline; do
        pline_num=$((pline_num + 1))
        [[ -z "$pline" || "$pline" == \#* || "$pline" == //* ]] && continue
        # Extract record type (@word)
        local rec_type
        rec_type=$(echo "$pline" | sed -n 's/^\(@[a-z-]*\).*/\1/p')
        [[ -z "$rec_type" ]] && continue
        # Check against profile allowlist
        case "$allowed" in
          *"|${rec_type}|"*) ;;  # Allowed
          *) warn "$file:$pline_num: ${rec_type} unexpected in profile '${profile}'" ;;
        esac
      done < "$file"
    fi
  fi

  if [[ ! -x "$gdld2mermaid" ]]; then
    err "$file: gdld2mermaid.sh not found, cannot validate GDLD"
    return
  fi

  local out rc=0
  out=$("$gdld2mermaid" "$file" --validate 2>&1) || rc=$?

  # Parse errors from gdld2mermaid output
  while IFS= read -r vline; do
    [[ -z "$vline" ]] && continue
    case "$vline" in
      *Error:*|*error:*)
        err "$file: $vline"
        ;;
      *Warning:*|*warn:*)
        warn "$file: $vline"
        ;;
    esac
  done <<< "$out"

  if [[ $rc -ne 0 ]]; then
    # gdld2mermaid returned error — ensure we counted at least one
    local found_error=false
    while IFS= read -r vline; do
      case "$vline" in
        *Error:*|*error:*) found_error=true ;;
      esac
    done <<< "$out"
    if [[ "$found_error" == "false" ]]; then
      err "$file: GDLD validation failed"
    fi
  fi
}

# === GDLM validation ===
lint_gdlm() {
  local file="$1"
  local seen_ids=""
  local line_num=0

  while IFS= read -r line; do
    line_num=$((line_num + 1))
    [[ -z "$line" || "$line" == \#* ]] && continue

    case "$line" in
      @memory*)
        local id_val ts_val
        id_val=$(_extract_field "$line" "id")
        ts_val=$(_extract_field "$line" "ts")

        if [[ -z "$id_val" ]]; then
          err "$file:$line_num: @memory missing required field 'id'"
        else
          # Check ID format: M-{agent}-{seq}
          if [[ ! "$id_val" =~ ^M- ]]; then
            err "$file:$line_num: @memory id '$id_val' does not follow M-{agent}-{seq} convention"
          fi
          # Check duplicate
          case "$seen_ids" in
            *"|$id_val|"*) err "$file:$line_num: duplicate id '$id_val'" ;;
          esac
          seen_ids="$seen_ids|$id_val|"
        fi

        if [[ -z "$ts_val" ]]; then
          err "$file:$line_num: @memory missing required field 'ts'"
        fi
        ;;
      @anchor*) ;; # anchors have different required fields
    esac
  done < "$file"
}

# === GDLU validation ===
lint_gdlu() {
  local file="$1"
  local source_ids=""
  local extract_ids=""
  local line_num=0

  # Pass 1: collect source IDs
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    [[ -z "$line" || "$line" == \#* ]] && continue
    case "$line" in
      @source*)
        local id_val
        id_val=$(_extract_field "$line" "id")
        if [[ -n "$id_val" ]]; then
          source_ids="$source_ids|$id_val|"
        fi
        ;;
    esac
  done < "$file"

  # Pass 2: validate sections and extracts
  line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    [[ -z "$line" || "$line" == \#* ]] && continue

    case "$line" in
      @section*)
        local src
        src=$(_extract_field "$line" "source")
        if [[ -n "$src" ]]; then
          case "$source_ids" in
            *"|$src|"*) ;;
            *) err "$file:$line_num: @section references unknown source '$src'" ;;
          esac
        fi
        ;;
      @extract*)
        local ext_id
        ext_id=$(_extract_field "$line" "id")
        if [[ -n "$ext_id" ]]; then
          case "$extract_ids" in
            *"|$ext_id|"*) err "$file:$line_num: duplicate extract id '$ext_id'" ;;
          esac
          extract_ids="$extract_ids|$ext_id|"
        fi
        ;;
    esac
  done < "$file"
}

# === GDLA validation ===
lint_gdla() {
  local file="$1"
  local schemas=""
  local line_num=0
  local valid_methods=" GET POST PUT DELETE PATCH HEAD OPTIONS QUERY MUTATION SUBSCRIPTION "

  # Pass 1: collect all @S schema names
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    [[ -z "$line" || "$line" == \#* ]] && continue
    case "$line" in
      @S\ *)
        local schema_name
        schema_name=$(echo "$line" | sed 's/\\|/@@P@@/g' | cut -d'|' -f1 | sed 's/^@S //')
        schemas="$schemas|$schema_name|"
        ;;
    esac
  done < "$file"

  # Pass 2: validate
  line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    [[ -z "$line" || "$line" == \#* ]] && continue
    case "$line" in
      @EP\ *)
        local method_path
        method_path=$(echo "$line" | sed 's/\\|/@@P@@/g' | cut -d'|' -f1 | sed 's/^@EP //')
        local method
        method=$(echo "$method_path" | cut -d' ' -f1)
        case "$valid_methods" in
          *" $method "*) ;;
          *) err "$file:$line_num: @EP has invalid method '$method'" ;;
        esac
        ;;
      @R\ *)
        local ref_part
        ref_part=$(echo "$line" | sed 's/\\|/@@P@@/g' | cut -d'|' -f1 | sed 's/^@R //')
        local source_name target_name
        source_name=$(echo "$ref_part" | awk -F' -> ' '{print $1}')
        target_name=$(echo "$ref_part" | awk -F' -> ' '{print $2}')
        case "$schemas" in
          *"|$source_name|"*) ;;
          *) err "$file:$line_num: @R references unknown schema '$source_name'" ;;
        esac
        case "$schemas" in
          *"|$target_name|"*) ;;
          *) err "$file:$line_num: @R references unknown schema '$target_name'" ;;
        esac
        ;;
    esac
  done < "$file"
}

# === Cross-layer validation ===
lint_cross_layer() {
  local file="$1" base_dir="$2"
  echo "Cross-layer validation for $file (base: $base_dir)..."

  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Look for refs: fields
    local refs
    refs=$(_extract_field "$line" "refs")
    [[ -z "$refs" ]] && continue

    # refs format: layer:ID (e.g., gdls:GL_ACCOUNT, gdlc:AuthModule)
    local layer ref_id
    layer=$(echo "$refs" | cut -d':' -f1)
    ref_id=$(echo "$refs" | cut -d':' -f2-)

    case "$layer" in
      gdls)
        # Check for @T <ref_id> in *.gdls files (grep -F for literal matching)
        local found=false
        for f in "$base_dir"/*.gdls; do
          [[ -f "$f" && -r "$f" ]] || continue
          if grep -qF "@T ${ref_id}|" "$f"; then
            found=true
            break
          fi
        done
        if [[ "$found" == "false" ]]; then
          err "$file:$line_num: cross-layer ref 'gdls:$ref_id' not found in any .gdls file"
        fi
        ;;
      gdlc)
        local found=false
        for f in "$base_dir"/*.gdlc; do
          [[ -f "$f" && -r "$f" ]] || continue
          # v2: check exports (3rd pipe field, exact match) OR file path basename
          if grep "^@F " "$f" 2>/dev/null | awk -F'|' -v sym="$ref_id" 'BEGIN{found=0}{
            n=split($3,a,","); for(i=1;i<=n;i++){gsub(/^ +| +$/,"",a[i]); if(a[i]==sym){found=1;exit}}
            p=$1; sub(/^@F /, "", p); m=split(p,b,"/"); if(b[m]==sym) found=1
          } END{exit !found}'; then
            found=true
            break
          fi
        done
        if [[ "$found" == "false" ]]; then
          err "$file:$line_num: cross-layer ref 'gdlc:$ref_id' not found in any .gdlc file exports or paths"
        fi
        ;;
      gdla)
        local found=false
        for f in "$base_dir"/*.gdla; do
          [[ -f "$f" && -r "$f" ]] || continue
          if grep -qF "@S ${ref_id}|" "$f"; then
            found=true
            break
          fi
        done
        if [[ "$found" == "false" ]]; then
          err "$file:$line_num: cross-layer ref 'gdla:$ref_id' not found in any .gdla file"
        fi
        ;;
      gdl|gdlu|gdld|gdlm)
        local found=false
        for f in "$base_dir"/*."$layer"; do
          [[ -f "$f" && -r "$f" ]] || continue
          if grep -qF "id:${ref_id}" "$f"; then
            found=true
            break
          fi
        done
        if [[ "$found" == "false" ]]; then
          err "$file:$line_num: cross-layer ref '$layer:$ref_id' not found in any .$layer file"
        fi
        ;;
      *)
        warn "$file:$line_num: unknown layer '$layer' in refs"
        ;;
    esac
  done < "$file"
}

# === .gdlignore validator ===
lint_gdlignore() {
  local file="$1"
  local line_num=0
  local valid_prefixes="gdl gdls gdlc gdla gdlm gdld gdlu"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    # Skip comments and blank lines
    [[ -z "$line" || "$line" == \#* ]] && continue
    # Strip trailing whitespace
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue

    # Check for format prefix
    if [[ "$line" =~ ^(gdl[a-z]*): ]]; then
      local prefix="${BASH_REMATCH[1]}"
      local found=false
      for vp in $valid_prefixes; do
        if [[ "$prefix" == "$vp" ]]; then found=true; break; fi
      done
      if [[ "$found" == "false" ]]; then
        err "$file:$line_num: unknown format prefix '${prefix}:' (valid: $valid_prefixes)"
      fi
    fi

    # Check for negation (not yet supported)
    if [[ "$line" == !* ]]; then
      warn "$file:$line_num: negation patterns (!) are not yet supported"
    fi
  done < "$file"
}

# === Main dispatch ===
lint_file() {
  local file="$1"
  local format
  format=$(get_format "$file")
  echo "Linting $file ($format)..."

  case "$format" in
    gdl)  lint_gdl "$file" ;;
    gdls)
      local ext_tables=""
      local ext_cols=""
      if [[ -n "$CONTEXT_DIR" ]]; then
        while IFS= read -r ctx_file; do
          [[ -f "$ctx_file" ]] || continue
          [[ "$ctx_file" == "$file" ]] && continue
          local ctx_current_table=""
          while IFS= read -r ctx_line; do
            [[ -z "$ctx_line" || "$ctx_line" == \#* ]] && continue
            case "$ctx_line" in
              @T\ *)
                ctx_current_table=$(echo "$ctx_line" | cut -d'|' -f1 | sed 's/^@T //')
                ext_tables="$ext_tables|$ctx_current_table|"
                ;;
              @D\ *|@R\ *|@PATH\ *|@E\ *|@META\ *|@DOMAIN\ *|@TABLES\ *)
                ctx_current_table=""
                ;;
              *)
                if [[ -n "$ctx_current_table" ]]; then
                  local ctx_col_name
                  ctx_col_name=$(echo "$ctx_line" | cut -d'|' -f1)
                  ext_cols="$ext_cols|${ctx_current_table}.${ctx_col_name}|"
                fi
                ;;
            esac
          done < "$ctx_file"
        done <<< "$(find "$CONTEXT_DIR" -name '*.gdls' 2>/dev/null || true)"
      elif [[ "$ALL_MODE" == "true" ]]; then
        ext_tables="$ALL_GDLS_TABLES"
        ext_cols="$ALL_GDLS_COLS"
      fi
      lint_gdls "$file" "$ext_tables" "$ext_cols"
      ;;
    gdlc) lint_gdlc "$file" "$ALL_GDLC_MODULES" ;;
    gdld) lint_gdld "$file" ;;
    gdlm) lint_gdlm "$file" ;;
    gdlu) lint_gdlu "$file" ;;
    gdla) lint_gdla "$file" ;;
    gdlignore) lint_gdlignore "$file" ;;
    *)    err "Unknown format: $file" ;;
  esac
}

# Parse args
STRICT=false
ALL_MODE=false
CROSS_LAYER=false
BASE_DIR=""
CONTEXT_DIR=""
EXCLUDE_PATTERN=""
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=true ;;
    --all) ALL_MODE=true ;;
    --cross-layer) CROSS_LAYER=true ;;
    --base=*) BASE_DIR="${arg#--base=}" ;;
    --context=*) CONTEXT_DIR="${arg#--context=}" ;;
    --exclude=*) EXCLUDE_PATTERN="${arg#--exclude=}" ;;
    *) TARGET="$arg" ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "Usage: gdl-lint.sh <file.gdl[s|c|d|m|u|a]> [--strict] [--context=DIR]" >&2
  echo "       gdl-lint.sh --all <directory> [--strict] [--exclude=PATTERN]" >&2
  echo "       gdl-lint.sh --cross-layer <file> --base=<directory>" >&2
  echo "  --context=DIR   Directory of .gdls files for cross-file @R resolution" >&2
  exit 1
fi

if [[ "$ALL_MODE" == "true" ]]; then
  if [[ ! -d "$TARGET" ]]; then
    echo "Error: directory '$TARGET' does not exist" >&2
    exit 1
  fi
  # Recursive scan with optional exclusion
  find_args=("$TARGET" -type f \( -name '*.gdl' -o -name '*.gdls' -o -name '*.gdlc' -o -name '*.gdld' -o -name '*.gdlm' -o -name '*.gdlu' -o -name '*.gdla' -o -name '.gdlignore' \))
  if [[ -n "$EXCLUDE_PATTERN" ]]; then
    find_args+=(! -path "$EXCLUDE_PATTERN")
  fi
  # Pre-collect all GDLS tables and columns for cross-file @R resolution
  ALL_GDLS_TABLES=""
  ALL_GDLS_COLS=""
  while IFS= read -r gdls_f; do
    [[ -z "$gdls_f" ]] && continue
    pre_current_table=""
    while IFS= read -r pre_line; do
      [[ -z "$pre_line" || "$pre_line" == \#* ]] && continue
      case "$pre_line" in
        @T\ *)
          pre_current_table=$(echo "$pre_line" | cut -d'|' -f1 | sed 's/^@T //')
          ALL_GDLS_TABLES="$ALL_GDLS_TABLES|$pre_current_table|"
          ;;
        @D\ *|@R\ *|@PATH\ *|@E\ *|@META\ *|@DOMAIN\ *|@TABLES\ *)
          pre_current_table=""
          ;;
        *)
          if [[ -n "$pre_current_table" ]]; then
            pre_col_name=$(echo "$pre_line" | cut -d'|' -f1)
            ALL_GDLS_COLS="$ALL_GDLS_COLS|${pre_current_table}.${pre_col_name}|"
          fi
          ;;
      esac
    done < "$gdls_f"
  done <<< "$(find "$TARGET" -type f -name '*.gdls' ${EXCLUDE_PATTERN:+! -path "$EXCLUDE_PATTERN"} 2>/dev/null | sort || true)"

  # Pre-scan: collect all @T module names across all GDLC files (portable — no process substitution)
  ALL_GDLC_MODULES=""
  _tmp_gdlc_list=$(mktemp)
  find "$TARGET" -name '*.gdlc' -type f ${EXCLUDE_PATTERN:+! -path "$EXCLUDE_PATTERN"} 2>/dev/null | sort > "$_tmp_gdlc_list"
  while IFS= read -r gdlc_file; do
    [[ -z "$gdlc_file" ]] && continue
    while IFS= read -r line; do
      case "$line" in
        @T\ *)
          mod_name=$(echo "$line" | cut -d'|' -f1 | sed 's/^@T //')
          ALL_GDLC_MODULES="$ALL_GDLC_MODULES|$mod_name|"
          ;;
      esac
    done < "$gdlc_file"
  done < "$_tmp_gdlc_list"
  rm -f "$_tmp_gdlc_list"

  file_count=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    lint_file "$f"
    file_count=$((file_count + 1))
  done <<< "$(find "${find_args[@]}" | sort || true)"
  if (( file_count == 0 )); then
    echo "Warning: no GDL files found in $TARGET" >&2
    warnings=$((warnings + 1))
  fi
elif [[ "$CROSS_LAYER" == "true" ]]; then
  lint_file "$TARGET"
  lint_cross_layer "$TARGET" "${BASE_DIR:-.}"
else
  lint_file "$TARGET"
fi

# Report
if ((errors > 0)); then
  echo "Lint failed with $errors error(s), $warnings warning(s)"
  exit 1
fi
if [[ "$STRICT" == "true" ]] && ((warnings > 0)); then
  echo "Lint failed in strict mode: $warnings warning(s) treated as errors"
  exit 1
fi
if ((warnings > 0)); then
  echo "Lint passed with $warnings warning(s)"
else
  echo "OK"
fi
exit 0
