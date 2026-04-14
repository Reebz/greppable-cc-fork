#!/usr/bin/env bash
# gdl-prescan.sh — Scan a project directory and detect available GDL bridge tools
# Usage: gdl-prescan.sh <directory> [--json]
#
# Detects source files, SQL migrations, Prisma schemas, and database configs.
# Outputs recommended bridge commands for skeleton generation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Directories to exclude from scanning
EXCLUDE_DIRS="node_modules|.git|__pycache__|.venv|vendor|target|dist|build|.next"

usage() {
  cat <<'USAGE'
gdl-prescan.sh — Detect available GDL bridge tools for a project

Usage: gdl-prescan.sh <directory> [--json] [--all]

Scans the target directory for source files, SQL migrations, Prisma schemas,
package.json dependencies, Docker Compose files, and database configurations.
Reports which bridge tools can generate GDL skeletons automatically.

Options:
  --json    Output results as JSON instead of human-readable text
  --all     Include all bridges (default: v1 bridges only)
  --help    Show this help

Detected bridges:
  SQL DDL                → sql2gdls.sh
  Prisma                 → prisma2gdls.sh
  npm (package.json)     → npm2gdld.sh (--all)
  Docker Compose         → compose2gdld.sh (--all)
  Go modules (go.mod)    → gomod2gdld.sh (--all)
  Python (requirements)  → pip2gdld.sh (--all)
  Rust (Cargo.toml)      → cargo2gdld.sh (--all)
  Maven (pom.xml)        → maven2gdld.sh (--all)
  Markdown docs          → docs2gdlu.sh (--all)
  OpenAPI spec           → openapi2gdla.sh
  GraphQL schema         → graphql2gdla.sh
  PostgreSQL (live)      → db2gdls.sh
USAGE
}

# --- Argument parsing ---
TARGET_DIR=""
JSON_MODE=false
ALL_BRIDGES=false

for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=true ;;
    --all) ALL_BRIDGES=true ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "Unknown flag: $arg" >&2; usage >&2; exit 1 ;;
    *)
      if [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="$arg"
      else
        echo "Error: unexpected argument '$arg'" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$TARGET_DIR" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Error: directory '$TARGET_DIR' does not exist. Check path or run: ls -d */" >&2
  exit 1
fi

# --- File counting helpers ---
# Count files by extension pattern, excluding build/vendor dirs.
# Uses find with -not -path to exclude dirs (macOS BSD compatible).
count_files_by_ext() {
  local dir="$1"
  shift
  # Build find arguments for each extension
  local find_args=()
  local first=true
  for ext in "$@"; do
    if [[ "$first" = true ]]; then
      find_args+=( -name "*${ext}" )
      first=false
    else
      find_args+=( -o -name "*${ext}" )
    fi
  done

  # Build exclusion predicates
  local exclude_args=()
  local IFS='|'
  for d in $EXCLUDE_DIRS; do
    exclude_args+=( -not -path "*/${d}/*" )
  done

  IFS=$' \t\n'  # Restore default before find command
  find "$dir" "${exclude_args[@]}" \( "${find_args[@]}" \) -type f 2>/dev/null | wc -l | tr -d ' '
}

# Count .sql files that contain CREATE TABLE (case insensitive)
count_sql_with_ddl() {
  local dir="$1"
  local count=0

  # Build exclusion predicates
  local exclude_args=()
  local IFS='|'
  for d in $EXCLUDE_DIRS; do
    exclude_args+=( -not -path "*/${d}/*" )
  done

  IFS=$' \t\n'  # Restore default before find command
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if grep -qi 'CREATE TABLE' "$file" 2>/dev/null; then
      count=$((count + 1))
    fi
  done <<< "$(find "$dir" "${exclude_args[@]}" -name "*.sql" -type f 2>/dev/null || true)"
  echo "$count"
}

# Check for database config indicators
detect_database_config() {
  local dir="$1"

  # Check for .env with DATABASE_URL
  if [[ -f "$dir/.env" ]] && grep -q 'DATABASE_URL' "$dir/.env" 2>/dev/null; then
    echo "true"
    return
  fi

  # Check for docker-compose.yml with postgres
  for compose_file in "$dir/docker-compose.yml" "$dir/docker-compose.yaml"; do
    if [[ -f "$compose_file" ]] && grep -qi 'postgres' "$compose_file" 2>/dev/null; then
      echo "true"
      return
    fi
  done

  echo "false"
}

# --- Detection ---
bridges=()
bridge_types=()
bridge_languages=()
bridge_counts=()
bridge_commands=()

# SQL DDL
sql_count=$(count_sql_with_ddl "$TARGET_DIR")
if [[ "$sql_count" -gt 0 ]] && [[ -x "$SCRIPT_DIR/sql2gdls.sh" ]]; then
  bridges+=("SQL DDL")
  bridge_types+=("schema")
  bridge_languages+=("sql")
  bridge_counts+=("$sql_count")
  bridge_commands+=("for f in <DIR>/*.sql; do bash scripts/sql2gdls.sh \"\$f\" --output=<OUTPUT>/schema; done")
fi

# Prisma
prisma_count=$(count_files_by_ext "$TARGET_DIR" ".prisma")
if [[ "$prisma_count" -gt 0 ]] && [[ -x "$SCRIPT_DIR/prisma2gdls.sh" ]]; then
  bridges+=("Prisma")
  bridge_types+=("schema")
  bridge_languages+=("prisma")
  bridge_counts+=("$prisma_count")
  bridge_commands+=("for f in <DIR>/*.prisma; do bash scripts/prisma2gdls.sh \"\$f\" --output=<OUTPUT>/schema; done")
fi

# v1: excluded from default — use --all to include
# npm/yarn (package.json)
if [[ "$ALL_BRIDGES" = true ]] && [[ -f "$TARGET_DIR/package.json" ]] && [[ -x "$SCRIPT_DIR/npm2gdld.sh" ]]; then
  bridges+=("npm (package.json)")
  bridge_types+=("diagram")
  bridge_languages+=("npm")
  bridge_counts+=("1")
  bridge_commands+=("bash scripts/npm2gdld.sh <DIR>/package.json --output=<OUTPUT>/diagram")
fi

# v1: excluded from default — use --all to include
# Docker Compose (check both legacy and V2 naming conventions)
if [[ "$ALL_BRIDGES" = true ]]; then
  for compose_file in "$TARGET_DIR/docker-compose.yml" "$TARGET_DIR/docker-compose.yaml" "$TARGET_DIR/compose.yml" "$TARGET_DIR/compose.yaml"; do
    if [[ -f "$compose_file" ]] && [[ -x "$SCRIPT_DIR/compose2gdld.sh" ]]; then
      bridges+=("Docker Compose")
      bridge_types+=("diagram")
      bridge_languages+=("compose")
      bridge_counts+=("1")
      bridge_commands+=("bash scripts/compose2gdld.sh \"$compose_file\" --output=<OUTPUT>/diagram")
      break  # Only detect once even if both .yml and .yaml exist
    fi
  done
fi

# v1: excluded from default — use --all to include
# Go modules (go.mod)
if [[ "$ALL_BRIDGES" = true ]] && [[ -f "$TARGET_DIR/go.mod" ]] && [[ -x "$SCRIPT_DIR/gomod2gdld.sh" ]]; then
  bridges+=("Go modules (go.mod)")
  bridge_types+=("diagram")
  bridge_languages+=("gomod")
  bridge_counts+=("1")
  bridge_commands+=("bash scripts/gomod2gdld.sh <DIR>/go.mod --output=<OUTPUT>/diagram")
fi

# v1: excluded from default — use --all to include
# Python requirements (requirements.txt)
if [[ "$ALL_BRIDGES" = true ]] && [[ -f "$TARGET_DIR/requirements.txt" ]] && [[ -x "$SCRIPT_DIR/pip2gdld.sh" ]]; then
  bridges+=("Python requirements")
  bridge_types+=("diagram")
  bridge_languages+=("pip")
  bridge_counts+=("1")
  bridge_commands+=("bash scripts/pip2gdld.sh <DIR>/requirements.txt --output=<OUTPUT>/diagram")
fi

# v1: excluded from default — use --all to include
# Rust Cargo (Cargo.toml)
if [[ "$ALL_BRIDGES" = true ]] && [[ -f "$TARGET_DIR/Cargo.toml" ]] && [[ -x "$SCRIPT_DIR/cargo2gdld.sh" ]]; then
  bridges+=("Cargo (Cargo.toml)")
  bridge_types+=("diagram")
  bridge_languages+=("cargo")
  bridge_counts+=("1")
  bridge_commands+=("bash scripts/cargo2gdld.sh <DIR>/Cargo.toml --output=<OUTPUT>/diagram")
fi

# v1: excluded from default — use --all to include
# Maven (pom.xml)
if [[ "$ALL_BRIDGES" = true ]] && [[ -f "$TARGET_DIR/pom.xml" ]] && [[ -x "$SCRIPT_DIR/maven2gdld.sh" ]]; then
  bridges+=("Maven (pom.xml)")
  bridge_types+=("diagram")
  bridge_languages+=("maven")
  bridge_counts+=("1")
  bridge_commands+=("bash scripts/maven2gdld.sh <DIR>/pom.xml --output=<OUTPUT>/diagram")
fi

# v1: excluded from default — use --all to include
# Markdown docs (.md files)
if [[ "$ALL_BRIDGES" = true ]]; then
  md_count=$(count_files_by_ext "$TARGET_DIR" ".md")
  if [[ "$md_count" -gt 0 ]] && [[ -x "$SCRIPT_DIR/docs2gdlu.sh" ]]; then
    bridges+=("Markdown docs")
    bridge_types+=("unstructured")
    bridge_languages+=("markdown")
    bridge_counts+=("$md_count")
    bridge_commands+=("bash scripts/docs2gdlu.sh --recursive <DIR> --output=<OUTPUT>/unstructured")
  fi
fi

# OpenAPI spec (openapi.json/yaml, swagger.json/yaml) — recursive search
# Build exclusions from EXCLUDE_DIRS (same as count_files_by_ext)
openapi_exclude=()
_oIFS="$IFS"; IFS='|'
for d in $EXCLUDE_DIRS; do
  openapi_exclude+=( -not -path "*/${d}/*" )
done
IFS="$_oIFS"

openapi_count=0
for spec_name in openapi.json openapi.yaml openapi.yml swagger.json swagger.yaml swagger.yml; do
  c=$(find "$TARGET_DIR" "${openapi_exclude[@]}" -name "$spec_name" -type f 2>/dev/null | wc -l)
  openapi_count=$((openapi_count + c))
done
if [[ "$openapi_count" -gt 0 ]] && [[ -x "$SCRIPT_DIR/openapi2gdla.sh" ]]; then
  bridges+=("OpenAPI spec")
  bridge_types+=("api")
  bridge_languages+=("openapi")
  bridge_counts+=("$openapi_count")
  bridge_commands+=("find <DIR> \\( -name 'openapi.json' -o -name 'openapi.yaml' -o -name 'openapi.yml' -o -name 'swagger.json' -o -name 'swagger.yaml' -o -name 'swagger.yml' \\) -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' -not -path '*/.venv/*' -not -path '*/target/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.next/*' -not -path '*/__pycache__/*' -type f -exec bash scripts/openapi2gdla.sh {} --output=<OUTPUT>/api \\;")
fi

# GraphQL schema (.graphql/.gql)
gql_count=$(count_files_by_ext "$TARGET_DIR" ".graphql" ".gql")
if [[ "$gql_count" -gt 0 ]] && [[ -x "$SCRIPT_DIR/graphql2gdla.sh" ]]; then
  bridges+=("GraphQL schema")
  bridge_types+=("api")
  bridge_languages+=("graphql")
  bridge_counts+=("$gql_count")
  bridge_commands+=("bash scripts/graphql2gdla.sh <DIR>/schema.graphql --output=<OUTPUT>/api")
fi

# PostgreSQL (live database)
db_config=$(detect_database_config "$TARGET_DIR")
if [[ "$db_config" = "true" ]] && [[ -x "$SCRIPT_DIR/db2gdls.sh" ]]; then
  bridges+=("PostgreSQL (live)")
  bridge_types+=("schema")
  bridge_languages+=("postgresql")
  bridge_counts+=("1")
  bridge_commands+=("bash scripts/db2gdls.sh --db=<DBNAME> --output=<OUTPUT>/schema")
fi

# --- Exclusion suggestions ---
suggested_exclusions=()
exclusion_formats=()
exclusion_reasons=()


# --- Output ---
bridge_count=${#bridges[@]}

if [[ "$JSON_MODE" = true ]]; then
  # JSON output
  echo "{"
  echo "  \"bridges\": ["
  for ((i = 0; i < bridge_count; i++)); do
    comma=""
    if [[ $i -lt $((bridge_count - 1)) ]]; then
      comma=","
    fi
    # Escape backslashes and double quotes for JSON
    cmd="${bridge_commands[$i]}"
    cmd="${cmd//\\/\\\\}"
    cmd="${cmd//\"/\\\"}"
    echo "    {"
    echo "      \"type\": \"${bridge_types[$i]}\","
    echo "      \"language\": \"${bridge_languages[$i]}\","
    echo "      \"file_count\": ${bridge_counts[$i]},"
    echo "      \"command\": \"${cmd}\""
    echo "    }${comma}"
  done
  echo "  ],"
  echo "  \"suggested_exclusions\": ["
  excl_count=${#suggested_exclusions[@]}
  for ((i = 0; i < excl_count; i++)); do
    comma=""
    if [[ $i -lt $((excl_count - 1)) ]]; then
      comma=","
    fi
    # Escape backslashes and double quotes for JSON
    pat="${suggested_exclusions[$i]}"
    pat="${pat//\\/\\\\}"
    pat="${pat//\"/\\\"}"
    fmt="${exclusion_formats[$i]}"
    rsn="${exclusion_reasons[$i]}"
    rsn="${rsn//\\/\\\\}"
    rsn="${rsn//\"/\\\"}"
    echo "    {"
    echo "      \"format\": \"${fmt}\","
    echo "      \"pattern\": \"${pat}\","
    echo "      \"reason\": \"${rsn}\""
    echo "    }${comma}"
  done
  echo "  ]"
  echo "}"
else
  # Human-readable output
  echo "Bridge Detection Report"
  echo "======================="
  echo ""
  if [[ "$bridge_count" -eq 0 ]]; then
    echo "No bridges detected."
  else
    for ((i = 0; i < bridge_count; i++)); do
      echo "${bridges[$i]}: ${bridge_counts[$i]} files detected"
      echo "  -> ${bridge_commands[$i]}"
    done
    echo ""
    echo "Total: $bridge_count bridge(s) detected"
  fi
  if [[ ${#suggested_exclusions[@]} -gt 0 ]]; then
    echo ""
    echo "Suggested Exclusions"
    echo "--------------------"
    for ((i = 0; i < ${#suggested_exclusions[@]}; i++)); do
      echo "  ${exclusion_formats[$i]}:${suggested_exclusions[$i]} (${exclusion_reasons[$i]})"
    done
  fi
fi

exit 0
