---
name: exploring-gdla-api-contracts
description: "Use when working with API endpoints, understanding what a service exposes, or checking API authentication and parameters before integrating. Works with .gdla API contract files — endpoint lookups, schema definitions, auth configuration, and cross-API dependencies. Triggers on: \"what endpoints does X expose\", \"what auth does Y require\", \"what parameters does this endpoint accept\", integrating with a service's API, or direct .gdla file operations. NOT for building new API endpoints from scratch, creating OpenAPI specs, or .gdls schema maps."
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
context: fork
---

# GDLA Quick Reference

## Available API Contracts

!`bash -c 'find docs/gdl -name "*.gdla" -maxdepth 3 2>/dev/null | while read f; do echo "- $f"; done'`

## Format

```
@D service-name|description|version|base-url
@S SchemaName|description
 field|type|required|format|description
@EP METHOD /path|description|responses|auth
@P param|location|type|required|description
@AUTH scheme|description|header
@ENUM Name|value1,value2,value3
@R Source -> Target|relationship|via field
@PATH Entity -> Entity|traversal description
```

Endpoints and auth are single-line records. Schemas use indented field lines (like GDLS tables).

## Grep Patterns

```bash
# All endpoints
grep "^@EP" contract.gdla

# Specific HTTP method
grep "^@EP GET" contract.gdla
grep "^@EP POST" contract.gdla

# GraphQL operations
grep "^@EP QUERY" contract.gdla
grep "^@EP MUTATION" contract.gdla
grep "^@EP SUBSCRIPTION" contract.gdla

# Find a schema and its fields
grep "@S Pet" -A 20 contract.gdla

# All schemas (just headers)
grep "^@S " contract.gdla

# Parameters for an endpoint
grep "^@EP GET /pets" -A 10 contract.gdla | grep "^@P"

# Authentication schemes
grep "^@AUTH" contract.gdla

# Endpoints requiring specific auth
grep "^@EP.*|bearer" contract.gdla

# Schema relationships
grep "^@R" contract.gdla

# Traversal paths
grep "^@PATH" contract.gdla

# Enums
grep "^@ENUM" contract.gdla

# Cross-file: all endpoints across all APIs
grep "^@EP" *.gdla

# Cross-file: find which APIs use bearer auth
grep "^@AUTH.*bearer" *.gdla
```

## Combined Queries (Fewer Tool Calls)

```bash
# Full API surface (endpoints + auth)
grep -E "^@EP|^@AUTH" contract.gdla

# Schema + relationships
grep -E "^@S |^@R " contract.gdla

# All constraints (enums + required fields)
grep -E "^@ENUM|required" contract.gdla

# Endpoints that return a specific schema
grep "^@EP.*Pet" contract.gdla

# Cross-API: all endpoints and their auth across all contracts
grep -E "^@EP|^@AUTH" *.gdla
```

## Tool Functions

Source the helpers:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/gdla-tools.sh"
```

| Function | Usage | What it does |
|----------|-------|-------------|
| `gdla_endpoints` | `gdla_endpoints [--method=M] [file.gdla]` | List endpoints, optionally filtered by method |
| `gdla_params` | `gdla_params "METHOD /path" [file.gdla]` | List parameters for an endpoint |
| `gdla_schemas` | `gdla_schemas [file.gdla]` | List schema names |
| `gdla_schema_fields` | `gdla_schema_fields SCHEMA [file.gdla]` | List fields for a schema |
| `gdla_auth` | `gdla_auth [file.gdla]` | List authentication schemes |
| `gdla_by_auth` | `gdla_by_auth SCHEME [file.gdla]` | Find endpoints requiring a specific auth scheme |
| `gdla_relationships` | `gdla_relationships [file.gdla]` | List @R relationship records |
| `gdla_paths` | `gdla_paths [file.gdla]` | List @PATH traversal records |

## Cross-Layer Search

| Function | Usage | What it does |
|----------|-------|-------------|
| `gdl_about` | `gdl_about TOPIC [dir] [--layer=gdla]` | Search across all GDL layers for TOPIC |

**Flags:**
- `--layer=gdla` — restrict to API contract layer
- `--exclude-layer=gdla` — skip API contracts
- `--summary` — show match counts only, no record content

## Key Rules

- `@EP` lines are complete — one grep returns the full endpoint with responses and auth
- `@S` blocks need `-A` context (like `@T` in GDLS) to see fields below the header
- `@P` lines follow their parent `@EP` — grep with context to see both
- `@AUTH`, `@R`, `@PATH`, `@ENUM` are single-line self-contained records
- Pipe within values is escaped as `\|` — use the tool functions for safe field extraction

## Bridge Tools

| Source | Bridge | Output |
|--------|--------|--------|
| OpenAPI JSON/YAML | `openapi2gdla.sh` | `.gdla` contract |
| GraphQL SDL | `graphql2gdla.sh` | `.gdla` contract |
| GDLA contract | `gdla2gdld.sh` | `.gdld` diagram |

## Visualization Pipeline

```bash
# OpenAPI → GDLA → GDLD → Mermaid
bash "${CLAUDE_PLUGIN_ROOT}/scripts/openapi2gdla.sh" spec.json --output=api/
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdla2gdld.sh" api/petstore.openapi.gdla > /tmp/api.gdld
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdld2mermaid.sh" /tmp/api.gdld
```
