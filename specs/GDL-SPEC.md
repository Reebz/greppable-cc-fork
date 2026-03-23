# GDL Specification v1.1

**Greppable Data Language** - A self-describing, key-value format for structured data records. Optimized for LLM agent querying using grep.

## Purpose

GDL is a deterministic data store for structured business records that agents query directly via grep, without needing an external database connection. Customer lists, order records, product catalogs, configuration data - anything an agent needs to look up by field value.

GDL is not for agent memory. See specs/GDLM-SPEC.md for the agent memory layer.

## Format

```
@type|key:value|key:value|key:value
```

| Element | Description |
|---------|-------------|
| `@type` | Record type prefix (enables `grep "^@type"` filtering) |
| `\|` | Field separator (pipe) |
| `key:value` | Self-describing field (no schema lookup needed) |
| One record per line | Streamable, appendable, diffable |

---

## Data Records

### Simple Records

```gdl
@customer|id:C001|name:Acme Inc|tier:enterprise|email:hello@acme.com
@customer|id:C002|name:Beta Corp|tier:startup|email:hi@beta.com
@customer|id:C003|name:Gamma Ltd|tier:growth|email:info@gamma.io
```

### Multi-Type Files

Different record types coexist naturally in one file:

```gdl
@customer|id:C001|name:Acme Inc|tier:enterprise
@customer|id:C002|name:Beta Corp|tier:startup
@order|id:O001|customer:C001|amount:4500.00|status:completed|date:2026-01-15
@order|id:O002|customer:C001|amount:2200.00|status:pending|date:2026-01-20
@order|id:O003|customer:C002|amount:890.00|status:completed|date:2026-01-18
```

### Relational References

Foreign keys use the referenced record's ID as a plain value:

```gdl
@order|id:O001|customer:C001|amount:4500.00|status:completed
```

To find the customer for order O001: grep `id:C001` to resolve the reference. No special syntax needed.

### Updates

For deterministic data, updates replace the existing record. Since GDL is file-based, the standard approach is:

1. **Small datasets:** Rewrite the file with the updated record
2. **Large datasets:** Append the updated record with the same ID. When reading, latest occurrence wins (same as database upsert semantics).

```gdl
# Original
@customer|id:C001|name:Acme Inc|tier:enterprise
# Updated (appended later)
@customer|id:C001|name:Acme Inc|tier:growth
```

For reading the latest: `grep "id:C001" data.gdl | tail -1`

---

## Schema Declaration

Document record structure with optional `@schema` records:

### Basic Schema

```gdl
@schema|type:customer|fields:id,name,tier,email
@schema|type:order|fields:id,customer,amount,status,date
```

### Enhanced Schema

Add constraints as documentation hints (not enforcement):

```gdl
@schema|type:customer|fields:id,name,tier,email|required:id,name|enum.tier:enterprise,growth,startup
@schema|type:order|fields:id,customer,amount,status,date|required:id,customer,amount
```

| Field | Purpose | Example |
|-------|---------|---------|
| `fields:` | All field names | `fields:id,name,tier` |
| `required:` | Fields that should always be present | `required:id,name` |
| `enum.{field}:` | Allowed values for a field | `enum.tier:enterprise,growth,startup` |

### Two Schema Layers

| Layer | Purpose | Model | Example |
|-------|---------|-------|---------|
| **GDLS** | Relational database schemas | Schema-on-write | `GL_ACCOUNT_ID\|BIGINT\|N\|PK` |
| **GDL @schema** | Key:value record documentation | Schema-on-read | `@schema\|type:customer\|required:id,name` |

GDLS describes what databases enforce. GDL @schema describes what records look like.

Schema lines are optional. GDL records are self-describing by design.

---

## File Organization

```
data/
  customers.gdl             # Customer records
  orders.gdl                # Order records
  products.gdl              # Product catalog
  config.gdl                # Configuration data
```

For large datasets, shard by domain or type:

```
data/
  sales/
    customers.gdl
    orders.gdl
    quotes.gdl
  inventory/
    products.gdl
    warehouses.gdl
    stock.gdl
```

---

## Grep Patterns

| Task | Command |
|------|---------|
| Find by type | `grep "^@customer" data.gdl` |
| Find by field value | `grep "tier:enterprise" data.gdl` |
| Find by ID | `grep "id:C001" data.gdl` |
| Cross-reference | `grep "customer:C001" data.gdl` (finds all orders for C001) |
| Count by type | `grep -c "^@order" data.gdl` |
| Count by value | `grep "status:completed" data.gdl \| wc -l` |
| Sum numeric field | `grep "^@order" data.gdl \| grep -o 'amount:[0-9.][0-9.]*' \| sed 's/^amount://' \| awk '{s+=$1}END{print s}'` |
| Latest record for ID | `grep "id:C001" data.gdl \| tail -1` |
| All records across files | `grep "tier:enterprise" data/*.gdl` |

---

## Escaping

When values contain `|` or `:`, escape with backslash:

```gdl
@product|id:P001|name:Type\:A Widget|desc:10\|20\|30 pack
```

| Character | Escape |
|-----------|--------|
| `\|` | Literal pipe in value |
| `\:` | Literal colon in value |
| `\\` | Literal backslash |

---

## File Conventions

| Convention | Value |
|------------|-------|
| Extension | `.gdl` |
| Encoding | UTF-8 |
| Line ending | LF |
| Comments | Lines starting with `#` or `//` |
| Blank lines | Allowed (ignored) |

### Version Header (Recommended)

Every GDL artifact file SHOULD include a version header comment:

```
# @VERSION spec:gdl v:1.1 generated:2026-02-15 source:manual
```

Fields:
- `spec` — format type (gdl, gdls, gdlc, gdld, gdlm, gdlu)
- `v` — spec version the file was generated against
- `generated` — date of generation (ISO 8601)
- `source` — generation method: `llm-inferred`, `ast-parsed`, `deterministic`, `manual`

This enables the linter to distinguish outdated artifacts from malformed ones,
and provides consumers with freshness and trust information.

### Accuracy Model

GDL artifacts span a spectrum from fully deterministic to LLM-approximate. The `source:` field in the `@VERSION` header communicates where an artifact sits on this spectrum:

| `source:` value | Meaning | Accuracy |
|-----------------|---------|----------|
| `ast-parsed` / `tree-sitter` | Generated from an AST parser or compiler | Exact — structural data is parsed, not inferred |
| `deterministic` | Computed from a fixed algorithm (e.g. schema introspection) | Exact |
| `manual` | Written by a human | Varies — human judgement, but intentional |
| `llm-inferred` | Generated by an LLM reading source material | Approximate — pattern-matched, not parsed |
| `agent` | Maintained by an agent over time (enrichment overlays) | Approximate for descriptions; curated over sessions |

**Why this matters.** When an agent generates a code map by reading source files, it is pattern-matching — not parsing an AST. Generic types get simplified, visibility is inferred from convention, overloaded functions may collapse, and complex unions get approximated. The `source:` field lets consumers know what level of trust to place in each artifact.

**The hybrid approach.** For formats with good tooling (e.g. TypeScript via tree-sitter), GDL uses a skeleton + enrichment split:

1. **Skeleton** (`source:tree-sitter`) — deterministic structure extracted from AST. Safe to regenerate. Contains `source-hash:` for staleness detection.
2. **Enrichment overlay** (`source:agent`) — semantic descriptions, flow annotations, and curated relationships. Preserved across regenerations.

This confines the approximate surface area to descriptions and semantic annotations, while structural data (names, types, visibility, imports) remains exact. See GDLC-SPEC for the full skeleton/enrichment specification.

**Consumer guidance:**
- Artifacts with `source:ast-parsed` or `source:tree-sitter` can be trusted for structural queries (member lookup, dependency tracing, import graphs).
- Artifacts with `source:llm-inferred` or `source:agent` should be treated as best-effort for descriptions and semantic relationships. Cross-reference with source code for high-stakes decisions.
- The `generated:` timestamp and `source-hash:` (where present) indicate freshness. Stale artifacts can be detected with `--check` flags on bridge tooling.

---

## Design Principles

1. **Self-describing** - Every record carries its field names. No schema lookup needed.
2. **Grep-first** - `@type` prefix enables instant filtering. `key:value` enables direct field matching.
3. **Deterministic** - Records represent facts. A customer record is a customer record.
4. **Multi-type native** - Different record types coexist in one file. `grep "^@type"` separates them.
5. **Bash-native** - Works with grep, cut, awk. No parsers or special tools required.

---

## Optimal Agent Prompt

```
Data specialist. Files: {data_path}/*.gdl

Format: @type|key:value|key:value - one self-describing record per line.

Grep "key:value" to find records. Grep "^@type" to filter by type.
```

**Token count:** ~36 tokens

---

## Comparison

| Aspect | GDL | CSV | JSON | YAML |
|--------|-----|-----|------|------|
| Self-describing | Yes (keys inline) | No (header row) | Yes | Yes |
| Multi-type files | Native (`@type`) | Awkward | Possible | Possible |
| Grep filtering | `grep "^@type"` | Manual | Needs `jq` | Needs `yq` |
| Field search | `grep "key:value"` | Position-based | Needs `jq` | Needs `yq` |
| Append-safe | Yes (line-oriented) | Yes | No (must close `]`) | No (indentation) |
| Git-diffable | Yes (one line = one record) | Yes | Noisy diffs | Moderate |
| Token efficiency | High | High | Low (+60-70%) | Medium (+30%) |

---

## Relationship to GDLS and Memory

GDLS, GDL, Memory, Diagram, and Code are sibling formats in the same language family:

| | GDLS | GDL | Memory | Diagram | Code | Documents |
|--|------|-----|--------|---------|------|-----------|
| Purpose | Schema and relationships | Deterministic data records | Agent knowledge and state | Visual knowledge | File-level code index | Unstructured content index |
| Fields | Positional | Key:value | Key:value + memory-specific | Key:value + diagram vocab | Positional (5-field files) | Key:value (`@source`, `@section`, `@extract`) |
| Extension | `.gdls` | `.gdl` | `.gdlm` | `.gdld` | `.gdlc` | `.gdlu` |
| Content | Structure of systems | Facts about entities | Observations, decisions, context | Architecture flows, patterns | Files, exports, imports | PDFs, transcripts, media indexes |
| Shared | `@` prefix, `\|` delimiter, line-oriented, grep-first |
