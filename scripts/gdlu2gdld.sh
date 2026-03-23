#!/usr/bin/env bash
# gdlu2gdld.sh - Convert GDLU unstructured index to GDLD diagram format
# Usage: gdlu2gdld.sh <file.gdlu> [--id=DIAGRAM_ID]
set -euo pipefail

file="${1:-}"
diagram_id="gdlu-overview"

for arg in "$@"; do
  case "$arg" in
    --id=*) diagram_id="${arg#--id=}" ;;
  esac
done

if [[ -z "$file" || ! -f "$file" ]]; then
  echo "Usage: gdlu2gdld.sh <file.gdlu> [--id=DIAGRAM_ID]" >&2
  exit 1
fi

# Helper: extract field from key-value record
_get() {
  local record="$1" key="$2"
  echo "$record" | sed 's/\\|/@@P@@/g' | awk -F'|' -v key="$key" '
  {
    for (i=1; i<=NF; i++) {
      idx = index($i, ":")
      if (idx > 0) {
        k = substr($i, 1, idx-1); v = substr($i, idx+1)
        gsub(/^@/, "", k)
        if (k == key) { gsub(/@@P@@/, "|", v); gsub(/\\:/, ":", v); print v; exit }
      }
    }
  }'
}

sanitize_id() {
  echo "$1" | sed 's/[^a-zA-Z0-9_-]/-/g'
}

# Emit diagram header
echo "@diagram|id:$diagram_id|type:flow|purpose:GDLU document index visualization"

# Collect content types for grouping
seen_groups=""

# Pass 1: sources -> nodes (skip stale/archived)
while IFS= read -r line; do
  case "$line" in
    @source*) ;;
    *) continue ;;
  esac
  local_status=$(_get "$line" "status")
  case "$local_status" in
    stale|archived) continue ;;
  esac

  id=$(_get "$line" "id")
  summary=$(_get "$line" "summary")
  content_type=$(_get "$line" "type")
  fmt=$(_get "$line" "format")

  # Create group for content type if not seen
  group_id=$(sanitize_id "$content_type")
  case "$seen_groups" in
    *"|$group_id|"*) ;;
    *)
      seen_groups="$seen_groups|$group_id|"
      echo "@group|id:$group_id|label:$content_type"
      ;;
  esac

  shape="box"
  case "$fmt" in
    png|figma) shape="hexagon" ;;
    mp3|mp4) shape="stadium" ;;
  esac

  echo "@node|id:$id|label:$summary|shape:$shape|group:$group_id"
done < "$file"

# Pass 2: extracts -> edges (connect source to key)
seen_edges=""
seen_nodes=""
while IFS= read -r line; do
  case "$line" in
    @extract*) ;;
    *) continue ;;
  esac
  local_status=$(_get "$line" "status")
  case "$local_status" in
    superseded|withdrawn) continue ;;
  esac

  source=$(_get "$line" "source")
  kind=$(_get "$line" "kind")
  key=$(_get "$line" "key")

  # Create a node for the key if not a source ID
  key_node=$(sanitize_id "$key")
  edge_key="$source->$key_node"
  case "$seen_edges" in
    *"|$edge_key|"*) continue ;;
  esac
  seen_edges="$seen_edges|$edge_key|"

  # Only emit key node once even if referenced from multiple sources
  case "$seen_nodes" in
    *"|$key_node|"*) ;;
    *)
      seen_nodes="$seen_nodes|$key_node|"
      echo "@node|id:$key_node|label:$key|shape:diamond"
      ;;
  esac
  echo "@edge|from:$source|to:$key_node|label:$kind"
done < "$file"
