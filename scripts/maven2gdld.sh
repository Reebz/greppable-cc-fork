#!/usr/bin/env bash
# maven2gdld.sh — Parse Maven pom.xml into GDLD dependency diagram
# Usage: maven2gdld.sh <pom.xml> [--output=DIR] [--dry-run]
set -uo pipefail

TARGET_FILE=""
OUTPUT_DIR=""
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --output=*) OUTPUT_DIR="${arg#--output=}" ;;
    --dry-run) DRY_RUN=true ;;
    --help|-h)
      cat <<'USAGE'
maven2gdld.sh — Parse Maven pom.xml into GDLD dependency diagram

Usage: maven2gdld.sh <pom.xml> [--output=DIR] [--dry-run]

Parses Maven pom.xml and generates a GDLD dependency flow diagram.

OPTIONS:
  --output=DIR   Write output to DIR/<artifactId>.maven.gdld
  --dry-run      Show what would be generated without writing
  --help         Show this help
USAGE
      exit 0 ;;
    -*)
      echo "Unknown flag: $arg. Run with --help for usage." >&2; exit 1 ;;
    *)
      if [[ -z "$TARGET_FILE" ]]; then
        TARGET_FILE="$arg"
      else
        echo "Error: unexpected argument '$arg'" >&2; exit 1
      fi ;;
  esac
done

if [[ -z "$TARGET_FILE" ]]; then
  echo "Error: provide a pom.xml file" >&2
  echo "Usage: maven2gdld.sh <pom.xml> [--output=DIR] [--dry-run]" >&2
  exit 1
fi

if [[ ! -f "$TARGET_FILE" ]]; then
  echo "Error: file '$TARGET_FILE' does not exist" >&2
  exit 1
fi

OUTPUT=$(awk '
  function strip_tag(line,   val) {
    val = line
    gsub(/^[[:space:]]*<[^>]+>/, "", val)
    gsub(/<\/[^>]+>[[:space:]]*$/, "", val)
    gsub(/^[[:space:]]+/, "", val)
    gsub(/[[:space:]]+$/, "", val)
    return val
  }
  function slugify(s) {
    gsub(/[^a-zA-Z0-9_-]/, "-", s)
    return s
  }
  function escape_pipe(s) {
    gsub(/\|/, "\\|", s)
    return s
  }
  function capitalize(s) {
    return toupper(substr(s, 1, 1)) substr(s, 2)
  }

  BEGIN {
    in_dep_mgmt = 0; in_deps = 0; in_dep = 0
    in_comment = 0; in_build = 0; in_parent = 0
    project_group = ""; project_artifact = ""; project_version = ""
    dep_count = 0
  }

  # Strip XML comments
  /<!--/ { in_comment = 1 }
  /-->/ { in_comment = 0 }
  in_comment { next }

  # Track build and parent sections to avoid picking up wrong coords
  /<build>/ { in_build = 1 }
  /<\/build>/ { in_build = 0 }
  /<parent>/ { in_parent = 1 }
  /<\/parent>/ { in_parent = 0 }

  /<dependencyManagement>/ { in_dep_mgmt = 1; next }
  /<\/dependencyManagement>/ { in_dep_mgmt = 0; next }

  # Skip everything inside dependencyManagement
  in_dep_mgmt { next }

  # Only process <dependencies> outside of dependencyManagement and build
  /<dependencies>/ && !in_build { in_deps = 1; next }
  /<\/dependencies>/ { in_deps = 0; next }

  /<dependency>/ && in_deps { in_dep = 1; d_group=""; d_artifact=""; d_version=""; d_scope="compile"; next }
  /<\/dependency>/ && in_dep {
    in_dep = 0
    if (d_artifact != "") {
      dep_count++
      groups[d_scope] = 1
      dep_groups[dep_count] = d_scope
      dep_artifacts[dep_count] = d_artifact
      dep_labels[dep_count] = d_group ":" d_artifact
      dep_versions[dep_count] = d_version
    }
    next
  }

  in_dep && /<groupId>/ { d_group = strip_tag($0); next }
  in_dep && /<artifactId>/ { d_artifact = strip_tag($0); next }
  in_dep && /<version>/ { d_version = strip_tag($0); next }
  in_dep && /<scope>/ { d_scope = strip_tag($0); next }

  # Project coordinates (top-level, not inside dependency, build, or parent)
  !in_dep && !in_deps && !in_dep_mgmt && !in_build && !in_parent && /<groupId>/ && project_group == "" { project_group = strip_tag($0); next }
  !in_dep && !in_deps && !in_dep_mgmt && !in_build && !in_parent && /<artifactId>/ && project_artifact == "" { project_artifact = strip_tag($0); next }
  !in_dep && !in_deps && !in_dep_mgmt && !in_build && !in_parent && /<version>/ && project_version == "" { project_version = strip_tag($0); next }

  END {
    if (project_artifact == "") project_artifact = "project"
    printf "@diagram|id:%s-deps|type:flow|purpose:Maven dependency graph for %s\n", slugify(project_artifact), project_artifact

    # Groups
    for (g in groups) {
      printf "@group|id:%s|label:%s Dependencies\n", g, capitalize(g)
    }

    # Project node
    proj_label = project_artifact
    if (project_version != "") proj_label = proj_label "@" project_version
    printf "@node|id:%s|label:%s|shape:box\n", slugify(project_artifact), proj_label

    # Dependency nodes and edges
    for (i = 1; i <= dep_count; i++) {
      node_id = slugify(dep_artifacts[i])
      label = dep_labels[i]
      if (dep_versions[i] != "") label = label "@" dep_versions[i]
      label = escape_pipe(label)
      printf "@node|id:%s|label:%s|group:%s|shape:box\n", node_id, label, dep_groups[i]
      printf "@edge|from:%s|to:%s|label:%s-depends|type:data\n", slugify(project_artifact), node_id, dep_groups[i]
    }
  }
' "$TARGET_FILE")

if [[ -z "$OUTPUT" ]]; then
  echo "No dependencies found in $TARGET_FILE" >&2
  exit 0
fi

if [[ "$DRY_RUN" = true ]]; then
  printf '%s\n' "$OUTPUT"
elif [[ -z "$OUTPUT_DIR" ]]; then
  printf '%s\n' "$OUTPUT"
else
  mkdir -p "$OUTPUT_DIR"
  # Extract artifactId from the output for filename
  ARTIFACT_ID=$(echo "$OUTPUT" | grep '^@diagram' | sed 's/.*purpose:Maven dependency graph for //')
  OUT_FILE="$OUTPUT_DIR/${ARTIFACT_ID}.maven.gdld"
  _tmp_out=$(mktemp "$(dirname "$OUT_FILE")/.gdl-atomic.XXXXXX")
  printf '%s\n' "$OUTPUT" > "$_tmp_out" || { rm -f "$_tmp_out"; exit 1; }
  mv "$_tmp_out" "$OUT_FILE"
  echo "Wrote $(echo "$OUTPUT" | grep -c '^@') records to $OUT_FILE" >&2
fi
