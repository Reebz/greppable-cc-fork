# GDLS Specification v1.1

**GDL Schema** - A positional, pipe-delimited format for representing database schemas and their relationships across enterprise systems. Optimized for LLM agent navigation using grep.

## Purpose

GDLS provides agents with a complete structural map of external systems. This includes:

- **Tables and columns** - What exists in each system (Snowflake, Databricks, Salesforce, etc.)
- **Within-system relationships** - How tables connect via foreign keys, hierarchies, and lookups
- **Cross-system relationships** - How entities map between systems (e.g., Salesforce Account = Snowflake CUSTOMER)
- **Traversal paths** - Multi-hop routes through related entities, within or across systems
- **Column value constraints** - What values are valid for specific columns (optional)

An agent reading GDLS can understand not just individual tables, but the full relational graph of an enterprise's data landscape.

## Performance

Table and column navigation tested at 2,000-10,000 tables with Claude Haiku 4.5:

| Scale | Tables | Accuracy | Tool Calls | Tokens |
|-------|--------|----------|------------|--------|
| S6 | 2,000 | 100% | 1.0 | 4,223 |
| S7 | 4,000 | 100% | 1.0 | 4,229 |
| S8 | 6,000 | 100% | 1.0 | 5,896 |
| S9 | 10,000 | 100% | 1.0 | 5,902 |

51% smaller file size than YAML. 18-23% fewer tokens per query.

---

## Core Format

### Domain Header

```
@D domain_name|description
```

Declares a domain (schema namespace). One per schema file.

```
@D finance|General ledger, accounts payable/receivable, billing, treasury
```

### Table Header

```
@T TABLE_NAME|description
```

Declares a table. Followed by column lines.

```
@T GL_ACCOUNT|Table storing gl account data
```

### Column Lines

```
COLUMN_NAME|SQL_TYPE|NULLABLE|KEY|DESCRIPTION
```

Positional fields (pipe-delimited):

| Position | Field | Values | Example |
|----------|-------|--------|---------|
| 1 | Column name | Any identifier | `GL_ACCOUNT_ID` |
| 2 | SQL type | Standard SQL types | `INTEGER`, `VARCHAR(50)`, `DECIMAL(18,2)` |
| 3 | Nullable | `N` (NOT NULL) or `Y` (nullable) | `N` |
| 4 | Key | `PK`, `FK`, `PK,FK`, or empty | `PK` |
| 5 | Description | Human-readable text | `Primary key for GL_ACCOUNT` |

Key markers:

| Marker | Meaning |
|--------|---------|
| `PK` | Primary key |
| `FK` | Foreign key (see `@R` declarations for target) |
| `PK,FK` | Column that is both primary key and foreign key (e.g., in junction tables) |
| (empty) | Regular column |

```
GL_ACCOUNT_ID|INTEGER|N|PK|Primary key for GL_ACCOUNT
GL_TEXT_1|VARCHAR(50)|Y||String identifier
GL_STATUS|VARCHAR(20)|N||Account status
GL_PARENT_ID|INTEGER|Y|FK|Parent account reference
GL_AMOUNT|DECIMAL(18,2)|Y||Currency amount
```

### Version Header (Optional)

Generated `.gdls` files MAY include a version header as the first line:

```
# @VERSION spec:gdls v:0.1.0 generated:2026-02-16 source:db-introspect source-hash:a1b2c3d source-path:db/schema.sql
```

Fields: `spec` (format name), `v` (spec version), `generated` (ISO date), `source` (how the file was created — e.g., `db-introspect`, `agent`, `manual`), optional `source-hash` (truncated SHA-256 of source), optional `source-path` (path to source file for live staleness comparison). Tools like `--check` strip `@VERSION` lines before comparing, since the `generated` date always differs.

### Format Header (Recommended)

Every `.gdls` file SHOULD include a format header comment as its first non-blank line (or immediately after `@VERSION`):

```
# @FORMAT COLUMN|SQL_TYPE|NULLABLE|KEY|DESCRIPTION
```

This makes the positional field order self-documenting. Agents and humans encountering the file for the first time can parse it without referencing the spec.

---

## Relationships

Relationships are declared with `@R` and define how tables connect. They are part of the GDLS specification but **optional in practice** - schemas work without them, and agents understand them naturally when present (the `@R source -> target` syntax is self-evident). Include relationships when agents need to generate multi-table joins or understand cross-system data flows. Omit them for simpler use cases where table/column navigation is sufficient.

### Format

```
@R source.column -> target.column|type|description
```

### Relationship Types

| Type | Meaning | Example |
|------|---------|---------|
| `fk` | Foreign key reference | Journal entry references an account |
| `equivalent` | Same entity across systems or names | Snowflake GL_ACCOUNT = Databricks gl_account |
| `feeds` | Data flows from source to target (ETL/sync) | Salesforce Account syncs to Snowflake nightly |
| `derives` | Target is computed/aggregated from source | Monthly summary derived from daily transactions |

### Within-System Relationships

Foreign keys between tables in the same system:

```gdls
@R GL_JOURNAL.GL_ACCOUNT_REF -> GL_ACCOUNT.GL_ACCOUNT_ID|fk|Journal account reference
@R GL_JOURNAL.CREATED_BY -> HR_EMPLOYEE.EMPLOYEE_ID|fk|Journal creator
@R AR_RECEIPT.GL_ACCOUNT_REF -> GL_ACCOUNT.GL_ACCOUNT_ID|fk|Receipt account
@R SO_LINE.SO_HEADER_ID -> SO_HEADER.SO_HEADER_ID|fk|Line to order header
@R SO_LINE.PRODUCT_ID -> PRODUCT.PRODUCT_ID|fk|Line item product
@R DEPARTMENT.PARENT_DEPT_ID -> DEPARTMENT.DEPT_ID|fk|Department hierarchy (self-ref)
```

Place within-domain `@R` declarations under the source table, along with `@PATH` and `@E` records. Ordering within a table block: columns → `@R` → `@PATH` → `@E`:

```gdls
@D finance|General ledger, accounts payable/receivable

@T GL_ACCOUNT|Account master data
GL_ACCOUNT_ID|INTEGER|N|PK|Primary key
GL_TEXT_1|VARCHAR(50)|Y||Account name
GL_STATUS|VARCHAR(20)|N||Account status
GL_PARENT_ID|INTEGER|Y|FK|Parent account
@R GL_ACCOUNT.GL_PARENT_ID -> GL_ACCOUNT.GL_ACCOUNT_ID|fk|Account hierarchy
@E GL_ACCOUNT.GL_STATUS|ACTIVE,INACTIVE,SUSPENDED|Account lifecycle states

@T GL_JOURNAL|Journal entries
GL_JOURNAL_ID|INTEGER|N|PK|Primary key
GL_JOURNAL_DATE|DATE|Y||Entry date
GL_AMOUNT|DECIMAL(18,2)|N||Amount
GL_ACCOUNT_REF|INTEGER|N|FK|Account reference
@R GL_JOURNAL.GL_ACCOUNT_REF -> GL_ACCOUNT.GL_ACCOUNT_ID|fk|Journal to account
@PATH GL_JOURNAL -> GL_ACCOUNT -> AR_RECEIPT|Journal to receipt via account

@T AR_RECEIPT|Accounts receivable receipts
AR_RECEIPT_ID|INTEGER|N|PK|Primary key
AR_AMOUNT|DECIMAL(18,2)|N||Receipt amount
AR_STATUS|VARCHAR(20)|N||Receipt status
GL_ACCOUNT_REF|INTEGER|N|FK|Account reference
@R AR_RECEIPT.GL_ACCOUNT_REF -> GL_ACCOUNT.GL_ACCOUNT_ID|fk|Receipt to account
@E AR_RECEIPT.AR_STATUS|PENDING,APPLIED,REVERSED,VOID|Receipt lifecycle
```

### Cross-System Relationships

When entities span systems, prefix with `system:`:

```gdls
@R snowflake:GL_ACCOUNT -> databricks:gl_account_v2|equivalent|Same entity, different naming
@R snowflake:CUSTOMER -> databricks:customer_analytics|derives|Analytics aggregated from source
@R salesforce:Account -> snowflake:CUSTOMER|feeds|Nightly ETL sync
@R salesforce:Contact -> snowflake:CUSTOMER_CONTACT|feeds|Real-time sync via Fivetran
@R snowflake:PRODUCT -> shopify:Product|equivalent|Product catalog master
```

Cross-system relationships live in a dedicated file at the schema root:

```
schema/
  _relationships.gdls      # All cross-system mappings
  snowflake/
    ...
  databricks/
    ...
```

### Cross-Domain Relationships

When tables in different domains within the same system reference each other:

```gdls
@R sales:SO_HEADER.CUSTOMER_ID -> finance:CUSTOMER.CUSTOMER_ID|fk|Order to customer
@R hr:EMPLOYEE.DEPT_ID -> finance:DEPARTMENT.DEPT_ID|fk|Employee department
```

Cross-domain relationships live in the system's root:

```
schema/
  snowflake/
    _relationships.gdls    # Cross-domain within Snowflake
    finance/
      schema.gdls          # Includes within-domain @R declarations
    hr/
      schema.gdls
    sales/
      schema.gdls
```

---

## Paths

Paths declare multi-hop traversal routes through related entities. Like `@R`, paths are **optional** - include them when agents regularly need to plan complex multi-join queries or cross-system data flows. The `@PATH A -> B -> C` syntax is self-evident and requires no prompt guidance.

### Format

```
@PATH entity -> entity -> entity -> entity|description
```

### Within-System Paths

```gdls
@PATH CUSTOMER -> SO_HEADER -> SO_LINE -> PRODUCT|Customer purchase history
@PATH EMPLOYEE -> DEPARTMENT -> COST_CENTER -> GL_ACCOUNT|Employee cost allocation
@PATH GL_JOURNAL -> GL_ACCOUNT -> AR_RECEIPT|Journal to receipt via account
```

### Cross-System Paths

```gdls
@PATH salesforce:Account -> snowflake:CUSTOMER -> snowflake:SO_HEADER -> snowflake:SO_LINE|CRM to order detail
@PATH salesforce:Opportunity -> snowflake:DEAL -> databricks:deal_analytics|Sales pipeline to analytics
@PATH shopify:Order -> snowflake:ECOM_ORDER -> databricks:revenue_summary|E-commerce to reporting
```

### Path Location

Paths are placed alongside their related relationships:

- Within-domain paths: under the source table in the domain `schema.gdls`
- Cross-domain paths: in the system `_relationships.gdls`
- Cross-system paths: in the root `_relationships.gdls`

---

## Index Files

For partitioned schemas at scale, index files provide navigation metadata.

### Format

```
@META tier_name|description|total_table_count

@DOMAIN domain_name|path/to/schema.gdls|description|table_count
@TABLES domain_name|TABLE1,TABLE2,TABLE3,...
```

### Example (`_index.gdls`)

```gdls
@META S6|Fortune 500 (8 domains)|2000

@DOMAIN finance|finance/schema.gdls|General ledger, accounts payable/receivable, billing, treasury|250
@TABLES finance|AP_ARCHIVE_14,AP_AUDIT_10,GL_ACCOUNT,GL_JOURNAL,AR_RECEIPT,BILL_CYCLE

@DOMAIN hr|hr/schema.gdls|Human resources, payroll, benefits, recruiting, training|250
@TABLES hr|EMP_MASTER,PAY_PERIOD,BENEFIT_PLAN,RECRUIT_APPLICATION

@DOMAIN sales|sales/schema.gdls|Sales orders, quotes, pricing, territories, commissions|200
@TABLES sales|SO_HEADER,SO_LINE,QUOTE_HEADER,PRICE_LIST,COMM_PLAN
```

---

## Directory Structure

```
schema/
  _relationships.gdls              # Cross-system relationships and paths
  snowflake/
    _index.gdls                    # Domain navigation index
    _relationships.gdls            # Cross-domain relationships within Snowflake
    finance/
      schema.gdls                  # Tables, columns, within-domain @R, @PATH, and @E
    hr/
      schema.gdls
    sales/
      schema.gdls
  databricks/
    _index.gdls
    _relationships.gdls
    warehouse/
      schema.gdls
  salesforce/
    _index.gdls
    objects/
      schema.gdls
```

---

## Grep Patterns

### Tables and Columns

| Task | Command |
|------|---------|
| Find table + all columns | `grep "^@T GL_ACCOUNT" -A 30 schema.gdls` |
| List all tables in domain | `grep "^@T " schema.gdls` |
| Find primary key columns | `grep "\|PK\|" schema.gdls` |
| Find foreign key columns | `grep "\|FK\|" schema.gdls` |
| Find domain header | `grep "^@D " schema.gdls` |
| Find table across domains | `grep "^@T GL_ACCOUNT" */schema.gdls` |
| Find table in index | `grep "GL_ACCOUNT" _index.gdls` |

### Relationships

| Task | Command |
|------|---------|
| All relationships for a table | `grep "GL_ACCOUNT" _relationships.gdls` |
| All foreign keys in a domain | `grep "^@R " schema.gdls` |
| All cross-system equivalents | `grep "\|equivalent\|" _relationships.gdls` |
| All data feeds from Salesforce | `grep "salesforce:" _relationships.gdls \| grep "\|feeds\|"` |
| What references GL_ACCOUNT? | `grep "-> GL_ACCOUNT" schema.gdls` |
| What does GL_JOURNAL reference? | `grep "^@R GL_JOURNAL" schema.gdls` |
| All relationships for a system | `grep "snowflake:" schema/_relationships.gdls` |

### Paths

| Task | Command |
|------|---------|
| Paths involving a table | `grep "GL_ACCOUNT" schema.gdls \| grep "^@PATH"` |
| All cross-system paths | `grep "^@PATH.*:.*->.*:" schema/_relationships.gdls` |
| Path from entity to entity | `grep "^@PATH.*CUSTOMER.*PRODUCT" schema.gdls` |

### Enums

| Task | Command |
|------|---------|
| Valid values for a column | `grep "^@E GL_ACCOUNT.GL_STATUS" schema.gdls` |
| All enums for a table | `grep "^@E GL_ACCOUNT\." schema.gdls` |
| All enums in a domain | `grep "^@E" schema.gdls` |
| Which columns have STATUS constraints? | `grep "^@E.*\..*STATUS" *.gdls` |
| Tables allowing a specific value | `grep "^@E.*ACTIVE" schema.gdls` |
| Extract just the values | `grep "^@E GL_ACCOUNT.GL_STATUS" schema.gdls \| cut -d'\|' -f2` |

---

## File Conventions

| Convention | Value |
|------------|-------|
| Extension | `.gdls` |
| Encoding | UTF-8 |
| Line ending | LF |
| Comments | Lines starting with `#` |
| Blank lines | Allowed between sections (recommended for readability) |
| Empty fields | Consecutive pipes: `\|\|` |

---

## Escaping

When values contain pipe characters, escape with backslash:

```
@T SPECIAL_TABLE|Table with pipe\|in description
COL_NAME|VARCHAR(50)|Y||Value with pipe\|inside
```

In practice, escaping is rarely needed in schema definitions.

---

## Design Principles

1. **Grep-first** - `@T`, `@D`, `@R`, `@PATH`, `@E` prefixes enable instant type filtering
2. **Positional efficiency** - Fixed column positions eliminate key-name overhead (51% smaller than YAML)
3. **Context-complete** - `grep -A 30` returns table + columns, relationships, paths, and enums in one call. `grep "TABLE" _relationships.gdls` returns all connections.
4. **Relationship-aware** - Foreign keys, cross-system mappings, and traversal paths are first-class schema elements
5. **Bash-native** - Works with grep, cut, awk directly, no parsers needed
6. **Scale-proven** - Tested at 10,000 tables with 100% accuracy, 1.0 tool calls
7. **System-spanning** - `system:entity` notation handles cross-system relationships natively

---

## Optional Extension: Schema Deltas

For incremental schema updates in multi-agent environments:

```
@DELTA|agent:sf-agent|ts:2026-01-31T14:30:00
+GL_ACCOUNT col NEW_FIELD|VARCHAR(100)|Y||Region code
-GL_ACCOUNT col OLD_FIELD
~GL_ACCOUNT col GL_TEXT_1|VARCHAR(100)|Y||Expanded from VARCHAR(50)
+@R GL_ACCOUNT.NEW_FIELD -> REGION.REGION_CODE|fk|New region reference
+@E GL_ACCOUNT.GL_STATUS|ACTIVE,INACTIVE,SUSPENDED|Account lifecycle states
```

Operators: `+` add, `-` remove, `~` modify.

---

## Optional Extension: Enum Records

For documenting valid column values. Enums are documentation, not enforcement — they describe what values exist, the same way `@T` describes what tables exist.

### Format

```
@E TABLE.COLUMN|VALUE1,VALUE2,VALUE3|description
```

| Position | Field | Required | Example |
|----------|-------|----------|---------|
| 1 | Table.Column | Yes | `GL_ACCOUNT.GL_STATUS` |
| 2 | Comma-separated values | Yes | `ACTIVE,INACTIVE,SUSPENDED` |
| 3 | Description | No | `Account lifecycle status` |

### Placement

Place `@E` records immediately after the column lines of their parent table:

```gdls
@T GL_ACCOUNT|Account master data
GL_ACCOUNT_ID|INTEGER|N|PK|Primary key
GL_STATUS|VARCHAR(20)|N||Account status
GL_PARENT_ID|INTEGER|Y|FK|Parent account
@E GL_ACCOUNT.GL_STATUS|ACTIVE,INACTIVE,SUSPENDED|Account lifecycle status

@T SO_HEADER|Sales order header
SO_HEADER_ID|INTEGER|N|PK|Primary key
ORDER_TYPE|VARCHAR(20)|N||Order classification
@E SO_HEADER.ORDER_TYPE|STANDARD,RETURN,EXCHANGE,TRANSFER|Sales order classification
```

### Rules

- Values are case-sensitive and literal (match what exists in the database)
- Commas inside values are not supported
- Description is optional — if omitted, trailing pipe is not needed
- Multiple `@E` records per table are allowed (one per constrained column)
- Absence of `@E` for a column is not an error — it just means no enum is documented

---

## Optimal Agent Prompts

### Schema navigation (tables/columns)

Proven 3-line prompt achieving 100% accuracy and 1.0 tool calls:

```
Database schema expert. Files: {schema_path}/[domain]/schema.gdls

Format: @T TABLE|desc followed by COLUMN|TYPE|N/Y|PK|desc lines, then @R, @PATH, @E records.

Grep for "@T TABLENAME" with after_context=30. PK: |PK|, FK: |FK|. Enums: grep "^@E TABLE".
```

### Relationship navigation

```
Schema relationship expert. Files: {schema_path}/[domain]/schema.gdls and {schema_path}/_relationships.gdls

Format: @R source.col -> target.col|type|desc and @PATH entity -> entity|desc

Within-domain: grep "^@R TABLE" in schema.gdls. Cross-domain/system: grep in _relationships.gdls.
```

### Combined (schema + relationships)

```
Database schema expert. Schema: {schema_path}/[domain]/schema.gdls, Cross-refs: {schema_path}/_relationships.gdls

Tables: grep "@T TABLE" with after_context=30. PK: |PK|, FK: |FK|
@R, @PATH under each table. Cross-domain/system refs in _relationships.gdls. Enums: grep "^@E TABLE".
```

---

## Relationship to GDL

GDLS and its siblings are formats in the same language family:

| | GDLS | GDL | GDLC | GDLU |
|--|------|-----|------|------|
| Purpose | Schema, relationships, enums, structural maps | Data records and agent memory | File-level code index | Unstructured content index |
| Fields | Positional (5-field columns) | Key:value (self-describing) | Positional | Key:value (`@source`, `@section`, `@extract`) |
| Extension | `.gdls` | `.gdl` | `.gdlc` | `.gdlu` |
| Records | `@D`, `@T`, `@R`, `@PATH`, `@E` | `@type\|key:value` | `@D`, `@F` | `@source`, `@section`, `@extract` |
| Shared | `@` prefix, `\|` delimiter, line-oriented, grep-first |

GDLS tells agents what systems look like and how they connect. GDL holds the data and memories agents work with. GDLC is a file-level code index (`@D` = directory, `@F` = file). GDLU indexes unstructured content (PDFs, transcripts, media) for grep-based retrieval.
