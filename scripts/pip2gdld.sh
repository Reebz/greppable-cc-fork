#!/usr/bin/env bash
# pip2gdld.sh — Convert requirements.txt to GDLD dependency diagram
# Usage: pip2gdld.sh <requirements.txt> [--output=DIR] [--dry-run]
# Pure awk parser — no pip or Python required.
set -uo pipefail

INPUT_FILE=""
OUTPUT_DIR=""
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --output=*) OUTPUT_DIR="${arg#--output=}" ;;
    --dry-run) DRY_RUN=true ;;
    --help|-h)
      cat <<'USAGE'
pip2gdld.sh — Convert requirements.txt to GDLD dependency diagram

Usage: pip2gdld.sh <requirements.txt> [--output=DIR] [--dry-run]

Parses a requirements.txt file using awk and generates a GDLD dependency
flow diagram with nodes for each dependency and edges showing
dependency relationships.

OPTIONS:
  --output=DIR   Write output to DIR/<project>.pip.gdld (default: stdout)
  --dry-run      Show what would be generated without writing
  --help         Show this help

FEATURES:
  - Extracts package names and version specifiers
  - Skips comments, blank lines, option lines (-r, -e, -c, etc.)
  - Strips extras brackets ([email]) and environment markers (; python_version)
  - Project name derived from parent directory
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
  echo "Usage: pip2gdld.sh <requirements.txt> [--output=DIR] [--dry-run]" >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: file not found: $INPUT_FILE" >&2
  exit 1
fi

# Project name from parent directory (requirements.txt has no name field)
project_name=$(basename "$(cd "$(dirname "$INPUT_FILE")" && pwd)")
project_slug=$(echo "$project_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

output=$(awk -v project="$project_slug" '
BEGIN {
  dep_count = 0
}

# Skip comments, blank lines, option lines
/^[[:space:]]*#/ { next }
/^[[:space:]]*$/ { next }
/^[[:space:]]*-/ { next }

{
  line = $0
  # Strip inline comments
  sub(/#.*$/, "", line)
  # Strip environment markers (everything after ;)
  sub(/;.*$/, "", line)
  # Strip whitespace
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
  if (line == "") next

  # Extract package name: everything before version specifier or extras
  pkg = line
  sub(/[=<>!~\[].*/, "", pkg)
  gsub(/[[:space:]]/, "", pkg)

  # Extract version: everything after package name
  ver = line
  sub(/^[^=<>!~\[]+/, "", ver)
  sub(/\[[^\]]*\]/, "", ver)  # strip extras brackets

  if (pkg != "") {
    dep_count++
    dep_names[dep_count] = pkg
    dep_versions[dep_count] = ver
  }
}

END {
  printf "@diagram|id:%s-deps|type:flow|purpose:requirements.txt dependency graph for %s\n", project, project
  printf "@group|id:deps|label:Dependencies\n"
  printf "@node|id:%s|label:%s|shape:box\n", project, project

  for (i = 1; i <= dep_count; i++) {
    # Slugify package name (lowercase, hyphens only)
    slug = dep_names[i]
    gsub(/[^a-zA-Z0-9-]/, "-", slug)
    # Build label
    label = dep_names[i]
    if (dep_versions[i] != "") label = label dep_versions[i]
    # Escape pipes
    gsub(/\|/, "\\|", label)
    printf "@node|id:%s|label:%s|group:deps|shape:box\n", slug, label
    printf "@edge|from:%s|to:%s|label:depends|type:data\n", project, slug
  }
}
' "$INPUT_FILE")

if [[ "$DRY_RUN" == true ]]; then
  echo "$output"
  exit 0
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  outfile="${OUTPUT_DIR}/${project_slug}.pip.gdld"
  _tmp_out=$(mktemp "$(dirname "$outfile")/.gdl-atomic.XXXXXX")
  echo "$output" > "$_tmp_out" || { rm -f "$_tmp_out"; exit 1; }
  mv "$_tmp_out" "$outfile"
  echo "Wrote: $outfile" >&2
else
  echo "$output"
fi
