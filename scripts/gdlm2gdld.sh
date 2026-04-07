#!/usr/bin/env bash
# gdlm2gdld.sh - Convert GDLM memory records to GDLD diagram format
# Usage: gdlm2gdld.sh <file.gdlm> [--id=ID] [--type=TYPE] [--since=DATE] [--min-connections=N] [--anchors-only] [--output=FILE]
set -euo pipefail

file=""
diagram_id=""
filter_type=""
filter_since=""
min_connections=0
anchors_only=false
output_file=""

for arg in "$@"; do
  case "$arg" in
    --id=*) diagram_id="${arg#--id=}" ;;
    --type=*) filter_type="${arg#--type=}" ;;
    --since=*) filter_since="${arg#--since=}" ;;
    --min-connections=*) min_connections="${arg#--min-connections=}" ;;
    --anchors-only) anchors_only=true ;;
    --output=*) output_file="${arg#--output=}" ;;
    *) [[ -z "$file" ]] && file="$arg" ;;
  esac
done

if [[ -z "$file" ]]; then
  echo "Usage: gdlm2gdld.sh <file.gdlm> [--id=ID] [--type=TYPE] [--since=DATE] [--min-connections=N] [--anchors-only] [--output=FILE]" >&2
  exit 1
fi

if [[ "$file" != "-" && ! -f "$file" ]]; then
  echo "Error: File not found: $file. Check path or run: ls *.gdlm" >&2
  exit 1
fi

# Validate --min-connections is numeric
case "$min_connections" in
  *[!0-9]*) echo "Error: --min-connections must be a non-negative integer" >&2; exit 1 ;;
esac

# Default diagram ID from filename
if [[ -z "$diagram_id" ]]; then
  if [[ "$file" == "-" ]]; then
    diagram_id="memory-graph"
  else
    diagram_id=$(basename "$file" .gdlm | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  fi
fi

# Read input
input=$(cat "$file")

# Helper: extract field value from @memory|key:value record
_get() {
  local record="$1" key="$2"
  echo "$record" | sed 's/\\|/@@P@@/g' | awk -F'|' -v key="$key" '
  {
    for (i=1; i<=NF; i++) {
      idx = index($i, ":")
      if (idx > 0) {
        k = substr($i, 1, idx-1); v = substr($i, idx+1)
        gsub(/^@[a-z]*/, "", k)
        if (k == key) { gsub(/@@P@@/, "|", v); print v; exit }
      }
    }
  }'
}

# Helper: look up subject by memory ID from tmpmap (literal match)
_lookup_subject() {
  grep -F "$1|" "$tmpmap" 2>/dev/null | head -1 | cut -d'|' -f2 || true
}

sanitize_id() {
  echo "$1" | sed 's/[^a-zA-Z0-9_-]/-/g'
}

capitalize_label() {
  echo "$1" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1'
}

# --- Collect anchors for grouping (deduplicated) ---
anchors=""
seen_anchors=""
while IFS= read -r line; do
  case "$line" in
    @anchor*) ;;
    *) continue ;;
  esac
  concept=$(_get "$line" "concept")
  [[ -z "$concept" ]] && continue
  case "$seen_anchors" in
    *";${concept};"*) continue ;;
  esac
  seen_anchors="${seen_anchors};${concept};"
  anchors="${anchors}${concept}"$'\n'
done <<< "$input"

# --- Build anchor set from memory records' anchor: fields ---
# Used to validate anchor-name relates targets (only link to anchors that have content)
anchor_set=""
while IFS= read -r line; do
  case "$line" in
    @memory*) ;;
    *) continue ;;
  esac
  mem_anchor=$(_get "$line" "anchor")
  [[ -z "$mem_anchor" ]] && continue
  case "$anchor_set" in
    *";${mem_anchor};"*) continue ;;
  esac
  anchor_set="${anchor_set};${mem_anchor};"
done <<< "$input"

# --- Build id→subject mapping from ALL memories (unfiltered) ---
# This allows relates: lookups to resolve targets even when filters exclude them
tmpmap=$(mktemp "${TMPDIR:-/tmp}/gdlm2gdld-map.XXXXXX")
trap 'rm -f "$tmpmap" "${_gdlm2gdld_tmpout:-}" "${tmpout:-}"' EXIT

while IFS= read -r line; do
  case "$line" in
    @memory*) ;;
    *) continue ;;
  esac
  mem_id=$(_get "$line" "id")
  mem_subject=$(_get "$line" "subject")
  echo "${mem_id}|${mem_subject}" >> "$tmpmap"
done <<< "$input"

# --- Collect filtered memories ---
filtered_memories=""
while IFS= read -r line; do
  case "$line" in
    @memory*) ;;
    *) continue ;;
  esac

  # Skip deleted records
  mem_status=$(_get "$line" "status")
  [[ "$mem_status" == "deleted" ]] && continue

  # Apply --type filter
  if [[ -n "$filter_type" ]]; then
    mem_type=$(_get "$line" "type")
    [[ "$mem_type" != "$filter_type" ]] && continue
  fi

  # Apply --since filter (assumes ISO 8601 UTC format)
  if [[ -n "$filter_since" ]]; then
    mem_ts=$(_get "$line" "ts")
    [[ "$mem_ts" < "$filter_since" ]] && continue
  fi

  filtered_memories="${filtered_memories}${line}"$'\n'
done <<< "$input"

# If --output specified, redirect all output to a temp file for atomic write
if [[ -n "$output_file" ]]; then
  mkdir -p "$(dirname "$output_file")"
  _gdlm2gdld_tmpout=$(mktemp "${output_file}.tmp.XXXXXX")
  exec 3>&1 1>"$_gdlm2gdld_tmpout"
fi

# --- Anchors-only mode ---
if [[ "$anchors_only" == true ]]; then
  echo "@diagram|id:${diagram_id}|type:flow|purpose:GDLM anchor-level knowledge graph"

  # Emit anchor nodes
  while IFS= read -r concept; do
    [[ -z "$concept" ]] && continue
    label=$(capitalize_label "$concept")
    echo "@node|id:${concept}|label:${label}|shape:box"
  done <<< "$anchors"

  # Find cross-anchor edges from relates: fields
  seen_edges=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    src_anchor=$(_get "$line" "anchor")
    [[ -z "$src_anchor" ]] && continue

    relates=$(_get "$line" "relates")
    [[ -z "$relates" ]] && continue

    # Process each relates entry
    while IFS= read -r rel_entry; do
      rel_entry=$(echo "$rel_entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$rel_entry" ]] && continue
      # Parse type~ID or bare ID
      if [[ "$rel_entry" == *"~"* ]]; then
        rel_type="${rel_entry%%~*}"
        rel_id="${rel_entry#*~}"
      else
        rel_type="related"
        rel_id="$rel_entry"
      fi

      # Dual-path lookup: memory ID or anchor concept name
      tgt_anchor=""
      if [[ "$rel_id" == M-* ]]; then
        # Memory ID path: look up target's subject, then find its anchor
        tgt_subject=$(_lookup_subject "$rel_id")
        [[ -z "$tgt_subject" ]] && continue

        # Find target's anchor by searching filtered_memories
        while IFS= read -r tgt_line; do
          [[ -z "$tgt_line" ]] && continue
          tgt_mem_id=$(_get "$tgt_line" "id")
          if [[ "$tgt_mem_id" == "$rel_id" ]]; then
            tgt_anchor=$(_get "$tgt_line" "anchor")
            break
          fi
        done <<< "$filtered_memories"
      else
        # Anchor concept name path: treat rel_id as anchor name directly
        # Only if the anchor actually exists in the anchor set
        case "$anchor_set" in
          *";${rel_id};"*) tgt_anchor="$rel_id" ;;
          *) continue ;;
        esac
      fi

      [[ -z "$tgt_anchor" || "$tgt_anchor" == "$src_anchor" ]] && continue

      edge_key="${src_anchor}|${tgt_anchor}"
      case "$seen_edges" in
        *";${edge_key};"*) continue ;;
      esac
      seen_edges="${seen_edges};${edge_key};"
      echo "@edge|from:${src_anchor}|to:${tgt_anchor}|label:${rel_type}|type:flow"
    done <<< "$(echo "$relates" | tr ',' $'\n')"
  done <<< "$filtered_memories"

  # Finalize --output if specified
  if [[ -n "$output_file" ]]; then
    exec 1>&3 3>&-
    mv "$_gdlm2gdld_tmpout" "$output_file"
    echo "Wrote: $output_file" >&2
  fi

  exit 0
fi

# --- Standard mode: generate records ---
_emit() {
  echo "@diagram|id:${diagram_id}|type:flow|purpose:GDLM memory knowledge graph"

  # Emit anchor groups (already deduplicated during collection)
  while IFS= read -r concept; do
    [[ -z "$concept" ]] && continue
    label=$(capitalize_label "$concept")
    echo "@group|id:${concept}|label:${label}"
  done <<< "$anchors"

  # Emit subject nodes
  seen_nodes=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    subject=$(_get "$line" "subject")
    [[ -z "$subject" ]] && continue

    node_id=$(sanitize_id "$subject")

    # Deduplicate by sanitized subject
    case "$seen_nodes" in
      *";${node_id};"*) continue ;;
    esac
    seen_nodes="${seen_nodes};${node_id};"

    # Shape: diamond for decisions, box for everything else
    mem_type=$(_get "$line" "type")
    shape="box"
    if [[ "$mem_type" == "decision" ]]; then
      shape="diamond"
    fi

    # Group from anchor
    anchor=$(_get "$line" "anchor")
    if [[ -n "$anchor" ]]; then
      echo "@node|id:${node_id}|label:${subject}|group:${anchor}|shape:${shape}"
    else
      echo "@node|id:${node_id}|label:${subject}|shape:${shape}"
    fi
  done <<< "$filtered_memories"

  # Emit explicit relates edges
  seen_edges=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    relates=$(_get "$line" "relates")
    [[ -z "$relates" ]] && continue

    src_subject=$(_get "$line" "subject")
    src_id=$(sanitize_id "$src_subject")

    # Process each relates entry
    while IFS= read -r rel_entry; do
      rel_entry=$(echo "$rel_entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$rel_entry" ]] && continue
      # Parse type~ID or bare ID
      if [[ "$rel_entry" == *"~"* ]]; then
        rel_type="${rel_entry%%~*}"
        rel_id="${rel_entry#*~}"
      else
        rel_type="related"
        rel_id="$rel_entry"
      fi

      # Dual-path lookup: memory ID or anchor concept name
      if [[ "$rel_id" == M-* ]]; then
        # Memory ID path: look up target subject from id mapping
        tgt_subject=$(_lookup_subject "$rel_id")
        [[ -z "$tgt_subject" ]] && continue
        tgt_id=$(sanitize_id "$tgt_subject")
      else
        # Anchor concept name path: link to anchor concept node
        # Only if the anchor actually exists in the anchor set
        case "$anchor_set" in
          *";${rel_id};"*) tgt_id=$(sanitize_id "$rel_id") ;;
          *) continue ;;
        esac
      fi

      # Deduplicate
      edge_key="${src_id}|${tgt_id}|${rel_type}"
      case "$seen_edges" in
        *";${edge_key};"*) continue ;;
      esac
      seen_edges="${seen_edges};${edge_key};"

      echo "@edge|from:${src_id}|to:${tgt_id}|label:${rel_type}|type:flow"
    done <<< "$(echo "$relates" | tr ',' $'\n')"
  done <<< "$filtered_memories"
}

# --- Apply min-connections filter or emit directly ---
if [[ "$min_connections" -gt 0 ]]; then
  tmpout=$(mktemp "${TMPDIR:-/tmp}/gdlm2gdld-out.XXXXXX")
  _emit > "$tmpout"

  # Count connections per node (from + to appearances in @edge records)
  connected_nodes=""
  while IFS= read -r edge_line; do
    [[ -z "$edge_line" ]] && continue
    from_id=$(echo "$edge_line" | sed 's/\\|/@@P@@/g' | awk -F'|' '{
      for (i=1; i<=NF; i++) { if (index($i,"from:") == 1) { v=substr($i,6); gsub(/@@P@@/, "|", v); print v; exit } }
    }')
    to_id=$(echo "$edge_line" | sed 's/\\|/@@P@@/g' | awk -F'|' '{
      for (i=1; i<=NF; i++) { if (index($i,"to:") == 1) { v=substr($i,4); gsub(/@@P@@/, "|", v); print v; exit } }
    }')
    connected_nodes="${connected_nodes}${from_id}"$'\n'"${to_id}"$'\n'
  done <<< "$(grep "^@edge" "$tmpout" || true)"

  # Build set of nodes meeting threshold
  kept_nodes=""
  while IFS= read -r node_line; do
    [[ -z "$node_line" ]] && continue
    node_id=$(echo "$node_line" | sed 's/\\|/@@P@@/g' | awk -F'|' '{
      for (i=1; i<=NF; i++) { if (index($i,"id:") == 1) { v=substr($i,4); gsub(/@@P@@/, "|", v); print v; exit } }
    }')
    count=$(echo "$connected_nodes" | grep -cF "$node_id" || true)
    if [[ "$count" -ge "$min_connections" ]]; then
      kept_nodes="${kept_nodes};${node_id};"
    fi
  done <<< "$(grep "^@node" "$tmpout" || true)"

  # Emit diagram header and groups unchanged
  grep -v "^@node\|^@edge" "$tmpout" || true

  # Emit kept nodes
  while IFS= read -r node_line; do
    [[ -z "$node_line" ]] && continue
    node_id=$(echo "$node_line" | sed 's/\\|/@@P@@/g' | awk -F'|' '{
      for (i=1; i<=NF; i++) { if (index($i,"id:") == 1) { v=substr($i,4); gsub(/@@P@@/, "|", v); print v; exit } }
    }')
    case "$kept_nodes" in
      *";${node_id};"*) echo "$node_line" ;;
    esac
  done <<< "$(grep "^@node" "$tmpout" || true)"

  # Emit edges where both endpoints are kept
  while IFS= read -r edge_line; do
    [[ -z "$edge_line" ]] && continue
    from_id=$(echo "$edge_line" | sed 's/\\|/@@P@@/g' | awk -F'|' '{
      for (i=1; i<=NF; i++) { if (index($i,"from:") == 1) { v=substr($i,6); gsub(/@@P@@/, "|", v); print v; exit } }
    }')
    to_id=$(echo "$edge_line" | sed 's/\\|/@@P@@/g' | awk -F'|' '{
      for (i=1; i<=NF; i++) { if (index($i,"to:") == 1) { v=substr($i,4); gsub(/@@P@@/, "|", v); print v; exit } }
    }')
    case "$kept_nodes" in
      *";${from_id};"*)
        case "$kept_nodes" in
          *";${to_id};"*) echo "$edge_line" ;;
        esac
        ;;
    esac
  done <<< "$(grep "^@edge" "$tmpout" || true)"

  rm -f "$tmpout"
else
  _emit
fi

# If --output specified, finalize atomic write
if [[ -n "$output_file" ]]; then
  exec 1>&3 3>&-
  mv "$_gdlm2gdld_tmpout" "$output_file"
  echo "Wrote: $output_file" >&2
fi
