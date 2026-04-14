# GDLU Specification v1.0

**GDL Unstructured** - A grep-native index format for unstructured content. Maps documents, media, and freeform text into agent-queryable records without containing the content itself.

## Purpose

GDLU is a grep-queryable **index** of unstructured content. It doesn't contain documents, it contains a structural map of documents.

An agent working with unstructured content needs to:
1. **Find** relevant documents for a query (without reading them all)
2. **Navigate** to the right section of a document
3. **Extract** key facts without full-document parsing
4. **Connect** unstructured content to other GDL layers (schemas, memory, data)

GDLU is not for structured business data (that's GDL), not for visual knowledge (that's GDLD).

---

## Scope and Limitations

### Where GDLU adds the most value

- **Binary formats** (PDF, PPTX, PNG, MP3) that agents cannot grep directly. This is the primary use case — making non-greppable content greppable.
- **Cross-type queries** ("find all decisions across meetings, emails, and contracts") where a single grep across `**/*.gdlu` replaces format-specific searches.
- **Document navigation** — `@section` records with locators (`p:4-12`, `t:08:30-15:20`) have no filesystem equivalent.

### Where GDLU adds moderate value

- **Poorly-organized text content** where file names and directory structure are unhelpful (e.g., `scan_20260115_v3_final.pdf`).
- **Large text documents** where grepping the source returns too much noise and sections provide useful chunking.

### Where GDLU adds little value

- **Well-organized text files** (Markdown, plain text) that are already directly greppable. For these, `grep -rl "keyword" docs/` is faster and more complete than an index.
- **Content that is rarely queried.** Indexing costs agent time. Only index documents that are likely to be referenced.

### Extraction is approximate, not authoritative

Like GDLD diagrams, GDLU extractions are structured summaries, not perfect representations. A diagram doesn't capture every nuance of a codebase; an extraction doesn't capture every fact in a document. GDLU is a **better summary than prose and a cheaper lookup than re-reading the source every time** — that is the value proposition.

Specific limitations:
- **Extraction completeness is unknowable.** If 15 clauses exist and 9 are extracted, there is no signal that 6 were missed. Agents should fall back to reading source documents when extractions don't answer a query.
- **Extraction accuracy depends on the indexing agent.** Use `confidence:` to express certainty. For high-stakes content (legal, financial), human verification of extractions is recommended.
- **Long-tail queries defeat extraction.** GDLU optimizes for anticipated, structured queries ("what's the liability cap?"). For unanticipated queries ("what did Sarah say about Auth0?"), agents should read the source directly.

### When NOT to use GDLU

- **Structured, machine-parseable content** with a formal schema (OpenAPI, Terraform, GraphQL SDL) belongs in GDLS.
- **Structured business data** (CSV exports, database dumps) belongs in GDL.
- **Routine, low-signal content** (automated notifications, "no blockers" standups) is usually not worth indexing. If indexed, use `signal:low` to let agents filter.

---

## Format

GDLU records use the GDL `@type|key:value` format:

```
@source|id:{id}|path:{path}|format:{format}|type:{content-type}|summary:{text}|ts:{ISO-timestamp}
@section|source:{id}|id:{id}|loc:{locator}|title:{title}|summary:{text}
@extract|source:{id}|id:{id}|kind:{kind}|key:{key}|value:{value}
```

### File Extension

| Convention | Value |
|------------|-------|
| Extension | `.gdlu` |
| Encoding | UTF-8 |
| Line ending | LF |
| Comments | Lines starting with `#` or `//` |
| Blank lines | Allowed (ignored) |

### Escaping

GDLU inherits GDL's escaping rules. When values contain `|` or `:`, escape with backslash:

| Character | Escape | Example |
|-----------|--------|---------|
| `\|` | `\\|` | `summary:Input\\|Output processing` |
| `:` | `\:` | `summary:Meeting at 3\:00 PM` |
| `\` | `\\` | `path:docs\\archive\\old` |

The `summary:`, `value:`, and `context:` fields are free-text and most likely to need escaping. The `loc:` field uses colons as sub-delimiters (e.g., `p:4-12`, `t:05\:30-12\:45`); these are part of the locator syntax and should not be escaped.

**Comma-separated fields** (`entities:`, `topics:`, `tags:`, `refs:`): Commas inside individual values are not supported. Use hyphens or abbreviations for names that contain commas (e.g., `Acme Inc` not `Acme, Inc.`).

### File Placement

GDLU index files live alongside or near their source material:

```
project/
├── unstructured/
│   ├── contracts/
│   │   ├── acme-msa.pdf
│   │   ├── beta-nda.pdf
│   │   └── contracts.gdlu       # Index for this directory
│   ├── meetings/
│   │   ├── 2026-01-15-standup.txt
│   │   ├── 2026-01-22-planning.txt
│   │   └── meetings.gdlu
│   └── research/
│       ├── market-analysis.pdf
│       └── research.gdlu
```

Convention: Named `.gdlu` files per directory (e.g., `contracts.gdlu`, `meetings.gdlu`). For cross-cutting queries, agents grep across `**/*.gdlu`.

**Sharding guidance:** When a single `.gdlu` file exceeds ~5,000 lines, shard by content type or date: `contracts-active.gdlu`, `contracts-archived.gdlu`, or `meetings-2025.gdlu`, `meetings-2026.gdlu`. The glob pattern `**/*.gdlu` catches all shards.

---

## Record Types

### Three records. That's it.

The entire format uses three record types. Content-type flexibility comes from field values, not new record types.

| Record | Purpose | Analogy |
|--------|---------|---------|
| `@source` | Declares a document/asset | Like `@diagram` in GDLD (declares a diagram file) |
| `@section` | A navigable chunk within a source | Like `@node`/`@group` in GDLD (parts of a diagram) |
| `@extract` | A key fact pulled from the content | Like `@edge` in GDLD (relationships and connections) |

---

### @source — Document Declaration

Declares an unstructured asset. One record per document/file/asset.

```
@source|id:{id}|path:{path}|format:{format}|type:{content-type}|summary:{text}|ts:{ISO-timestamp}
```

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique identifier (e.g., `U-001`, `U-sf-042-001` in multi-agent) |
| `path` | Yes | Relative file path or URL for cloud-hosted content |
| `format` | Yes | File format: `pdf`, `txt`, `md`, `docx`, `png`, `mp3`, `html`, `eml`, `pptx`, `csv`, `figma`, `gdoc` |
| `type` | Yes | Semantic content type — open vocabulary (see Content Types) |
| `summary` | Yes | One-line description of what this document contains |
| `ts` | Yes | ISO timestamp of when this record was created/last updated |
| `agent` | Recommended | ID of the agent that created this index entry |
| `status` | No | `active` (default), `stale`, `superseded`, `archived` |
| `signal` | No | `high`, `medium`, `low` — how much queryable value this source has |
| `pages` | No | Page count (for paged documents) |
| `duration` | No | Duration (for audio/video, e.g., `45m`) |
| `author` | No | Creator/author of the source document |
| `created` | No | Creation date of the source document (distinct from `ts:` which is the index date) |
| `entities` | No | Comma-separated key entities mentioned |
| `topics` | No | Comma-separated topics/themes |
| `tags` | No | Comma-separated classification tags |
| `refs` | No | Cross-references (see Cross-References section) |

#### Content Types (open vocabulary)

The `type:` field supports comma-separated values for hybrid documents. Common values:

| Category | Example Types |
|----------|--------------|
| Legal | `contract`, `nda`, `terms-of-service`, `policy`, `contract-amendment` |
| Business | `report`, `proposal`, `invoice`, `presentation`, `sow` |
| Technical | `architecture-doc`, `api-doc`, `runbook`, `post-mortem` |
| Communication | `email`, `chat-log`, `meeting-transcript`, `meeting-notes` |
| Research | `paper`, `analysis`, `survey`, `benchmark` |
| Media | `screenshot`, `diagram-image`, `recording`, `video` |
| Knowledge | `wiki-article`, `faq`, `how-to`, `onboarding` |

Hybrid documents use comma-separation: `type:contract,technical-spec,project-plan`.

New content types don't require spec changes.

#### Examples

```gdlu
# Legal contract
@source|id:U-001|path:contracts/acme-msa.pdf|format:pdf|type:contract|pages:42|author:legal-team|created:2024-03-15|summary:Master service agreement between Acme Corp and Beta LLC, 3yr term, $500K liability cap|entities:Acme Corp,Beta LLC|topics:MSA,indemnification,IP-assignment|tags:legal,active,enterprise|agent:doc-agent|ts:2026-02-01T10:00:00|signal:high

# Meeting transcript
@source|id:U-010|path:meetings/2026-01-15-standup.txt|format:txt|type:meeting-transcript|duration:25m|author:auto-transcribed|created:2026-01-15|summary:Weekly standup covering sprint progress, blocker on auth migration, decision to defer analytics|entities:Alice,Sarah,Mike|topics:sprint-review,auth-migration,analytics|tags:standup,engineering|agent:doc-agent|ts:2026-01-16T09:00:00|signal:high

# Low-signal routine standup
@source|id:U-015|path:meetings/2026-01-20-standup.txt|format:txt|type:meeting-transcript|duration:8m|created:2026-01-20|summary:Daily standup, no decisions or blockers|tags:standup,engineering|agent:doc-agent|ts:2026-01-20T10:00:00|signal:low

# Hybrid document (contract + tech spec + project plan)
@source|id:U-060|path:engagements/platform-engagement-v3.pdf|format:pdf|type:contract,technical-spec,project-plan|pages:150|created:2025-11-01|summary:Combined MSA, tech spec, and project plan for Platform Engagement with MegaCorp|entities:MegaCorp|topics:MSA,architecture,milestones|tags:legal,technical,active|agent:doc-agent|ts:2026-02-01T14:00:00|signal:high

# Cloud-hosted content (path is URL)
@source|id:U-070|path:https://figma.com/file/abc123/Dashboard|format:figma|type:design-file|author:design-team|created:2026-01-10|summary:Platform dashboard designs, 12 frames covering user management and analytics|entities:platform-team|topics:UI,dashboard|tags:design,active|agent:doc-agent|ts:2026-01-15T11:00:00|signal:medium

# Contract with amendment (refs: links to original)
@source|id:U-002|path:contracts/acme-amendment-1.pdf|format:pdf|type:contract-amendment|pages:3|created:2025-09-01|summary:Amendment 1 - increases liability cap to $750K|entities:Acme Corp|tags:legal,active|refs:gdlu:U-001|agent:doc-agent|ts:2026-02-01T10:30:00|signal:high
```

---

### @section — Navigable Chunk

Breaks a source into navigable parts. An agent can grep for sections, then read only the relevant part of the source.

```
@section|source:{source-id}|id:{id}|loc:{locator}|title:{title}|summary:{text}
```

| Field | Required | Description |
|-------|----------|-------------|
| `source` | Yes | ID of the parent `@source` record |
| `id` | Yes | Unique section identifier (e.g., `S-001`) |
| `loc` | Yes | Location within the source (open vocabulary — see Locator Formats) |
| `title` | Yes | Section heading or label |
| `summary` | Yes | What this section contains |
| `parent` | No | ID of the parent section (for hierarchical documents) |
| `entities` | No | Key entities in this section |
| `topics` | No | Topics covered |
| `tags` | No | Classification tags |

#### Locator Formats (`loc:` — open vocabulary)

The `loc:` prefix adapts to the content type. This is an open vocabulary — new prefixes can be introduced for new content formats without spec changes.

| Content Format | Locator Pattern | Example |
|---------------|-----------------|---------|
| PDF | `p:{start}-{end}` | `p:4-12` |
| Text/Markdown | `L:{start}-{end}` | `L:45-89` |
| Audio/Video | `t:{start}-{end}` | `t:05\:30-12\:45` |
| Slides | `s:{start}-{end}` | `s:8-12` |
| Email thread | `msg:{index}` | `msg:3` |
| HTML | `id:{anchor}` | `id:section-auth` |
| Image | `region:{description}` | `region:top-right` |
| Figma | `page:{name}` | `page:User-Management` |
| API collection | `folder:{name}` | `folder:Authentication` |
| IaC modules | `module:{name}` | `module:networking` |

#### Examples

```gdlu
# PDF contract sections
@section|source:U-001|id:S-001|loc:p:1-3|title:Definitions|summary:Defines key terms - Service Provider, Client, Deliverables, Confidential Information
@section|source:U-001|id:S-002|loc:p:4-12|title:Scope of Services|summary:Professional services model, SOW process, change request procedures
@section|source:U-001|id:S-003|loc:p:13-18|title:Payment Terms|summary:Net-30 payment, milestone-based billing, late payment penalties at 1.5%/month

# Meeting transcript sections
@section|source:U-010|id:S-010|loc:t:00\:00-08\:30|title:Sprint Review|summary:3 stories completed, 2 carried over, velocity at 34 points|topics:sprint
@section|source:U-010|id:S-011|loc:t:08\:30-15\:20|title:Auth Migration Blocker|summary:OAuth token refresh failing in staging, Sarah investigating|entities:Sarah|topics:auth-migration|tags:blocker

# Hierarchical sections (parent/child)
@section|source:U-060|id:S-060|loc:p:41-90|title:Technical Specification|summary:System architecture, API contracts, data models
@section|source:U-060|id:S-061|loc:p:41-55|title:System Architecture|summary:High-level architecture, component diagram|parent:S-060
@section|source:U-060|id:S-062|loc:p:56-70|title:API Specification|summary:REST endpoints, request/response schemas|parent:S-060
```

---

### @extract — Key Fact Extraction

Captures specific facts, values, entities, or quotes from the source. These are the high-value grep targets — an agent searching for "what's the liability cap?" greps extractions, not full documents.

```
@extract|source:{source-id}|id:{id}|kind:{kind}|key:{key}|value:{value}
```

| Field | Required | Description |
|-------|----------|-------------|
| `source` | Yes | ID of the parent `@source` record |
| `id` | Yes | Unique extraction identifier (e.g., `X-001`) |
| `kind` | Yes | Extraction type — recommended vocabulary (see Kinds) |
| `key` | Yes | What was extracted (the semantic label) |
| `value` | Yes | The extracted value |
| `section` | No | ID of the `@section` this was extracted from |
| `confidence` | No | `high`, `medium`, `low` (see Confidence Levels) |
| `context` | No | Brief surrounding context for disambiguation |
| `supersedes` | No | ID of a previous `@extract` this replaces (for corrections/amendments) |
| `status` | No | `active` (default), `superseded`, `withdrawn` |

#### Extraction Kinds (recommended vocabulary)

The `kind:` field uses a recommended vocabulary. Prefer these standard values over synonyms to ensure consistent grep results across agents.

| Kind | Use this, NOT | Description |
|------|---------------|-------------|
| `metric` | ~~kpi, measurement, number, stat~~ | A number, measurement, or KPI |
| `date` | ~~deadline, timestamp, milestone~~ | A significant date or deadline |
| `entity` | ~~person, org, company, system~~ | A person, org, or system mentioned |
| `decision` | ~~resolution, conclusion, determination~~ | A decision that was made |
| `action` | ~~todo, task, follow-up~~ | An action item or TODO |
| `clause` | ~~provision, term, stipulation~~ | A contractual or policy clause |
| `quote` | ~~excerpt, statement, verbatim~~ | A verbatim significant quote |
| `risk` | ~~concern, issue, problem, threat~~ | An identified risk or concern |
| `requirement` | ~~constraint, condition, must-have~~ | A stated requirement or constraint |
| `term` | ~~definition, concept, glossary~~ | A defined term or concept |

New kinds can be introduced when none of the above fits. Use lowercase, hyphenated names (e.g., `kind:pricing-tier`).

#### Confidence Levels

| Level | Meaning | Agent guidance |
|-------|---------|---------------|
| `high` | Fact is explicitly stated in the source, unambiguous | Trust the extraction |
| `medium` | Fact is inferred or paraphrased from the source | Verify against source if critical |
| `low` | Fact is uncertain, ambiguous, or partially extracted | Read the source before acting |

#### Supersession

When a fact changes (e.g., amendment changes the liability cap), use `supersedes:` to chain extractions:

```gdlu
# Original extraction
@extract|source:U-001|id:X-001|kind:metric|key:liability-cap|value:$500,000|confidence:high|status:superseded

# Amendment extraction that replaces it
@extract|source:U-002|id:X-002|kind:metric|key:liability-cap|value:$750,000|confidence:high|supersedes:X-001|context:Amendment 1 supersedes original clause 8.1
```

When an agent greps `key:liability-cap` and gets multiple results, it should:
1. Check `supersedes:` — if present, follow the chain to the latest
2. Check `status:` — skip `superseded` or `withdrawn` records
3. If neither field is present, compare source `created:` dates (latest wins)

#### Examples

```gdlu
# Contract extractions
@extract|source:U-001|id:X-001|kind:metric|key:liability-cap|value:$500,000|section:S-005|confidence:high|context:Total aggregate liability capped per SOW
@extract|source:U-001|id:X-002|kind:date|key:term-end|value:2027-03-15|section:S-002|confidence:high
@extract|source:U-001|id:X-003|kind:clause|key:IP-assignment|value:work-for-hire, assigns to Client upon payment|section:S-004|confidence:high
@extract|source:U-001|id:X-004|kind:clause|key:termination-for-convenience|value:either party, 90 days written notice|section:S-006|confidence:high

# Meeting extractions
@extract|source:U-010|id:X-010|kind:decision|key:defer-analytics|value:Analytics dashboard deferred to next sprint|section:S-012|confidence:high
@extract|source:U-010|id:X-011|kind:action|key:investigate-oauth|value:Sarah to debug token refresh failure in staging by EOD Wednesday|section:S-011
@extract|source:U-010|id:X-012|kind:risk|key:auth-blocker|value:OAuth token refresh failing, blocks 3 downstream stories|section:S-011|confidence:high

# Superseded extraction (amendment changed the cap)
@extract|source:U-002|id:X-020|kind:metric|key:liability-cap|value:$750,000|confidence:high|supersedes:X-001|context:Amendment 1 increases cap from $500K
```

---

## Cross-References

The `refs:` field supports cross-layer and intra-layer references using the pattern `{layer}:{id}`:

| Prefix | Layer | Example |
|--------|-------|---------|
| `gdlu:` | Other GDLU sources | `refs:gdlu:U-001` (amendment references original contract) |
| `gdls:` | GDLS schema tables | `refs:gdls:GL_ACCOUNT` |
| `gdl:` | GDL data records | `refs:gdl:C001` |
| `gdld:` | GDLD diagram IDs | `refs:gdld:platform-architecture` |

Multiple refs are comma-separated: `refs:gdlu:U-001,gdls:GL_ACCOUNT,gdld:platform-architecture`

### Cross-Reference Traversal

Forward traversal (document to code):
```bash
# 1. Find the contract
grep "^@source.*id:U-001" contracts/contracts.gdlu
# → refs:gdlu:U-002 (amendment)

# 2. Follow to amendment
grep "^@source.*id:U-002" contracts/contracts.gdlu
# → refs:gdls:GL_ACCOUNT

# 3. Follow to schema
grep "^@T GL_ACCOUNT " schema/snowflake/finance/schema.gdls
```

Reverse traversal (what documents reference this table?):
```bash
grep "refs:.*gdls:GL_ACCOUNT" **/*.gdlu
```

---

## Grep Patterns

All patterns work across ANY content type. GDLU uses `.*` wildcards between fields, which is readable but not field-boundary-aware. For high-precision queries, pipe-anchor the first field: `grep "^@extract|source:U-001"` is more precise than `grep "^@extract.*source:U-001"`.

### Finding Sources

```bash
# All sources of a content type
grep "^@source.*type:contract" **/*.gdlu

# All PDFs
grep "^@source.*format:pdf" **/*.gdlu

# Sources mentioning an entity
grep "^@source.*entities:.*Acme" **/*.gdlu

# High-signal sources only
grep "^@source.*signal:high" **/*.gdlu

# All active sources (excludes stale/superseded/archived)
grep "^@source" **/*.gdlu | grep -v "status:superseded\|status:archived\|status:stale"
```

### Navigating Sections

```bash
# All sections of a specific source (pipe-anchored for precision)
grep "^@section|source:U-001" contracts/contracts.gdlu

# Top-level sections only (no parent field)
grep "^@section|source:U-060" engagements/engagements.gdlu | grep -v "parent:"

# Sections tagged as blockers
grep "^@section.*tags:.*blocker" **/*.gdlu
```

### Querying Extractions

```bash
# Find a specific extracted value
grep "^@extract.*key:liability-cap" **/*.gdlu

# All decisions (across all content types)
grep "^@extract.*kind:decision" **/*.gdlu

# All active extractions (skip superseded)
grep "^@extract.*kind:metric" **/*.gdlu | grep -v "status:superseded"

# All action items
grep "^@extract.*kind:action" **/*.gdlu
```

---

## Ingestion Patterns

The format doesn't mandate an ingestion method — any process that produces valid records works.

### Agent-Driven Ingestion (Primary)

```
1. Agent reads source file (PDF, transcript, email, etc.)
2. Agent produces @source record with summary, entities, topics, ts, agent
3. Agent produces @section records for navigable chunks
4. Agent produces @extract records for key facts
5. Agent appends all records to the directory's .gdlu file
6. Agent commits to git
```

### Indexing Guidelines

Not every document needs GDLU records. Index documents that contain decisions, metrics, obligations, risks, or requirements.

**Two-pass ingestion for large directories:**
1. Quick scan (first page, subject line, file metadata) → produce `@source` only, set `signal:` level
2. Full read for `signal:medium` and `signal:high` sources only → produce `@section` and `@extract` records

A `@source` record with no `@section` or `@extract` records signals: "this document was reviewed and found to have low extractable value."

### Incremental Updates

When source content changes:
1. Agent re-reads the source
2. Agent updates `ts:` on all affected records
3. For changed extractions, create new `@extract` with `supersedes:` pointing to the old one, and set `status:superseded` on the old record
4. Agent commits to git

---

## Concurrency

GDLU files may be written by multiple agents:

- **Reads** do not require locks
- **Appends** use `flock` for file-level locking (microsecond duration)
- **Rewrites** (updating existing records) should be done under lock

In multi-agent environments, use agent-prefixed IDs to prevent collisions: `U-doc-042-001` instead of `U-001`.

---

## Design Principles

1. **Index, don't store.** GDLU records point to content; they don't contain it. Source files live on disk.
2. **Grep-first.** Every record type and field is designed for `grep "^@type.*field:value"` retrieval.
3. **Approximate, not authoritative.** Extractions are structured summaries. Agents should verify against source documents for critical decisions.
4. **Open vocabularies, recommended values.** `type:`, `loc:`, and `kind:` are extensible. Standard values prevent vocabulary explosion across agents.
5. **Line-oriented, append-friendly.** One record per line. Streamable, diffable, git-mergeable.
6. **Supersession over deletion.** Mark old records as `status:superseded` rather than deleting them. Full history is preserved.
7. **Binary content is the sweet spot.** GDLU adds the most value for formats agents can't grep directly (PDF, PPTX, images, audio).

---

## Optimal Agent Prompt

### Minimal (~40 tokens)

```
Documents: **/*.gdlu — grep "^@source" for docs, "^@extract.*kind:K" for facts, "^@section|source:ID" for navigation. Verify critical extractions against source files.
```

### With ingestion (~70 tokens)

```
Documents: **/*.gdlu — grep "^@source" for docs, "^@extract.*kind:K" for facts.
To index: read doc, produce @source (id,path,format,type,summary,ts,agent), @section (loc,title,summary), @extract (kind,key,value,confidence). Append to dir .gdlu file.
```

---

## Abstraction Test

Does this structure work for any content type?

| Content | @source | @section (loc:) | @extract (kind:) | Rating |
|---------|---------|-----------------|------------------|--------|
| PDF contract | format:pdf, type:contract | loc:p:13-18 | kind:clause, kind:metric | Works Well |
| Meeting transcript | format:txt, type:meeting-transcript | loc:t:08\:30-15\:20 | kind:decision, kind:action | Works Well |
| Research paper | format:pdf, type:paper | loc:p:5-12 | kind:metric, kind:quote | Works Well |
| Email thread | format:eml, type:email | loc:msg:3 | kind:decision, kind:action | Works Well |
| Slide deck | format:pptx, type:presentation | loc:s:6-14 | kind:metric, kind:date | Works Well |
| Audio recording | format:mp3, type:recording | loc:t:12\:00-15\:30 | kind:quote, kind:decision | Works Well |
| Screenshot | format:png, type:screenshot | loc:region:top-right | kind:metric, kind:risk | Works Well |
| Wiki article | format:md, type:wiki-article | loc:L:1-45 | kind:term, kind:requirement | Moderate (text is already greppable) |
| Figma design | format:figma, type:design-file | loc:page:User-Mgmt | kind:decision | Works Awkwardly (visual content) |
| Video recording | format:mp4, type:recording | loc:t:05\:30-22\:00 | kind:decision, kind:quote | Works Well |

All content types use the same three record types. Flexibility comes from field values, not new record types.

---

## Relationship to Other GDL Layers

| Layer | Relationship to GDLU |
|-------|---------------------|
| **GDLS** (schemas) | `refs:gdls:TABLE` on `@source` connects docs to the data they describe |
| **GDL** (data) | `refs:gdl:C001` connects docs to relevant business records |
| **GDLD** (diagrams) | Diagrams visualize knowledge from docs; `refs:gdld:diagram-id` links them |

---

## What GDLU Is NOT

- **Not a document store** — source files live on disk, GDLU indexes them
- **Not full-text search** — for unanticipated queries, agents read source documents directly
- **Not OCR/transcription** — GDLU assumes source content is already readable
- **Not vector embeddings** — grep on structured fields, not similarity search
- **Not a replacement for GDLD** — visual knowledge (architecture, flows, patterns) belongs in GDLD
- **Not for structured data** — formal schemas belong in GDLS, business records belong in GDL

---

## GDL Family Summary (Updated)

| Format | Extension | Purpose | Record Style |
|--------|-----------|---------|-------------|
| GDLS | `.gdls` | Schema maps (tables, relationships) | Positional (`@T`, `@R`, `@PATH`) |
| GDL | `.gdl` | Structured data records | Key-value (`@type\|key:value`) |
| GDLD | `.gdld` | Visual knowledge (diagrams) | Key-value (`@diagram`, `@node`, `@edge`) |
| **GDLU** | **`.gdlu`** | **Unstructured content index** | **Key-value (`@source`, `@section`, `@extract`)** |

---

## Future Considerations

These items were identified during the v0.2 spec sketch and may be addressed in future versions:

1. **Multi-value extractions**: Currently each value is a separate `@extract` (e.g., key:milestone-1, key:milestone-2). A list-value pattern may add clarity for common cases.

2. **Ingestion tooling**: A standard `gdlu-index.sh` shell utility could wrap the agent-driven ingestion workflow described in the Ingestion Patterns section.

3. **Density guidance**: Target extraction density (e.g., ~1 section per 5-10 pages, ~2-3 extractions per section) may be useful for large documents.

4. **Cross-source deduplication**: When the same fact appears in multiple sources, independent extraction is acceptable in v1.0. Future versions may add explicit cross-extraction references.
