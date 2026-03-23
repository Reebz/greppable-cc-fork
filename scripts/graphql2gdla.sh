#!/usr/bin/env bash
# graphql2gdla.sh — Convert GraphQL SDL to GDLA API contract format
# Usage: graphql2gdla.sh <schema.graphql> [--output=DIR] [--dry-run] [--check]
# Dependencies: awk (BSD or GNU)
set -uo pipefail

INPUT_FILE=""
OUTPUT_DIR=""
DRY_RUN=false
CHECK_MODE=false

for arg in "$@"; do
  case "$arg" in
    --output=*) OUTPUT_DIR="${arg#--output=}" ;;
    --dry-run) DRY_RUN=true ;;
    --check) CHECK_MODE=true ;;
    --help|-h)
      cat <<'USAGE'
graphql2gdla.sh — Convert GraphQL SDL to GDLA API contract format

Usage: graphql2gdla.sh <schema.graphql> [--output=DIR] [--dry-run] [--check]

Parses a GraphQL schema SDL and generates a GDLA file with operations
(Query, Mutation, Subscription) mapped to @EP records, plus @ENUM and
@AUTH where applicable.

Note: Named types (not Query/Mutation/Subscription) are NOT emitted as
@S schemas — those belong in GDLS via a separate graphql2gdls.sh bridge.
Only operations are mapped to GDLA.

OPTIONS:
  --output=DIR   Write output to DIR/<name>.graphql.gdla (default: stdout)
  --dry-run      Show what would be generated without writing
  --check        Compare generated GDLA with existing file (drift detection)
  --help         Show this help

MAPPING:
  type Query { field(...): Type }        → @EP QUERY field|...|200:Type|
  type Mutation { field(...): Type }     → @EP MUTATION field|...|200:Type|
  type Subscription { field(...): Type } → @EP SUBSCRIPTION field|...|200:Type|
  extend type Query { ... }              → same as type Query
  enum Name { A B C }                   → @ENUM Name|A,B,C
  union Name = A | B | C               → @ENUM Name|A,B,C
  scalar DateTime                       → skipped (not operations)
  @deprecated(reason: "...")            → [DEPRECATED] in description
USAGE
      exit 0
      ;;
    -*)
      echo "Unknown argument: $arg. Run with --help for usage." >&2
      exit 1
      ;;
    *)
      if [[ -z "$INPUT_FILE" ]]; then
        INPUT_FILE="$arg"
      else
        echo "Error: unexpected argument '$arg'" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$INPUT_FILE" ]]; then
  echo "Usage: graphql2gdla.sh <schema.graphql> [--output=DIR] [--dry-run] [--check]" >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: file not found: $INPUT_FILE" >&2
  exit 1
fi

today=$(date +%Y-%m-%d)
basename_no_ext=$(basename "$INPUT_FILE" | sed 's/\.[^.]*$//')

# --- Main awk parser (BSD awk compatible — no match() capture groups) ---
output=$(awk -v today="$today" -v source_file="$(basename "$INPUT_FILE")" '
BEGIN {
  is_op_type = 0
  method = ""
  brace_depth = 0
  enum_name = ""
  in_enum = 0
  enum_values = ""
  in_docstring = 0
  ep_count = 0
  enum_count = 0
  param_count = 0
}

# Helper: process a single operation field line and emit @EP + @P records
function process_op_field(line,    field_name, args_str, paren_open, paren_close, return_type, deprecated, dep_reason, desc, resp, tmp, after_paren, colon_pos, dp, rest, rest2, q1, q2, n, i, arg_parts, p_name, p_type, p_required, eq_pos_a, at_pos_a, colon_pos_a) {
  gsub(/^[[:space:]]+/, "", line)
  if (line == "" || line ~ /^[{}]/) return

  # Check for @deprecated
  deprecated = 0
  dep_reason = ""
  if (index(line, "@deprecated") > 0) {
    deprecated = 1
    dp = index(line, "@deprecated(reason:")
    if (dp > 0) {
      rest = substr(line, dp)
      q1 = index(rest, "\"")
      if (q1 > 0) {
        rest2 = substr(rest, q1 + 1)
        q2 = index(rest2, "\"")
        if (q2 > 0) {
          dep_reason = substr(rest2, 1, q2 - 1)
          # Escape pipes in deprecated reason
          gsub(/\|/, "\\|", dep_reason)
        }
      }
    }
    gsub(/@deprecated\([^)]*\)/, "", line)
    gsub(/@deprecated/, "", line)
    gsub(/[[:space:]]+$/, "", line)
  }

  # Remove any remaining directives
  gsub(/@[a-zA-Z_]+\([^)]*\)/, "", line)
  gsub(/@[a-zA-Z_]+/, "", line)
  gsub(/[[:space:]]+$/, "", line)

  # Extract field name
  tmp = line
  gsub(/[^a-zA-Z_0-9].*/, "", tmp)
  field_name = tmp
  if (field_name == "") return

  # Extract arguments
  args_str = ""
  paren_open = index(line, "(")
  paren_close = 0
  if (paren_open > 0) {
    paren_close = index(line, ")")
    while (paren_close == 0) {
      if ((getline nextline) > 0) {
        gsub(/^[[:space:]]+/, "", nextline)
        line = line " " nextline
        paren_close = index(line, ")")
      } else break
    }
    if (paren_close == 0) return
    if (paren_close > paren_open) {
      args_str = substr(line, paren_open + 1, paren_close - paren_open - 1)
    }
  }

  # Extract return type
  return_type = ""
  if (paren_open > 0) {
    after_paren = substr(line, paren_close + 1)
    colon_pos = index(after_paren, ":")
    if (colon_pos > 0) return_type = substr(after_paren, colon_pos + 1)
  } else {
    colon_pos = index(line, ":")
    if (colon_pos > 0) return_type = substr(line, colon_pos + 1)
  }
  gsub(/^[[:space:]]+/, "", return_type)
  gsub(/[[:space:]]+$/, "", return_type)
  gsub(/!/, "", return_type)

  # Convert [Type] → Type[]
  if (substr(return_type, 1, 1) == "[" && substr(return_type, length(return_type), 1) == "]") {
    return_type = substr(return_type, 2, length(return_type) - 2)
    gsub(/!/, "", return_type)
    return_type = return_type "[]"
  }

  # Build description
  desc = ""
  if (deprecated) {
    desc = "[DEPRECATED"
    if (dep_reason != "") desc = desc ": " dep_reason
    desc = desc "]"
  }

  resp = ""
  if (return_type != "") resp = "200:" return_type

  ep_count++
  endpoints[ep_count] = "@EP " method " " field_name "|" desc "|" resp "|"

  # Parse arguments → @P (normalize space-separated to comma-separated)
  if (args_str != "") {
    # BSD awk: insert commas before tokens that look like "argName:" (new arg boundaries)
    n_tok = split(args_str, _tok, /[[:space:]]+/)
    args_str = ""
    for (_ti = 1; _ti <= n_tok; _ti++) {
      if (_ti > 1 && _tok[_ti] ~ /^[a-zA-Z_][a-zA-Z_0-9]*:/) {
        args_str = args_str "," _tok[_ti]
      } else {
        if (args_str != "") args_str = args_str " "
        args_str = args_str _tok[_ti]
      }
    }
    n = split(args_str, arg_parts, ",")
    for (i = 1; i <= n; i++) {
      gsub(/^[[:space:]]+/, "", arg_parts[i])
      gsub(/[[:space:]]+$/, "", arg_parts[i])
      if (arg_parts[i] == "") continue

      p_name = ""
      p_type = ""
      p_required = ""
      colon_pos_a = index(arg_parts[i], ":")
      if (colon_pos_a > 0) {
        p_name = substr(arg_parts[i], 1, colon_pos_a - 1)
        gsub(/[[:space:]]/, "", p_name)
        p_type = substr(arg_parts[i], colon_pos_a + 1)
        gsub(/^[[:space:]]+/, "", p_type)
        eq_pos_a = index(p_type, "=")
        if (eq_pos_a > 0) p_type = substr(p_type, 1, eq_pos_a - 1)
        at_pos_a = index(p_type, "@")
        if (at_pos_a > 0) p_type = substr(p_type, 1, at_pos_a - 1)
        gsub(/[[:space:]]+$/, "", p_type)
        if (substr(p_type, length(p_type), 1) == "!") {
          p_required = "required"
          p_type = substr(p_type, 1, length(p_type) - 1)
        }
        gsub(/!/, "", p_type)
        if (substr(p_type, 1, 1) == "[" && substr(p_type, length(p_type), 1) == "]") {
          p_type = substr(p_type, 2, length(p_type) - 2)
          gsub(/!/, "", p_type)
          p_type = p_type "[]"
        }
      }
      if (p_name != "") {
        param_count++
        params[param_count] = ep_count "|@P " p_name "|query|" p_type "|" p_required "|"
      }
    }
  }
}

# Strip comments
/^[[:space:]]*#/ { next }

# Skip single-line docstrings
/^[[:space:]]*""".*"""[[:space:]]*$/ { next }

# Track multi-line docstrings
/^[[:space:]]*"""/ {
  if (in_docstring) { in_docstring = 0 } else { in_docstring = 1 }
  next
}
in_docstring { next }

# Union type → @ENUM (handles multi-line unions with leading |)
/^[[:space:]]*union[[:space:]]+/ {
  uline = $0
  gsub(/^[[:space:]]*union[[:space:]]+/, "", uline)
  # Accumulate multi-line unions (line ends with = or |)
  while (uline ~ /[=|][[:space:]]*$/) {
    if ((getline nextline) > 0) {
      gsub(/^[[:space:]]+/, "", nextline)
      uline = uline " " nextline
    } else break
  }
  # Split on =
  eq_pos = index(uline, "=")
  if (eq_pos > 0) {
    u_name = substr(uline, 1, eq_pos - 1)
    gsub(/[[:space:]]/, "", u_name)
    u_rest = substr(uline, eq_pos + 1)
    gsub(/^[[:space:]]*/, "", u_rest)
    gsub(/[[:space:]]*$/, "", u_rest)
    n = split(u_rest, variants, "|")
    u_vals = ""
    for (i = 1; i <= n; i++) {
      gsub(/[[:space:]]/, "", variants[i])
      if (variants[i] != "") {
        if (u_vals != "") u_vals = u_vals ","
        u_vals = u_vals variants[i]
      }
    }
    if (u_name != "" && u_vals != "") {
      enum_count++
      enums[enum_count] = "@ENUM " u_name "|" u_vals
    }
  }
  next
}

# Scalar → skip
/^[[:space:]]*scalar[[:space:]]/ { next }

# Enum start (handles single-line: enum Foo { A B C })
/^[[:space:]]*enum[[:space:]]+/ {
  eline = $0
  gsub(/^[[:space:]]*enum[[:space:]]+/, "", eline)
  # Check for single-line enum (both { and } on same line)
  if (index(eline, "{") > 0 && index(eline, "}") > 0) {
    e_name = eline
    gsub(/[[:space:]]*\{.*/, "", e_name)
    gsub(/[[:space:]]/, "", e_name)
    # Extract values between { and }
    e_body = eline
    gsub(/^[^{]*\{/, "", e_body)
    gsub(/\}.*/, "", e_body)
    gsub(/^[[:space:]]+/, "", e_body)
    gsub(/[[:space:]]+$/, "", e_body)
    # Split on whitespace
    n = split(e_body, e_parts, /[[:space:]]+/)
    e_vals = ""
    for (i = 1; i <= n; i++) {
      gsub(/@deprecated.*/, "", e_parts[i])
      gsub(/[[:space:]]/, "", e_parts[i])
      if (e_parts[i] != "") {
        if (e_vals != "") e_vals = e_vals ","
        e_vals = e_vals e_parts[i]
      }
    }
    if (e_name != "" && e_vals != "") {
      enum_count++
      enums[enum_count] = "@ENUM " e_name "|" e_vals
    }
    next
  }
  gsub(/[[:space:]]*\{.*/, "", eline)
  gsub(/[[:space:]]/, "", eline)
  enum_name = eline
  in_enum = 1
  enum_values = ""
  next
}

# Enum close
in_enum && /\}/ {
  if (enum_name != "" && enum_values != "") {
    enum_count++
    enums[enum_count] = "@ENUM " enum_name "|" enum_values
  }
  in_enum = 0
  enum_name = ""
  next
}

# Enum values
in_enum {
  gsub(/^[[:space:]]+/, "")
  gsub(/[[:space:]]+$/, "")
  gsub(/#.*/, "")
  gsub(/[[:space:]]+$/, "")
  if ($0 != "" && $0 != "{") {
    val = $0
    gsub(/@deprecated.*/, "", val)
    gsub(/[[:space:]]+$/, "", val)
    if (val != "") {
      if (enum_values != "") enum_values = enum_values ","
      enum_values = enum_values val
    }
  }
  next
}

# Type or extend type
/^[[:space:]]*(extend[[:space:]]+)?type[[:space:]]+/ {
  tline = $0
  gsub(/^[[:space:]]*/, "", tline)
  gsub(/^extend[[:space:]]+/, "", tline)
  gsub(/^type[[:space:]]+/, "", tline)
  # Save the full line before stripping for single-line detection
  full_tline = tline
  gsub(/[[:space:]]*implements.*/, "", tline)
  gsub(/[[:space:]]*@.*/, "", tline)
  gsub(/[[:space:]]*\{.*/, "", tline)
  gsub(/[[:space:]]/, "", tline)
  type_name = tline

  if (type_name == "Query" || type_name == "Mutation" || type_name == "Subscription") {
    is_op_type = 1
    if (type_name == "Query") method = "QUERY"
    else if (type_name == "Mutation") method = "MUTATION"
    else method = "SUBSCRIPTION"
    brace_depth = 1

    # Handle single-line op type: type Query { field: Type }
    if (index(full_tline, "{") > 0 && index(full_tline, "}") > 0) {
      body = full_tline
      gsub(/^[^{]*\{/, "", body)
      gsub(/\}.*/, "", body)
      # Split body on common field separators and process each
      n_fields = split(body, field_arr, /[[:space:]]*[,;][[:space:]]*|[[:space:]]{2,}/)
      for (fi = 1; fi <= n_fields; fi++) {
        gsub(/^[[:space:]]+/, "", field_arr[fi])
        gsub(/[[:space:]]+$/, "", field_arr[fi])
        if (field_arr[fi] != "" && field_arr[fi] ~ /[a-zA-Z_].*:/) {
          process_op_field(field_arr[fi])
        }
      }
      is_op_type = 0
      method = ""
      brace_depth = 0
      next
    }
  } else {
    is_op_type = 0
    brace_depth = 1
  }
  next
}

# Track brace depth for op types — also handle field + } on same line
is_op_type && /\}/ {
  # Check if there is a field before the closing brace
  pre_brace = $0
  gsub(/[[:space:]]*\}.*/, "", pre_brace)
  gsub(/^[[:space:]]+/, "", pre_brace)
  if (pre_brace != "" && pre_brace ~ /[a-zA-Z_].*:/) {
    process_op_field(pre_brace)
  }
  brace_depth--
  if (brace_depth <= 0) {
    is_op_type = 0
    method = ""
  }
  next
}

# Operation fields inside Query/Mutation/Subscription
is_op_type && /^[[:space:]]+[a-zA-Z_]/ {
  process_op_field($0)
  next
}

# Close non-op type
!is_op_type && brace_depth > 0 && /\}/ {
  brace_depth--
  if (brace_depth <= 0) {
    brace_depth = 0
  }
  next
}

END {
  print "# @VERSION spec:gdla v:0.1.0 generated:" today " source:graphql-bridge file:" source_file
  print ""

  # Domain
  sname = source_file
  gsub(/\.[^.]*$/, "", sname)
  print "@D " sname "|GraphQL API||"

  # Enums
  if (enum_count > 0) {
    print ""
    for (i = 1; i <= enum_count; i++) {
      print enums[i]
    }
  }

  # Endpoints + params
  if (ep_count > 0) {
    print ""
    for (i = 1; i <= ep_count; i++) {
      print endpoints[i]
      for (j = 1; j <= param_count; j++) {
        split(params[j], pp, /\|/)
        assoc_ep = pp[1]
        if (assoc_ep + 0 == i) {
          param_line = ""
          for (k = 2; k <= length(pp); k++) {
            if (k > 2) param_line = param_line "|"
            param_line = param_line pp[k]
          }
          print param_line
        }
      }
    }
  }
}
' "$INPUT_FILE")

# --- Service slug for output file ---
service_slug=$(echo "$basename_no_ext" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

# --- Output ---
if [[ "$CHECK_MODE" == true ]]; then
  if [[ -z "$OUTPUT_DIR" ]]; then
    echo "Error: --check requires --output=DIR" >&2
    exit 1
  fi
  existing="${OUTPUT_DIR}/${service_slug}.graphql.gdla"
  if [[ ! -f "$existing" ]]; then
    echo "DRIFT: no existing file at $existing" >&2
    echo "$output"
    exit 1
  fi
  _tmp_generated=$(mktemp)
  echo "$output" > "$_tmp_generated"
  if diff -q "$_tmp_generated" "$existing" &>/dev/null; then
    rm -f "$_tmp_generated"
    echo "OK: $existing is up to date" >&2
    exit 0
  else
    echo "DRIFT: $existing differs from generated output" >&2
    diff --unified "$_tmp_generated" "$existing" >&2 || true
    rm -f "$_tmp_generated"
    exit 1
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "$output"
  exit 0
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  outfile="${OUTPUT_DIR}/${service_slug}.graphql.gdla"
  _tmp_out=$(mktemp "$(dirname "$outfile")/.gdl-atomic.XXXXXX")
  echo "$output" > "$_tmp_out" || { rm -f "$_tmp_out"; exit 1; }
  mv "$_tmp_out" "$outfile"
  echo "Wrote: $outfile" >&2
else
  echo "$output"
fi
