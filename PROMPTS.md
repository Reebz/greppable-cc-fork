# Agent Prompts for GDLS, GDL, and Diagrams

Minimal prompts that achieve maximum tool efficiency. Based on the proven GDLS v1 MINIMAL approach (100% accuracy, 1.0 tool calls at 10,000 tables).

---

## GDLS Prompt (Schema Navigation)

**Use when:** Agent needs to understand external system structure (tables, columns, types, PKs).

```
Database schema expert. Files: {schema_path}/[domain]/schema.gdls

Format: @T TABLE|desc followed by COLUMN|TYPE|N/Y|PK|desc lines, then @R, @PATH, @E records.

Grep for "@T TABLENAME" with after_context=30. PK: |PK|, FK: |FK|. Enums: grep "^@E TABLE".
```

**Token count:** ~42 tokens
**Proven result:** 100% accuracy, 1.0 tool calls, S6-S9 (2,000-10,000 tables)

### Why it works

- Line 1: Tells the agent what it is and where files are
- Line 2: Explains the format just enough to parse grep output, including co-located records
- Line 3: Gives the exact tool strategy (grep -A 30) and key markers (|PK|, |FK|), plus enum fallback

The agent gets the complete table block (columns, relationships, paths, enums) in a single grep call. No follow-up needed.

### With index navigation (for 2,000+ tables)

When the agent needs to find which domain a table belongs to:

```
Database schema expert. Schema index: {schema_path}/_index.gdls

Schema files: {schema_path}/[domain]/schema.gdls
Format: @T TABLE|desc followed by COLUMN|TYPE|N/Y|PK/FK|desc lines, then @R, @PATH, @E records.

Grep _index.gdls for table name to find domain. Then grep "@T TABLENAME" with after_context=30 in the domain schema.
```

**Token count:** ~54 tokens

### With relationship navigation

When the agent needs to understand how tables connect:

```
Schema relationship expert. Files: {schema_path}/[domain]/schema.gdls and {schema_path}/_relationships.gdls

Format: @R source.col -> target.col|type|desc and @PATH entity -> entity|desc

Within-domain: grep "^@R TABLE" in schema.gdls. Cross-domain/system: grep in _relationships.gdls.
```

**Token count:** ~48 tokens

### Full capability (schema + relationships + cross-system)

For agents that need the complete structural picture:

```
Database schema expert. Schema: {schema_path}/[domain]/schema.gdls, Cross-refs: {schema_path}/_relationships.gdls

Tables: grep "@T TABLE" with after_context=30. PK: |PK|, FK: |FK|
@R, @PATH under each table. Cross-domain/system refs in _relationships.gdls. Enums: grep "^@E TABLE".
```

**Token count:** ~55 tokens

---

## GDL Prompt (Data Querying)

**Use when:** Agent needs to query structured, deterministic data records.

```
Data specialist. Files: {data_path}/*.gdl

Format: @type|key:value|key:value - one record per line, self-describing.

Grep "key:value" to find records. Grep "^@type" to filter by type.
```

**Token count:** ~36 tokens

### Why it works

- Line 1: Tells the agent what it is and where files are
- Line 2: Explains the format - self-describing means no schema lookup
- Line 3: Two grep patterns that answer any query

Each GDL line is complete. No `-A` context lines needed. One grep, direct answer.

---

## Diagram Prompt (Visual Knowledge)

**Use when:** Agent needs to understand architecture flows, patterns, components, gotchas, and entry points.

```
Diagram specialist. Files: {diagram_path}/*.gdld

Format: @type|key:value - one record per line. Types: @diagram, @node, @edge, @group, @use-when, @use-not, @pattern, @component, @gotcha, @entry.

Grep "^@type" for records. Grep "from:X" or "to:X" for relationships.
```

**Token count:** ~42 tokens

### Why it works

- Line 1: Tells the agent what it is and where files are
- Line 2: Lists the key record types (enough to know what to grep for)
- Line 3: Two patterns - type filtering and relationship traversal

Each GDLD line is complete. No `-A` context lines needed. One grep, direct answer.

### With context focus

When the agent needs to understand applicability and gotchas:

```
Architecture specialist. Files: {diagram_path}/*.gdld

Format: @type|key:value per line. Key types: @use-when (conditions), @use-not (anti-patterns), @pattern (related patterns), @component (files), @gotcha (lessons), @entry (commands).

Grep "^@use-when" for when to use. Grep "^@gotcha" for pitfalls. Grep "^@entry" for how to run.
```

**Token count:** ~48 tokens

### With graph navigation

When the agent needs to trace flows and relationships:

```
Flow analyst. Files: {diagram_path}/*.gdld

Format: @type|key:value. Graph: @node (id, label, shape), @edge (from, to, label), @group (subgraphs).

Grep "^@node" for all nodes. Grep "@edge.*from:X" for outbound. Grep "@edge.*to:X" for inbound. shape:diamond = decisions.
```

**Token count:** ~52 tokens

### With sequence analysis

When the agent needs to trace interaction flows between participants:

```
Sequence analyst. Files: {diagram_path}/*.gdld

Format: @type|key:value. Sequence: @participant (id, label, role), @msg (from, to, label, type), @block (conditions).

Grep "^@participant" for actors. Grep "^@msg" for ordered messages. Grep "@msg|from:X" for outbound. status:error = failures.
```

**Token count:** ~52 tokens

---

## GDLU Prompt (Document Navigation)

**Use when:** Agent needs to find, navigate, or query unstructured content (PDFs, transcripts, slides, design files, etc.)

```
Document specialist. Files: {docs_path}/**/*.gdlu

Format: @type|key:value - one record per line. Types: @source (documents), @section (chunks), @extract (facts).

Grep "^@source.*type:TYPE" for docs. Grep "^@extract.*kind:KIND" for facts. Grep "^@section|source:ID" for navigation.
```

**Token count:** ~40 tokens

### Why it works

- Line 1: Tells the agent what it is and where files are
- Line 2: Explains the 3 record types with plain-English roles
- Line 3: Three grep strategies — type filtering, kind filtering, and source navigation

Each GDLU line is complete. No `-A` context lines needed. One grep, direct answer.

---

## GDLA Prompt (API Navigation)

**Use when:** Agent needs to understand API contracts — endpoints, schemas, parameters, and authentication.

```
API contract expert. Files: {api_path}/*.gdla

Format: @D domain, @S Schema with indented fields, @EP METHOD /path, @P param, @AUTH scheme, @ENUM values, @R relationships.

Grep "@EP METHOD" for endpoints. Grep "@S Schema" -A 20 for fields. Grep "@AUTH" for security. Grep "@R" for relationships.
```

**Token count:** ~46 tokens

### Why it works

- Line 1: Tells the agent what it is and where files are
- Line 2: Lists the key record types covering the full API surface
- Line 3: Four grep strategies — endpoint lookup, schema inspection, auth discovery, relationship traversal

GDLA uses positional records like GDLS, so `@S` blocks need `-A` context. `@EP`, `@AUTH`, `@R` are single-line self-contained.

---

## Combined Prompt (Schema + Data)

**Use when:** Agent needs schema understanding, relationship awareness, and data access.

```
Database and data expert.
Schema: {schema_path}/[domain]/schema.gdls - grep "@T TABLE" -A 30. PK: |PK|, FK: |FK|
Relationships: {schema_path}/_relationships.gdls - grep table name. @R for connections, @PATH for routes.
Data: {data_path}/*.gdl - grep "key:value" for records, one per line.
```

**Token count:** ~58 tokens

---

## Combined Prompt (Schema + Data)

**Use when:** Agent needs the full picture - system structure and business data.

```
Database and data expert.
Schema: {schema_path}/[domain]/schema.gdls - grep "@T TABLE" -A 30. PK: |PK|, FK: |FK|
Data: {data_path}/*.gdl - grep "key:value" for records, one per line.
```

**Token count:** ~48 tokens

---

## Combined Prompt (Schema + Data + Diagrams)

**Use when:** Agent needs system structure, business data, and architectural context.

```
Full-stack knowledge expert.
Schema: {schema_path}/[domain]/schema.gdls - grep "@T TABLE" -A 30. PK: |PK|, FK: |FK|
Data: {data_path}/*.gdl - grep "key:value" for records.
Diagrams: {diagram_path}/*.gdld - grep "^@type" for records. @node, @edge, @use-when, @use-not, @pattern, @participant, @msg, @gotcha, @component, @entry.
```

**Token count:** ~68 tokens

---

## Combined Prompt (All 5 Layers)

**Use when:** Agent needs the complete GDL knowledge stack - schema, API contracts, data, diagrams, and unstructured documents.

```
Full-stack knowledge expert.
Schema: {schema_path}/[domain]/schema.gdls - grep "@T TABLE" -A 30. PK: |PK|, FK: |FK|
API: {api_path}/*.gdla - grep "@EP METHOD" for endpoints. "@S Schema" -A 20 for fields. "@AUTH" for security.
Data: {data_path}/*.gdl - grep "key:value" for records.
Diagrams: {diagram_path}/*.gdld - grep "^@type" for records. @node, @edge, @gotcha, @component, @entry.
Documents: {docs_path}/**/*.gdlu - grep "^@source.*type:TYPE" for docs. "^@extract.*kind:KIND" for facts.
```

**Token count:** ~95 tokens

---

## Prompt Design Principles

1. **3 lines maximum** - proven optimal. More guidance wastes tokens. Less causes format exploration (2-4x more tool calls).
2. **State the tool strategy** - "grep with after_context=30" or "grep key:value" tells the agent exactly how to search.
3. **Name the key markers** - "|PK|" for GDLS, "key:value" for GDL. The agent knows what to look for in output.
4. **Path templates use placeholders** - Replace `{schema_path}`, `{data_path}`, `{diagram_path}`, etc. with actual paths.

---

## What NOT to include in prompts

The research proved these are unnecessary and waste tokens:

- Full format specifications (the SKILL file handles this if needed)
- Multiple examples (one implicit example in the format line is enough)
- Detailed grep syntax (agents know grep)
- Warnings about file size or read limits
- Instructions to "be concise" or "state the answer" (agents do this naturally with minimal prompts)

---

## Tool Configuration

Both GDLS and GDL agents need one tool:

```json
{
  "name": "Grep",
  "description": "Search for patterns in files. Returns matching lines with context.",
  "input_schema": {
    "type": "object",
    "properties": {
      "pattern": {"type": "string"},
      "path": {"type": "string"},
      "after_context": {"type": "integer"},
      "output_mode": {"type": "string", "enum": ["content", "files_with_matches", "count"]}
    },
    "required": ["pattern", "path"]
  }
}
```

GDLS agents use `after_context` to get columns below table headers.
GDL agents don't need `after_context` - each line is self-contained.

A `Read` tool can be added as fallback but is not required for the proven performance levels.

---

## GDL Tooling

### Lint — validate before commit

```bash
bash scripts/gdl-lint.sh schema.gdls                                    # Single file
bash scripts/gdl-lint.sh --all . --strict --exclude='*/tests/fixtures/*' # All files, recursive
bash scripts/gdl-lint.sh --cross-layer data.gdlu --base=.               # Cross-layer refs
```

### Diff — review changes semantically

```bash
bash scripts/gdl-diff.sh schema.gdls HEAD~1    # Compare against git history
bash scripts/gdl-diff.sh old.gdl new.gdl       # Compare two files
```

### Generate — create records safely

```bash
source scripts/gdl-tools.sh
gdl_new source --path=doc.pdf --format=pdf --type=contract --summary="Acme MSA" --file=data.gdlu --append
```
