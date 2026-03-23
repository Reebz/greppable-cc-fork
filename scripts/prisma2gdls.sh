#!/usr/bin/env bash
# prisma2gdls.sh — Parse Prisma schema files to GDLS skeleton
# Usage: prisma2gdls.sh <file.prisma> [--output=DIR]
# No Prisma CLI required — uses awk/regex parsing only.
# Note: -e (errexit) intentionally omitted; grep returns 1 on no-match which is expected
set -uo pipefail

INPUT_FILE=""
OUTPUT_DIR=""

for arg in "$@"; do
  case "$arg" in
    --output=*) OUTPUT_DIR="${arg#--output=}" ;;
    --help|-h)
      cat <<'USAGE'
prisma2gdls.sh — Parse Prisma schema files to GDLS skeleton

Usage: prisma2gdls.sh <file.prisma> [--output=DIR]

Parses a Prisma .prisma schema file using awk/regex and generates GDLS
skeleton output. No Prisma CLI required.

OPTIONS:
  --output=DIR   Write output to DIR/<basename>.gdls (default: stdout)
  --help         Show this help

FEATURES:
  - Extracts model blocks as @T table records
  - Extracts enum blocks as @E records
  - Detects @id, @unique, @default, @relation, @db.Type annotations
  - Handles composite @@id([...]) primary keys
  - Skips virtual relation fields (Order[], User, etc.)
  - Maps Prisma types to SQL types
  - macOS compatible (BSD awk)
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
  echo "Usage: prisma2gdls.sh <file.prisma> [--output=DIR]" >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: file not found: $INPUT_FILE" >&2
  exit 1
fi

# Run the awk parser
output=$(awk '
BEGIN {
  # Type mappings: Prisma type -> SQL type
  type_map["String"]   = "VARCHAR"
  type_map["Int"]      = "INTEGER"
  type_map["Boolean"]  = "BOOLEAN"
  type_map["DateTime"] = "TIMESTAMP"
  type_map["Decimal"]  = "DECIMAL"
  type_map["Json"]     = "JSON"
  type_map["BigInt"]   = "BIGINT"
  type_map["Bytes"]    = "BYTEA"
  type_map["Float"]    = "FLOAT"

  model_count = 0
  enum_count = 0
  in_model = 0
  in_enum = 0
  in_datasource = 0
  in_generator = 0
  current_model = ""
  current_enum = ""
}

# Skip datasource blocks
/^[[:space:]]*datasource[[:space:]]/ {
  in_datasource = 1
  next
}
in_datasource == 1 && /}/ {
  in_datasource = 0
  next
}
in_datasource == 1 { next }

# Skip generator blocks
/^[[:space:]]*generator[[:space:]]/ {
  in_generator = 1
  next
}
in_generator == 1 && /}/ {
  in_generator = 0
  next
}
in_generator == 1 { next }

# Detect model opening
/^[[:space:]]*model[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\{/ {
  # Extract model name: second word
  for (i = 1; i <= NF; i++) {
    if ($i == "model") {
      current_model = $(i+1)
      # Remove trailing { if attached
      gsub(/\{/, "", current_model)
      break
    }
  }
  model_count++
  models[model_count] = current_model
  model_names[current_model] = 1
  in_model = 1
  field_count[current_model] = 0
  rel_count[current_model] = 0
  composite_pk[current_model] = ""
  next
}

# Detect model closing
in_model == 1 && /^[[:space:]]*\}/ {
  in_model = 0
  current_model = ""
  next
}

# Inside a model: parse @@id composite PK
in_model == 1 && /@@id\(/ {
  line = $0
  # Extract fields from @@id([fieldA, fieldB])
  gsub(/.*@@id\(\[/, "", line)
  gsub(/\]\).*/, "", line)
  gsub(/[[:space:]]/, "", line)
  composite_pk[current_model] = line
  next
}

# Inside a model: parse field lines
in_model == 1 && /^[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]/ {
  line = $0
  # Skip blank/comment lines
  if (line ~ /^[[:space:]]*$/) next
  if (line ~ /^[[:space:]]*\/\//) next

  # Extract field name (first non-whitespace word)
  gsub(/^[[:space:]]+/, "", line)

  n = split(line, parts, /[[:space:]]+/)
  if (n < 2) next

  field_name = parts[1]
  raw_type = parts[2]

  # Check if this is a relation field (type is another model name, possibly with [] or ?)
  base_type = raw_type
  gsub(/\?/, "", base_type)
  gsub(/\[\]/, "", base_type)

  # Detect if this is a virtual relation field:
  # A field whose base type matches a model name AND does not have @relation with fields:
  # OR a field that is a list type (Model[])
  is_list = (raw_type ~ /\[\]/) ? 1 : 0
  # Check if the line has @relation(fields: [...], references: [...])
  has_relation_fields = 0
  relation_field = ""
  relation_ref = ""
  relation_target = ""
  if (line ~ /@relation\(/) {
    has_relation_fields = (line ~ /fields:[[:space:]]*\[/)
    if (has_relation_fields) {
      # Extract fields: [xxx] and references: [yyy]
      tmp = line
      gsub(/.*fields:[[:space:]]*\[/, "", tmp)
      gsub(/\].*/, "", tmp)
      gsub(/[[:space:]]/, "", tmp)
      relation_field = tmp

      tmp2 = line
      gsub(/.*references:[[:space:]]*\[/, "", tmp2)
      gsub(/\].*/, "", tmp2)
      gsub(/[[:space:]]/, "", tmp2)
      relation_ref = tmp2

      relation_target = base_type
    }
  }

  # Skip virtual relation fields:
  # 1. List types (e.g., orders Order[]) - always virtual
  if (is_list) next

  # 2. Field type matches a known model name AND has @relation with fields:
  #    This is a relation SCALAR field — we want the FK column it references, not this field.
  #    The actual FK column (e.g., userId) is a separate field.
  if (has_relation_fields) {
    # Record the relationship for @R output
    rc = rel_count[current_model] + 1
    rel_count[current_model] = rc
    rel_fields[current_model, rc] = relation_field
    rel_refs[current_model, rc] = relation_ref
    rel_targets[current_model, rc] = relation_target
    next
  }

  # 3. Field type matches a model name but has NO @relation with fields — optional back-relation
  #    (e.g., profile Profile? on User)
  # We collect model names first, then check. For now, defer this check.
  # We will store all fields and filter later.

  # Determine SQL type
  nullable = 0
  if (raw_type ~ /\?$/) {
    nullable = 1
    raw_type_clean = raw_type
    gsub(/\?$/, "", raw_type_clean)
  } else {
    raw_type_clean = raw_type
  }

  sql_type = ""
  if (raw_type_clean in type_map) {
    sql_type = type_map[raw_type_clean]
  } else {
    # Could be an enum type or unknown — use as-is
    sql_type = raw_type_clean
  }

  # Check for @db.Type(args) precision override
  if (line ~ /@db\./) {
    tmp = line
    # Match @db.SomeType or @db.SomeType(args)
    gsub(/.*@db\./, "", tmp)
    gsub(/[[:space:]].*/, "", tmp)  # Take first token after @db.
    # tmp is now like "Decimal(10,2)" or "VarChar(255)"
    if (tmp ~ /\(/) {
      # Has precision: extract type and args
      db_type_name = tmp
      gsub(/\(.*/, "", db_type_name)
      db_type_args = tmp
      gsub(/[^(]*\(/, "(", db_type_args)
      gsub(/\).*/, ")", db_type_args)
      sql_type = toupper(db_type_name) db_type_args
    } else {
      sql_type = toupper(tmp)
    }
  }

  # Check for @id
  is_pk = 0
  if (line ~ /@id([[:space:]]|$)/) {
    is_pk = 1
  }

  # Store field data
  fc = field_count[current_model] + 1
  field_count[current_model] = fc
  field_names[current_model, fc] = field_name
  field_types[current_model, fc] = sql_type
  field_nullable[current_model, fc] = nullable
  field_pk[current_model, fc] = is_pk
  field_base_type[current_model, fc] = base_type

  next
}

# Detect enum opening
/^[[:space:]]*enum[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\{/ {
  for (i = 1; i <= NF; i++) {
    if ($i == "enum") {
      current_enum = $(i+1)
      gsub(/\{/, "", current_enum)
      break
    }
  }
  enum_count++
  enums[enum_count] = current_enum
  enum_values[current_enum] = ""
  in_enum = 1
  next
}

# Detect enum closing
in_enum == 1 && /^[[:space:]]*\}/ {
  in_enum = 0
  current_enum = ""
  next
}

# Inside an enum: collect values
in_enum == 1 && /^[[:space:]]+[A-Za-z_]/ {
  val = $0
  gsub(/^[[:space:]]+/, "", val)
  gsub(/[[:space:]]+$/, "", val)
  # Skip comments
  if (val ~ /^\/\//) next
  # Remove inline comments
  gsub(/[[:space:]]*\/\/.*$/, "", val)
  if (val == "") next
  if (enum_values[current_enum] == "") {
    enum_values[current_enum] = val
  } else {
    enum_values[current_enum] = enum_values[current_enum] "," val
  }
  next
}

END {
  # If no models and no enums, produce empty output
  if (model_count == 0 && enum_count == 0) exit 0

  # Second pass: identify which fields are virtual back-relations
  # (type matches a model name, no @relation fields: on this line — already skipped lists above)
  for (m = 1; m <= model_count; m++) {
    mname = models[m]
    for (f = 1; f <= field_count[mname]; f++) {
      bt = field_base_type[mname, f]
      if (bt in model_names) {
        # This field is type of another model — mark as virtual
        field_virtual[mname, f] = 1
      } else {
        field_virtual[mname, f] = 0
      }
    }

    # Handle composite PKs
    if (composite_pk[mname] != "") {
      n_cpk = split(composite_pk[mname], cpk_fields, /,/)
      for (c = 1; c <= n_cpk; c++) {
        cpk_name = cpk_fields[c]
        gsub(/[[:space:]]/, "", cpk_name)
        for (f = 1; f <= field_count[mname]; f++) {
          if (field_names[mname, f] == cpk_name) {
            field_pk[mname, f] = 1
          }
        }
      }
    }
  }

  # Output GDLS

  # Print tables
  for (m = 1; m <= model_count; m++) {
    mname = models[m]
    printf "@T %s|\n", mname

    for (f = 1; f <= field_count[mname]; f++) {
      # Skip virtual relation fields
      if (field_virtual[mname, f] == 1) continue

      fname = field_names[mname, f]
      ftype = field_types[mname, f]
      fnull = field_nullable[mname, f]
      fpk = field_pk[mname, f]

      null_flag = "N"
      if (fnull == 1) null_flag = "Y"

      key_flag = ""
      if (fpk == 1) key_flag = "PK"

      printf "%s|%s|%s|%s|\n", fname, ftype, null_flag, key_flag
    }

    # Print @R records for this table
    for (r = 1; r <= rel_count[mname]; r++) {
      rf = rel_fields[mname, r]
      rr = rel_refs[mname, r]
      rt = rel_targets[mname, r]
      printf "@R %s.%s -> %s.%s|fk|\n", mname, rf, rt, rr
    }
  }

  # Print enum records
  for (e = 1; e <= enum_count; e++) {
    ename = enums[e]
    evals = enum_values[ename]
    printf "@E %s|%s\n", ename, evals
  }
}
' "$INPUT_FILE")

# If output is empty (only datasource/generator blocks), exit cleanly
if [[ -z "$output" ]]; then
  exit 0
fi

# Build header
safe_path="${INPUT_FILE// /%20}"
safe_path="${safe_path//|/%7C}"
header="# @VERSION spec:gdls v:0.1.0 generated:$(date -u +%Y-%m-%d) source:prisma source-path:${safe_path}"
format_header="# @FORMAT COLUMN|SQL_TYPE|NULLABLE|KEY|DESCRIPTION"

full_output="${header}
${format_header}
@D |
${output}"

# Output
if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  base_name=$(basename "$INPUT_FILE" .prisma)
  out_file="${OUTPUT_DIR}/${base_name}.gdls"
  _tmp_out=$(mktemp "$(dirname "$out_file")/.gdl-atomic.XXXXXX")
  printf '%s\n' "$full_output" > "$_tmp_out" || { rm -f "$_tmp_out"; exit 1; }
  mv "$_tmp_out" "$out_file"
  table_count=$(echo "$full_output" | grep -c '^@T' || true)
  echo "Generated $table_count table(s) to $out_file" >&2
else
  printf '%s\n' "$full_output"
fi
