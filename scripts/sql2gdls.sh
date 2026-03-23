#!/usr/bin/env bash
# sql2gdls.sh — Parse SQL DDL files to GDLS skeleton (no database required)
# Usage: sql2gdls.sh <file.sql> [--output=DIR]
# Note: -e (errexit) intentionally omitted; grep returns 1 on no-match which is expected
set -uo pipefail

SQL_FILE=""
OUTPUT_DIR=""

for arg in "$@"; do
  case "$arg" in
    --output=*) OUTPUT_DIR="${arg#--output=}" ;;
    --help|-h)
      cat <<'USAGE'
sql2gdls.sh — Parse SQL DDL files to GDLS skeleton

Usage: sql2gdls.sh <file.sql> [--output=DIR]

Parses CREATE TABLE, ALTER TABLE ADD COLUMN, and REFERENCES from SQL DDL.
Generates GDLS skeleton with empty descriptions.
Skips TEMPORARY tables. Strips SQL comments.

Options:
  --output=DIR   Write output to DIR/<basename>.gdls (default: stdout)
  --help, -h     Show this help
USAGE
      exit 0
      ;;
    -*)
      echo "Unknown argument: $arg. Run with --help for usage." >&2
      exit 1
      ;;
    *)
      if [[ -z "$SQL_FILE" ]]; then
        SQL_FILE="$arg"
      else
        echo "Error: unexpected argument '$arg'" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$SQL_FILE" ]]; then
  echo "Usage: sql2gdls.sh <file.sql> [--output=DIR]" >&2
  exit 1
fi

if [[ ! -f "$SQL_FILE" ]]; then
  echo "Error: file not found: $SQL_FILE" >&2
  exit 1
fi

# Main parsing via awk — handles comment stripping, CREATE TABLE, columns, ALTER TABLE
output=$(awk '
BEGIN {
  in_block_comment = 0
  in_create = 0
  is_temp = 0
  current_table = ""
  table_count = 0
}

# Strip block comments /* ... */
{
  line = $0
  result = ""

  while (length(line) > 0) {
    if (in_block_comment) {
      pos = index(line, "*/")
      if (pos > 0) {
        in_block_comment = 0
        line = substr(line, pos + 2)
      } else {
        line = ""
      }
    } else {
      pos = index(line, "/*")
      if (pos > 0) {
        result = result substr(line, 1, pos - 1)
        in_block_comment = 1
        line = substr(line, pos + 2)
      } else {
        result = result line
        line = ""
      }
    }
  }

  $0 = result
}

# Strip line comments (-- to end of line)
{
  pos = index($0, "--")
  if (pos > 0) {
    $0 = substr($0, 1, pos - 1)
  }
}

# Skip empty lines after comment stripping
/^[[:space:]]*$/ { next }

# Detect CREATE [TEMPORARY] TABLE [IF NOT EXISTS] [schema.]name
{
  line = $0
  # Normalize whitespace
  gsub(/[[:space:]]+/, " ", line)
  gsub(/^[[:space:]]+/, "", line)
  gsub(/[[:space:]]+$/, "", line)

  upper_line = toupper(line)
}

# Match CREATE TABLE (with optional TEMPORARY, IF NOT EXISTS)
upper_line ~ /^CREATE[[:space:]]+(TEMPORARY[[:space:]]+)?TABLE[[:space:]]+(IF[[:space:]]+NOT[[:space:]]+EXISTS[[:space:]]+)?/ {
  # Check for TEMPORARY
  if (upper_line ~ /^CREATE[[:space:]]+TEMPORARY/) {
    is_temp = 1
    in_create = 0
    current_table = ""
    next
  }

  is_temp = 0

  # Extract table name: strip CREATE TABLE [IF NOT EXISTS] prefix
  tname = line
  sub(/^[Cc][Rr][Ee][Aa][Tt][Ee][[:space:]]+[Tt][Aa][Bb][Ll][Ee][[:space:]]+/, "", tname)
  sub(/^[Ii][Ff][[:space:]]+[Nn][Oo][Tt][[:space:]]+[Ee][Xx][Ii][Ss][Tt][Ss][[:space:]]+/, "", tname)

  # Remove everything from opening paren onwards
  sub(/[[:space:]]*\(.*/, "", tname)

  # Remove schema prefix (schema.table -> table)
  if (index(tname, ".") > 0) {
    sub(/^[^.]+\./, "", tname)
  }

  # Remove quotes (double quotes, backticks, square brackets)
  gsub(/"/, "", tname)
  gsub(/`/, "", tname)
  gsub(/\[/, "", tname)
  gsub(/\]/, "", tname)

  # Trim whitespace
  gsub(/^[[:space:]]+/, "", tname)
  gsub(/[[:space:]]+$/, "", tname)

  if (tname != "") {
    current_table = tname
    in_create = 1
    table_count++
    tables[table_count] = tname
    table_columns[tname] = ""
    table_rels[tname] = ""

    # Handle inline columns (single-line CREATE TABLE)
    paren_pos = index(line, "(")
    if (paren_pos > 0) {
      inline = substr(line, paren_pos + 1)
      # Check for closing paren — complete table on one line
      close_pos = 0
      depth = 0
      for (ci = 1; ci <= length(inline); ci++) {
        ch = substr(inline, ci, 1)
        if (ch == "(") depth++
        else if (ch == ")") {
          if (depth == 0) { close_pos = ci; break }
          depth--
        }
      }
      if (close_pos > 0) {
        inline = substr(inline, 1, close_pos - 1)
        in_create = 0
      }
      # Split on commas respecting parentheses
      depth = 0
      col_start = 1
      for (ci = 1; ci <= length(inline); ci++) {
        ch = substr(inline, ci, 1)
        if (ch == "(") depth++
        else if (ch == ")") depth--
        else if (ch == "," && depth == 0) {
          piece = substr(inline, col_start, ci - col_start)
          if (piece != "") {
            gsub(/^[[:space:]]+/, "", piece)
            gsub(/[[:space:]]+$/, "", piece)
            inline_cols[++inline_n] = piece
          }
          col_start = ci + 1
        }
      }
      # Last piece
      piece = substr(inline, col_start)
      gsub(/^[[:space:]]+/, "", piece)
      gsub(/[[:space:]]+$/, "", piece)
      if (piece != "") inline_cols[++inline_n] = piece
      # Process each inline column via process_col
      for (ic = 1; ic <= inline_n; ic++) {
        process_col(inline_cols[ic], tname)
      }
      inline_n = 0
      delete inline_cols
    }
  }
  next
}

# Inside CREATE TABLE block — parse columns
in_create == 1 && is_temp == 0 {
  line = $0
  gsub(/^[[:space:]]+/, "", line)
  gsub(/[[:space:]]+$/, "", line)

  # End of CREATE TABLE block
  if (line ~ /^\)/) {
    in_create = 0
    next
  }

  # Remove trailing comma
  sub(/,[[:space:]]*$/, "", line)

  process_col(line, current_table)
  next
}

function process_col(line, tbl_name) {
  # Skip standalone CONSTRAINT, PRIMARY KEY(...), UNIQUE(...), CHECK(...), FOREIGN KEY lines
  _upper_check = toupper(line)
  if (_upper_check ~ /^(CONSTRAINT[[:space:]]|PRIMARY[[:space:]]+KEY[[:space:]]*\(|UNIQUE[[:space:]]*\(|CHECK[[:space:]]*\(|FOREIGN[[:space:]]+KEY)/) {
    return
  }

  # Remove trailing comma (for inline column splits)
  sub(/,[[:space:]]*$/, "", line)

  # Skip if empty after cleanup
  if (line == "" || line ~ /^[[:space:]]*$/) return

  # First token is column name
  _col_name = ""
  _col_rest = ""

  # Handle quoted column names (double quotes, backticks, square brackets)
  _parsed = 0
  if (substr(line, 1, 1) == "\"") {
    _pos = index(substr(line, 2), "\"")
    if (_pos > 0) {
      _col_name = substr(line, 2, _pos - 1)
      _col_rest = substr(line, _pos + 2)
      gsub(/^[[:space:]]*/, "", _col_rest)
      _parsed = 1
    }
  } else if (substr(line, 1, 1) == "`") {
    _pos = index(substr(line, 2), "`")
    if (_pos > 0) {
      _col_name = substr(line, 2, _pos - 1)
      _col_rest = substr(line, _pos + 2)
      gsub(/^[[:space:]]*/, "", _col_rest)
      _parsed = 1
    }
  } else if (substr(line, 1, 1) == "[") {
    _pos = index(substr(line, 2), "]")
    if (_pos > 0) {
      _col_name = substr(line, 2, _pos - 1)
      _col_rest = substr(line, _pos + 2)
      gsub(/^[[:space:]]*/, "", _col_rest)
      _parsed = 1
    }
  }

  if (!_parsed) {
    # Unquoted (or unclosed quote fallback): first word
    _fallback_line = line
    gsub(/^["`\[]/, "", _fallback_line)
    _split_pos = index(_fallback_line, " ")
    if (_split_pos > 0) {
      _col_name = substr(_fallback_line, 1, _split_pos - 1)
      _col_rest = substr(_fallback_line, _split_pos + 1)
    } else {
      _col_name = _fallback_line
      _col_rest = ""
    }
    # Strip any stray quote chars from name
    gsub(/`/, "", _col_name)
    gsub(/\[/, "", _col_name)
    gsub(/\]/, "", _col_name)
    gsub(/"/, "", _col_name)
  }

  # Skip if column name looks like a keyword
  _upper_col = toupper(_col_name)
  if (_upper_col ~ /^(CONSTRAINT|PRIMARY|UNIQUE|CHECK|FOREIGN|INDEX)$/) return

  # Parse type from _col_rest
  gsub(/^[[:space:]]+/, "", _col_rest)

  _col_type = ""
  _remainder = ""

  # Split _col_rest into words
  _n = split(_col_rest, _words, " ")
  if (_n >= 1) {
    _col_type = _words[1]
    _idx = 2

    # Multi-word type continuations
    while (_idx <= _n) {
      _uw = toupper(_words[_idx])
      if (_uw ~ /^(NOT|NULL|DEFAULT|PRIMARY|REFERENCES|UNIQUE|CHECK|CONSTRAINT|GENERATED)($|\()/) break
      if (_uw ~ /^(VARYING|PRECISION|WITHOUT|WITH|ZONE|TIME)($|\()/) {
        _col_type = _col_type " " _words[_idx]
        _idx++
      } else {
        break
      }
    }

    # Rebuild _remainder from _idx onwards
    _remainder = ""
    for (_i = _idx; _i <= _n; _i++) {
      if (_remainder != "") _remainder = _remainder " "
      _remainder = _remainder _words[_i]
    }
  }

  # Uppercase the type
  _col_type = toupper(_col_type)

  # Detect NOT NULL → nullable flag (N = not null, Y = nullable)
  _nullable = "Y"
  _upper_remainder = toupper(_remainder)
  if (_upper_remainder ~ /NOT[[:space:]]+NULL/) {
    _nullable = "N"
  }

  # Detect PRIMARY KEY (implies NOT NULL)
  _key_flag = ""
  if (_upper_remainder ~ /PRIMARY[[:space:]]+KEY/) {
    _key_flag = "PK"
    _nullable = "N"
  }

  # Detect REFERENCES table(column)
  _fk_table = ""
  _fk_col = ""
  if (match(_upper_remainder, /REFERENCES[[:space:]]+/)) {
    _ref_part = _remainder
    sub(/.*[Rr][Ee][Ff][Ee][Rr][Ee][Nn][Cc][Ee][Ss][[:space:]]+/, "", _ref_part)
    gsub(/"/, "", _ref_part)
    gsub(/`/, "", _ref_part)
    gsub(/\[/, "", _ref_part)
    gsub(/\]/, "", _ref_part)

    _paren_pos = index(_ref_part, "(")
    if (_paren_pos > 0) {
      _fk_table = substr(_ref_part, 1, _paren_pos - 1)
      _rest_after = substr(_ref_part, _paren_pos + 1)
      _close_paren = index(_rest_after, ")")
      if (_close_paren > 0) {
        _fk_col = substr(_rest_after, 1, _close_paren - 1)
      }
    } else {
      split(_ref_part, _ref_words, " ")
      _fk_table = _ref_words[1]
    }
    gsub(/[[:space:]]+/, "", _fk_table)
    gsub(/[[:space:]]+/, "", _fk_col)
  }

  # Build GDLS column line: col|TYPE|NULLABLE|KEY|DESCRIPTION
  _col_line = _col_name "|" _col_type "|" _nullable "|" _key_flag "|"

  if (table_columns[tbl_name] != "") {
    table_columns[tbl_name] = table_columns[tbl_name] "\n" _col_line
  } else {
    table_columns[tbl_name] = _col_line
  }

  # Add FK relationship if detected
  if (_fk_table != "" && _fk_col != "") {
    _rel_line = "@R " tbl_name "." _col_name " -> " _fk_table "." _fk_col "|fk|"
    if (table_rels[tbl_name] != "") {
      table_rels[tbl_name] = table_rels[tbl_name] "\n" _rel_line
    } else {
      table_rels[tbl_name] = _rel_line
    }
  }
}

# Skip lines inside TEMPORARY table blocks — track paren depth
is_temp == 1 {
  _tline = $0
  for (_ti = 1; _ti <= length(_tline); _ti++) {
    _tc = substr(_tline, _ti, 1)
    if (_tc == "(") temp_depth++
    else if (_tc == ")") {
      if (temp_depth > 0) temp_depth--
      else { is_temp = 0; break }
    }
  }
  next
}

# ALTER TABLE ... ADD [COLUMN] col_name type ...
{
  line = $0
  gsub(/^[[:space:]]+/, "", line)
  gsub(/[[:space:]]+$/, "", line)
  upper_line = toupper(line)

  if (upper_line ~ /^ALTER[[:space:]]+TABLE/) {
    alter_line = line
    sub(/^[Aa][Ll][Tt][Ee][Rr][[:space:]]+[Tt][Aa][Bb][Ll][Ee][[:space:]]+/, "", alter_line)
    sub(/^[Ii][Ff][[:space:]]+[Ee][Xx][Ii][Ss][Tt][Ss][[:space:]]+/, "", alter_line)

    upper_alter = toupper(alter_line)
    add_pos = index(upper_alter, " ADD ")
    if (add_pos > 0) {
      alter_table = substr(alter_line, 1, add_pos - 1)
      col_def = substr(alter_line, add_pos + 5)

      # Strip quotes, backticks, brackets from table name
      gsub(/"/, "", alter_table)
      gsub(/`/, "", alter_table)
      gsub(/\[/, "", alter_table)
      gsub(/\]/, "", alter_table)
      gsub(/^[[:space:]]+/, "", alter_table)
      gsub(/[[:space:]]+$/, "", alter_table)
      if (index(alter_table, ".") > 0) {
        sub(/^[^.]+\./, "", alter_table)
      }

      # Remove optional COLUMN keyword
      sub(/^[Cc][Oo][Ll][Uu][Mm][Nn][[:space:]]+/, "", col_def)
      gsub(/^[[:space:]]+/, "", col_def)

      # Remove trailing semicolon
      sub(/;[[:space:]]*$/, "", col_def)

      # Skip empty column definitions (malformed SQL)
      if (col_def == "" || col_def ~ /^[[:space:]]*$/) next

      # Ensure table exists in tables array
      found = 0
      for (t = 1; t <= table_count; t++) {
        if (tables[t] == alter_table) {
          found = 1
          break
        }
      }
      if (!found) {
        table_count++
        tables[table_count] = alter_table
        table_columns[alter_table] = ""
        table_rels[alter_table] = ""
      }

      # Use shared column parser (handles quoting, types, nullable, PK, FK)
      process_col(col_def, alter_table)
    }
  }
}

END {
  for (t = 1; t <= table_count; t++) {
    tname = tables[t]
    print "@T " tname "|"
    n_cols = split(table_columns[tname], col_lines, "\n")
    for (c = 1; c <= n_cols; c++) {
      if (col_lines[c] != "") print col_lines[c]
    }
    if (table_rels[tname] != "") {
      n_rels = split(table_rels[tname], rel_lines, "\n")
      for (r = 1; r <= n_rels; r++) {
        if (rel_lines[r] != "") print rel_lines[r]
      }
    }
  }
}
' "$SQL_FILE")

# Empty output check — no tables found
if [[ -z "$output" ]]; then
  echo "No tables found in $SQL_FILE" >&2
  exit 0
fi

# Build final output with header
today=$(date -u +%Y-%m-%d)
safe_path="${SQL_FILE// /%20}"
safe_path="${safe_path//|/%7C}"
header="# @VERSION spec:gdls v:0.1.0 generated:${today} source:sql-ddl source-path:${safe_path}
# @FORMAT COLUMN|SQL_TYPE|NULLABLE|KEY|DESCRIPTION
@D |"

final_output="${header}
${output}"

# Output
if [[ -n "$OUTPUT_DIR" ]]; then
  if [[ ! -d "$OUTPUT_DIR" ]]; then
    echo "Error: output directory does not exist: $OUTPUT_DIR" >&2
    exit 1
  fi
  base_name=$(basename "$SQL_FILE" .sql)
  output_file="${OUTPUT_DIR}/${base_name}.gdls"
  _tmp_out=$(mktemp "$(dirname "$output_file")/.gdl-atomic.XXXXXX")
  printf '%s\n' "$final_output" > "$_tmp_out" || { rm -f "$_tmp_out"; exit 1; }
  mv "$_tmp_out" "$output_file"
  table_count=$(echo "$output" | grep -c '^@T ' || true)
  echo "Generated $table_count table(s) to $output_file" >&2
else
  printf '%s\n' "$final_output"
fi
