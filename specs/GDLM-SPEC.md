# Memory Specification v1.1

**Agent Memory Layer** - A three-tier memory system for shared agent knowledge, built on the GDL format with memory-specific fields and retrieval mechanisms.

## Purpose

The Memory layer gives agents persistent, shared knowledge that survives across sessions and spans multiple agents. It stores observations, decisions, preferences, and learned facts - anything an agent discovers that other agents (or its future self) would benefit from knowing.

Memory is not for deterministic business data (that's GDL) or structural maps of external systems (that's GDLS). Memory is subjective, evolving, and agent-authored.

## Optimal Agent Prompts

**Tier 1 — Reading/Querying (~40 tokens):**
```
GDLM: @memory records with key:value fields. Required: id, agent, subject, detail, ts.
grep "^@memory" file.gdlm | grep "subject:TOPIC". Anchors: grep "^@anchor".
Three tiers: active/ (current), archive/ (summaries), history/ (originals).
```

**Tier 2 — Writing/Generating (~100 tokens):**
```
GDLM generation:
- IDs: M-{agent}-{seq} (e.g., M-discovery-001)
- Required fields: id, agent, subject, detail, ts (ISO 8601 UTC)
- Optional: type (observation|decision|preference|error|fact|task|procedural), tags (comma-sep),
  confidence (high|medium|low), relates (ID or type~ID), anchor, source, status
- @anchor records: id + terms (comma-sep synonyms for concept matching)
- Use gdl_new memory for concurrent-safe writes with mkdir-based locking
```

---

## Format

Memory records use the GDL `@type|key:value` format with memory-specific fields:

```
@memory|id:{id}|agent:{agent}|subject:{subject}|tags:{tag1,tag2}|detail:{text}|confidence:{level}|ts:{timestamp}
```

### Required Fields

| Field | Description | Example |
|-------|-------------|---------|
| `id` | Unique memory identifier | `M-sf-042-017` |
| `agent` | Agent that created the memory | `sf-042` |
| `subject` | Primary topic (flat, not hierarchical) | `GL_ACCOUNT` |
| `detail` | The actual knowledge content | `NEW_FIELD contains region codes` |
| `ts` | ISO timestamp | `2026-01-31T14:30:00` |

### Optional Fields

| Field | Description | Example |
|-------|-------------|---------|
| `tags` | Comma-separated retrieval tags | `snowflake,finance,schema-change` |
| `confidence` | Agent's certainty level | `high`, `medium`, `low` |
| `relates` | Links to memory IDs or anchor concept names (optional type prefix: `supersedes~M-001`) | `M-sf-042-015`, `supersedes~M-sf-042-015`, or `bridge-tools,testing-strategy` |
| `type` | Memory classification | `observation`, `decision`, `preference`, `error`, `fact`, `task`, `procedural` |
| `anchor` | Concept anchor reference | `data-pipeline` |
| `status` | Record state (for corrections/deletions) | `corrected`, `deleted`, `compacted` |
| `source` | Where the knowledge came from | `snowflake-query`, `user-instruction` |

> `relates` values can be memory IDs (`M-*`) for precise record-level links, or anchor concept names (e.g., `bridge-tools`) for concept-level links. Automated extraction (session2gdlm) produces anchor-name relates; manual records typically use memory IDs.

### Memory ID Convention

```
M-{agent_short_name}-{sequence}
```

IDs are unique per agent, preventing conflicts during concurrent writes:

```mem
@memory|id:M-sf-042-001|agent:sf-042|subject:GL_ACCOUNT|detail:table has 13 columns|ts:2026-01-31T14:30:00
@memory|id:M-db-007-001|agent:db-007|subject:customer_analytics|detail:derived from CUSTOMER table nightly|ts:2026-01-31T14:35:00
```

---

## Three-Tier Memory Model

```
┌──────────────────────────────────────────────┐
│                 ACTIVE                        │
│                                               │
│  Recent memories (last N days or entries)     │
│  memory/active/*.gdlm                          │
│  Fast retrieval. Full detail. Grep-first.     │
├──────────────────────────────────────────────┤
│                 ARCHIVE                       │
│                                               │
│  Compacted summaries of older memories       │
│  memory/archive/*.gdlm                         │
│  Reduced volume. Key insights preserved.      │
├──────────────────────────────────────────────┤
│                 HISTORY                       │
│                                               │
│  Complete uncompacted originals              │
│  memory/history/*.gdlm                         │
│  Full audit trail. Rarely accessed.           │
└──────────────────────────────────────────────┘
```

### Active Tier

Where agents read and write during normal operations.

```
memory/active/
  systems.gdlm          # Observations about external systems
  decisions.gdlm        # Design and architectural decisions
  preferences.gdlm      # User and org preferences
  tasks.gdlm            # Task history and status
  errors.gdlm           # Errors and resolutions
```

- **All agent writes go here.** Append-only with file locking.
- **Primary query target.** Agents grep active tier first.
- **Sharded by topic** to distribute write contention.

### Archive Tier

Compacted summaries of memories that have aged out of the active tier.

```
memory/archive/
  systems.gdlm          # Compacted system observations
  decisions.gdlm        # Compacted decisions
  errors.gdlm           # Compacted error history
```

- **Read-only for agents.** Only the compaction process writes here.
- **Secondary query target.** Agents search archive when active tier doesn't answer the question.
- **Summaries, not copies.** 50 related memories might become 3-5 summary records.

### History Tier

Complete, uncompacted originals. The full audit trail.

```
memory/history/
  2026-01/
    systems.gdlm        # All original system observations from Jan 2026
    decisions.gdlm      # All original decisions from Jan 2026
  2026-02/
    ...
```

- **Never queried in normal operations.** Only for forensic analysis, dispute resolution, or recovering detail lost in compaction.
- **Organized by time period** (monthly or weekly depending on volume).
- **Git-versioned** for additional protection.

---

## Compaction

Compaction is a periodic process that moves aging memories from active to archive, preserving essential knowledge while reducing volume.

### Process

```
1. Compaction agent reads active tier memories older than threshold
   (e.g., 30 days, or when active file exceeds N lines)

2. Groups related memories by subject and tags

3. For each group, generates a summary record:
   - Preserves key facts and decisions
   - Notes the count of original records
   - Links to the time period in history tier

4. Moves original records to history tier (by time period)

5. Writes summary records to archive tier

6. Removes compacted records from active tier

7. Commits all changes to git
```

### Compaction Record Format

```mem
@memory|id:MC-2026-01-sf|agent:compactor|type:summary|subject:GL_ACCOUNT|tags:snowflake,finance|detail:13 observations from sf-042 in Jan 2026. Key findings: REGION_CODE field added, 13 total columns, joins to AR_RECEIPT via GL_ACCOUNT_REF|confidence:high|source:compacted|relates:M-sf-042-001,M-sf-042-018|ts:2026-02-01T00:00:00
```

### Compaction Rules

| Rule | Description |
|------|-------------|
| **Latest wins** | When multiple memories update the same fact, keep only the latest |
| **Decisions persist** | Decision records are compacted but always preserved in summary |
| **Errors with resolutions** | Error + resolution pairs compress to the resolution |
| **Unresolved errors** | Errors without resolutions are promoted to active (not compacted) |
| **Corrections collapse** | Original + correction becomes just the corrected version |
| **Deletions vanish** | Records marked `status:deleted` are moved to history only |

### Compaction Trigger

- **Time-based:** Memories older than N days (configurable, default 30)
- **Volume-based:** When an active file exceeds N lines (configurable, default 1,000)
- **Manual:** Triggered by orchestration layer or human operator

---

## Concept Anchors

Concept Anchors provide deterministic, file-native similarity search without vector embeddings. They solve the retrieval problem: "How does an agent find conceptually related memories when it doesn't know the exact field values to grep for?"

### How It Works

A small anchor file maps core concepts to scope keywords. When an agent needs related memories, it does a two-grep lookup:

```
1. Grep the anchor file for the query term → find the concept anchor
2. Grep active memories for that anchor → find all related memories
```

### Anchor File Format

```
memory/anchors.gdlm
```

```mem
@anchor|concept:data-pipeline|scope:etl,sync,transform,load,extract,ingest,fivetran,dbt,pipeline,batch,stream,cdc
@anchor|concept:auth-security|scope:authentication,authorization,oauth,jwt,token,session,rbac,permission,sso,mfa,credential
@anchor|concept:customer-data|scope:customer,account,contact,client,subscriber,user,profile,crm,salesforce
@anchor|concept:financial-reporting|scope:gl,ledger,journal,receipt,invoice,billing,revenue,cost,budget,forecast,ar,ap
@anchor|concept:data-quality|scope:validation,duplicate,missing,null,anomaly,outlier,drift,freshness,completeness,accuracy
@anchor|concept:performance|scope:latency,throughput,timeout,slow,bottleneck,cache,index,optimize,scale,memory,cpu
@anchor|concept:schema-change|scope:migration,alter,add-column,drop,rename,refactor,breaking-change,backward-compatible
@anchor|concept:error-handling|scope:retry,fallback,circuit-breaker,timeout,exception,failure,recovery,dead-letter,alert
@anchor|concept:compliance|scope:gdpr,sox,hipaa,pci,audit,retention,encryption,masking,anonymize,consent,regulation
@anchor|concept:integration|scope:api,webhook,rest,graphql,grpc,connector,adapter,middleware,gateway,endpoint
```

### Two-Grep Retrieval

**Agent query:** "What do we know about data quality issues?"

```bash
# Step 1: Find the concept anchor
grep "data quality" memory/anchors.gdlm
# → @anchor|concept:data-quality|scope:validation,duplicate,missing,null,anomaly,...

# Step 2: Find memories tagged with this anchor
grep "anchor:data-quality" memory/active/*.gdlm
# → All memories that agents tagged with the data-quality anchor
```

**Agent query:** "Anything related to authentication?"

```bash
# Step 1: Find anchor (grep any scope keyword)
grep "authentication\|oauth\|jwt" memory/anchors.gdlm
# → @anchor|concept:auth-security|scope:authentication,authorization,oauth,jwt,...

# Step 2: Find memories
grep "anchor:auth-security" memory/active/*.gdlm
```

### Anchor Design Principles

| Principle | Description |
|-----------|-------------|
| **50-100 anchors** | Enough to cover the conceptual landscape, few enough to be manageable |
| **Broad scope keywords** | Each anchor maps 8-15 keywords covering synonyms, abbreviations, and related terms |
| **Two-grep maximum** | Any retrieval completes in exactly two grep calls |
| **Agent-maintained** | Agents can propose new anchors when they encounter concepts that don't fit existing ones |
| **Domain-agnostic** | Anchors work for technical, business, compliance, or any other conceptual domain |
| **Flat structure** | No hierarchy. A memory can reference any anchor regardless of "category" |

### When Agents Write Memories

Agents include the `anchor` field when writing memories to enable future concept-based retrieval:

```mem
@memory|id:M-sf-042-018|agent:sf-042|subject:GL_ACCOUNT|anchor:schema-change|tags:snowflake,finance|detail:added REGION_CODE VARCHAR(100) for geographic region tracking|confidence:high|ts:2026-01-31T14:30:00
```

The anchor field is optional. Memories without anchors are still findable by subject, tags, and other fields. Anchors add a conceptual retrieval path.

### Expanding Anchors

Anchors are not limited to business domains. They can represent any conceptual grouping:

| Domain | Example Anchors |
|--------|----------------|
| **Technical** | `retry-logic`, `caching-strategy`, `deployment-pattern` |
| **Business** | `customer-churn`, `revenue-recognition`, `pricing-model` |
| **Compliance** | `data-retention`, `access-control`, `audit-trail` |
| **Project** | `migration-phase`, `rollback-plan`, `go-live-readiness` |
| **User preferences** | `response-style`, `tool-preferences`, `reporting-format` |
| **Architectural** | `microservices`, `event-driven`, `data-mesh` |

New anchors are proposed by agents and added to `anchors.gdlm` through the standard append workflow.

---

## Corrections and Deletions

### Corrections

Append a new record with the same ID. Latest timestamp wins.

```mem
@memory|id:M-sf-042-001|agent:sf-042|subject:GL_ACCOUNT|detail:has 12 columns|ts:2026-01-31T14:30:00
@memory|id:M-sf-042-001|agent:sf-042|subject:GL_ACCOUNT|detail:has 13 columns|status:corrected|ts:2026-01-31T14:45:00
```

**Resolution rule:** `grep "id:M-sf-042-001" memory/active/systems.gdlm | tail -1`

### Deletions

Append with `status:deleted`:

```mem
@memory|id:M-sf-042-001|agent:sf-042|status:deleted|ts:2026-01-31T16:00:00
```

The original record remains in the file (and eventually moves to history via compaction). The deletion marker ensures agents reading the latest version see it as deleted.

---

## Memory Types

| Type | Purpose | Retention | Example |
|------|---------|-----------|---------|
| `observation` | Something the agent noticed | Compacts after 30 days | "GL_ACCOUNT has a new field" |
| `decision` | A choice that was made | Always preserved in summaries | "Chose JWT over session tokens" |
| `preference` | User or org preference | Long-lived, rarely compacted | "User prefers concise responses" |
| `error` | Something that went wrong | Compacts with resolution | "Snowflake query timeout on large join" |
| `fact` | Established knowledge | Compacts, latest version kept | "GL_ACCOUNT has 13 columns" |
| `task` | Work done or pending | Compacts when completed | "Completed Snowflake audit" |
| `procedural` | How-to knowledge (runbooks, workflows) | Long-lived, updated when process changes | "To deploy: run build, then push to main" |
| `summary` | Compacted summary record | Archive tier, long-lived | "13 observations in Jan 2026..." |

---

## Tags

Tags provide multi-path retrieval. A memory can have multiple tags, enabling discovery from different angles:

```mem
@memory|id:M-sf-042-018|agent:sf-042|subject:GL_ACCOUNT|tags:snowflake,finance,schema-change,region|anchor:schema-change|detail:added REGION_CODE|ts:2026-01-31T14:30:00
```

This memory is findable via:
- `grep "subject:GL_ACCOUNT"` (by subject)
- `grep "tags:.*snowflake"` (by system tag)
- `grep "tags:.*schema-change"` (by change type tag)
- `grep "anchor:schema-change"` (by concept anchor)
- `grep "agent:sf-042"` (by authoring agent)

Tags are free-form. There is no controlled vocabulary. Agents use whatever tags make sense for retrieval. Over time, common tag patterns emerge organically.

---

## Relates

The `relates` field links memories to each other, creating an explicit knowledge graph within the memory layer. Relationships can optionally include a **type** using `~` syntax for filtered traversal.

### Basic Syntax (untyped)

```
relates:M-sf-042-015,M-db-007-003
```

### Typed Syntax

```
relates:supersedes~M-sf-042-015,caused_by~M-db-007-003
```

### Relationship Types

| Type | Meaning | Use Case |
|------|---------|----------|
| `supersedes` | This memory replaces that one | Version chains, corrections |
| `caused_by` | This happened because of that | Root cause analysis |
| `supports` | This evidence backs that claim | Evidence gathering |
| `contradicts` | This conflicts with that | Conflict detection |
| `refines` | This adds detail to that | Detail expansion |

Types are **recommended but not enforced**. Untyped relationships remain valid. Use types when the relationship semantic matters for traversal.

### Example

```mem
@memory|id:M-sf-042-018|agent:sf-042|subject:GL_ACCOUNT|detail:added REGION_CODE|relates:supersedes~M-sf-042-015|ts:2026-01-31T14:30:00
@memory|id:M-sf-042-015|agent:sf-042|subject:GL_ACCOUNT|detail:region tracking requested by analytics team|ts:2026-01-30T10:00:00
```

An agent reading M-sf-042-018 can follow the `relates` link to find the original request that led to the change.

### Graph Queries

```bash
# Find all memories related to a specific memory (any type)
grep "relates:.*M-sf-042-018" memory/active/*.gdlm

# Find memories with a specific relationship type
grep "relates:.*supersedes~" memory/active/*.gdlm
grep "relates:.*caused_by~" memory/active/*.gdlm

# Find the chain: start with a memory, follow its relates
grep "id:M-sf-042-018" memory/active/*.gdlm | grep -o 'relates:[^|]*' | sed 's/^relates://'
# → supersedes~M-sf-042-015

# Reverse lookup: what points TO this memory?
grep "relates:.*M-sf-042-015" memory/active/*.gdlm

# Reverse lookup with type filter
grep "relates:.*supersedes~M-sf-042-015" memory/active/*.gdlm
```

For complex traversal patterns, see `scripts/gdlm-tools.sh` helpers.

---

## Confidence

The `confidence` field records how certain the agent is about a piece of knowledge:

| Level | Meaning | Agent Action |
|-------|---------|-------------|
| `high` | Verified fact or direct observation | Trust without further checking |
| `medium` | Inferred or partially verified | Consider verifying before acting on it |
| `low` | Uncertain, speculative, or from indirect source | Verify before any action |

```mem
@memory|id:M-sf-042-018|agent:sf-042|subject:GL_ACCOUNT|detail:REGION_CODE maps to ISO 3166 codes|confidence:high|ts:2026-01-31T14:30:00
@memory|id:M-db-007-005|agent:db-007|subject:customer_analytics|detail:refresh might be running weekly not daily|confidence:low|ts:2026-01-31T15:00:00
```

Agents should weight high-confidence memories over low-confidence ones when conflicts exist.

---

## Vector Embeddings (Optional)

Vector embeddings provide probabilistic semantic search as an optional layer on top of the deterministic grep-native system.

### When to Use

- The anchor system handles 90%+ of similarity queries deterministically
- Vectors add value when: the concept space is very large (1000+ anchors would be unwieldy), queries are genuinely open-ended and can't be anticipated, or fuzzy matching across natural language descriptions is needed

### Architecture

```
memory/
  active/*.gdlm          # Source of truth (GDL format, grep-native)
  vectors/
    embeddings.json     # Vector index (derived, regenerable)
```

The vector index is **derived** from the .gdlm files, not the other way around. If vectors are lost, they can be regenerated from the source .gdlm files.

### Embedding Process

1. New memory written to .gdlm file (normal append workflow)
2. Background process reads new records and generates embeddings
3. Embeddings stored alongside the memory ID for lookup
4. Semantic search returns memory IDs, which are then resolved via grep

### Key Principle

Vectors are a **search optimization**, not a data format. The .gdlm files remain the source of truth. Grep remains the primary query mechanism. Vectors provide an additional retrieval path for cases where concept anchors are insufficient.

---

## File Conventions

| Convention | Value |
|------------|-------|
| Extension | `.gdlm` |
| Encoding | UTF-8 |
| Line ending | LF |
| Comments | Lines starting with `#` or `//` |
| Blank lines | Allowed (ignored) |

---

## Directory Structure

```
memory/
  anchors.gdlm                    # Concept anchor definitions
  active/                        # Current working memory
    systems.gdlm
    decisions.gdlm
    preferences.gdlm
    tasks.gdlm
    errors.gdlm
  archive/                       # Compacted summaries
    systems.gdlm
    decisions.gdlm
    errors.gdlm
  history/                       # Uncompacted originals
    2026-01/
      systems.gdlm
      decisions.gdlm
      tasks.gdlm
      errors.gdlm
    2026-02/
      ...
  vectors/                       # Optional vector embeddings
    embeddings.json
```

---

## Grep Patterns

| Task | Command |
|------|---------|
| Find by subject | `grep "subject:GL_ACCOUNT" memory/active/*.gdlm` |
| Find by agent | `grep "agent:sf-042" memory/active/*.gdlm` |
| Find by tag | `grep "tags:.*snowflake" memory/active/*.gdlm` |
| Find by anchor | `grep "anchor:data-quality" memory/active/*.gdlm` |
| Find by type | `grep "type:decision" memory/active/*.gdlm` |
| Latest version of a memory | `grep "id:M-sf-042-001" memory/active/systems.gdlm \| tail -1` |
| Today's memories | `grep "2026-01-31" memory/active/*.gdlm` |
| High-confidence only | `grep "confidence:high" memory/active/*.gdlm` |
| Related memories | `grep "relates:.*M-sf-042-018" memory/active/*.gdlm` |
| All from archive | `grep "subject:GL_ACCOUNT" memory/archive/*.gdlm` |
| Concept anchor lookup | `grep "etl\|pipeline" memory/anchors.gdlm` |

---

## Design Principles

1. **GDL-native** - Memory records use the same `@type|key:value` format as GDL. Same tools, same grep patterns.
2. **Three-tier lifecycle** - Active for speed, archive for compacted insights, history for complete audit trail.
3. **Concept Anchors** - Deterministic similarity search in two grep calls. No vectors required.
4. **Multi-path retrieval** - Subject, tags, anchors, type, agent, and relates all provide independent retrieval paths.
5. **Append-only corrections** - Latest timestamp wins. Full history preserved.
6. **Confidence-aware** - Agents can weight knowledge by certainty level.
7. **Compaction as curation** - Old memories don't disappear, they get summarized. Originals preserved in history.
8. **Vectors optional** - Deterministic retrieval first. Probabilistic search available when needed.

---

## Relationship to GDLS and GDL

| | GDLS | GDL | Memory | Code | Documents |
|--|------|-----|--------|------|-----------|
| Purpose | Schema and relationships | Deterministic data records | Agent knowledge and state | File-level code index | Unstructured content index |
| Content | Structure of external systems | Facts about business entities | Observations, decisions, context | Files, exports, imports | PDFs, transcripts, media indexes |
| Authored by | Schema tools/validation | Data processes/agents | Agents during operation | src2gdlc (tree-sitter) | Agents during ingestion |
| Mutability | Low (schema changes are rare) | Medium (records update) | High (knowledge evolves constantly) | Medium (changes with code) | Medium (new docs added, supersession) |
| Fields | Positional (fixed structure) | Key:value (self-describing) | Key:value + memory-specific | Positional (5-field files) | Key:value (`@source`, `@section`, `@extract`) |
| Extension | `.gdls` | `.gdl` | `.gdlm` | `.gdlc` | `.gdlu` |
| Shared | `@` prefix, `\|` delimiter, line-oriented, grep-first |
