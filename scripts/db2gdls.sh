#!/usr/bin/env bash
# db2gdls.sh — Extract PostgreSQL schema to GDLS skeleton
# Usage: db2gdls.sh --db=DBNAME [--host=HOST] [--port=PORT] [--user=USER]
#                    [--schema=SCHEMA] [--output=FILE] [--table=TABLE]
#                    [--dry-run] [--check] [--with-enrichment]
# Note: -e (errexit) intentionally omitted; grep returns 1 on no-match which is expected
set -uo pipefail

DB_NAME=""
DB_HOST=""
DB_PORT=""
DB_USER=""
SCHEMA_FILTER=""
TABLE_FILTER=""
OUTPUT_FILE=""
DRY_RUN=false
CHECK_MODE=false
WITH_ENRICHMENT=false

for arg in "$@"; do
  case "$arg" in
    --db=*) DB_NAME="${arg#--db=}" ;;
    --host=*) DB_HOST="${arg#--host=}" ;;
    --port=*) DB_PORT="${arg#--port=}" ;;
    --user=*) DB_USER="${arg#--user=}" ;;
    --schema=*) SCHEMA_FILTER="${arg#--schema=}" ;;
    --table=*) TABLE_FILTER="${arg#--table=}" ;;
    --output=*) OUTPUT_FILE="${arg#--output=}" ;;
    --dry-run) DRY_RUN=true ;;
    --check) CHECK_MODE=true ;;
    --with-enrichment) WITH_ENRICHMENT=true ;;
    --help|-h)
      cat <<'USAGE'
db2gdls.sh — Extract PostgreSQL schema to GDLS skeleton

CONNECTION:
  --db=DBNAME      Database name (required)
  --host=HOST      Database host (default: local socket)
  --port=PORT      Database port (default: 5432)
  --user=USER      Database user (default: $PGUSER or current OS user)

FILTERS:
  --schema=NAME    Only extract tables from this schema (default: all non-system)
  --table=NAME     Only extract this specific table

OUTPUT:
  --output=FILE    Write to file (default: stdout)
  --dry-run        Show what would be generated without generating
  --check          Compare database against existing --output file for drift
  --with-enrichment  Also generate a .enrich.gdls template alongside skeleton

Generates GDLS skeleton files with empty descriptions.
Use with an enrichment overlay (.enrich.gdls) for descriptions.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg. Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

if [[ -z "$DB_NAME" ]]; then
  echo "Usage: db2gdls.sh --db=DBNAME [--host=HOST] [--port=PORT] [--user=USER] [--schema=SCHEMA] [--output=FILE]" >&2
  exit 1
fi

# Validate SQL identifier inputs to prevent injection
_validate_identifier() {
  local name="$1" value="$2"
  if [[ -n "$value" && ! "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "Error: $name must be a valid SQL identifier (letters, digits, underscore): '$value'" >&2
    exit 1
  fi
}
_validate_identifier "--db" "$DB_NAME"
_validate_identifier "--schema" "$SCHEMA_FILTER"
_validate_identifier "--table" "$TABLE_FILTER"
_validate_identifier "--user" "$DB_USER"

# Validate --host (hostname characters only)
if [[ -n "$DB_HOST" && ! "$DB_HOST" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Error: --host contains invalid characters: '$DB_HOST'" >&2
  exit 1
fi

# Validate --port (digits only)
if [[ -n "$DB_PORT" && ! "$DB_PORT" =~ ^[0-9]+$ ]]; then
  echo "Error: --port must be a number: '$DB_PORT'" >&2
  exit 1
fi

# Warn if --with-enrichment used without --output
if [[ "$WITH_ENRICHMENT" == "true" && -z "$OUTPUT_FILE" ]]; then
  echo "Warning: --with-enrichment requires --output; enrichment overlay will not be generated" >&2
fi

# Verify psql available
if ! command -v psql &>/dev/null; then
  echo "Error: psql is required. Install PostgreSQL client tools." >&2
  exit 1
fi

# Build psql connection args (only add flags when explicitly set)
PSQL_ARGS=(-d "$DB_NAME" -t -A)
if [[ -n "$DB_HOST" ]]; then
  PSQL_ARGS+=(-h "$DB_HOST")
fi
if [[ -n "$DB_PORT" ]]; then
  PSQL_ARGS+=(-p "$DB_PORT")
fi
if [[ -n "$DB_USER" ]]; then
  PSQL_ARGS+=(-U "$DB_USER")
fi

# Helper: run psql query, return raw output
_db_query() {
  local sql="$1"; shift
  local err_file
  err_file=$(mktemp)
  local result
  if result=$(psql "${PSQL_ARGS[@]}" -c "$sql" "$@" 2>"$err_file"); then
    rm -f "$err_file"
    printf '%s' "$result"
  else
    echo "Error: psql query failed: $(cat "$err_file")" >&2
    rm -f "$err_file"
    exit 1
  fi
}

# Test connection
if ! psql "${PSQL_ARGS[@]}" -c "SELECT 1" >/dev/null 2>&1; then
  echo "Error: Cannot connect to database '$DB_NAME'" >&2
  exit 1
fi

# Build WHERE clauses for schema/table filters
schema_where="table_schema NOT IN ('information_schema', 'pg_catalog', 'pg_toast')"
if [[ -n "$SCHEMA_FILTER" ]]; then
  schema_where="table_schema = '$SCHEMA_FILTER'"
fi

table_where=""
if [[ -n "$TABLE_FILTER" ]]; then
  table_where="AND table_name = '$TABLE_FILTER'"
fi

# --- Dry run mode ---
if [[ "$DRY_RUN" == "true" ]]; then
  schema_count=$(_db_query "SELECT COUNT(DISTINCT table_schema) FROM information_schema.tables WHERE $schema_where $table_where") || exit 1
  table_count=$(_db_query "SELECT COUNT(*) FROM information_schema.tables WHERE $schema_where AND table_type = 'BASE TABLE' $table_where") || exit 1
  col_count=$(_db_query "SELECT COUNT(*) FROM information_schema.columns c JOIN information_schema.tables t ON c.table_schema = t.table_schema AND c.table_name = t.table_name WHERE t.${schema_where} AND t.table_type = 'BASE TABLE'$( [[ -n "$TABLE_FILTER" ]] && echo " AND t.table_name = '$TABLE_FILTER'" )") || exit 1
  fk_count=$(_db_query "SELECT COUNT(*) FROM information_schema.table_constraints WHERE $schema_where AND constraint_type = 'FOREIGN KEY' $table_where") || exit 1
  echo "Would generate: $schema_count schemas, $table_count tables, $col_count columns, $fk_count foreign keys" >&2
  if [[ -n "$OUTPUT_FILE" ]]; then
    echo "Output: $OUTPUT_FILE" >&2
  fi
  exit 0
fi

# --- Main extraction ---
output=""

# Header
output+="# @VERSION spec:gdls v:0.1.0 generated:$(date -u +%Y-%m-%d) source:db-introspect"$'\n'
output+="# @FORMAT COLUMN|SQL_TYPE|NULLABLE|KEY|DESCRIPTION"$'\n'

# Get schemas
schemas=$(_db_query "SELECT DISTINCT table_schema FROM information_schema.tables WHERE $schema_where $table_where ORDER BY table_schema") || exit 1

while IFS= read -r schema; do
  [[ -z "$schema" ]] && continue
  # Escape single quotes in schema/table names (second-order injection defense)
  safe_schema="${schema//\'/\'\'}"
  output+="@D ${schema}|"$'\n'

  # Get tables in this schema
  tables=$(_db_query "SELECT table_name FROM information_schema.tables WHERE table_schema = '$safe_schema' AND table_type = 'BASE TABLE' $table_where ORDER BY table_name") || exit 1

  while IFS= read -r table; do
    [[ -z "$table" ]] && continue
    safe_table="${table//\'/\'\'}"
    output+="@T ${table}|"$'\n'

    # Get primary key columns for this table
    pk_cols=$(_db_query "
      SELECT kcu.column_name
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
      WHERE tc.table_schema = '$safe_schema'
        AND tc.table_name = '$safe_table'
        AND tc.constraint_type = 'PRIMARY KEY'
    ") || exit 1
    # Replace newlines with | for multi-column PK matching
    pk_list="|$(echo "$pk_cols" | tr '\n' '|')|"

    # Get foreign key columns for this table
    fk_cols=$(_db_query "
      SELECT kcu.column_name
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
      WHERE tc.table_schema = '$safe_schema'
        AND tc.table_name = '$safe_table'
        AND tc.constraint_type = 'FOREIGN KEY'
    ") || exit 1
    # Replace newlines with | for multi-column FK matching
    fk_list="|$(echo "$fk_cols" | tr '\n' '|')|"

    # Get columns (use udt_name for USER-DEFINED types like enums)
    columns=$(_db_query "
      SELECT column_name,
        CASE WHEN data_type = 'USER-DEFINED'
          THEN udt_name
          WHEN data_type = 'ARRAY'
          THEN SUBSTRING(udt_name FROM 2) || '[]'
          WHEN character_maximum_length IS NOT NULL
          THEN data_type || '(' || character_maximum_length || ')'
          WHEN numeric_precision IS NOT NULL AND data_type IN ('numeric', 'decimal')
          THEN data_type || '(' || numeric_precision || ',' || COALESCE(numeric_scale, 0) || ')'
          ELSE data_type
        END as full_type,
        is_nullable
      FROM information_schema.columns
      WHERE table_schema = '$safe_schema'
        AND table_name = '$safe_table'
      ORDER BY ordinal_position
    " -F $'\x1f') || exit 1

    while IFS=$'\x1f' read -r col_name full_type nullable; do
      [[ -z "$col_name" ]] && continue
      null_flag="Y"
      [[ "$nullable" == "NO" ]] && null_flag="N"
      key_flag=""
      case "$pk_list" in *"|$col_name|"*) key_flag="PK" ;; esac
      case "$fk_list" in *"|$col_name|"*)
        if [[ -n "$key_flag" ]]; then key_flag="PK,FK"; else key_flag="FK"; fi
        ;;
      esac
      output+="${col_name}|${full_type}|${null_flag}|${key_flag}|"$'\n'
    done <<< "$columns"

    # Get foreign key relationships for @R records using pg_constraint
    # (information_schema.constraint_column_usage produces cartesian products for composite FKs)
    # Note: target uses table.column (no schema prefix) per GDLS @R convention.
    # Cross-schema refs work when all schemas are in the same file; for name collisions,
    # use separate GDLS files per schema with _relationships.gdls for cross-schema mappings.
    fk_rels=$(_db_query "
      SELECT
        a_from.attname,
        c_to.relname || '.' || a_to.attname
      FROM pg_constraint con
      JOIN pg_attribute a_from
        ON a_from.attrelid = con.conrelid
        AND a_from.attnum = ANY(con.conkey)
      JOIN pg_class c_to ON c_to.oid = con.confrelid
      JOIN pg_attribute a_to
        ON a_to.attrelid = con.confrelid
        AND a_to.attnum = con.confkey[array_position(con.conkey, a_from.attnum)]
      WHERE con.contype = 'f'
        AND con.conrelid = (
          SELECT c.oid FROM pg_class c
          JOIN pg_namespace n ON c.relnamespace = n.oid
          WHERE c.relname = '$safe_table' AND n.nspname = '$safe_schema'
        )
      ORDER BY a_from.attname
    " -F $'\x1f') || exit 1

    while IFS=$'\x1f' read -r fk_col fk_target; do
      [[ -z "$fk_col" ]] && continue
      output+="@R ${table}.${fk_col} -> ${fk_target}|fk|"$'\n'
    done <<< "$fk_rels"

    # Get enum values for columns in this table (per GDLS spec: @E after @R within table block)
    # Escape pipe characters in enum labels (would corrupt GDLS record structure)
    # Detect comma-containing labels (ambiguous with GDLS @E value separator)
    enum_cols=$(_db_query "
      SELECT
        c.column_name,
        string_agg(REPLACE(e.enumlabel, '|', '\|'), ',' ORDER BY e.enumsortorder),
        bool_or(e.enumlabel LIKE '%,%')
      FROM information_schema.columns c
      JOIN pg_type t ON t.typname = c.udt_name
      JOIN pg_namespace tn ON t.typnamespace = tn.oid AND tn.nspname = c.udt_schema
      JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE c.table_schema = '$safe_schema'
        AND c.table_name = '$safe_table'
      GROUP BY c.table_schema, c.table_name, c.column_name
      ORDER BY c.column_name
    " -F $'\x1f') || exit 1

    while IFS=$'\x1f' read -r enum_col enum_vals has_comma; do
      [[ -z "$enum_col" ]] && continue
      if [[ "$has_comma" == "t" ]]; then
        echo "Warning: enum ${table}.${enum_col} has labels containing commas; @E values may be ambiguous" >&2
      fi
      output+="@E ${table}.${enum_col}|${enum_vals}|"$'\n'
    done <<< "$enum_cols"

  done <<< "$tables"

done <<< "$schemas"

# --- Check mode (drift detection) ---
if [[ "$CHECK_MODE" == "true" ]]; then
  if [[ -z "$OUTPUT_FILE" || ! -f "$OUTPUT_FILE" ]]; then
    echo "Error: --check requires an existing --output file to compare against" >&2
    exit 1
  fi
  # Use .gdls extension so gdl-diff.sh can detect the format
  check_tmp=$(mktemp -d)
  trap "rm -rf '$check_tmp'" EXIT
  fresh="$check_tmp/fresh.gdls"
  existing_stripped="$check_tmp/existing.gdls"
  fresh_stripped="$check_tmp/freshstrip.gdls"
  printf '%s' "$output" > "$fresh"
  # Strip @VERSION lines — the generated: date always differs
  grep -v '^# @VERSION' "$OUTPUT_FILE" > "$existing_stripped" || true
  grep -v '^# @VERSION' "$fresh" > "$fresh_stripped" || true
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  diff_out=$(bash "$SCRIPT_DIR/gdl-diff.sh" "$existing_stripped" "$fresh_stripped" 2>&1) || true
  rm -f "$fresh" "$existing_stripped" "$fresh_stripped"
  if echo "$diff_out" | grep -q "No changes"; then
    echo "Schema is fresh — no drift detected." >&2
    exit 0
  else
    echo "Schema drift detected:" >&2
    echo "$diff_out" >&2
    exit 1
  fi
fi

# --- Output ---
if [[ -n "$OUTPUT_FILE" ]]; then
  tmp_out=$(mktemp)
  trap "rm -f '$tmp_out'" EXIT
  printf '%s' "$output" > "$tmp_out"
  mv "$tmp_out" "$OUTPUT_FILE"
  table_count=$(echo "$output" | grep -c '^@T' || true)
  echo "Generated $table_count table(s) to $OUTPUT_FILE" >&2
else
  printf '%s' "$output"
fi

# --- Enrichment overlay ---
if [[ "$WITH_ENRICHMENT" == "true" && -n "$OUTPUT_FILE" ]]; then
  enrich_file="${OUTPUT_FILE%.gdls}.enrich.gdls"
  if [[ -f "$enrich_file" ]]; then
    echo "Enrichment file already exists: $enrich_file (skipping)" >&2
  else
    enrich_output=""
    enrich_output+="# @VERSION spec:gdls v:0.1.0 generated:$(date -u +%Y-%m-%d) source:agent"$'\n'
    enrich_output+="# @FORMAT COLUMN|SQL_TYPE|NULLABLE|KEY|DESCRIPTION"$'\n'
    enrich_output+="# Enrichments for $(basename "$OUTPUT_FILE")"$'\n'
    enrich_output+="# Fill in descriptions below. Only non-empty fields are merged."$'\n'
    enrich_output+=$'\n'
    # Echo @D and @T lines with placeholder descriptions
    while IFS= read -r line; do
      case "$line" in
        "@D "*)
          domain_name=$(echo "$line" | cut -d'|' -f1)
          enrich_output+="${domain_name}|TODO: describe this domain"$'\n'
          ;;
        "@T "*)
          table_name=$(echo "$line" | cut -d'|' -f1)
          enrich_output+="${table_name}|TODO: describe this table"$'\n'
          ;;
      esac
    done <<< "$output"
    printf '%s' "$enrich_output" > "$enrich_file"
    echo "Generated enrichment template: $enrich_file" >&2
  fi
fi
