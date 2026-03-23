#!/usr/bin/env bash
# cargo2gdld.sh — Convert Cargo.toml dependencies to GDLD diagram
# Usage: cargo2gdld.sh <Cargo.toml> [--output=DIR] [--dry-run]
# Pure awk parser — no cargo or Rust required.
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
cargo2gdld.sh — Convert Cargo.toml dependencies to GDLD diagram

Usage: cargo2gdld.sh <Cargo.toml> [--output=DIR] [--dry-run]

Parses a Cargo.toml file using awk and generates a GDLD dependency
flow diagram with nodes for each dependency and edges showing
dependency relationships.

OPTIONS:
  --output=DIR   Write output to DIR/<name>.cargo.gdld (default: stdout)
  --dry-run      Show what would be generated without writing
  --help         Show this help

FEATURES:
  - Extracts [dependencies], [dev-dependencies], [build-dependencies]
  - Handles both simple (name = "version") and table (name = { version = "..." }) syntax
  - Groups deps, dev-deps, and build-deps separately
  - Package name from [package] section
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
  echo "Usage: cargo2gdld.sh <Cargo.toml> [--output=DIR] [--dry-run]" >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: file not found: $INPUT_FILE" >&2
  exit 1
fi

output=$(awk '
BEGIN {
  section = ""
  project_name = ""
  project_version = ""
  dep_count = 0
}

# Section detection
/^\[package\]/ { section = "package"; next }
/^\[dependencies\]/ { section = "deps"; next }
/^\[dev-dependencies\]/ { section = "devdeps"; next }
/^\[build-dependencies\]/ { section = "builddeps"; next }
# Dotted subsection syntax: [dependencies.serde], [dev-dependencies.tokio], etc.
# Extract dep name from header, set section to "subsection" to skip inner keys
/^\[dependencies\./ {
  sub_name = $0; sub(/^\[dependencies\./, "", sub_name); sub(/\].*/, "", sub_name)
  dep_count++; dep_names[dep_count] = sub_name; dep_versions[dep_count] = ""; dep_sections[dep_count] = "deps"
  section = "subsection"; next
}
/^\[dev-dependencies\./ {
  sub_name = $0; sub(/^\[dev-dependencies\./, "", sub_name); sub(/\].*/, "", sub_name)
  dep_count++; dep_names[dep_count] = sub_name; dep_versions[dep_count] = ""; dep_sections[dep_count] = "devdeps"
  section = "subsection"; next
}
/^\[build-dependencies\./ {
  sub_name = $0; sub(/^\[build-dependencies\./, "", sub_name); sub(/\].*/, "", sub_name)
  dep_count++; dep_names[dep_count] = sub_name; dep_versions[dep_count] = ""; dep_sections[dep_count] = "builddeps"
  section = "subsection"; next
}
/^\[/ { section = "other"; next }

# Package name and version
section == "package" && /^name[[:space:]]*=/ {
  name = $0
  sub(/^name[[:space:]]*=[[:space:]]*"/, "", name)
  sub(/".*/, "", name)
  project_name = name
}
section == "package" && /^version[[:space:]]*=/ {
  ver = $0
  sub(/^version[[:space:]]*=[[:space:]]*"/, "", ver)
  sub(/".*/, "", ver)
  project_version = ver
}

# Skip blank lines, comments
/^[[:space:]]*$/ { next }
/^[[:space:]]*#/ { next }

# Inside a dotted subsection: capture version, skip everything else
section == "subsection" && /^version[[:space:]]*=/ {
  ver = $0
  if (match($0, /"[^"]*"/)) {
    ver = substr($0, RSTART+1, RLENGTH-2)
  } else {
    ver = ""
  }
  dep_versions[dep_count] = ver
  next
}
section == "subsection" { next }

# Simple dep: name = "version" (NO curly braces)
(section == "deps" || section == "devdeps" || section == "builddeps") && /^[a-zA-Z_]/ && !/\{/ {
  dep = $0
  sub(/[[:space:]]*=.*/, "", dep)
  ver = $0
  if (match($0, /"[^"]*"/)) {
    ver = substr($0, RSTART+1, RLENGTH-2)
  } else {
    ver = ""
  }
  dep_count++
  dep_names[dep_count] = dep
  dep_versions[dep_count] = ver
  dep_sections[dep_count] = section
  next
}

# Complex dep: name = { version = "..." ... }
(section == "deps" || section == "devdeps" || section == "builddeps") && /^[a-zA-Z_]/ && /\{/ {
  dep = $0
  sub(/[[:space:]]*=.*/, "", dep)
  ver = ""
  if (match($0, /version[[:space:]]*=[[:space:]]*"[^"]*"/)) {
    ver = substr($0, RSTART, RLENGTH)
    sub(/^version[[:space:]]*=[[:space:]]*"/, "", ver)
    sub(/"$/, "", ver)
  }
  dep_count++
  dep_names[dep_count] = dep
  dep_versions[dep_count] = ver
  dep_sections[dep_count] = section
  next
}

END {
  if (project_name == "") project_name = "unknown"
  if (project_version == "") project_version = "0.0.0"

  printf "@diagram|id:%s-deps|type:flow|purpose:Cargo.toml dependency graph for %s\n", project_name, project_name
  printf "@group|id:deps|label:Dependencies\n"
  printf "@group|id:devdeps|label:Dev Dependencies\n"
  printf "@group|id:builddeps|label:Build Dependencies\n"
  printf "@node|id:%s|label:%s@%s|shape:box\n", project_name, project_name, project_version

  for (i = 1; i <= dep_count; i++) {
    slug = dep_names[i]
    label = dep_names[i]
    if (dep_versions[i] != "") label = label "@" dep_versions[i]
    gsub(/\|/, "\\|", label)
    group = dep_sections[i]
    if (dep_sections[i] == "deps") edge_label = "depends"
    else if (dep_sections[i] == "devdeps") edge_label = "dev-depends"
    else edge_label = "build-depends"
    printf "@node|id:%s|label:%s|group:%s|shape:box\n", slug, label, group
    printf "@edge|from:%s|to:%s|label:%s|type:data\n", project_name, slug, edge_label
  }
}
' "$INPUT_FILE")

if [[ "$DRY_RUN" == true ]]; then
  echo "$output"
  exit 0
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  # Extract project name for filename
  proj=$(awk '/^\[package\]/,/^\[/ { if (/^name/) { sub(/^name[[:space:]]*=[[:space:]]*"/, ""); sub(/".*/, ""); print; exit } }' "$INPUT_FILE")
  if [[ -z "$proj" ]]; then
    proj=$(basename "$INPUT_FILE" .toml | sed 's/^sample-//')
  fi
  outfile="${OUTPUT_DIR}/${proj}.cargo.gdld"
  _tmp_out=$(mktemp "$(dirname "$outfile")/.gdl-atomic.XXXXXX")
  echo "$output" > "$_tmp_out" || { rm -f "$_tmp_out"; exit 1; }
  mv "$_tmp_out" "$outfile"
  echo "Wrote: $outfile" >&2
else
  echo "$output"
fi
