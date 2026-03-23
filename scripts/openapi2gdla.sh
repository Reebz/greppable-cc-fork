#!/usr/bin/env bash
# openapi2gdla.sh — Convert OpenAPI/Swagger specs to GDLA API contract format
# Usage: openapi2gdla.sh <spec.json|spec.yaml> [--output=DIR] [--dry-run] [--check]
# Requires: jq, python3 with PyYAML (for YAML input only)
set -uo pipefail

# --- Dependency check ---
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed. Install with: brew install jq" >&2
  exit 1
fi

INPUT_FILE=""
OUTPUT_DIR=""
DRY_RUN=false
CHECK_MODE=false

for arg in "$@"; do
  case "$arg" in
    --output=*) OUTPUT_DIR="${arg#--output=}" ;;
    --dry-run) DRY_RUN=true ;;
    --check) CHECK_MODE=true ;;
    --help|-h)
      cat <<'USAGE'
openapi2gdla.sh — Convert OpenAPI/Swagger specs to GDLA API contract format

Usage: openapi2gdla.sh <spec.json|spec.yaml> [--output=DIR] [--dry-run] [--check]

Parses an OpenAPI 2.0/3.0/3.1 or Swagger specification and generates a GDLA
file with @D (domain), @S (schemas), @EP (endpoints), @P (parameters),
@AUTH (security schemes), @ENUM (enums), @R (relationships).

OPTIONS:
  --output=DIR   Write output to DIR/<service>.openapi.gdla (default: stdout)
  --dry-run      Show what would be generated without writing
  --check        Compare generated GDLA with existing file (drift detection)
  --help         Show this help

REQUIREMENTS:
  - jq (always required)
  - python3 + PyYAML (only for YAML input; not needed for JSON)

KNOWN LIMITATIONS (v0.1):
  - discriminator: polymorphic type mapping deferred to v0.2
  - Full recursive $ref inlining: by design, captures structure not expanded trees
  - External $ref: emits stub @S records with [external: filename] descriptions
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
  echo "Usage: openapi2gdla.sh <spec.json|spec.yaml> [--output=DIR] [--dry-run] [--check]" >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: file not found: $INPUT_FILE" >&2
  exit 1
fi

# --- YAML/JSON detection and conversion ---
json_input=""
case "$INPUT_FILE" in
  *.yaml|*.yml)
    if ! python3 -c "import yaml" 2>/dev/null; then
      echo "Error: PyYAML is required for YAML input. Install with:" >&2
      echo "  pip3 install --user pyyaml" >&2
      echo "  brew install python-pyyaml" >&2
      echo "Or pass a JSON file instead." >&2
      exit 1
    fi
    json_input=$(python3 -c "
import sys, json
try:
    import yaml
    with open(sys.argv[1], 'r') as f:
        data = yaml.safe_load(f)
    json.dump(data, sys.stdout)
except yaml.YAMLError as e:
    print(f'Error: invalid YAML: {e}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" "$INPUT_FILE") || exit 1
    ;;
  *)
    # Validate JSON
    if ! jq empty "$INPUT_FILE" 2>/dev/null; then
      echo "Error: invalid JSON in $INPUT_FILE" >&2
      exit 1
    fi
    json_input=$(cat "$INPUT_FILE")
    ;;
esac

# --- Version detection ---
spec_version=$(echo "$json_input" | jq -r '.openapi // .swagger // empty')
if [[ -z "$spec_version" ]]; then
  echo "Error: cannot detect OpenAPI/Swagger version (no .openapi or .swagger field)" >&2
  exit 1
fi

is_swagger=false
case "$spec_version" in
  2.*) is_swagger=true ;;
  3.*) ;;
  *)
    echo "Error: unsupported spec version: $spec_version" >&2
    exit 1
    ;;
esac

# --- Escape helpers ---
escape_pipe() {
  echo "$1" | tr '\n\r\t' '   ' | sed 's/[[:space:]]*$//' | sed 's/|/\\|/g'
}

# --- Extract service info for @D ---
if [[ "$is_swagger" == true ]]; then
  service_title=$(echo "$json_input" | jq -r '.info.title // "unknown"')
  service_desc=$(echo "$json_input" | jq -r '.info.description // .info.title // ""')
  service_version=$(echo "$json_input" | jq -r '.info.version // ""')
  base_url=$(echo "$json_input" | jq -r '(.basePath // "")')
else
  service_title=$(echo "$json_input" | jq -r '.info.title // "unknown"')
  service_desc=$(echo "$json_input" | jq -r '.info.description // .info.title // ""')
  service_version=$(echo "$json_input" | jq -r '.info.version // ""')
  base_url=$(echo "$json_input" | jq -r '(.servers[0].url // "")')
fi

# Slugify service name
service_slug=$(echo "$service_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
[[ -z "$service_slug" ]] && service_slug="unknown-api"

today=$(date +%Y-%m-%d)

# --- Build output ---
output=""
output+="# @VERSION spec:gdla v:0.1.0 generated:${today} source:openapi-bridge file:$(basename "$INPUT_FILE")"$'\n'
output+=""$'\n'
output+="@D ${service_slug}|$(escape_pipe "$service_desc")|${service_version}|${base_url}"$'\n'

# --- Auth schemes ---
if [[ "$is_swagger" == true ]]; then
  auth_entries=$(echo "$json_input" | jq -c '.securityDefinitions // {} | to_entries[]' 2>/dev/null || true)
  if [[ -n "$auth_entries" ]]; then
    output+=""$'\n'
    while IFS= read -r line; do
      local_name=$(echo "$line" | jq -r '.key')
      local_type=$(echo "$line" | jq -r '.value.type // ""')
      local_in=$(echo "$line" | jq -r '.value.in // ""')
      local_header=$(echo "$line" | jq -r '.value.name // ""')
      local_desc=""
      case "$local_type" in
        apiKey) local_desc="API key in ${local_in}" ;;
        oauth2) local_desc="OAuth 2.0" ;;
        basic) local_desc="HTTP Basic" ; local_header="Authorization" ;;
        *) local_desc="$local_type" ;;
      esac
      output+="@AUTH ${local_name}|${local_desc}|${local_header}"$'\n'
    done <<< "$auth_entries"
  fi
else
  auth_path=".components.securitySchemes"
  auth_count=$(echo "$json_input" | jq -r "${auth_path} // {} | length" 2>/dev/null || echo "0")
  if [[ "$auth_count" -gt 0 ]]; then
    output+=""$'\n'
    while IFS= read -r line; do
      local_name=$(echo "$line" | jq -r '.key')
      local_type=$(echo "$line" | jq -r '.value.type // ""')
      local_scheme=$(echo "$line" | jq -r '.value.scheme // ""')
      local_in=$(echo "$line" | jq -r '.value.in // ""')
      local_header=$(echo "$line" | jq -r '.value.name // ""')
      local_desc=""
      case "$local_type" in
        apiKey) local_desc="API key in ${local_in}" ;;
        http)
          case "$local_scheme" in
            bearer) local_desc="Bearer token" ; local_header="Authorization" ;;
            basic) local_desc="HTTP Basic" ; local_header="Authorization" ;;
            *) local_desc="HTTP ${local_scheme}" ; local_header="Authorization" ;;
          esac
          ;;
        oauth2) local_desc="OAuth 2.0" ; local_header="Authorization" ;;
        openIdConnect) local_desc="OpenID Connect" ; local_header="Authorization" ;;
        *) local_desc="$local_type" ;;
      esac
      output+="@AUTH ${local_name}|${local_desc}|${local_header}"$'\n'
    done <<< "$(echo "$json_input" | jq -c "${auth_path} // {} | to_entries[]" 2>/dev/null || true)"
  fi
fi

# --- Schemas ---
schemas_path=""
if [[ "$is_swagger" == true ]]; then
  schemas_path=".definitions"
else
  schemas_path=".components.schemas"
fi

seen_schemas=""
enum_output=""
rel_output=""

schema_entries=$(echo "$json_input" | jq -c "${schemas_path} // {} | to_entries[]" 2>/dev/null || true)
if [[ -n "$schema_entries" ]]; then
  output+=""$'\n'
  while IFS= read -r entry; do
    schema_name=$(echo "$entry" | jq -r '.key')
    schema_desc=$(echo "$entry" | jq -r '.value.description // ""')
    seen_schemas="${seen_schemas}|${schema_name}|"

    # Check for allOf composition
    allof_count=$(echo "$entry" | jq -r '.value.allOf // [] | length')
    if [[ "$allof_count" -gt 0 ]]; then
      # Emit relationships for allOf refs
      while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        ref_name=$(echo "$ref" | sed 's|.*/||')
        [[ -z "$ref_name" ]] && continue
        rel_output+="@R ${schema_name} -> ${ref_name}|allOf|"$'\n'
      done <<< "$(echo "$entry" | jq -r '.value.allOf[]."$ref" // empty' 2>/dev/null || true)"
    fi

    # Check for oneOf/anyOf
    for variant_type in oneOf anyOf; do
      variant_count=$(echo "$entry" | jq -r ".value.${variant_type} // [] | length")
      if [[ "$variant_count" -gt 0 ]]; then
        while IFS= read -r ref; do
          [[ -z "$ref" ]] && continue
          ref_name=$(echo "$ref" | sed 's|.*/||')
          [[ -z "$ref_name" ]] && continue
          rel_output+="@R ${schema_name} -> ${ref_name}|${variant_type}|"$'\n'
        done <<< "$(echo "$entry" | jq -r --arg vt "$variant_type" '.value[$vt][]."$ref" // empty' 2>/dev/null || true)"
      fi
    done

    output+="@S ${schema_name}|$(escape_pipe "$schema_desc")"$'\n'

    # Check for enum (top-level enum schema) — escape commas and pipes in values
    top_enum=$(echo "$entry" | jq -r '.value.enum // empty | map(gsub(","; "\\,") | gsub("\\|"; "\\|")) | join(",")')
    if [[ -n "$top_enum" ]]; then
      enum_output+="@ENUM ${schema_name}|${top_enum}"$'\n'
    fi

    # Schema properties → fields (merge top-level + allOf inline properties)
    props=$(echo "$entry" | jq -c '((.value.properties // {}) + (reduce (.value.allOf[]? | select(.properties) | .properties) as $p ({}; . + $p))) | to_entries[]' 2>/dev/null || true)
    required_list=$(echo "$entry" | jq -r '((.value.required // []) + [(.value.allOf[]? | select(.required) | .required[])?]) | unique | .[]' 2>/dev/null || true)
    if [[ -n "$props" ]]; then
      while IFS= read -r prop; do
        field_name=$(echo "$prop" | jq -r '.key')
        field_type=$(echo "$prop" | jq -r '.value.type // ""')
        field_format=$(echo "$prop" | jq -r '.value.format // ""')
        field_desc=$(echo "$prop" | jq -r '.value.description // ""')

        # Handle $ref in property
        field_ref=$(echo "$prop" | jq -r '.value."$ref" // empty')
        if [[ -n "$field_ref" ]]; then
          ref_target=$(echo "$field_ref" | sed 's|.*/||')
          # Check for external ref
          case "$field_ref" in
            \#*) field_type="$ref_target" ;;
            *)
              local_file=$(echo "$field_ref" | cut -d'#' -f1)
              ref_target=$(echo "$field_ref" | sed 's|.*/||')
              field_type="$ref_target"
              # Emit stub for external ref if not seen
              if [[ "$seen_schemas" != *"|${ref_target}|"* ]]; then
                output+="@S ${ref_target}|[external: ${local_file}]"$'\n'
                seen_schemas="${seen_schemas}|${ref_target}|"
              fi
              ;;
          esac
          rel_output+="@R ${schema_name} -> ${ref_target}|references|via ${field_name}"$'\n'
        fi

        # Handle array items
        items_ref=$(echo "$prop" | jq -r '.value.items."$ref" // empty')
        items_type=$(echo "$prop" | jq -r '.value.items.type // empty')
        if [[ -n "$items_ref" ]]; then
          ref_target=$(echo "$items_ref" | sed 's|.*/||')
          field_type="${ref_target}[]"
          rel_output+="@R ${schema_name} -> ${ref_target}|references|via ${field_name}"$'\n'
        elif [[ -n "$items_type" ]]; then
          field_type="${items_type}[]"
        elif [[ "$field_type" == "array" ]]; then
          field_type="array"
        fi

        # Check if field is required
        is_required=""
        if echo "$required_list" | grep -qxF "$field_name" 2>/dev/null; then
          is_required="required"
        fi

        # Check for field-level enum — escape commas and pipes in values
        field_enum=$(echo "$prop" | jq -r '.value.enum // empty | map(gsub(","; "\\,") | gsub("\\|"; "\\|")) | join(",")')
        if [[ -n "$field_enum" ]]; then
          enum_output+="@ENUM ${schema_name}_${field_name}|${field_enum}"$'\n'
          [[ -z "$field_format" ]] && field_format="enum"
        fi

        output+=" ${field_name}|${field_type}|${is_required}|${field_format}|$(escape_pipe "$field_desc")"$'\n'
      done <<< "$props"
    fi
  done <<< "$schema_entries"
fi

# --- Enums ---
if [[ -n "$enum_output" ]]; then
  output+=""$'\n'
  output+="$enum_output"
fi

# --- Endpoints ---
paths_json=$(echo "$json_input" | jq -c '.paths // {} | to_entries[]' 2>/dev/null || true)
if [[ -n "$paths_json" ]]; then
  output+=""$'\n'
  while IFS= read -r path_entry; do
    api_path=$(echo "$path_entry" | jq -r '.key')

    # Path-level parameters (hoisted to each operation)
    path_params=$(echo "$path_entry" | jq -c '.value.parameters // []')

    # Iterate operations
    for method in get post put delete patch head options; do
      op=$(echo "$path_entry" | jq -c ".value.${method} // empty")
      [[ -z "$op" ]] && continue

      method_upper=$(echo "$method" | tr '[:lower:]' '[:upper:]')
      op_desc=$(echo "$op" | jq -r '.summary // .description // ""')

      # Build responses string
      responses=""
      resp_entries=$(echo "$op" | jq -c '.responses // {} | to_entries[]' 2>/dev/null || true)
      if [[ -n "$resp_entries" ]]; then
        while IFS= read -r resp; do
          resp_code=$(echo "$resp" | jq -r '.key')
          # Try to find schema reference
          resp_ref=""
          if [[ "$is_swagger" == true ]]; then
            resp_ref=$(echo "$resp" | jq -r '.value.schema."$ref" // empty')
            if [[ -z "$resp_ref" ]]; then
              resp_ref=$(echo "$resp" | jq -r '.value.schema.items."$ref" // empty')
              if [[ -n "$resp_ref" ]]; then
                resp_ref="${resp_ref}[]"
              fi
            fi
          else
            # OpenAPI 3.x: look in content.application/json.schema, fallback to first content type
            resp_ref=$(echo "$resp" | jq -r '(.value.content["application/json"].schema."$ref" // (.value.content | to_entries[0]?.value.schema."$ref") // empty)' 2>/dev/null || true)
            if [[ -z "$resp_ref" ]]; then
              resp_ref=$(echo "$resp" | jq -r '(.value.content["application/json"].schema.items."$ref" // (.value.content | to_entries[0]?.value.schema.items."$ref") // empty)' 2>/dev/null || true)
              if [[ -n "$resp_ref" ]]; then
                resp_ref="${resp_ref}[]"
              fi
            fi
            # Check for oneOf/anyOf in response schema
            if [[ -z "$resp_ref" ]]; then
              resp_ref=$(echo "$resp" | jq -r '(.value.content["application/json"].schema.oneOf[0]."$ref" // (.value.content["application/json"].schema.anyOf[0]."$ref") // empty)' 2>/dev/null || true)
            fi
            # Check for response-level $ref
            if [[ -z "$resp_ref" ]]; then
              resp_ref=$(echo "$resp" | jq -r '.value."$ref" // empty' 2>/dev/null || true)
            fi
          fi
          resp_type=""
          if [[ -n "$resp_ref" ]]; then
            # Extract type name, handle array suffix
            if [[ "$resp_ref" == *"[]" ]]; then
              resp_type=$(echo "${resp_ref%\[\]}" | sed 's|.*/||')"[]"
            else
              resp_type=$(echo "$resp_ref" | sed 's|.*/||')
            fi
          fi
          if [[ -n "$responses" ]]; then
            responses="${responses},${resp_code}:${resp_type}"
          else
            responses="${resp_code}:${resp_type}"
          fi
        done <<< "$resp_entries"
      fi

      # Auth
      auth_scheme=""
      op_security=$(echo "$op" | jq -c '.security // empty')
      if [[ -z "$op_security" ]]; then
        # Fall back to global security
        op_security=$(echo "$json_input" | jq -c '.security // empty')
      fi
      if [[ -n "$op_security" && "$op_security" != "null" ]]; then
        auth_scheme=$(echo "$op_security" | jq -r '.[0] // {} | keys[0] // empty' 2>/dev/null || true)
      fi

      output+="@EP ${method_upper} ${api_path}|$(escape_pipe "$op_desc")|${responses}|${auth_scheme}"$'\n'

      # Parameters (merge path-level + operation-level, resolve $ref)
      merged_params=$(echo "$op" | jq -c --argjson pp "$path_params" '(.parameters // []) + $pp | unique_by(if ."$ref" then ."$ref" else (.name + .in) end) | .[]' 2>/dev/null || true)
      if [[ -n "$merged_params" ]]; then
        while IFS= read -r param; do
          # Resolve $ref parameters from components/definitions
          p_ref=$(echo "$param" | jq -r '."$ref" // empty')
          if [[ -n "$p_ref" ]]; then
            # Convert #/components/parameters/Foo to .components.parameters.Foo
            ref_jq_path=$(echo "$p_ref" | sed 's|^#/||' | sed 's|/|.|g')
            param=$(echo "$json_input" | jq -c ".${ref_jq_path} // {}" 2>/dev/null || echo "$param")
          fi
          p_name=$(echo "$param" | jq -r '.name // empty')
          [[ -z "$p_name" ]] && continue
          p_in=$(echo "$param" | jq -r '.in // "query"')
          p_type=$(echo "$param" | jq -r '(if .schema."$ref" then (.schema."$ref" | split("/") | last) elif .schema.type then .schema.type elif .type then .type else "string" end)')
          p_required=$(echo "$param" | jq -r 'if .required == true then "required" else "" end')
          p_desc=$(echo "$param" | jq -r '.description // ""')
          output+="@P ${p_name}|${p_in}|${p_type}|${p_required}|$(escape_pipe "$p_desc")"$'\n'
        done <<< "$merged_params"
      fi

      # Request body (OpenAPI 3.x) — fallback to first content type if no application/json
      if [[ "$is_swagger" != true ]]; then
        req_ref=$(echo "$op" | jq -r '(.requestBody.content["application/json"].schema."$ref" // (.requestBody.content | to_entries[0]?.value.schema."$ref") // empty)' 2>/dev/null || true)
        if [[ -n "$req_ref" ]]; then
          req_type=$(echo "$req_ref" | sed 's|.*/||')
          req_required=$(echo "$op" | jq -r 'if .requestBody.required == true then "required" else "" end')
          output+="@P body|body|${req_type}|${req_required}|Request body"$'\n'
        fi
      fi
    done
  done <<< "$paths_json"
fi

# --- Relationships ---
# Deduplicate relationships
if [[ -n "$rel_output" ]]; then
  output+=""$'\n'
  deduped_rels=$(echo "$rel_output" | sort -u)
  output+="$deduped_rels"$'\n'
fi

# Remove trailing newline
output="${output%$'\n'}"

# --- Output ---
if [[ "$CHECK_MODE" == true ]]; then
  if [[ -z "$OUTPUT_DIR" ]]; then
    echo "Error: --check requires --output=DIR" >&2
    exit 1
  fi
  existing="${OUTPUT_DIR}/${service_slug}.openapi.gdla"
  if [[ ! -f "$existing" ]]; then
    echo "DRIFT: no existing file at $existing" >&2
    echo "$output"
    exit 1
  fi
  _tmp_generated=$(mktemp)
  echo "$output" > "$_tmp_generated"
  if diff -q "$_tmp_generated" "$existing" &>/dev/null; then
    rm -f "$_tmp_generated"
    echo "OK: $existing is up to date" >&2
    exit 0
  else
    echo "DRIFT: $existing differs from generated output" >&2
    diff --unified "$_tmp_generated" "$existing" >&2 || true
    rm -f "$_tmp_generated"
    exit 1
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "$output"
  exit 0
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  outfile="${OUTPUT_DIR}/${service_slug}.openapi.gdla"
  _tmp_out=$(mktemp "$(dirname "$outfile")/.gdl-atomic.XXXXXX")
  echo "$output" > "$_tmp_out" || { rm -f "$_tmp_out"; exit 1; }
  mv "$_tmp_out" "$outfile"
  echo "Wrote: $outfile" >&2
else
  echo "$output"
fi
