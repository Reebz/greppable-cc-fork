#!/usr/bin/env bash
# compose2gdld.sh — Convert Docker Compose service topology to GDLD diagram
# Usage: compose2gdld.sh <docker-compose.yml> [--output=DIR] [--dry-run]
#
# Pure awk parser (no yq dependency). Extracts services, images, build contexts,
# and depends_on relationships from Docker Compose files.
#
# Known limitations:
# - Requires space-based indentation (YAML spec forbids tabs, but we don't validate)
# - YAML anchors/aliases (&/*) not resolved — services using <<: *alias won't inherit deps
# - Multi-line string values (|, >) not parsed
# - Only processes a single file (no docker-compose.override.yml merging)
# - Supports docker-compose.yml, docker-compose.yaml, compose.yml, compose.yaml
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
compose2gdld.sh — Convert Docker Compose service topology to GDLD diagram

Usage: compose2gdld.sh <docker-compose.yml> [--output=DIR] [--dry-run]

Parses a Docker Compose file using awk and generates a GDLD topology
diagram with nodes for each service and edges for depends_on relationships.

OPTIONS:
  --output=DIR   Write output to DIR/<basename>.compose.gdld (default: stdout)
  --dry-run      Show what would be generated without writing
  --help         Show this help

FEATURES:
  - Extracts service definitions with image or build context
  - Handles both list-style and map-style depends_on
  - No yq dependency — pure awk parser
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
  echo "Usage: compose2gdld.sh <docker-compose.yml> [--output=DIR] [--dry-run]" >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: file not found: $INPUT_FILE" >&2
  exit 1
fi

basename_no_ext=$(basename "$INPUT_FILE" | sed 's/\.[^.]*$//')

# Single-pass awk parser (BSD awk compatible — no gawk extensions).
# State machine:
#   State 0: Looking for "services:" at indent 0
#   State 1: Inside services block — 2-space indented keys are service names
#   State 2: Inside a service — reading image/build/ports/depends_on
#   State 3: Inside depends_on — handle both list and map syntax
output=$(awk '
BEGIN {
  svc_count = 0
  edge_count = 0
  in_services = 0
  current_service = ""
  in_depends_on = 0
  depends_indent = 0
  service_indent = 2
}

# Skip comments and blank lines
/^[[:space:]]*#/ { next }
/^[[:space:]]*$/ { next }

# Compute indent level
{
  line = $0
  indent = 0
  while (substr(line, indent + 1, 1) == " ") indent++
}

# Top-level "services:" key
/^services:/ {
  in_services = 1
  current_service = ""
  in_depends_on = 0
  next
}

# Top-level keys other than services — exit services block
in_services && indent == 0 && /^[a-zA-Z]/ {
  in_services = 0
  current_service = ""
  in_depends_on = 0
  next
}

# Inside services block
in_services {
  # Service name: exactly 2-space indented key ending with ":"
  if (indent == 2 && /^  [a-zA-Z_][a-zA-Z0-9_-]*:/) {
    # Extract service name: strip leading spaces, strip trailing ":"
    sname = line
    sub(/^[[:space:]]+/, "", sname)
    sub(/:.*/, "", sname)
    current_service = sname
    in_depends_on = 0
    svc_count++
    svc_names[svc_count] = current_service
    svc_images[current_service] = ""
    svc_builds[current_service] = ""
    next
  }

  # Inside a service definition (indent > 2)
  if (current_service != "" && indent > service_indent) {

    # Exit depends_on if indent drops below depends_indent
    if (in_depends_on && indent < depends_indent) {
      in_depends_on = 0
    }

    # image: field
    if (!in_depends_on && /^[[:space:]]*image:/) {
      val = line
      sub(/^[[:space:]]*image:[[:space:]]*/, "", val)
      sub(/#.*$/, "", val)        # strip inline comments
      gsub(/^[[:space:]]+/, "", val)
      gsub(/[[:space:]]+$/, "", val)
      gsub(/^["'"'"']|["'"'"']$/, "", val)  # strip quotes
      if (val != "") svc_images[current_service] = val
      next
    }

    # build: field (short form with path value)
    if (!in_depends_on && /^[[:space:]]*build:[[:space:]]*[^[:space:]]/) {
      svc_builds[current_service] = "yes"
      next
    }

    # build: field (long form — "build:" alone on line)
    if (!in_depends_on && /^[[:space:]]*build:[[:space:]]*$/) {
      svc_builds[current_service] = "yes"
      next
    }

    # depends_on: field (enter depends_on block)
    if (!in_depends_on && /^[[:space:]]*depends_on:/) {
      in_depends_on = 1
      depends_indent = indent + 2
      next
    }

    # Inside depends_on block
    if (in_depends_on && indent >= depends_indent) {
      # List syntax: "      - servicename"
      if (/^[[:space:]]*-[[:space:]]/) {
        dep = line
        sub(/^[[:space:]]*-[[:space:]]+/, "", dep)
        sub(/[[:space:]]*$/, "", dep)
        if (dep != "") {
          edge_count++
          edge_from[edge_count] = current_service
          edge_to[edge_count] = dep
        }
        next
      }
      # Map syntax: "      servicename:" at depends_indent level
      if (indent == depends_indent && /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_-]*:/) {
        dep = line
        sub(/^[[:space:]]+/, "", dep)
        sub(/:.*/, "", dep)
        if (dep != "") {
          edge_count++
          edge_from[edge_count] = current_service
          edge_to[edge_count] = dep
        }
        next
      }
    }
  }

  # If indent drops back to service level or above, reset depends_on
  if (indent <= service_indent && current_service != "") {
    in_depends_on = 0
  }
}

END {
  printf "@diagram|id:%s-topology|type:flow|purpose:Docker Compose service topology\n", "'"$basename_no_ext"'"
  for (i = 1; i <= svc_count; i++) {
    name = svc_names[i]
    if (svc_images[name] != "") {
      label = name " (" svc_images[name] ")"
    } else if (svc_builds[name] != "") {
      label = name " [build]"
    } else {
      label = name
    }
    gsub(/\|/, "\\|", label)
    printf "@node|id:%s|label:%s|shape:box\n", name, label
  }
  for (i = 1; i <= edge_count; i++) {
    printf "@edge|from:%s|to:%s|label:depends_on|type:flow\n", edge_from[i], edge_to[i]
  }
}
' "$INPUT_FILE")

if [[ "$DRY_RUN" == true ]]; then
  echo "$output"
  exit 0
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  outfile="${OUTPUT_DIR}/${basename_no_ext}.compose.gdld"
  _tmp_out=$(mktemp "$(dirname "$outfile")/.gdl-atomic.XXXXXX")
  echo "$output" > "$_tmp_out" || { rm -f "$_tmp_out"; exit 1; }
  mv "$_tmp_out" "$outfile"
  echo "Wrote: $outfile" >&2
else
  echo "$output"
fi
