# GDLA Specification v0.1

**GDL API** — A positional, pipe-delimited format for representing API contracts — endpoints, schemas, parameters, authentication, and traversal paths. Optimized for LLM agent navigation using grep.

## Purpose

GDLA provides agents with a complete structural map of an API contract. This includes:

- **Service domains** — API identity, version, base URL (`@D`)
- **Schemas** — Request/response data structures with typed fields (`@S`, indented fields)
- **Endpoints** — Operations with HTTP verbs or GraphQL operations (`@EP`)
- **Parameters** — Query, path, header, and body parameters (`@P`)
- **Authentication** — Security schemes and headers (`@AUTH`)
- **Constrained values** — Enum definitions for closed sets (`@ENUM`)
- **Relationships** — Schema-to-schema dependencies (`@R`)
- **Traversal paths** — Multi-hop API navigation chains (`@PATH`)

An agent reading GDLA can understand the full surface area of an API without parsing OpenAPI YAML, GraphQL SDL, or Swagger JSON.

GDLA is not for database schemas (that's GDLS), not for runtime behaviour or API call logs.

---

## Scope and Limitations

### Where GDLA adds the most value

- **Large API contracts** (100+ endpoints, 50+ schemas) where agents need to grep for specific operations without loading the entire spec into context.
- **Cross-API queries** ("find all endpoints that require auth", "what schemas reference User?") where a single grep across `**/*.gdla` replaces format-specific parsing.
- **API-to-database mapping** — combining GDLA with GDLS enables tracing from API endpoint to database table via cross-layer references.

### Where GDLA adds moderate value

- **Small APIs** (< 20 endpoints) where the full OpenAPI spec fits in a single context window.
- **Stable APIs** that rarely change — the indexing cost may not be justified by query frequency.

### Where GDLA adds little value

- **Internal function calls** — GDLA captures contract structure, not code-level call graphs.
- **Runtime API monitoring** — GDLA captures contract structure, not runtime behaviour.

### Known v0.1 limitations

- **`$ref` depth**: OpenAPI `$ref` resolution captures schema names and relationships, not fully expanded trees. Query the referenced `@S` for nested field details.
- **`discriminator`**: Polymorphic type mapping (OpenAPI `discriminator`) is deferred to v0.2.
- **External `$ref`**: References to external files emit stub `@S` records with `[external: filename]` descriptions.
- **Nested objects**: Represented by `$ref` target name in type field (e.g., `items|LineItem[]|required`).

---

## Format

GDLA records use positional pipe-delimited fields (like GDLS):

```
@D service-name|description|version|base-url
@S SchemaName|description
 field|type|required|format|description
@EP METHOD /path|description|responses|auth
@P param|location|type|required|description
@R Source -> Target|relationship|via field
@AUTH scheme|description|header
@ENUM EnumName|value1,value2,value3
@PATH A -> B -> C|via /path/{id}/subpath
```

### File Extension

| Convention | Value |
|------------|-------|
| Extension | `.gdla` |
| Encoding | UTF-8 |
| Line ending | LF |
| Comments | Lines starting with `#` or `//` |
| Blank lines | Allowed (ignored) |

### Escaping

GDLA inherits GDL's escaping rules:

| Character | Escape | Notes |
|-----------|--------|-------|
| `\|` | Literal pipe in value | Common in description fields |
| `\:` | Literal colon in value | Rare in GDLA |
| `\\` | Literal backslash | |

### File Placement

GDLA index files live alongside API definitions or in a dedicated directory:

```
project/
├── api/
│   ├── openapi.yaml            # Source spec
│   ├── api-contracts.gdla      # GDLA index
│   └── graphql/
│       ├── schema.graphql      # Source SDL
│       └── graphql-ops.gdla    # GDLA index (operations only)
```

Convention: One `.gdla` file per API service. For cross-API queries, agents grep across `**/*.gdla`.

---

## Record Types

### @D — API Domain

Declares an API service. One `@D` per service per file.

```
@D service-name|description|version|base-url
```

| Position | Field | Required | Description |
|----------|-------|----------|-------------|
| 1 | Service name | Yes | API identifier (e.g., `petstore-api`) |
| 2 | Description | Yes | What this API does |
| 3 | Version | No | API version (e.g., `3.0.1`, `v2`) |
| 4 | Base URL | No | Base URL or server path |

**Note:** GDLA `@D` has 4 fields, unlike GDLS `@D` which has 2 fields. The file extension disambiguates.

#### Examples

```gdla
@D petstore-api|Pet store management API|3.0.1|https://api.petstore.io/v1
@D user-service|User authentication and profile management|2.0|/api/v2
```

---

### @S — Schema Definition

Declares a data schema (request body, response type, component). Followed by indented field lines that bind to this schema.

```
@S SchemaName|description
```

| Position | Field | Required | Description |
|----------|-------|----------|-------------|
| 1 | Schema name | Yes | Type name (e.g., `User`, `OrderResponse`) |
| 2 | Description | No | What this schema represents |

### Schema Fields (indented)

Indented lines (leading space) below an `@S` record are schema fields belonging to that schema.

```
 field|type|required|format|description
```

| Position | Field | Required | Description |
|----------|-------|----------|-------------|
| 1 | Field name | Yes | Property name |
| 2 | Type | Yes | Data type (`string`, `integer`, `User[]`, etc.) |
| 3 | Required | No | `required` or empty |
| 4 | Format | No | Format hint (`email`, `date-time`, `uuid`, etc.) |
| 5 | Description | No | What this field represents |

**Orphan handling:** Indented field lines before any `@S` record → linter warns, parser ignores.

#### Examples

```gdla
@S Pet|A pet in the store
 id|integer|required|int64|Unique pet identifier
 name|string|required||Pet display name
 status|string||enum|Pet status in the store
 tags|Tag[]|||Optional classification tags

@S Error|Standard error response
 code|integer|required|int32|HTTP status code
 message|string|required||Error description
```

---

### @EP — Endpoint

Declares an API operation. The METHOD field accepts both HTTP verbs and GraphQL operations.

```
@EP METHOD /path|description|responses|auth
```

| Position | Field | Required | Description |
|----------|-------|----------|-------------|
| 1 | Method + Path | Yes | `METHOD /path` (e.g., `GET /pets/{petId}`, `QUERY users`) |
| 2 | Description | No | What this endpoint does |
| 3 | Responses | No | Response codes and types (e.g., `200:Pet,404:Error`) |
| 4 | Auth | No | Required auth scheme (e.g., `api_key`, `bearer`) |

**Valid methods:**
- HTTP verbs: `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS`
- GraphQL operations: `QUERY`, `MUTATION`, `SUBSCRIPTION`

**Method extraction:** The first pipe field is split on the first space → method + path.

#### Examples

```gdla
@EP GET /pets|List all pets|200:Pet[],400:Error|api_key
@EP POST /pets|Create a new pet|201:Pet,400:Error|bearer
@EP GET /pets/{petId}|Get pet by ID|200:Pet,404:Error|api_key
@EP DELETE /pets/{petId}|Delete a pet|204:,404:Error|bearer
@EP QUERY users|Fetch user list|200:User[]|bearer
@EP MUTATION createUser|Create a new user|200:User|bearer
```

---

### @P — Parameter

Declares a parameter for the preceding `@EP` endpoint. `@P` lines bind to the most recent `@EP`.

```
@P param|location|type|required|description
```

| Position | Field | Required | Description |
|----------|-------|----------|-------------|
| 1 | Parameter name | Yes | Param identifier |
| 2 | Location | Yes | `query`, `path`, `header`, `cookie`, `body` |
| 3 | Type | Yes | Data type |
| 4 | Required | No | `required` or empty |
| 5 | Description | No | What this parameter does |

**Orphan handling:** `@P` before any `@EP` → linter warns, parser ignores.

#### Examples

```gdla
@EP GET /pets|List all pets|200:Pet[]|api_key
@P limit|query|integer||Maximum number of items to return
@P offset|query|integer||Number of items to skip
@EP GET /pets/{petId}|Get pet by ID|200:Pet,404:Error|api_key
@P petId|path|string|required|The pet identifier
```

---

### @AUTH — Authentication Scheme

Declares a security scheme used by the API.

```
@AUTH scheme|description|header
```

| Position | Field | Required | Description |
|----------|-------|----------|-------------|
| 1 | Scheme name | Yes | Identifier (e.g., `api_key`, `bearer`, `oauth2`) |
| 2 | Description | No | How this auth works |
| 3 | Header | No | Header or location (e.g., `Authorization`, `X-API-Key`) |

#### Examples

```gdla
@AUTH api_key|API key authentication|X-API-Key
@AUTH bearer|JWT bearer token|Authorization
@AUTH oauth2|OAuth 2.0 implicit flow|Authorization
```

---

### @ENUM — Enumerated Values

Declares a closed set of allowed values.

```
@ENUM EnumName|value1,value2,value3
```

| Position | Field | Required | Description |
|----------|-------|----------|-------------|
| 1 | Enum name | Yes | Type name |
| 2 | Values | Yes | Comma-separated allowed values |

#### Examples

```gdla
@ENUM PetStatus|available,pending,sold
@ENUM OrderStatus|placed,approved,delivered
```

---

### @R — Relationship

Declares a dependency between schemas.

```
@R Source -> Target|relationship|via field
```

| Position | Field | Required | Description |
|----------|-------|----------|-------------|
| 1 | Source → Target | Yes | Arrow-separated schema names |
| 2 | Relationship type | No | `references`, `embeds`, `extends`, `oneOf`, `allOf` |
| 3 | Via field | No | Which field creates the relationship |

#### Examples

```gdla
@R Pet -> Tag|references|via tags
@R Order -> Pet|references|via petId
@R AdminUser -> User|extends|
@R SearchResult -> User|oneOf|
@R SearchResult -> Post|oneOf|
```

---

### @PATH — Traversal Path

Declares a multi-hop API navigation chain.

```
@PATH A -> B -> C|via /path/{id}/subpath
```

| Position | Field | Required | Description |
|----------|-------|----------|-------------|
| 1 | Entity chain | Yes | Arrow-separated entities or endpoints |
| 2 | Via description | No | The API path or description of traversal |

#### Examples

```gdla
@PATH User -> Order -> Pet|via /users/{id}/orders/{orderId}/pet
@PATH Store -> Inventory -> Pet|via /store/inventory → /pets/{petId}
```

---

### @VERSION — Format Header (Recommended)

Cross-format convention. Declares the spec version and generation metadata.

```
# @VERSION spec:gdla v:0.1.0 generated:YYYY-MM-DD source:openapi-bridge
```

This is a comment line (starts with `#`) containing structured metadata. Parsers scan the first 10 lines.

| Field | Required | Description |
|-------|----------|-------------|
| `spec` | Yes | Format identifier (`gdla`) |
| `v` | Yes | Spec version |
| `generated` | No | ISO date of generation |
| `source` | No | Generation method (`openapi-bridge`, `graphql-bridge`, `manual`, `agent`) |

---

## Block Structure

Records are grouped by context:

```gdla
# @VERSION spec:gdla v:0.1.0 generated:2026-02-18 source:openapi-bridge

@D petstore-api|Pet store management API|3.0.1|https://api.petstore.io/v1

@AUTH api_key|API key authentication|X-API-Key
@AUTH bearer|JWT bearer token|Authorization

@S Pet|A pet in the store
 id|integer|required|int64|Unique pet identifier
 name|string|required||Pet display name
 status|string||enum|Pet status in the store

@S Error|Standard error response
 code|integer|required|int32|HTTP status code
 message|string|required||Error description

@ENUM PetStatus|available,pending,sold

@EP GET /pets|List all pets|200:Pet[],400:Error|api_key
@P limit|query|integer||Maximum items
@P offset|query|integer||Skip count

@EP POST /pets|Create a new pet|201:Pet,400:Error|bearer
@P body|body|Pet|required|Pet to create

@EP GET /pets/{petId}|Get pet by ID|200:Pet,404:Error|api_key
@P petId|path|string|required|Pet identifier

@R Pet -> Tag|references|via tags
@R Order -> Pet|references|via petId

@PATH User -> Order -> Pet|via /users/{id}/orders/{orderId}/pet
```

**Binding rules:**
- Indented field lines bind to the preceding `@S`
- `@P` lines bind to the preceding `@EP`
- `@R`, `@AUTH`, `@ENUM`, `@PATH` are file-level (not bound to a block)

---

## Grep Patterns

### Finding Endpoints

```bash
# All endpoints
grep "^@EP" *.gdla

# GET endpoints only
grep "^@EP GET" *.gdla

# All endpoints for a path pattern
grep "^@EP.*\/pets" *.gdla

# Endpoints requiring auth
grep "^@EP.*|bearer" *.gdla

# GraphQL queries
grep "^@EP QUERY" *.gdla
```

### Finding Schemas

```bash
# All schema definitions
grep "^@S" *.gdla

# Specific schema
grep "^@S Pet|" *.gdla

# Fields of a specific schema (requires context)
grep -A 20 "^@S Pet|" *.gdla | grep "^ "
```

### Finding Parameters

```bash
# All required parameters
grep "^@P.*|required|" *.gdla

# Path parameters
grep "^@P.*|path|" *.gdla

# Query parameters
grep "^@P.*|query|" *.gdla
```

### Relationships

```bash
# All relationships
grep "^@R" *.gdla

# What references Pet?
grep "^@R.*-> Pet|" *.gdla

# What does Order reference?
grep "^@R Order ->" *.gdla
```

### Authentication

```bash
# All auth schemes
grep "^@AUTH" *.gdla

# Bearer token endpoints
grep "^@EP.*|bearer$" *.gdla
```

### Cross-Format

```bash
# API endpoint for a database table
grep "^@S User|" api/*.gdla
grep "^@T USER_ACCOUNT " schemas/*.gdls
```

---

## Design Principles

1. **Grep-first** — `@D`, `@S`, `@EP`, `@P`, `@R`, `@AUTH`, `@ENUM`, `@PATH` prefixes enable instant type filtering.
2. **Positional efficiency** — Fixed field positions per record type eliminate key-name overhead.
3. **Context-complete** — `grep -A 20 "^@EP GET /pets"` returns the endpoint plus its parameters in one call.
4. **Method-aware** — HTTP verbs and GraphQL operations share the same `@EP` record, unifying REST and GraphQL queries.
5. **Bash-native** — Works with grep, cut, awk directly, no parsers needed.
6. **Family-parallel** — Shares `@R`, `@PATH`, `@ENUM` with GDLS for agents that already know that format.

---

## Relationship to GDL Family

GDLA and its siblings are formats in the same language family:

| Format | Extension | Purpose | Record Style |
|--------|-----------|---------|-------------|
| GDLS | `.gdls` | Schema maps (tables, relationships) | Positional (`@D`, `@T`, `@R`, `@PATH`, `@E`) |
| GDL | `.gdl` | Structured data records | Key-value (`@type\|key:value`) |
| GDLD | `.gdld` | Visual knowledge (diagrams) | Key-value (`@diagram`, `@node`, `@edge`) |
| GDLU | `.gdlu` | Unstructured content index | Key-value (`@source`, `@section`, `@extract`) |
| **GDLA** | **`.gdla`** | **API contract maps** | **Positional (`@D`, `@S`, `@EP`, `@P`, `@R`)** |

GDLS tells agents what databases look like. **GDLA tells agents what APIs look like.** The two positional formats share `@R` for relationships and `@PATH` for traversal, enabling cross-layer queries.

**Key differences from GDLS:**
- `@D` has 4 fields (service + description + version + base-url) vs 2 fields in GDLS
- `@S` is unique to GDLA for schema definitions (distinct from GDLS tables)
- `@EP` is unique to GDLA (endpoints with HTTP/GraphQL methods)
- `@P` is unique to GDLA (API parameters bound to endpoints)
- `@AUTH` is unique to GDLA (authentication schemes)

---

## Generation Pipeline

### Bridge-Generated Skeletons

GDLA files are typically generated by bridge scripts, then optionally enriched by agents:

1. **OpenAPI bridge** (`openapi2gdla.sh`): Parses OpenAPI 2.0/3.0/3.1 specs (YAML or JSON) → GDLA
2. **GraphQL bridge** (`graphql2gdla.sh`): Parses GraphQL SDL → GDLA (operations only; types → GDLS)

Bridge output includes `# @VERSION` headers with `source:openapi-bridge` or `source:graphql-bridge`.

### Agent Enrichment

Agents can enrich bridge-generated GDLA with:
- Better descriptions on `@EP` and `@S` records
- `@PATH` records for key API navigation flows
- Cross-layer `@R` references linking to GDLS entities

---

## Visualization

```
GDLA → gdla2gdld.sh → GDLD → gdld2mermaid.sh → Mermaid
```

The `gdla2gdld` converter maps:
- `@D` → `@group` (service group)
- `@S` → `@node` shape:box (schema)
- `@EP` → `@node` shape:diamond (endpoint, labeled `METHOD /path`)
- `@R` → `@edge` type:data
- `@AUTH` → `@node` in "auth" group
- `@PATH` → chain of `@edge` records

---

## Optimal Agent Prompt

### Minimal (~40 tokens)

```
API contracts: **/*.gdla — grep "^@EP METHOD" for endpoints, "^@S Name|" for schemas, "^@P" for params, "^@AUTH" for auth. Cross-ref with GDLS for database mapping.
```

### With bridge usage (~70 tokens)

```
API contracts: **/*.gdla — grep "^@EP" for endpoints, "^@S" for schemas.
To index: run openapi2gdla.sh or graphql2gdla.sh. Output: @D (domain), @S (schemas with indented fields), @EP (endpoints), @P (params), @AUTH, @ENUM, @R, @PATH.
```

---

## Out of Scope

- Runtime API behaviour (latency, error rates, call logs)
- API versioning strategy or migration paths
- Rate limiting rules or quota definitions
- WebSocket or streaming protocol specifics
- Full recursive `$ref` inlining (by design — GDLA captures structure, not expanded trees)
- OpenAPI `discriminator` polymorphism (deferred to v0.2)
