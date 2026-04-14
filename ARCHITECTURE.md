# Multi-Agent Orchestration Architecture

A file-native, grep-queryable architecture for multi-agent systems using GDLS, GDL, GDLA, Diagrams, and Documents as the schema, data, API contract, visual context, and unstructured content layers.

---

## Overview

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                          Agent Layer                                                      │
│                                                                                          │
│   sf-agent    db-agent    crm-agent    analytics-agent  ...                              │
│   (Snowflake) (Databricks) (Salesforce) (Reporting)                                      │
│                                                                                          │
│   Each agent: reads any file, proposes schema changes,                                   │
│   queries data and diagrams via grep                                                     │
├──────────────────────────────────────────────────────────────────────────────────────────┤
│                          File Layer                                                      │
│                                                                                          │
│   schema/    api/        data/       diagrams/  unstructured/                            │
│   *.gdls     *.gdla      *.gdl       *.gdld     *.gdlu                                  │
│                                                                                          │
│   Map of the API         Company    Visual     Document                                  │
│   world      contracts   data       knowledge  indexes                                   │
│                          records    (flows)    (PDFs, media)                              │
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
├── data/                            # GDL - company data records
│   ├── customers.gdl
│   ├── orders.gdl
│   └── products.gdl
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
2. **Architecture context** (optional) - `grep "^@diagram" diagrams/*.gdld` for available flow/pattern/sequence diagrams
3. **Document context** (optional) - `grep "^@source.*signal:high" unstructured/**/*.gdlu` for key unstructured documents

This gives the agent a complete picture: what the systems look like (GDLS), how systems are structured (diagrams), and what documents exist (GDLU).

### Read Path (Any Agent, Any Time)

Agents read freely from any file. No locks needed for reads.

```bash
# Understand a table's structure
grep "^@T GL_ACCOUNT" -A 30 schema/snowflake/finance/schema.gdls

# Find enterprise customers in data
grep "tier:enterprise" data/customers.gdl

# Check architecture gotchas before implementing
grep "^@gotcha" diagrams/flows/*.gdld

# Find sequence diagrams for agent interactions
grep "@diagram.*type:sequence" diagrams/sequences/*.gdld
```

### Write Path (Schema Updates)

Schema changes require validation because they affect all agents' understanding of the system. The workflow:

```
1. Agent discovers a change in the external system
   (e.g., new field created in Snowflake)

2. Agent writes a proposed change to schema-updates/pending/
   File: {agent}-{timestamp}.gdl

3. Validation process applies the change
   - Reads the pending file
   - Updates the relevant .gdls schema
   - Moves the pending file to applied/
   - Commits to git

4. Other agents get the update on next git pull
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

## Concurrency Model

### Why File Locking Works at 100 Agents

Agent operations are slow relative to I/O:
- External API call (Snowflake, Salesforce): 1-10 seconds
- Claude thinking/generating: 2-15 seconds
- Full agent task cycle: 30 seconds to minutes

File writes are fast:
- Acquire lock: ~microseconds
- Append one line: ~microseconds
- Release lock: ~microseconds

At 100 agents each writing a few times per minute, the probability of two agents contending for the same lock at the same microsecond is negligible. Reads don't require locks. POSIX guarantees atomic appends for lines under the pipe buffer size (~4KB), so concurrent readers never see partial lines.

---

## Git Coordination

### Commit Strategy

Each agent commits after meaningful work:

```bash
git add schema-updates/pending/sf-042-20260131.gdl
git commit -m "sf-042: propose REGION_CODE on GL_ACCOUNT"
git pull --rebase
git push
```

### Merge Behavior

Data files (.gdl) are append-only in normal operation. Two agents appending different lines to the same file produces clean auto-merges in Git (different lines, no conflicts).

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
                                                                    │
                                                                    v
                                                              ┌──────────┐
                                                              │  Other   │
                                                              │  agents  │
                                                              │  git pull│
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

**Step 3:** Validation process reads pending file, applies to GDLS:
```
# Appended to schema/snowflake/finance/schema.gdls under @T GL_ACCOUNT:
REGION_CODE|VARCHAR(100)|Y||Geographic region code
```

**Step 4:** Pending file moved to `schema-updates/applied/` for audit.

**Step 5:** All agents receive update on next `git pull`.

---

## Failure Modes and Recovery

### Agent Crashes Mid-Write

**Risk:** Agent acquires lock, crashes before releasing.

**Mitigation:** File locks (flock) are automatically released when the process dies. The OS handles this. If the append was partial, the incomplete line is visible but won't match any valid grep pattern (no valid record prefix on a partial line).

### Git Push Conflict

**Risk:** Two agents push simultaneously, one is rejected.

**Mitigation:** Standard git pull --rebase, then retry push. For append-only .gdl files, rebase always succeeds (no line conflicts). For schema files, conflicts are handled by the validation workflow.

### Stale Schema Read

**Risk:** Agent reads GDLS schema that doesn't reflect a recent external system change.

**Mitigation:** Agents that modify external systems MUST write the schema update proposal before proceeding with further work. Other agents receive updates on next git pull once the validation process applies the change.

### Lock Contention at Scale

**Risk:** Too many agents writing to the same file.

**Mitigation:** Files are partitioned by system and domain, distributing writes across many files. If a single file becomes a bottleneck, further shard it. The grep-based query pattern works regardless of how many files exist.

---

## Agent Configuration

### System Prompt Template

Each agent receives a prompt based on its role:

```
{role_description}.
Schema: schema/{system}/[domain]/schema.gdls - grep "@T TABLE" with after_context=30, PK: |PK|
```

See PROMPTS.md for optimized prompt variants by capability level.

### Tool Requirements

Minimum tool set for any agent:

| Tool | Purpose |
|------|---------|
| **Grep** | Query GDLS schemas, GDL data, diagrams |
| **Bash** | File append (with flock), git operations, external system commands |

Optional:

| Tool | Purpose |
|------|---------|
| **Read** | Full file read when grep context isn't sufficient |
| **Write** | Schema update proposals, new data files |

### Agent Identity

Each agent has a short identifier used in records and git commits:

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
- Schema files: partitioned by system and domain

### Path to 1,000 Agents

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
| API layer | GDLA (.gdla files) | API contract maps (endpoints, schemas, auth) |
| Diagram layer | GDLD (.gdld files) | Visual knowledge (flows, patterns, gotchas) |
| Document layer | GDLU (.gdlu files) | Unstructured content index (PDFs, transcripts) |
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
| Lint | `scripts/gdl-lint.sh` | Format validation for all 5 GDL layers. Supports `--all` (recursive), `--strict`, `--cross-layer`, `--exclude=`. CI gate via `.github/workflows/gdl-lint.yml`. |
| Diff | `scripts/gdl-diff.sh` | Semantic diff for GDLS (table/column level), GDL/GDLU (record/field level). Supports git-ref mode (`file HEAD~1`). |
| Generate | `gdl_new` in `scripts/gdl-tools.sh` | Auto-incremented ID generation for source records. `--append` flag with flock-based locking for concurrent writes. |
| Convert | `scripts/gdls2gdld.sh`, `gdlu2gdld.sh`, `gdla2gdld.sh` | Cross-layer format bridges to GDLD diagrams. |
| Render | `scripts/gdld2mermaid.sh` | GDLD to Mermaid markdown with `--validate` flag. |

## Specifications

| Spec | File | Purpose |
|------|------|---------|
| GDLS | specs/GDLS-SPEC.md | Schema format for structural maps |
| GDL | specs/GDL-SPEC.md | Data format for business records |
| GDLD | specs/GDLD-SPEC.md | Diagram format for visual knowledge |
| GDLU | specs/GDLU-SPEC.md | Document index format for unstructured content |
| GDLA | specs/GDLA-SPEC.md | API contract format for endpoints, schemas, auth |
| GDL Skill | skills/querying-gdl-data/SKILL.md | Agent quick reference for data querying |
| GDLA Skill | skills/exploring-gdla-api-contracts/SKILL.md | Agent quick reference for API contract navigation |
| Diagram Skill | skills/querying-gdld-diagrams/SKILL.md | Agent quick reference for diagram querying |
| Meta Skill | skills/using-greppable/SKILL.md | Autopilot enforcement and format routing |

### Plugin Entry Points

Two directories serve different audiences:

| Directory | Pattern | Visibility | Purpose |
|-----------|---------|------------|---------|
| `commands/` | Flat `*.md` files | Slash autocomplete (`/greppable:X`) | User-invocable: about, convert, diagram, discover, onboard, pr-summary, status |
| `skills/` | Subdirectory `SKILL.md` | Model-triggered (no slash menu) | Auto-invoked by description match: querying-gdl-data, querying-gdld-diagrams, exploring-gdla-api-contracts, using-greppable |

Commands use `disable-model-invocation: true` (human-only). Skills use `disable-model-invocation: false` (Claude decides when to invoke). Hooks in `hooks/` are auto-discovered from `hooks/hooks.json` — no declaration in `plugin.json` needed.
| Prompts | PROMPTS.md | Optimized minimal prompts for each layer |
