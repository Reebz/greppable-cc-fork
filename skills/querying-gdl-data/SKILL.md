---
name: querying-gdl-data
description: "Use when working with structured business data records — orders, invoices, products, or any @type records in .gdl files. Covers: filtering records by field values, aggregating data by region/status/category, cross-referencing between record types, extracting specific fields, or converting GDL data to CSV/JSON. Triggers on: \"show me all orders over X\", \"filter by status\", \"aggregate by region\", business data queries, or direct .gdl file operations. NOT for SQL database queries, .gdls schema maps, or .gdlm memory files."
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
context: fork
---

# GDL Quick Reference

## Available Data Files

!`bash -c 'find docs/gdl -name "*.gdl" -not -name "rules.gdl" -maxdepth 3 2>/dev/null | while read f; do count=$(grep -c "^@" "$f" 2>/dev/null || echo 0); echo "- $f ($count records)"; done'`

## Format

```
@type|key:value|key:value|key:value
```

Every record is one line. Every field is self-describing (key:value). No schema lookup needed.

## Grep Patterns

```bash
# Filter by record type
grep "^@customer" data.gdl

# Find by field value
grep "tier:enterprise" data.gdl

# Find by ID
grep "id:C001" data.gdl

# Cross-reference (find orders for customer C001)
grep "customer:C001" data.gdl

# Count records
grep -c "^@order" data.gdl

# Sum numeric field
grep "^@order" data.gdl | grep -o 'amount:[0-9.][0-9.]*' | sed 's/^amount://' | awk '{s+=$1}END{print s}'

# Latest version of a record (if appended updates)
grep "id:C001" data.gdl | tail -1
```

## Example

```gdl
@customer|id:C001|name:Acme Inc|tier:enterprise|email:hello@acme.com
@customer|id:C002|name:Beta Corp|tier:startup|email:hi@beta.com
@order|id:O001|customer:C001|amount:4500.00|status:completed|date:2026-01-15
@order|id:O002|customer:C002|amount:890.00|status:pending|date:2026-01-20
```

## Escaping

`\|` = literal pipe, `\:` = literal colon, `\\` = literal backslash.

## Tool Functions

Source the helpers:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-tools.sh"
```

| Function | Usage | What it does |
|----------|-------|-------------|
| `csv2gdl` | `csv2gdl TYPE FILE` | Convert CSV to GDL records |
| `json2gdl` | `json2gdl TYPE FILE` | Convert JSON array or JSONL to GDL records. Supports stdin via `-`. Requires `jq`. |
| `gdl_describe` | `gdl_describe FILE` | Describe record types and sample records in a GDL file |
| `gdl_latest` | `gdl_latest ID FILE` | Get latest version of a record by ID |
| `gdl_values` | `gdl_values TYPE FIELD FILE` | List unique values for a field |

## Cross-Layer Search

| Function | Usage | What it does |
|----------|-------|-------------|
| `gdl_about` | `gdl_about TOPIC [dir] [--layer=L] [--exclude-layer=L] [--summary] [--regex] [--ignore-case]` | Search across all GDL layers for TOPIC |

**Flags:**
- `--layer=gdl|gdls|gdlc|gdla|gdld|gdlm|gdlu` — restrict to one layer
- `--exclude-layer=LAYERS` — skip comma-separated layers
- `--summary` — show match counts only, no record content
- `--regex` / `-E` — extended regex matching
- `--ignore-case` / `-i` — case-insensitive search

## Key Rules

- Each line is a complete, self-describing record
- `grep "key:value"` directly answers queries - no context lines needed
- Multiple record types coexist in one file
- References use plain ID values (e.g., `customer:C001`)

## Null Convention

Distinguish between explicit absence and missing fields:

| Pattern | Meaning | Use Case |
|---------|---------|----------|
| `email:null` | Explicit absence | "We asked, they have no email" |
| No `email:` field | Not applicable | "We didn't collect this field" |

```bash
# Find records with explicitly null email
grep "email:null" data.gdl

# Find records without email field
grep "^@customer" data.gdl | grep -v "email:"
```

## Recommended Field Names

Use consistent field names across files for easier cross-file queries:

| Field | Purpose | Example |
|-------|---------|---------|
| `id:` | Primary identifier | `id:C001` |
| `name:` | Human-readable name | `name:Acme Inc` |
| `ts:` | Timestamp (ISO 8601) | `ts:2026-02-02T14:30:00Z` |
| `status:` | Current state | `status:active` |
| `source:` | Data provenance | `source:crm-export-2026-02-01` |
| `type:` | Record subtype | `type:enterprise` |
| `author:` | Creator/modifier | `author:agent-sf-042` |

These are conventions, not requirements. GDL remains flexible.

## Wide Records Principle

Include all relevant context in each record so a single grep returns complete information:

```gdl
# Good: Wide record with full context
@order|id:O001|customer:C001|customer_name:Acme Inc|amount:4500.00|status:completed|date:2026-01-15|rep:Jane Smith

# Avoid: Narrow record requiring follow-up queries
@order|id:O001|customer:C001|amount:4500.00
```

**Why:** Single grep = single tool call. Wide records align with GDL's "1 grep per query" philosophy.

**Note:** "Wide" means relevant context, not every possible field. Include what an agent would need to answer questions about this record.

## Analytical Patterns

Simple aggregations work with grep + standard Unix tools:

```bash
# Count records by type
grep -c "^@customer" data.gdl

# Distinct values for a field
grep "^@customer" data.gdl | grep -o 'tier:[^|]*' | sed 's/^tier://' | sort -u

# Count by field value
grep "^@order" data.gdl | grep -o 'status:[^|]*' | sed 's/^status://' | sort | uniq -c

# Sum numeric field
grep "^@order" data.gdl | grep -o 'amount:[0-9.][0-9.]*' | sed 's/^amount://' | awk '{s+=$1}END{print s}'

# Filter and count
grep "status:completed" data.gdl | wc -l
```

**When to use DuckDB instead:**

For GROUP BY, JOINs, window functions, or complex aggregations, convert to CSV and use DuckDB:

```bash
# Complex analytics → use DuckDB
duckdb -c "SELECT status, COUNT(*), SUM(amount) FROM read_csv('orders.csv') GROUP BY status"
```

GDL excels at lookup and simple counts. SQL excels at analytics.

## Converting Between GDL and JSONL

**GDL → JSONL:**

```bash
# Simple conversion (assumes no nested colons in values)
grep "^@customer" data.gdl | sed 's/^@customer|//' | awk -F'|' '{
  printf "{";
  for(i=1;i<=NF;i++) {
    split($i,kv,":");
    printf "\"%s\":\"%s\"", kv[1], kv[2];
    if(i<NF) printf ",";
  }
  print "}"
}'
```

**JSONL → GDL:**

```bash
# Using jq
cat data.jsonl | jq -r '"@customer|id:\(.id)|name:\(.name)|tier:\(.tier)"'
```

**Use case:** Store in GDL (human-readable, greppable), export to JSONL for AI batch APIs (OpenAI, Anthropic).

## Discovering Schema

GDL is self-describing. Infer schema from existing records:

```bash
# List all record types in a file
cut -d'|' -f1 data.gdl | sort -u

# Show fields for a record type (from first record)
grep "^@customer" data.gdl | head -1 | tr '|' '\n' | tail -n +2 | cut -d':' -f1

# Count field usage across all records of a type
grep "^@customer" data.gdl | tr '|' '\n' | grep ':' | cut -d':' -f1 | sort | uniq -c | sort -rn

# Generate @schema from existing records
type="customer"
fields=$(grep "^@$type" data.gdl | head -1 | tr '|' '\n' | tail -n +2 | cut -d':' -f1 | tr '\n' ',' | sed 's/,$//')
echo "@schema|type:$type|fields:$fields"
```

Records ARE the schema. These patterns make it explicit.

## Tooling Recipes

### Blast Radius — What does an entity touch?

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-tools.sh"
gdl_about GL_ACCOUNT . --summary
```

Shows match counts across all GDL layers for an entity. Use before modifying to understand impact.

### Cross-Layer Coverage — One-liner audit

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-tools.sh"
for entity in GL_ACCOUNT GL_JOURNAL CUSTOMER; do
  echo "=== $entity ===" && gdl_about "$entity" . --summary
done
```

### Project Health Check

```bash
echo "=== File counts ==="
for ext in gdl gdls gdlc gdla gdld gdlm gdlu; do
  count=$(find . -name "*.$ext" | wc -l | tr -d ' ')
  echo "  .$ext: $count files"
done
echo "=== Lint ==="
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-lint.sh" --all . --exclude='*/tests/fixtures/*'
echo "=== Recent changes ==="
git log --oneline -5 -- '*.gdl' '*.gdls' '*.gdlc' '*.gdla' '*.gdld' '*.gdlm' '*.gdlu'
```

### Validate Before Commit

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-lint.sh" schema.gdls
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-lint.sh" --all . --strict --exclude='*/tests/fixtures/*'
```

### Semantic Diff — Review changes

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-diff.sh" schema.gdls HEAD~1
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-diff.sh" old.gdl new.gdl
```

### Generate Records Safely

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-tools.sh"
gdl_new memory --agent=sf-042 --subject=GL_ACCOUNT --detail="New column" --file=memory/active/systems.gdlm --append
gdl_new source --path=doc.pdf --format=pdf --type=contract --summary="Acme MSA" --file=data.gdlu --append
```

## Why GDL Works: External Validation

Filesystem + grep outperforms RAG for structured data retrieval:

**Vercel (2024):**
> "LLMs have been trained on massive amounts of code, spending countless hours navigating directories, grepping through files. If agents excel at filesystem operations for code, they'll excel at filesystem operations for anything."

**LlamaIndex Benchmark:**
- Filesystem agent: 8.4 correctness vs RAG 6.4 (+31%)
- Filesystem agent: 9.6 relevance vs RAG 8.0 (+20%)

**Letta/MemGPT LoCoMo Benchmark:**
- Filesystem + grep: 74.0%
- Mem0 specialized memory: 68.5%

**Why grep wins:**
- Deterministic (no hallucination)
- Zero infrastructure
- Pre-installed everywhere
- Agents already trained on grep patterns
