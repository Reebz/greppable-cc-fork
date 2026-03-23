---
name: traversing-gdlm-memory
description: "Use when agent memory from prior sessions could inform current work — choosing between alternatives when past decisions exist, investigating why something was built a certain way, or checking if a problem was already solved. Triggers on: \"what did we decide about X\", \"why did we choose Y\", \"what do we know about Z\", references to past session work (\"last time\", \"before\", \"we decided\"), recording decisions/observations/errors, correcting memories, following supersedes chains, concept anchors, or any .gdlm file operation. NOT for general \"remember my preferences\", git log/blame searches, episodic conversation memory, PR comment reviews, or meeting notes in docs/."
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
context: fork
---

# Memory Quick Reference

## Available Memory Files

!`bash -c 'find docs/gdl/memory/active -name "*.gdlm" -maxdepth 1 2>/dev/null | while read f; do count=$(grep -c "^@memory" "$f" 2>/dev/null || echo 0); echo "- $(basename "$f"): $count records"; done'`

## Format

```
@memory|id:{id}|agent:{agent}|subject:{subject}|tags:{t1,t2}|detail:{text}|confidence:{level}|anchor:{concept}|ts:{timestamp}
```

Each memory is one line. Each field is self-describing (key:value). Latest timestamp wins for corrections.

## Required Fields

| Field | Description |
|-------|-------------|
| `id` | `M-{agent}-{seq}` unique identifier |
| `agent` | Agent that authored the memory |
| `subject` | Primary topic (flat) |
| `detail` | The knowledge content |
| `ts` | ISO timestamp |

## Optional Fields

| Field | Description |
|-------|-------------|
| `tags` | Comma-separated retrieval tags |
| `confidence` | `high`, `medium`, `low` |
| `relates` | Links to other memory IDs (typed: `supersedes~M-001`) |
| `type` | `observation`, `decision`, `preference`, `error`, `fact`, `task`, `procedural` |
| `anchor` | Concept anchor reference |
| `status` | `corrected`, `deleted`, `compacted` |

## Three Tiers

| Tier | Path | Purpose |
|------|------|---------|
| Active | `memory/active/*.gdlm` | Current working memory (read/write) |
| Archive | `memory/archive/*.gdlm` | Compacted summaries (read-only) |
| History | `memory/history/{period}/*.gdlm` | Full originals (forensic only) |

## Concept Anchors

Two-grep similarity search via `memory/anchors.gdlm`:

```bash
# Step 1: Find anchor by keyword
grep "authentication\|oauth" memory/anchors.gdlm
# → @anchor|concept:auth-security|scope:authentication,authorization,oauth,...

# Step 2: Find memories by anchor
grep "anchor:auth-security" memory/active/*.gdlm
```

## Grep Patterns

```bash
# By subject
grep "subject:GL_ACCOUNT" memory/active/*.gdlm

# By agent
grep "agent:sf-042" memory/active/*.gdlm

# By tag
grep "tags:.*snowflake" memory/active/*.gdlm

# By anchor concept
grep "anchor:data-quality" memory/active/*.gdlm

# By type
grep "type:decision" memory/active/*.gdlm

# Latest version of a memory
grep "id:M-sf-042-001" memory/active/systems.gdlm | tail -1

# High-confidence only
grep "confidence:high" memory/active/*.gdlm

# Related memories
grep "relates:.*M-sf-042-018" memory/active/*.gdlm

# Search archive when active doesn't answer
grep "subject:GL_ACCOUNT" memory/archive/*.gdlm
```

## Graph Traversal

Source the helpers: `source "${CLAUDE_PLUGIN_ROOT}/scripts/gdlm-tools.sh"`

| Helper | Purpose | Example |
|--------|---------|---------|
| `gdlm_get` | Fetch memory by ID | `gdlm_get M-sf-042-018` |
| `gdlm_outbound` | What does X relate to? | `gdlm_outbound M-001 supersedes` |
| `gdlm_inbound` | What points TO X? | `gdlm_inbound M-001 caused_by` |
| `gdlm_follow` | Follow chain N hops | `gdlm_follow M-ERR-001 caused_by 5` |
| `gdlm_chain` | Follow to end | `gdlm_chain M-001 supersedes` |
| `gdlm_filter` | Filter by type + keyword | `gdlm_filter decision auth` |

### Relationship Types

| Type | Meaning |
|------|---------|
| `supersedes` | This replaces that |
| `caused_by` | This happened because of that |
| `supports` | This evidence backs that claim |
| `contradicts` | This conflicts with that |
| `refines` | This adds detail to that |

## Writing Memories

```mem
@memory|id:M-sf-042-018|agent:sf-042|subject:GL_ACCOUNT|anchor:schema-change|tags:snowflake,finance|detail:added REGION_CODE VARCHAR(100)|confidence:high|ts:2026-01-31T14:30:00
```

## Corrections

Append new record with same ID. Latest timestamp wins:

```mem
@memory|id:M-sf-042-001|agent:sf-042|subject:GL_ACCOUNT|detail:has 13 columns|status:corrected|ts:2026-01-31T14:45:00
```

## Deletions

Append with `status:deleted`:

```mem
@memory|id:M-sf-042-001|agent:sf-042|status:deleted|ts:2026-01-31T16:00:00
```

## Key Rules

- Each line is a complete, self-describing record
- `grep "key:value"` directly answers queries - no context lines needed
- Active tier is the primary query target; search archive when active is insufficient
- Concept anchors enable similarity search in exactly two grep calls
- Latest timestamp always wins for corrections
- Include `anchor` field when writing to enable concept-based retrieval

## Query Cookbook

Common queries translated to commands:

| Question | Command |
|----------|---------|
| "Auth decisions last month" | `grep "type:decision" *.gdlm \| grep "anchor:auth-security" \| grep "2026-01"` |
| "What superseded M-001?" | `gdlm_inbound M-001 supersedes` |
| "Current version of M-001" | `gdlm_chain M-001 supersedes` |
| "Why did this error happen?" | `gdlm_follow M-ERR-001 caused_by 5` |
| "How important is M-001?" | `gdlm_inbound M-001 \| wc -l` |
| "All procedural knowledge" | `gdlm_filter procedural` |
| "Decisions about deployment" | `gdlm_filter decision deploy` |
| "High-confidence facts" | `grep "type:fact" *.gdlm \| grep "confidence:high"` |

## Tooling Recipes

### Generate Memory Records

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-tools.sh"
gdl_new memory --agent=sf-042 --subject=GL_ACCOUNT --detail="Added REGION_CODE" --file=memory/active/systems.gdlm --append
```

Auto-increments the ID from the max sequence in the file. `--append` writes directly with flock-based locking.

### Time Travel — Compare memory across git history

```bash
# What did we know last week?
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-diff.sh" memory/active/systems.gdlm HEAD~5

# Show a specific memory at a past commit
git show abc123:memory/active/systems.gdlm | grep "subject:GL_ACCOUNT"
```

### Validate Memory Files

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-lint.sh" memory/active/systems.gdlm
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-lint.sh" --all memory/active/
```

Checks required fields (id, agent, ts), M-{agent}-{seq} ID format, and duplicate IDs.
