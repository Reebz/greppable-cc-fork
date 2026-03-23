#!/usr/bin/env bash
# GDLM Tools - Bash helpers for memory graph traversal
# Source this file: source scripts/gdlm-tools.sh

GDLM_PATH="${GDLM_PATH:-memory/active}"

# 1. gdlm_get - Fetch a memory by ID
gdlm_get() {
  local id=$1
  if [[ -z "$id" ]]; then
    echo "Usage: gdlm_get <memory-id>" >&2
    return 1
  fi
  grep "id:$id" "$GDLM_PATH"/*.gdlm 2>/dev/null
}

# 2. gdlm_outbound - What does X relate to? (optionally filtered by type)
gdlm_outbound() {
  local id=$1
  local type=$2
  if [[ -z "$id" ]]; then
    echo "Usage: gdlm_outbound <memory-id> [relationship-type]" >&2
    return 1
  fi
  local relates
  relates=$(grep "id:$id" "$GDLM_PATH"/*.gdlm 2>/dev/null | grep -o 'relates:[^|]*' | sed 's/^relates://' | tr ',' '\n')
  if [[ -n "$type" ]]; then
    echo "$relates" | grep "^${type}~" | sed "s/^${type}~//"
  else
    echo "$relates" | sed 's/^[^~]*~//'
  fi
}

# 3. gdlm_inbound - What points TO X? (reverse lookup, optionally filtered by type)
gdlm_inbound() {
  local id=$1
  local type=$2
  if [[ -z "$id" ]]; then
    echo "Usage: gdlm_inbound <memory-id> [relationship-type]" >&2
    return 1
  fi
  if [[ -n "$type" ]]; then
    grep "relates:.*${type}~${id}" "$GDLM_PATH"/*.gdlm 2>/dev/null
  else
    grep "relates:.*${id}" "$GDLM_PATH"/*.gdlm 2>/dev/null
  fi
}

# 4. gdlm_follow - Follow relationship chain N hops
gdlm_follow() {
  local id=$1
  local type=$2
  local depth=${3:-2}
  if [[ -z "$id" ]]; then
    echo "Usage: gdlm_follow <memory-id> <relationship-type> [depth=2]" >&2
    return 1
  fi
  local current="$id"
  for ((i=0; i<depth; i++)); do
    local next
    next=$(gdlm_outbound "$current" "$type" | head -1)
    [[ -z "$next" ]] && break
    gdlm_get "$next"
    current="$next"
  done
}

# 5. gdlm_chain - Follow until end (e.g., supersession chain to find current version)
gdlm_chain() {
  local id=$1
  local type=${2:-supersedes}
  if [[ -z "$id" ]]; then
    echo "Usage: gdlm_chain <memory-id> [relationship-type=supersedes]" >&2
    return 1
  fi
  local current="$id"
  while true; do
    local next
    next=$(gdlm_outbound "$current" "$type" | head -1)
    [[ -z "$next" ]] && break
    gdlm_get "$next"
    current="$next"
  done
}

# 6. gdlm_filter - Filter by type and/or keyword
gdlm_filter() {
  local memtype=$1
  local keyword=$2
  if [[ -z "$memtype" ]]; then
    echo "Usage: gdlm_filter <memory-type> [keyword]" >&2
    return 1
  fi
  if [[ -n "$keyword" ]]; then
    grep "type:$memtype" "$GDLM_PATH"/*.gdlm 2>/dev/null | grep "$keyword"
  else
    grep "type:$memtype" "$GDLM_PATH"/*.gdlm 2>/dev/null
  fi
}

echo "GDLM tools loaded. Available: gdlm_get, gdlm_outbound, gdlm_inbound, gdlm_follow, gdlm_chain, gdlm_filter"
