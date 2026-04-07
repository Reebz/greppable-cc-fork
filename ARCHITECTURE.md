# Multi-Agent Orchestration Architecture

A file-native, grep-queryable architecture for multi-agent systems using GDLS, GDL, GDLC, GDLA, Memory, Diagrams, and Documents as the schema, data, code structure, API contract, knowledge, visual context, and unstructured content layers.

---

## Overview

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                          Agent Layer                                                      │
│                                                                                          │
│   sf-agent    db-agent    crm-agent    analytics-agent  ...                              │
│   (Snowflake) (Databricks) (Salesforce) (Reporting)                                      │
│                                                                                          │
│   Each agent: reads any file, appends to shared memory,                                  │
│   proposes schema changes, queries data and diagrams via grep                            │
├──────────────────────────────────────────────────────────────────────────────────────────┤
│                          File Layer                                                      │
│                                                                                          │
│   schema/    code/       api/        memory/     data/       diagrams/  unstructured/    │
│   *.gdls     *.gdlc      *.gdla      *.gdlm      *.gdl      *.gdld     *.gdlu          │
│                                                                                          │
│   Map of the Code        API         Shared     Company    Visual     Document           │
│   world      structure   contracts   agent      data       knowledge  indexes            │
│              maps                    knowledge  records    (flows)    (PDFs, media)       │
│                                                                                          │
│   All git-versioned. All grep-native. No database required.                              │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

**Core principle:** The filesystem is the coordination layer. Git is the audit trail. Grep is the query engine.

---

## File Structure

```
project/
├── schema/                          # GDLS - structural maps of external systems
│   ├── snowflake/
│   │   ├── _index.gdls               # Domain navigation index
│   │   ├── finance/
│   │   │   └── schema.gdls           # Table definitions (250 tables)
│   │   ├── hr/
│   │   │   └── schema.gdls
│   │   └── sales/
│   │       └── schema.gdls
│   ├── databricks/
│   │   ├── _index.gdls
│   │   └── warehouse/
│   │       └── schema.gdls
│   └── salesforce/
│       ├── _index.gdls
│       └── objects/
│           └── schema.gdls
│
├── memory/                          # Agent memory (.gdlm) - see specs/GDLM-SPEC.md
│   ├── anchors.gdlm                  # Concept anchor definitions
│   ├── active/                      # Current working memory
│   │   ├── systems.gdlm              # Observations about external systems
│   │   ├── decisions.gdlm            # Design/architectural decisions
│   │   ├── preferences.gdlm          # User and org preferences
│   │   ├── tasks.gdlm                # Task history and status
│   │   └── errors.gdlm               # Errors encountered and resolutions
│   ├── archive/                     # Compacted summaries (read-only)
│   │   └── *.gdlm
│   └── history/                     # Full uncompacted originals
│       └── {period}/*.gdlm
│
├── data/                            # GDL - company data records
│   ├── customers.gdl
│   ├── orders.gdl
│   └── products.gdl
│
├── code/                            # GDLC - file-level code index
│   └── project.gdlc                   # @D directory records, @F file records (paths, exports, imports)
│
├── api/                             # GDLA - API contract maps
│   ├── petstore.openapi.gdla          # OpenAPI-sourced contract
│   └── graphql.gdla                   # GraphQL-sourced contract
│
├── diagrams/                        # GDLD - visual knowledge (flows, patterns)
│   ├── flows/                       # Architecture and processing flows
│   │   ├── document-ingestion.gdld
│   │   ├── search-pipeline.gdld
│   │   └── data-processing.gdld
│   ├── patterns/                    # Reusable patterns with gotchas
│   │   ├── file-based-state.gdld
│   │   └── large-file-navigation.gdld
│   ├── concepts/                    # Knowledge graphs and relationships
│   │   ├── character-relationships.gdld
│   │   └── cross-project-patterns.gdld
│   ├── states/                      # State machine diagrams
│   │   └── order-lifecycle.gdld
│   └── sequences/                   # Sequence/interaction diagrams
│       └── agent-handoff.gdld
│
├── unstructured/                    # GDLU - unstructured content indexes
│   ├── contracts/
│   │   ├── acme-msa.pdf             # Source document (not GDL)
│   │   └── contracts.gdlu           # Index of contracts
│   ├── meetings/
│   │   └── meetings.gdlu            # Index of meeting transcripts
│   └── research/
│       └── research.gdlu            # Index of research documents
│
├── schema-updates/                  # Proposed schema changes (staging area)
│   ├── pending/                     # Awaiting validation
│   └── applied/                     # Applied changes (audit trail)
│
└── .git/                            # Version control for everything
```

---

## How Agents Operate

### Agent Bootstrap

When an agent starts, it reads in this order:

1. **Schema index** - `grep "^@DOMAIN" schema/{system}/_index.gdls` to understand what domains exist
2. **Relevant memory** - `grep "subject:{relevant_topic}" memory/active/systems.gdlm` to see what other agents already know
3. **Task context** - `grep "agent:{self}" memory/active/tasks.gdlm` to see own history and pending work
4. **Concept anchors** - `memory/anchors.gdlm` loaded for concept-based retrieval during operation
5. **Architecture context** (optional) - `grep "^@diagram" diagrams/*.gdld` for available flow/pattern/sequence diagrams
6. **Document context** (optional) - `grep "^@source.*signal:high" unstructured/**/*.gdlu` for key unstructured documents

This gives the agent a complete picture: what the systems look like (GDLS), what's been learned (memory), what needs doing (tasks), how systems are structured (diagrams), and what documents exist (GDLU). See specs/GDLM-SPEC.md for the full three-tier memory model.

### Read Path (Any Agent, Any Time)

Agents read freely from any file. No locks needed for reads.

```bash
# Understand a table's structure
grep "^@T GL_ACCOUNT" -A 30 schema/snowflake/finance/schema.gdls

# Check what other agents know about this table
grep "subject:GL_ACCOUNT" memory/active/systems.gdlm

# Find enterprise customers in data
grep "tier:enterprise" data/customers.gdl

# Check recent decisions
grep "type:decision" memory/active/decisions.gdlm | tail -10

# Concept-based search: find related knowledge
grep "pipeline" memory/anchors.gdlm
# → @anchor|concept:data-pipeline|scope:etl,sync,...
grep "anchor:data-pipeline" memory/active/*.gdlm

# Check architecture gotchas before implementing
grep "^@gotcha" diagrams/flows/*.gdld

# Find sequence diagrams for agent interactions
grep "@diagram.*type:sequence" diagrams/sequences/*.gdld
```

### Write Path (Memory)

Agents append to shared memory files using file locking:

```
1. Agent acquires file lock (flock)
2. Agent appends one line to the appropriate .gdlm file
3. Agent releases lock
4. Agent commits and pushes to git
```

Lock duration: microseconds (single line append). At 100 agents writing a few times per minute, contention is effectively zero.

**Memory write example:**

```mem
@memory|id:M-sf-042-017|agent:sf-042|type:observation|subject:GL_ACCOUNT|anchor:schema-change|tags:snowflake,finance|detail:NEW_FIELD added, contains region codes, VARCHAR(100)|confidence:high|ts:2026-01-31T14:30:00
```

See specs/GDLM-SPEC.md for the full memory format including concept anchors, confidence levels, and the three-tier lifecycle.

### Write Path (Schema Updates)

Schema changes require validation because they affect all agents' understanding of the system. The workflow:

```
1. Agent discovers a change in the external system
   (e.g., new field created in Snowflake)

2. Agent writes a proposed change to schema-updates/pending/
   File: {agent}-{timestamp}.gdl

3. Agent logs the discovery in memory
   → appends to memory/active/systems.gdlm

4. Validation process applies the change
   - Reads the pending file
   - Updates the relevant .gdls schema
   - Moves the pending file to applied/
   - Commits to git

5. Other agents get the update on next git pull
```

**Pending schema change format:**

```gdl
@schema-update|agent:sf-042|system:snowflake|domain:finance|table:GL_ACCOUNT|action:add-column|column:NEW_FIELD|type:VARCHAR(100)|nullable:Y|ts:2026-01-31T14:30:00
```

**Validation** can be:
- A cron job that processes pending/ every N seconds
- A git hook triggered on push
- A dedicated lightweight validation agent
- Manual review for critical schemas

The validation step is intentionally decoupled from the writing agent. The agent proposes; the system applies.

---

## Memory Patterns

> Full specification: **specs/GDLM-SPEC.md**

Memory uses a three-tier model: **active** (recent, read/write), **archive** (compacted summaries, read-only), and **history** (full uncompacted originals, forensic use). Agents write to active tier and query active first, falling back to archive.

### Key Features

| Feature | Description |
|---------|-------------|
| **Concept Anchors** | Deterministic similarity search in two grep calls via `memory/anchors.gdlm` |
| **Multi-path retrieval** | Subject, tags, anchors, type, agent, relates - multiple ways to find knowledge |
| **Three-tier lifecycle** | Active → Archive (compacted) → History (full originals) |
| **Confidence levels** | `high`, `medium`, `low` - agents weight knowledge by certainty |
| **Append-only corrections** | Latest timestamp wins. Full history preserved |
| **Compaction** | Periodic summarization of aging memories, originals preserved in history |

### Core Memory Queries

| Question | Command |
|----------|---------|
| What do we know about GL_ACCOUNT? | `grep "subject:GL_ACCOUNT" memory/active/*.gdlm` |
| What has the Snowflake agent learned? | `grep "agent:sf-042" memory/active/*.gdlm` |
| What decisions were made today? | `grep "type:decision" memory/active/decisions.gdlm \| grep "2026-01-31"` |
| Concept search (data quality) | `grep "data.quality" memory/anchors.gdlm` then `grep "anchor:data-quality" memory/active/*.gdlm` |
| Latest version of a memory | `grep "id:M-sf-042-001" memory/active/systems.gdlm \| tail -1` |
| Check archive for older knowledge | `grep "subject:GL_ACCOUNT" memory/archive/*.gdlm` |

---

## Concurrency Model

### Why File Locking Works at 100 Agents

Agent operations are slow relative to I/O:
- External API call (Snowflake, Salesforce): 1-10 seconds
- Claude thinking/generating: 2-15 seconds
- Full agent task cycle: 30 seconds to minutes

Memory writes are fast:
- Acquire lock: ~microseconds
- Append one line: ~microseconds
- Release lock: ~microseconds

At 100 agents each writing a few times per minute, the probability of two agents contending for the same lock at the same microsecond is negligible.

### Topic-Based File Sharding

Memory is sharded by topic, not by agent:

```
memory/active/
  systems.gdlm       # ~40% of writes (system observations)
  decisions.gdlm     # ~15% of writes
  tasks.gdlm         # ~25% of writes
  preferences.gdlm   # ~5% of writes
  errors.gdlm        # ~15% of writes
```

This distributes writes across files. Even if 100 agents all write to `systems.gdlm`, the lock contention per second is:

```
100 agents × 2 writes/minute = ~3.3 writes/second
Lock duration: ~100 microseconds
Contention probability: ~0.03% per write
```

Effectively zero.

### Read-Write Isolation

Reads don't require locks. An agent reading a .gdlm file while another appends to it will either see the new line or not (depending on timing), but will never see a partial line because POSIX guarantees atomic appends for lines under the pipe buffer size (~4KB). A memory line is typically 100-300 bytes.

---

## Git Coordination

### Commit Strategy

Each agent commits after meaningful work:

```bash
git add memory/active/systems.gdlm
git commit -m "sf-042: observed NEW_FIELD on GL_ACCOUNT"
git pull --rebase
git push
```

### Merge Behavior

Memory files (.gdlm) and data files (.gdl) are append-only in normal operation. Two agents appending different lines to the same file produces clean auto-merges in Git (different lines, no conflicts).

Schema files (.gdls) are modified less frequently and go through the validation workflow, so conflicts are rare and managed.

### Sync Frequency

| Agent Type | Pull Frequency | Rationale |
|------------|---------------|-----------|
| Active task agent | Every 30-60 seconds | Needs current system state |
| Background monitoring | Every 5 minutes | Low urgency |
| On-demand | Before critical operations | Pull just before making changes |

### Audit Trail

Git provides a complete audit trail automatically:

```bash
# Who changed what in memory?
git log --oneline memory/active/systems.gdlm

# What did sf-042 do today?
git log --author="sf-042" --since="2026-01-31"

# When was GL_ACCOUNT schema last updated?
git log --oneline schema/snowflake/finance/schema.gdls

# Revert an agent's mistake
git revert {commit_hash}
```

---

## Schema Update Workflow

### Discovery → Proposal → Validation → Application

```
┌──────────┐     ┌──────────────────┐     ┌────────────┐     ┌──────────┐
│  Agent    │     │  schema-updates/ │     │ Validation │     │  schema/ │
│  discovers│────>│  pending/        │────>│  process   │────>│  *.gdls   │
│  change   │     │  {agent}-{ts}.gdl│     │            │     │  updated │
└──────────┘     └──────────────────┘     └────────────┘     └──────────┘
      │                                                             │
      v                                                             v
┌──────────┐                                                 ┌──────────┐
│  memory/ │                                                 │  Other   │
│  active/ │                                                 │  agents  │
│  systems │                                                 │  git pull│
│  .gdlm    │                                                 └──────────┘
└──────────┘
```

### Example: Agent Creates a Field in Snowflake

**Step 1:** Agent executes DDL against Snowflake:
```sql
ALTER TABLE GL_ACCOUNT ADD COLUMN REGION_CODE VARCHAR(100);
```

**Step 2:** Agent writes schema update proposal:
```gdl
@schema-update|agent:sf-042|system:snowflake|domain:finance|table:GL_ACCOUNT|action:add-column|column:REGION_CODE|type:VARCHAR(100)|nullable:Y|desc:Geographic region code|ts:2026-01-31T14:30:00
```

**Step 3:** Agent logs to memory:
```mem
@memory|id:M-sf-042-018|agent:sf-042|type:observation|subject:GL_ACCOUNT|anchor:schema-change|tags:snowflake,finance|detail:added REGION_CODE VARCHAR(100) for geographic region tracking|confidence:high|ts:2026-01-31T14:30:00
```

**Step 4:** Validation process reads pending file, applies to GDLS:
```
# Appended to schema/snowflake/finance/schema.gdls under @T GL_ACCOUNT:
REGION_CODE|VARCHAR(100)|Y||Geographic region code
```

**Step 5:** Pending file moved to `schema-updates/applied/` for audit.

**Step 6:** All agents receive update on next `git pull`.

---

## Failure Modes and Recovery

### Agent Crashes Mid-Write

**Risk:** Agent acquires lock, crashes before releasing.

**Mitigation:** File locks (flock) are automatically released when the process dies. The OS handles this. If the append was partial, the incomplete line is visible but won't match any valid grep pattern (no `@memory` prefix on a partial line).

### Git Push Conflict

**Risk:** Two agents push simultaneously, one is rejected.

**Mitigation:** Standard git pull --rebase, then retry push. For append-only .gdlm and .gdl files, rebase always succeeds (no line conflicts). For schema files, conflicts are handled by the validation workflow.

### Stale Schema Read

**Risk:** Agent reads GDLS schema that doesn't reflect a recent external system change.

**Mitigation:** Agents that modify external systems MUST write both the schema update proposal AND the memory observation before proceeding with further work. Other agents can check `memory/active/systems.gdlm` for recent changes even before the schema is formally updated.

### Memory Corruption

**Risk:** A memory or data file becomes corrupted or contains incorrect data.

**Mitigation:** Git revert to last known good state. All memory is versioned. The append-based correction pattern means incorrect memories are superseded, not deleted - the full history is always available in the history tier (see specs/GDLM-SPEC.md).

### Lock Contention at Scale

**Risk:** Too many agents writing to the same file.

**Mitigation:** Topic-based file sharding distributes writes. If a single file becomes a bottleneck, further shard it (e.g., `systems-snowflake.gdlm`, `systems-databricks.gdlm`). The query pattern (`grep "subject:X" memory/active/*.gdlm`) works regardless of how many files exist.

---

## Agent Configuration

### System Prompt Template

Each agent receives a prompt based on its role:

```
{role_description}.
Schema: schema/{system}/[domain]/schema.gdls - grep "@T TABLE" with after_context=30, PK: |PK|
Memory: memory/active/*.gdlm - grep "subject:TOPIC" or "anchor:CONCEPT". Latest ts wins.
Log observations to memory/active/systems.gdlm. Log decisions to memory/active/decisions.gdlm.
```

See PROMPTS.md for optimized prompt variants by capability level.

### Tool Requirements

Minimum tool set for any agent:

| Tool | Purpose |
|------|---------|
| **Grep** | Query GDLS schemas, GDL data, agent memory |
| **Bash** | File append (with flock), git operations, external system commands |

Optional:

| Tool | Purpose |
|------|---------|
| **Read** | Full file read when grep context isn't sufficient |
| **Write** | Schema update proposals, new data files |

### Agent Identity

Each agent has a short identifier used in memory records and git commits:

```
sf-001 through sf-099    # Snowflake agents
db-001 through db-099    # Databricks agents
crm-001 through crm-099  # Salesforce agents
ops-001 through ops-099  # Operations agents
```

---

## Scaling Considerations

### Current Design: 100 Agents

- File locking: sufficient
- Git coordination: single repo, pull/push cycle
- Memory files: 5-10 topic files
- Schema files: partitioned by system and domain

### Path to 1,000 Agents

- Shard memory files by system (`systems-snowflake.gdlm`, `systems-databricks.gdlm`)
- Increase git pull frequency management (not all agents pull at the same time)
- Consider git shallow clones for agents that don't need full history

### Path to 10,000 Agents

- Git becomes the bottleneck at this scale
- Add a notification layer (pub/sub) so agents pull on-demand instead of polling
- Shard into multiple git repos by system/domain
- Consider a merge service that batches pushes
- The file format (GDLS/GDL) doesn't change - only the coordination layer scales

---

## Summary

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Schema layer | GDLS (.gdls files) | Map of external systems (tables, relationships, enums) |
| Data layer | GDL (.gdl files) | Structured business data |
| Code layer | GDLC (.gdlc files) | File-level code index (paths, exports, imports) |
| API layer | GDLA (.gdla files) | API contract maps (endpoints, schemas, auth) |
| Memory layer | Memory (.gdlm files) | Shared agent knowledge (three-tier) |
| Diagram layer | GDLD (.gdld files) | Visual knowledge (flows, patterns, gotchas) |
| Document layer | GDLU (.gdlu files) | Unstructured content index (PDFs, transcripts) |
| Retrieval | Concept Anchors (anchors.gdlm) | Deterministic similarity search |
| Coordination | Git | Version control, audit, merge |
| Concurrency | flock | File-level locking for writes |
| Query engine | grep | Universal query across all layers |
| Audit trail | git log | Who changed what, when, why |
| Recovery | git revert | Rollback any change |

No databases. No message queues. No vector databases required. No infrastructure beyond a filesystem and git.

---

## Tooling

| Tool | Script | Purpose |
|------|--------|---------|
| Lint | `scripts/gdl-lint.sh` | Format validation for all 7 GDL layers. Supports `--all` (recursive), `--strict`, `--cross-layer`, `--exclude=`. CI gate via `.github/workflows/gdl-lint.yml`. |
| Diff | `scripts/gdl-diff.sh` | Semantic diff for GDLS (table/column level), GDL/GDLM/GDLU (record/field level). Supports git-ref mode (`file HEAD~1`). |
| Generate | `gdl_new` in `scripts/gdl-tools.sh` | Auto-incremented ID generation for memory and source records. `--append` flag with flock-based locking for concurrent writes. |
| Convert | `scripts/gdls2gdld.sh`, `gdlc2gdld.sh`, `gdlu2gdld.sh`, `gdla2gdld.sh` | Cross-layer format bridges to GDLD diagrams. |
| Render | `scripts/gdld2mermaid.sh` | GDLD to Mermaid markdown with `--validate` flag. |

## Specifications

| Spec | File | Purpose |
|------|------|---------|
| GDLS | specs/GDLS-SPEC.md | Schema format for structural maps |
| GDL | specs/GDL-SPEC.md | Data format for business records |
| GDLC | specs/GDLC-SPEC.md | File-level code index format |
| GDLM | specs/GDLM-SPEC.md | Memory format with three-tier lifecycle |
| GDLD | specs/GDLD-SPEC.md | Diagram format for visual knowledge |
| GDLU | specs/GDLU-SPEC.md | Document index format for unstructured content |
| GDLA | specs/GDLA-SPEC.md | API contract format for endpoints, schemas, auth |
| GDL Skill | skills/querying-gdl-data/SKILL.md | Agent quick reference for data querying |
| Memory Skill | skills/traversing-gdlm-memory/SKILL.md | Agent quick reference for memory operations |
| GDLA Skill | skills/exploring-gdla-api-contracts/SKILL.md | Agent quick reference for API contract navigation |
| Diagram Skill | skills/querying-gdld-diagrams/SKILL.md | Agent quick reference for diagram querying |
| Meta Skill | skills/using-greppable/SKILL.md | Autopilot enforcement and format routing |

### Plugin Entry Points

Two directories serve different audiences:

| Directory | Pattern | Visibility | Purpose |
|-----------|---------|------------|---------|
| `commands/` | Flat `*.md` files | Slash autocomplete (`/greppable:X`) | User-invocable: about, convert, diagram, discover, memory, onboard, pr-summary, status |
| `skills/` | Subdirectory `SKILL.md` | Model-triggered (no slash menu) | Auto-invoked by description match: querying-gdl-data, querying-gdld-diagrams, traversing-gdlm-memory, exploring-gdla-api-contracts, using-greppable |

Commands use `disable-model-invocation: true` (human-only). Skills use `disable-model-invocation: false` (Claude decides when to invoke). Hooks in `hooks/` are auto-discovered from `hooks/hooks.json` — no declaration in `plugin.json` needed.
| Prompts | PROMPTS.md | Optimized minimal prompts for each layer |
