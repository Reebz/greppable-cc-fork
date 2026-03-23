#!/usr/bin/env bash
# npm2gdld.sh — Convert package.json dependencies to GDLD diagram
# Usage: npm2gdld.sh <package.json> [--output=DIR] [--dry-run]
# Requires: jq
set -uo pipefail

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed. Install with: brew install jq" >&2
  exit 1
fi

INPUT_FILE=""
OUTPUT_DIR=""
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --output=*) OUTPUT_DIR="${arg#--output=}" ;;
    --dry-run) DRY_RUN=true ;;
    --help|-h)
      cat <<'USAGE'
npm2gdld.sh — Convert package.json dependencies to GDLD diagram

Usage: npm2gdld.sh <package.json> [--output=DIR] [--dry-run]

Parses a package.json file using jq and generates a GDLD dependency
flow diagram with nodes for each dependency and edges showing
dependency relationships.

OPTIONS:
  --output=DIR   Write output to DIR/<name>.npm.gdld (default: stdout)
  --dry-run      Show what would be generated without writing
  --help         Show this help

FEATURES:
  - Extracts dependencies and devDependencies
  - Slugifies scoped package names (@scope/pkg → scope-pkg)
  - Groups deps and devDeps separately
  - Generates @diagram, @group, @node, @edge records
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
  echo "Usage: npm2gdld.sh <package.json> [--output=DIR] [--dry-run]" >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: file not found: $INPUT_FILE" >&2
  exit 1
fi

# Validate JSON
if ! jq empty "$INPUT_FILE" 2>/dev/null; then
  echo "Error: invalid JSON in $INPUT_FILE" >&2
  exit 1
fi

# Slugify: strip leading @, replace / with -, lowercase
slugify() {
  echo "$1" | sed 's/^@//' | tr '/' '-' | tr '[:upper:]' '[:lower:]'
}

# Escape pipe and colon in GDLD field values
escape_gdld() {
  echo "$1" | sed 's/|/\\|/g'
}

# Read project name (fallback to directory basename)
project_name=$(jq -r '.name // empty' "$INPUT_FILE")
if [[ -z "$project_name" ]]; then
  project_name=$(basename "$(dirname "$INPUT_FILE")")
fi
project_slug=$(slugify "$project_name")
project_version=$(jq -r '.version // "0.0.0"' "$INPUT_FILE")

# Track emitted node IDs to avoid duplicates (package in both deps and devDeps)
seen_nodes=""

# Build output
output=""
output+="@diagram|id:${project_slug}-deps|type:flow|purpose:npm dependency graph for ${project_name}"$'\n'
output+="@group|id:deps|label:Dependencies"$'\n'
output+="@group|id:devdeps|label:Dev Dependencies"$'\n'
output+="@node|id:${project_slug}|label:$(escape_gdld "${project_name}@${project_version}")|shape:box"$'\n'
seen_nodes=" ${project_slug} "

# Dependencies
deps=$(jq -r '.dependencies // {} | to_entries[] | "\(.key)\t\(.value)"' "$INPUT_FILE" 2>/dev/null || true)
if [[ -n "$deps" ]]; then
  while IFS=$'\t' read -r dep version; do
    dep_slug=$(slugify "$dep")
    dep_label=$(escape_gdld "${dep}@${version}")
    output+="@node|id:${dep_slug}|label:${dep_label}|group:deps|shape:box"$'\n'
    output+="@edge|from:${project_slug}|to:${dep_slug}|label:depends|type:data"$'\n'
    seen_nodes+="${dep_slug} "
  done <<< "$deps"
fi

# DevDependencies (skip node if already emitted as a dependency)
devdeps=$(jq -r '.devDependencies // {} | to_entries[] | "\(.key)\t\(.value)"' "$INPUT_FILE" 2>/dev/null || true)
if [[ -n "$devdeps" ]]; then
  while IFS=$'\t' read -r dep version; do
    dep_slug=$(slugify "$dep")
    dep_label=$(escape_gdld "${dep}@${version}")
    if [[ "$seen_nodes" != *" ${dep_slug} "* ]]; then
      output+="@node|id:${dep_slug}|label:${dep_label}|group:devdeps|shape:box"$'\n'
    fi
    output+="@edge|from:${project_slug}|to:${dep_slug}|label:dev-depends|type:data"$'\n'
  done <<< "$devdeps"
fi

# Remove trailing newline
output="${output%$'\n'}"

if [[ "$DRY_RUN" == true ]]; then
  echo "$output"
  exit 0
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  outfile="${OUTPUT_DIR}/${project_slug}.npm.gdld"
  _tmp_out=$(mktemp "$(dirname "$outfile")/.gdl-atomic.XXXXXX")
  echo "$output" > "$_tmp_out" || { rm -f "$_tmp_out"; exit 1; }
  mv "$_tmp_out" "$outfile"
  echo "Wrote: $outfile" >&2
else
  echo "$output"
fi
