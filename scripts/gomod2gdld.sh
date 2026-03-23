#!/usr/bin/env bash
# gomod2gdld.sh — Convert go.mod dependencies to GDLD diagram
# Usage: gomod2gdld.sh <go.mod> [--output=DIR] [--dry-run]
# Pure awk parser — no external dependencies.
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
gomod2gdld.sh — Convert go.mod dependencies to GDLD diagram

Usage: gomod2gdld.sh <go.mod> [--output=DIR] [--dry-run]

Parses a go.mod file using awk and generates a GDLD dependency
flow diagram with nodes for each dependency and edges showing
dependency relationships.

OPTIONS:
  --output=DIR   Write output to DIR/<module>.gomod.gdld (default: stdout)
  --dry-run      Show what would be generated without writing
  --help         Show this help

FEATURES:
  - Extracts direct and indirect dependencies
  - Groups direct vs indirect deps separately
  - Handles both single-line and grouped require blocks
  - Uses slugified full module path as node ID (/ replaced with -, dots preserved to avoid collisions)
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
  echo "Usage: gomod2gdld.sh <go.mod> [--output=DIR] [--dry-run]" >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: file not found: $INPUT_FILE" >&2
  exit 1
fi

output=$(awk '
BEGIN {
  module_name = ""
  dep_count = 0
  in_require = 0
}

# Module declaration
/^module / {
  module_name = $2
}

# Single-line require
/^require [^(]/ {
  dep_count++
  dep_paths[dep_count] = $2
  dep_versions[dep_count] = $3
  dep_indirect[dep_count] = ($0 ~ /\/\/ indirect/) ? 1 : 0
  next
}

# Start of grouped require block
/^require \(/ {
  in_require = 1
  next
}

# End of grouped require block
in_require && /^\)/ {
  in_require = 0
  next
}

# Inside grouped require block
in_require && NF >= 2 {
  dep_count++
  dep_paths[dep_count] = $1
  dep_versions[dep_count] = $2
  dep_indirect[dep_count] = ($0 ~ /\/\/ indirect/) ? 1 : 0
}

END {
  if (module_name == "") module_name = "unknown"
  n = split(module_name, parts, "/")
  module_short = parts[n]

  printf "@diagram|id:%s-deps|type:flow|purpose:go.mod dependency graph for %s\n", module_short, module_name
  printf "@group|id:direct|label:Direct Dependencies\n"
  printf "@group|id:indirect|label:Indirect Dependencies\n"
  printf "@node|id:%s|label:%s|shape:box\n", module_short, module_short

  for (i = 1; i <= dep_count; i++) {
    # Use slugified full path as ID to avoid collisions
    # e.g., golang.org/x/crypto → golang.org-x-crypto
    slug = dep_paths[i]
    gsub(/\//, "-", slug)
    # Extract short name for label readability
    n = split(dep_paths[i], segs, "/")
    short = segs[n]
    # Escape pipes in label
    label = short "@" dep_versions[i]
    gsub(/\|/, "\\|", label)
    group = dep_indirect[i] ? "indirect" : "direct"
    edge_label = dep_indirect[i] ? "indirect" : "depends"
    printf "@node|id:%s|label:%s|group:%s|shape:box\n", slug, label, group
    printf "@edge|from:%s|to:%s|label:%s|type:data\n", module_short, slug, edge_label
  }
}
' "$INPUT_FILE")

if [[ "$DRY_RUN" == true ]]; then
  echo "$output"
  exit 0
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  # Extract module short name directly from go.mod for robust filename
  module_short=$(awk '/^module / { n=split($2,p,"/"); print p[n]; exit }' "$INPUT_FILE")
  if [[ -z "$module_short" ]]; then
    module_short="unknown"
  fi
  outfile="${OUTPUT_DIR}/${module_short}.gomod.gdld"
  _tmp_out=$(mktemp "$(dirname "$outfile")/.gdl-atomic.XXXXXX")
  echo "$output" > "$_tmp_out" || { rm -f "$_tmp_out"; exit 1; }
  mv "$_tmp_out" "$outfile"
  echo "Wrote: $outfile" >&2
else
  echo "$output"
fi
