#!/usr/bin/env bash
# GDLD Tools - Bash helpers for diagram querying and filtering
# Source this file: source scripts/gdld-tools.sh

# Internal helper: extract a field value from a GDLD record
# Lightweight copy from gdld2mermaid.sh, prefixed _ to avoid collision
# Usage: _gdld_get_field "record" "key"
_gdld_get_field() {
  local record="$1"
  local key="$2"
  echo "$record" | sed 's/\\|/@@PIPE@@/g' | awk -F'|' -v key="$key" '
  {
    for (i=1; i<=NF; i++) {
      idx = index($i, ":")
      if (idx > 0) {
        k = substr($i, 1, idx-1)
        v = substr($i, idx+1)
        gsub(/^@/, "", k)
        if (k == key) {
          gsub(/\\\\/, "@@BACKSLASH@@", v)
          gsub(/@@PIPE@@/, "|", v)
          gsub(/\\:/, ":", v)
          gsub(/@@BACKSLASH@@/, "\\", v)
          print v
          exit
        }
      }
    }
  }'
}

# 1. gdld_gotchas - List gotchas sorted by severity
# Usage: gdld_gotchas <file.gdld>
# Output: SEVERITY|ISSUE|DETAIL|FIX
gdld_gotchas() {
  local file="${1:-}"
  if [[ -z "$file" ]]; then
    echo "Usage: gdld_gotchas <file.gdld>" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdld" >&2
    return 1
  fi
  grep "^@gotcha|" "$file" | while IFS= read -r line; do
    local severity issue detail fix
    severity=$(_gdld_get_field "$line" "severity")
    issue=$(_gdld_get_field "$line" "issue")
    detail=$(_gdld_get_field "$line" "detail")
    fix=$(_gdld_get_field "$line" "fix")
    # Assign priority: critical=1, warning=2, info=3, empty=4
    local pri
    case "$severity" in
      critical) pri=1 ;;
      warning)  pri=2 ;;
      info)     pri=3 ;;
      *)        pri=4; severity="unset" ;;
    esac
    echo "${pri}|${severity}|${issue}|${detail}|${fix}"
  done | sort -t'|' -k1,1n | cut -d'|' -f2-
}

# 2. gdld_nodes - List node ID|LABEL pairs, optionally filtered by group
# Usage: gdld_nodes <file.gdld> [--group=GROUP]
gdld_nodes() {
  local file=""
  local group_filter=""
  # Parse args
  while [[ $# -gt 0 ]]; do
    case $1 in
      --group=*) group_filter="${1#*=}"; shift ;;
      --group)   group_filter="$2"; shift 2 ;;
      *)         file="$1"; shift ;;
    esac
  done
  if [[ -z "$file" ]]; then
    echo "Usage: gdld_nodes <file.gdld> [--group=GROUP]" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdld" >&2
    return 1
  fi
  grep "^@node|" "$file" | while IFS= read -r line; do
    local id label node_group
    id=$(_gdld_get_field "$line" "id")
    label=$(_gdld_get_field "$line" "label")
    node_group=$(_gdld_get_field "$line" "group")
    if [[ -n "$group_filter" ]]; then
      [[ "$node_group" == "$group_filter" ]] || continue
    fi
    echo "${id}|${label}"
  done
}

# 3. gdld_components - List NAME|FILE|DOES
# Usage: gdld_components <file.gdld>
gdld_components() {
  local file="${1:-}"
  if [[ -z "$file" ]]; then
    echo "Usage: gdld_components <file.gdld>" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdld" >&2
    return 1
  fi
  grep "^@component|" "$file" | while IFS= read -r line; do
    local name comp_file does
    name=$(_gdld_get_field "$line" "name")
    comp_file=$(_gdld_get_field "$line" "file")
    does=$(_gdld_get_field "$line" "does")
    echo "${name}|${comp_file}|${does}"
  done
}

# 4. gdld_subgraph - Extract group + its nodes + internal edges
# Usage: gdld_subgraph <file.gdld> <GROUP>
gdld_subgraph() {
  local file="${1:-}"
  local group="${2:-}"
  if [[ -z "$file" || -z "$group" ]]; then
    echo "Usage: gdld_subgraph <file.gdld> <GROUP>" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdld" >&2
    return 1
  fi
  # Output the group record itself
  grep "^@group|" "$file" | while IFS= read -r line; do
    local gid
    gid=$(_gdld_get_field "$line" "id")
    if [[ "$gid" == "$group" ]]; then
      echo "$line"
    fi
  done
  # Collect node IDs in this group (including child groups)
  local node_ids=()
  # Find child groups (direct and nested) with cycle detection
  local all_groups=("$group")
  local queue=("$group")
  while [[ ${#queue[@]} -gt 0 ]]; do
    local current="${queue[0]}"
    queue=("${queue[@]:1}")
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local gid parent
      gid=$(_gdld_get_field "$line" "id")
      parent=$(_gdld_get_field "$line" "parent")
      if [[ "$parent" == "$current" ]]; then
        # Cycle detection: skip if already visited
        local already_seen=false
        local ag
        for ag in "${all_groups[@]}"; do
          [[ "$ag" == "$gid" ]] && already_seen=true && break
        done
        if [[ "$already_seen" == "false" ]]; then
          all_groups+=("$gid")
          queue+=("$gid")
        fi
      fi
    done <<< "$(grep "^@group|" "$file" || true)"
  done
  # Collect nodes from all groups in the tree
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local node_group nid
    node_group=$(_gdld_get_field "$line" "group")
    nid=$(_gdld_get_field "$line" "id")
    local g
    for g in "${all_groups[@]}"; do
      if [[ "$node_group" == "$g" ]]; then
        echo "$line"
        node_ids+=("$nid")
        break
      fi
    done
  done <<< "$(grep "^@node|" "$file" || true)"
  # Output edges where both endpoints are in our node set
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local efrom eto
    efrom=$(_gdld_get_field "$line" "from")
    eto=$(_gdld_get_field "$line" "to")
    local from_match=false to_match=false
    local nid
    for nid in "${node_ids[@]}"; do
      [[ "$efrom" == "$nid" ]] && from_match=true
      [[ "$eto" == "$nid" ]] && to_match=true
    done
    if [[ "$from_match" == "true" && "$to_match" == "true" ]]; then
      echo "$line"
    fi
  done <<< "$(grep "^@edge|" "$file" || true)"
}

# 5. gdld_filter - Apply scenario, output filtered GDLD lines
# Usage: gdld_filter <file.gdld> --scenario=NAME
gdld_filter() {
  local file=""
  local scenario=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --scenario=*) scenario="${1#*=}"; shift ;;
      --scenario)   scenario="$2"; shift 2 ;;
      *)            file="$1"; shift ;;
    esac
  done
  if [[ -z "$file" || -z "$scenario" ]]; then
    echo "Usage: gdld_filter <file.gdld> --scenario=NAME" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdld" >&2
    return 1
  fi
  # Validate scenario exists
  if ! grep -q "^@scenario|" "$file" 2>/dev/null; then
    echo "Error: No scenarios defined in $file" >&2
    return 1
  fi
  local scenario_line
  scenario_line=$(grep "^@scenario|" "$file" | while IFS= read -r line; do
    local sid
    sid=$(_gdld_get_field "$line" "id")
    if [[ "$sid" == "$scenario" ]]; then
      echo "$line"
    fi
  done)
  if [[ -z "$scenario_line" ]]; then
    echo "Error: Unknown scenario: $scenario" >&2
    return 1
  fi
  # Build inheritance chain (child -> parent order), with cycle detection
  local chain=()
  local current="$scenario"
  local visited=",$scenario,"
  local max_depth=10
  local depth=0
  while [[ -n "$current" ]] && ((depth < max_depth)); do
    chain+=("$current")
    local parent_scenario=""
    parent_scenario=$(grep "^@scenario|" "$file" | while IFS= read -r sline; do
      local sid
      sid=$(_gdld_get_field "$sline" "id")
      if [[ "$sid" == "$current" ]]; then
        _gdld_get_field "$sline" "inherits"
      fi
    done)
    if [[ -n "$parent_scenario" && "$visited" == *",$parent_scenario,"* ]]; then
      echo "Error: Circular scenario inheritance detected: $parent_scenario" >&2
      return 1
    fi
    if [[ -n "$parent_scenario" ]]; then
      visited="$visited$parent_scenario,"
    fi
    current="$parent_scenario"
    depth=$((depth + 1))
  done
  # Collect excludes and overrides from chain (parent first, child last = child wins)
  local excludes=()
  local overrides=()
  local i
  for ((i=${#chain[@]}-1; i>=0; i--)); do
    local sc="${chain[$i]}"
    # Collect excludes for this scenario
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local esc
      esc=$(_gdld_get_field "$line" "scenario")
      if [[ "$esc" == "$sc" ]]; then
        local target
        target=$(_gdld_get_field "$line" "target")
        excludes+=("$target")
      fi
    done <<< "$(grep "^@exclude|" "$file" 2>/dev/null || true)"
    # Collect overrides (parent first, child appended last = child wins via last-write)
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local osc
      osc=$(_gdld_get_field "$line" "scenario")
      if [[ "$osc" == "$sc" ]]; then
        overrides+=("$line")
      fi
    done <<< "$(grep "^@override|" "$file" 2>/dev/null || true)"
  done
  # Process file line by line
  while IFS= read -r line; do
    # Skip comments and blank lines — pass through
    if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
      echo "$line"
      continue
    fi
    # Skip scenario/override/exclude meta-records
    if [[ "$line" =~ ^@scenario\| ]] || [[ "$line" =~ ^@override\| ]] || [[ "$line" =~ ^@exclude\| ]]; then
      continue
    fi
    # Check if this line's target should be excluded
    local line_id=""
    if [[ "$line" =~ ^@node\| ]]; then
      line_id=$(_gdld_get_field "$line" "id")
    elif [[ "$line" =~ ^@edge\| ]]; then
      # Exclude edges to/from excluded nodes
      local efrom eto
      efrom=$(_gdld_get_field "$line" "from")
      eto=$(_gdld_get_field "$line" "to")
      local skip=false
      local exc
      for exc in "${excludes[@]}"; do
        [[ "$efrom" == "$exc" || "$eto" == "$exc" ]] && skip=true
      done
      if [[ "$skip" == "true" ]]; then
        continue
      fi
    fi
    # Check exclusion
    if [[ -n "$line_id" ]]; then
      local excluded=false
      local exc
      for exc in "${excludes[@]}"; do
        [[ "$line_id" == "$exc" ]] && excluded=true
      done
      if [[ "$excluded" == "true" ]]; then
        continue
      fi
      # Apply overrides (last override wins — parent collected first, child last)
      local modified_line="$line"
      local ov
      for ov in "${overrides[@]}"; do
        local otarget ofield ovalue
        otarget=$(_gdld_get_field "$ov" "target")
        if [[ "$otarget" == "$line_id" ]]; then
          ofield=$(_gdld_get_field "$ov" "field")
          ovalue=$(_gdld_get_field "$ov" "value")
          # Replace field value in the line (using awk for safe replacement)
          modified_line=$(echo "$modified_line" | awk -F'|' -v fld="$ofield" -v val="$ovalue" '
          {
            for (i=1; i<=NF; i++) {
              idx = index($i, ":")
              if (idx > 0) {
                k = substr($i, 1, idx-1)
                gsub(/^@/, "", k)
                if (k == fld) { $i = (i==1 ? "@" : "") fld ":" val }
              }
              printf "%s%s", (i>1 ? "|" : ""), $i
            }
            printf "\n"
          }')
        fi
      done
      echo "$modified_line"
    else
      echo "$line"
    fi
  done < "$file"
}

# 6. gdld_view - Apply view filter, output filtered GDLD lines
# Usage: gdld_view <file.gdld> --view=NAME
gdld_view() {
  local file=""
  local view=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --view=*) view="${1#*=}"; shift ;;
      --view)   view="$2"; shift 2 ;;
      *)        file="$1"; shift ;;
    esac
  done
  if [[ -z "$file" || -z "$view" ]]; then
    echo "Usage: gdld_view <file.gdld> --view=NAME" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdld" >&2
    return 1
  fi
  # Find the view definition
  local view_line=""
  view_line=$(grep "^@view|" "$file" | while IFS= read -r line; do
    local vid
    vid=$(_gdld_get_field "$line" "id")
    if [[ "$vid" == "$view" ]]; then
      echo "$line"
    fi
  done)
  if [[ -z "$view_line" ]]; then
    echo "Error: Unknown view: $view" >&2
    return 1
  fi
  local tag_filter includes excludes
  tag_filter=$(_gdld_get_field "$view_line" "filter")
  includes=$(_gdld_get_field "$view_line" "includes")
  excludes=$(_gdld_get_field "$view_line" "excludes")
  # Extract tag name if filter is tags:XXX
  local filter_tag=""
  if [[ "$tag_filter" =~ ^tags: ]]; then
    filter_tag="${tag_filter#tags:}"
  fi
  # Build set of included node IDs
  local included_nodes=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local nid ntags ngroup
    nid=$(_gdld_get_field "$line" "id")
    ntags=$(_gdld_get_field "$line" "tags")
    ngroup=$(_gdld_get_field "$line" "group")
    local include_node=true
    # Tag filter: only include if tag matches
    if [[ -n "$filter_tag" ]]; then
      if ! echo ",$ntags," | grep -q ",$filter_tag,"; then
        include_node=false
      fi
    fi
    # Group includes: only nodes in specified groups (ungrouped nodes pass through)
    if [[ -n "$includes" && -n "$ngroup" ]]; then
      if ! echo ",$includes," | grep -q ",$ngroup,"; then
        include_node=false
      fi
    fi
    # Group excludes: remove nodes in excluded groups
    if [[ -n "$excludes" && -n "$ngroup" ]]; then
      if echo ",$excludes," | grep -q ",$ngroup,"; then
        include_node=false
      fi
    fi
    if [[ "$include_node" == "true" ]]; then
      included_nodes+=("$nid")
    fi
  done <<< "$(grep "^@node|" "$file" || true)"
  # Output filtered lines
  while IFS= read -r line; do
    if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
      echo "$line"
      continue
    fi
    # Skip view/scenario meta records
    if [[ "$line" =~ ^@view\| ]] || [[ "$line" =~ ^@scenario\| ]] || [[ "$line" =~ ^@override\| ]] || [[ "$line" =~ ^@exclude\| ]]; then
      continue
    fi
    # Pass through diagram record
    if [[ "$line" =~ ^@diagram\| ]]; then
      echo "$line"
      continue
    fi
    # Filter nodes
    if [[ "$line" =~ ^@node\| ]]; then
      local nid
      nid=$(_gdld_get_field "$line" "id")
      local found=false
      local inc
      for inc in "${included_nodes[@]}"; do
        [[ "$nid" == "$inc" ]] && found=true
      done
      if [[ "$found" == "true" ]]; then
        echo "$line"
      fi
      continue
    fi
    # Filter edges — only if both endpoints are included
    if [[ "$line" =~ ^@edge\| ]]; then
      local efrom eto
      efrom=$(_gdld_get_field "$line" "from")
      eto=$(_gdld_get_field "$line" "to")
      local from_ok=false to_ok=false
      local inc
      for inc in "${included_nodes[@]}"; do
        [[ "$efrom" == "$inc" ]] && from_ok=true
        [[ "$eto" == "$inc" ]] && to_ok=true
      done
      if [[ "$from_ok" == "true" && "$to_ok" == "true" ]]; then
        echo "$line"
      fi
      continue
    fi
    # Filter groups — only if they have included nodes
    if [[ "$line" =~ ^@group\| ]]; then
      local gid
      gid=$(_gdld_get_field "$line" "id")
      # Check if any included node belongs to this group
      local has_nodes=false
      local inc
      for inc in "${included_nodes[@]}"; do
        local inc_group
        inc_group=$(grep "^@node|" "$file" | while IFS= read -r nline; do
          local nid2
          nid2=$(_gdld_get_field "$nline" "id")
          if [[ "$nid2" == "$inc" ]]; then
            _gdld_get_field "$nline" "group"
          fi
        done)
        if [[ "$inc_group" == "$gid" ]]; then
          has_nodes=true
          break
        fi
      done
      if [[ "$has_nodes" == "true" ]]; then
        echo "$line"
      fi
      continue
    fi
    # Pass through other context records (gotchas, components, etc.)
    echo "$line"
  done < "$file"
}

# 7. gdld_neighbors - 1-hop outbound/inbound neighbors with optional type filter
# Usage: gdld_neighbors <file.gdld> <node> [--direction=out|in|both] [--type=TYPE]
gdld_neighbors() {
  local file="" node="" direction="out" type_filter=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --direction=*) direction="${1#*=}"; shift ;;
      --direction)   direction="$2"; shift 2 ;;
      --type=*)      type_filter="${1#*=}"; shift ;;
      --type)        type_filter="$2"; shift 2 ;;
      *)             if [[ -z "$file" ]]; then file="$1"; elif [[ -z "$node" ]]; then node="$1"; fi; shift ;;
    esac
  done
  if [[ -z "$file" || -z "$node" ]]; then
    echo "Usage: gdld_neighbors <file.gdld> <node> [--direction=out|in|both] [--type=TYPE]" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdld" >&2
    return 1
  fi
  if [[ "$direction" != "out" && "$direction" != "in" && "$direction" != "both" ]]; then
    echo "Error: direction must be 'out', 'in', or 'both'" >&2
    return 1
  fi
  awk -F'|' -v target="$node" -v dir="$direction" -v tfilter="$type_filter" '
  /^@edge/ {
    from=""; to=""; etype=""
    for (i=1; i<=NF; i++) {
      if ($i ~ /^from:/) from = substr($i, 6)
      if ($i ~ /^to:/)   to = substr($i, 4)
      if ($i ~ /^type:/) etype = substr($i, 6)
    }
    if (from == "" || to == "") next
    if (tfilter != "" && etype != tfilter) next
    if ((dir == "out" || dir == "both") && from == target) print to
    if ((dir == "in" || dir == "both") && to == target) print from
  }
  ' "$file"
}

# 8. gdld_traverse - N-hop DFS traversal with cycle detection
# Usage: gdld_traverse <file.gdld> <node> [--depth=N] [--type=TYPE] [--format=list|gdld|trace]
gdld_traverse() {
  local file="" node="" depth=3 type_filter="" format="list"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --depth=*)  depth="${1#*=}"; shift ;;
      --depth)    depth="$2"; shift 2 ;;
      --type=*)   type_filter="${1#*=}"; shift ;;
      --type)     type_filter="$2"; shift 2 ;;
      --format=*) format="${1#*=}"; shift ;;
      --format)   format="$2"; shift 2 ;;
      *)          if [[ -z "$file" ]]; then file="$1"; elif [[ -z "$node" ]]; then node="$1"; fi; shift ;;
    esac
  done
  if [[ -z "$file" || -z "$node" ]]; then
    echo "Usage: gdld_traverse <file.gdld> <node> [--depth=N] [--type=TYPE] [--format=list|gdld|trace]" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdld" >&2
    return 1
  fi
  if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
    echo "Error: depth must be a non-negative integer" >&2
    return 1
  fi

  case "$format" in
    list)
      awk -F'|' -v start="$node" -v maxd="$depth" -v tfilter="$type_filter" '
      /^@edge/ {
        from=""; to=""; etype=""
        for (i=1; i<=NF; i++) {
          if ($i ~ /^from:/) from = substr($i, 6)
          if ($i ~ /^to:/)   to = substr($i, 4)
          if ($i ~ /^type:/) etype = substr($i, 6)
        }
        if (from == "" || to == "") next
        if (tfilter != "" && etype != tfilter) next
        n = ++ac[from]
        adj[from, n] = to
      }
      /^@node/ {
        for (i=1; i<=NF; i++) {
          if ($i ~ /^id:/) has_node[substr($i, 4)] = 1
        }
      }
      END {
        if (!(start in has_node)) exit
        descend(start, 0)
      }
      function descend(node, d,    i, nb) {
        if (d > maxd) return
        if (seen[node]) return
        seen[node] = 1
        print node
        for (i = 1; i <= ac[node]; i++) {
          nb = adj[node, i]
          descend(nb, d + 1)
        }
      }
      ' "$file"
      ;;
    trace)
      awk -F'|' -v start="$node" -v maxd="$depth" -v tfilter="$type_filter" '
      /^@edge/ {
        from=""; to=""; label=""; etype=""
        for (i=1; i<=NF; i++) {
          if ($i ~ /^from:/)  from = substr($i, 6)
          if ($i ~ /^to:/)    to = substr($i, 4)
          if ($i ~ /^label:/) label = substr($i, 7)
          if ($i ~ /^type:/)  etype = substr($i, 6)
        }
        if (from == "" || to == "") next
        if (tfilter != "" && etype != tfilter) next
        n = ++ac[from]
        adj[from, n] = to
        albl[from, n] = label
      }
      /^@node/ {
        for (i=1; i<=NF; i++) {
          if ($i ~ /^id:/) has_node[substr($i, 4)] = 1
        }
      }
      END {
        if (!(start in has_node)) exit
        descend(start, 0)
      }
      function descend(node, d,    i, nb, lbl) {
        if (d > maxd) return
        if (seen[node]) return
        seen[node] = 1
        for (i = 1; i <= ac[node]; i++) {
          nb = adj[node, i]
          if (!seen[nb] && d + 1 <= maxd) {
            lbl = albl[node, i]
            if (lbl == "") lbl = "-"
            printf "%s --[%s]--> %s\n", node, lbl, nb
            descend(nb, d + 1)
          }
        }
      }
      ' "$file"
      ;;
    gdld)
      local ids
      ids=$(gdld_traverse "$file" "$node" --depth="$depth" ${type_filter:+--type="$type_filter"} --format=list) || return 1
      if [[ -z "$ids" ]]; then return 0; fi
      local id_str
      id_str=$(echo "$ids" | tr '\n' ' ')
      echo "@diagram|id:traverse-${node}|type:flow|purpose:DFS from ${node} depth ${depth}"
      awk -F'|' -v id_list="$id_str" '
      BEGIN { n = split(id_list, arr, " "); for (i=1; i<=n; i++) ids[arr[i]] = 1 }
      /^@group/ {
        gid = ""
        for (i=1; i<=NF; i++) {
          if ($i ~ /^id:/) gid = substr($i, 4)
        }
        grp_line[gid] = $0
        grp_order[++gc] = gid
        next
      }
      /^@node/ {
        nid = ""; ngrp = ""
        for (i=1; i<=NF; i++) {
          if ($i ~ /^id:/) nid = substr($i, 4)
          if ($i ~ /^group:/) ngrp = substr($i, 7)
        }
        if ((nid in ids) && !(nid in node_seen)) {
          node_seen[nid] = 1
          node_out[++nc] = $0
          if (ngrp != "") need_grp[ngrp] = 1
        }
        next
      }
      /^@edge/ {
        from = ""; to = ""
        for (i=1; i<=NF; i++) {
          if ($i ~ /^from:/) from = substr($i, 6)
          if ($i ~ /^to:/) to = substr($i, 4)
        }
        if ((from in ids) && (to in ids)) edge_out[++ec] = $0
        next
      }
      END {
        for (i = 1; i <= gc; i++) {
          if (grp_order[i] in need_grp && grp_order[i] in grp_line)
            print grp_line[grp_order[i]]
        }
        for (i = 1; i <= nc; i++) print node_out[i]
        for (i = 1; i <= ec; i++) print edge_out[i]
      }
      ' "$file"
      ;;
    *)
      echo "Error: format must be 'list', 'gdld', or 'trace'" >&2
      return 1
      ;;
  esac
}

# 9. gdld_path - BFS shortest path between two nodes
# Usage: gdld_path <file.gdld> <from> <to> [--format=list|trace]
gdld_path() {
  local file="" from_node="" to_node="" format="list"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --format=*) format="${1#*=}"; shift ;;
      --format)   format="$2"; shift 2 ;;
      *)          if [[ -z "$file" ]]; then file="$1";
                  elif [[ -z "$from_node" ]]; then from_node="$1";
                  elif [[ -z "$to_node" ]]; then to_node="$1"; fi; shift ;;
    esac
  done
  if [[ -z "$file" || -z "$from_node" || -z "$to_node" ]]; then
    echo "Usage: gdld_path <file.gdld> <from> <to> [--format=list|trace]" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdld" >&2
    return 1
  fi

  case "$format" in
    list)
      awk -F'|' -v src="$from_node" -v dst="$to_node" '
      /^@edge/ {
        from=""; to=""
        for (i=1; i<=NF; i++) {
          if ($i ~ /^from:/) from = substr($i, 6)
          if ($i ~ /^to:/)   to = substr($i, 4)
        }
        if (from != "" && to != "") {
          n = ++ac[from]
          adj[from, n] = to
        }
      }
      /^@node/ {
        for (i=1; i<=NF; i++) {
          if ($i ~ /^id:/) has_node[substr($i, 4)] = 1
        }
      }
      END {
        if (!(src in has_node)) exit
        if (src == dst) { print src; exit }
        if (!(dst in has_node)) exit
        # BFS
        queue[1] = src; head = 1; tail = 1
        vis[src] = 1; par[src] = ""
        found = 0
        while (head <= tail) {
          cur = queue[head++]
          for (i = 1; i <= ac[cur]; i++) {
            nb = adj[cur, i]
            if (nb in vis) continue
            vis[nb] = 1
            par[nb] = cur
            if (nb == dst) { found = 1; break }
            queue[++tail] = nb
          }
          if (found) break
        }
        if (!found) exit
        # Reconstruct path (reverse)
        n = 0; cur = dst
        while (cur != "") {
          pth[++n] = cur
          cur = par[cur]
        }
        for (i = n; i >= 1; i--) print pth[i]
      }
      ' "$file"
      ;;
    trace)
      awk -F'|' -v src="$from_node" -v dst="$to_node" '
      /^@edge/ {
        from=""; to=""; label=""
        for (i=1; i<=NF; i++) {
          if ($i ~ /^from:/)  from = substr($i, 6)
          if ($i ~ /^to:/)    to = substr($i, 4)
          if ($i ~ /^label:/) label = substr($i, 7)
        }
        if (from != "" && to != "") {
          n = ++ac[from]
          adj[from, n] = to
          albl[from, n] = label
        }
      }
      /^@node/ {
        for (i=1; i<=NF; i++) {
          if ($i ~ /^id:/) has_node[substr($i, 4)] = 1
        }
      }
      END {
        if (!(src in has_node)) exit
        if (src == dst) { printf "%s\n", src; exit }
        if (!(dst in has_node)) exit
        queue[1] = src; head = 1; tail = 1
        vis[src] = 1; par[src] = ""
        found = 0
        while (head <= tail) {
          cur = queue[head++]
          for (i = 1; i <= ac[cur]; i++) {
            nb = adj[cur, i]
            if (nb in vis) continue
            vis[nb] = 1
            par[nb] = cur
            plbl[nb] = albl[cur, i]
            if (nb == dst) { found = 1; break }
            queue[++tail] = nb
          }
          if (found) break
        }
        if (!found) exit
        n = 0; cur = dst
        while (cur != "") {
          pth[++n] = cur
          plb[n] = plbl[cur]
          cur = par[cur]
        }
        printf "%s", pth[n]
        for (i = n-1; i >= 1; i--) {
          lbl = plb[i]
          if (lbl == "") lbl = "-"
          printf " --[%s]--> %s", lbl, pth[i]
        }
        printf "\n"
      }
      ' "$file"
      ;;
    *)
      echo "Error: format must be 'list' or 'trace'" >&2
      return 1
      ;;
  esac
}

# 10. gdld_closure - Transitive closure (all reachable nodes)
# Usage: gdld_closure <file.gdld> <node> [--direction=out|in]
gdld_closure() {
  local file="" node="" direction="out"
  while [[ $# -gt 0 ]]; do
    case $1 in
      --direction=*) direction="${1#*=}"; shift ;;
      --direction)   direction="$2"; shift 2 ;;
      *)             if [[ -z "$file" ]]; then file="$1"; elif [[ -z "$node" ]]; then node="$1"; fi; shift ;;
    esac
  done
  if [[ -z "$file" || -z "$node" ]]; then
    echo "Usage: gdld_closure <file.gdld> <node> [--direction=out|in]" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdld" >&2
    return 1
  fi
  if [[ "$direction" != "out" && "$direction" != "in" ]]; then
    echo "Error: direction must be 'out' or 'in'" >&2
    return 1
  fi
  awk -F'|' -v start="$node" -v dir="$direction" '
  /^@edge/ {
    from=""; to=""
    for (i=1; i<=NF; i++) {
      if ($i ~ /^from:/) from = substr($i, 6)
      if ($i ~ /^to:/)   to = substr($i, 4)
    }
    if (from != "" && to != "") {
      if (dir == "in") {
        n = ++ac[to]; adj[to, n] = from
      } else {
        n = ++ac[from]; adj[from, n] = to
      }
    }
  }
  /^@node/ {
    for (i=1; i<=NF; i++) {
      if ($i ~ /^id:/) has_node[substr($i, 4)] = 1
    }
  }
  END {
    if (!(start in has_node)) exit
    dfs(start)
  }
  function dfs(node,    i, nb) {
    if (seen[node]) return
    seen[node] = 1
    print node
    for (i = 1; i <= ac[node]; i++) {
      nb = adj[node, i]
      dfs(nb)
    }
  }
  ' "$file"
}

# 11. gdld_topo - Topological ordering via tsort
# Usage: gdld_topo <file.gdld>
# Note: exits non-zero if the graph contains cycles (tsort behaviour).
#       Callers under set -e should use: gdld_topo file.gdld 2>/dev/null || true
gdld_topo() {
  local file="${1:-}"
  if [[ -z "$file" ]]; then
    echo "Usage: gdld_topo <file.gdld>" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "Error: File not found: $file. Check path or run: ls *.gdld" >&2
    return 1
  fi
  if ! command -v tsort &>/dev/null; then
    echo "Error: tsort not found in PATH" >&2
    return 1
  fi
  local edges
  edges=$(awk -F'|' '
  /^@edge/ {
    from=""; to=""
    for (i=1; i<=NF; i++) {
      if ($i ~ /^from:/) from = substr($i, 6)
      if ($i ~ /^to:/)   to = substr($i, 4)
    }
    if (from != "" && to != "" && from != to) print from, to
  }
  ' "$file")
  if [[ -z "$edges" ]]; then return 0; fi
  echo "$edges" | tsort
}

echo "GDLD tools loaded. Available: gdld_gotchas, gdld_nodes, gdld_components, gdld_subgraph, gdld_filter, gdld_view, gdld_neighbors, gdld_traverse, gdld_path, gdld_closure, gdld_topo"
