---
name: querying-gdld-diagrams
description: "Use when creating, modifying, or querying .gdld diagram files — architecture flows, sequence diagrams, service topology, and gotcha/anti-pattern records. Also triggers when: investigating how services connect, understanding request flows or data pipelines, assessing blast radius of a change, \"how does X connect to Y\", \"what calls what\", \"show me the flow\", or documenting what NOT to do. NOT for .gdls schema maps — .gdld and .gdls are different formats."
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
context: fork
---

# GDLD Quick Reference

## Available Diagrams

!`bash -c 'find docs/gdl -name "*.gdld" -maxdepth 3 2>/dev/null | while read f; do title=$(grep -m1 "^@diagram" "$f" 2>/dev/null | grep -o "title:[^|]*" | sed "s/title://"); echo "- $f${title:+ ($title)}"; done'`

## Format

```
@type|key:value|key:value|key:value
```

Every record is one line. Every field is self-describing (key:value). No schema lookup needed.

## Core Record Types

| Type | Purpose | Key Fields |
|------|---------|------------|
| `@diagram` | File metadata | `id`, `type`, `purpose` |
| `@group` | Subgraph | `id`, `label`, `file`, `parent`, `pattern` |
| `@node` | Graph node | `id`, `label`, `group`, `shape`, `status`, `tags` |
| `@edge` | Relationship | `from`, `to`, `label`, `type`, `status`, `tags` |
| `@use-when` | When to use | `condition`, `threshold` |
| `@use-not` | When NOT to use | `condition`, `reason` |
| `@component` | Key component | `name`, `file`, `does` |
| `@config` | Configuration | `param`, `value`, `source` |
| `@gotcha` | Lesson learned | `issue`, `detail`, `fix`, `severity` |
| `@recovery` | Failure handling | `issue`, `means`, `fix`, `severity` |
| `@decision` | Architectural decision | `id`, `title`, `status`, `reason` |
| `@pattern` | Related pattern | `name`, `for`, `file` |
| `@entry` | Entry point | `use-case`, `command` |
| `@note` | Freeform prose | `context`, `text` |
| `@participant` | Sequence actor | `id`, `label`, `role` |
| `@msg` | Ordered message | `from`, `to`, `label`, `type` |
| `@block` | Conditional/loop start | `id`, `type`, `label` |
| `@endblock` | Block end | `id` |
| `@seq-note` | Sequence annotation | `over`, `text` |
| `@scenario` | Diagram variant | `id`, `label`, `inherits` |
| `@override` | Element override in scenario | `scenario`, `target`, `field`, `value` |
| `@exclude` | Remove element from scenario | `scenario`, `target` |
| `@view` | Named perspective/filter | `id`, `label`, `filter`, `includes`, `excludes`, `level` |
| `@include` | File inclusion | `file`, `records`, `prefix` |
| `@deploy-env` | Deployment environment | `id`, `label`, `provider` |
| `@deploy-node` | Infrastructure node | `id`, `label`, `env`, `parent`, `technology` |
| `@deploy-instance` | Component-to-node map | `component`, `node`, `instances`, `config` |
| `@infra-node` | Non-app infrastructure | `id`, `label`, `node`, `technology` |

## Grep Patterns

```bash
# What is this diagram?
grep "^@diagram" file.gdld

# When to use / not use?
grep "^@use-when" file.gdld
grep "^@use-not" file.gdld

# What are the gotchas?
grep "^@gotcha" file.gdld

# How do I run it?
grep "^@entry" file.gdld

# What components are involved?
grep "^@component" file.gdld

# All nodes / edges
grep "^@node" file.gdld
grep "^@edge" file.gdld

# What connects to node X?
grep "@edge|to:X" file.gdld

# What does X connect to?
grep "@edge|from:X" file.gdld

# Decision points
grep "@node.*shape:diamond" file.gdld

# Cross-file: all gotchas
grep "^@gotcha" *.gdld

# Recovery procedures
grep "^@recovery" file.gdld

# Configuration values
grep "^@config" file.gdld

# Pattern references
grep "^@pattern" file.gdld

# Notes and caveats
grep "^@note" file.gdld

# Sequence: participants, messages
grep "^@participant" file.gdld
grep "^@msg" file.gdld

# Messages from/to a participant
grep "@msg|from:X" file.gdld
grep "@msg|to:X" file.gdld

# Decisions
grep "^@decision" file.gdld
grep "@decision.*status:accepted" file.gdld

# Elements by tag
grep "tags:.*pii" file.gdld
grep "tags:" file.gdld

# Deprecated or planned elements
grep "status:deprecated" file.gdld
grep "status:planned" file.gdld

# Cross-file edge references
grep "diagram-id#" *.gdld

# Severity filtering
grep "severity:critical" file.gdld
grep "severity:" file.gdld

# Scenarios and overrides
grep "^@scenario" file.gdld
grep "@override.*scenario:production" file.gdld

# Views
grep "^@view" file.gdld

# Includes
grep "^@include" file.gdld

# Deployment
grep "^@deploy-env" file.gdld
grep "^@deploy-node.*env:production" file.gdld
grep "^@deploy-instance" file.gdld
grep "^@infra-node" file.gdld
```

## Combined Queries (Fewer Tool Calls)

Use regex unions to answer multi-type queries in a single grep:

```bash
# Full applicability picture (use + don't use)
grep -E "^@use-when|^@use-not" file.gdld

# Gotchas + recovery procedures together
grep -E "^@gotcha|^@recovery" file.gdld

# Complete graph (all nodes and edges)
grep -E "^@node|^@edge" file.gdld

# Implementation context (components + config)
grep -E "^@component|^@config" file.gdld

# All decision points + their branches
grep "shape:diamond" file.gdld && grep "type:conditional" file.gdld

# Cross-file: all gotchas and recovery across all diagrams
grep -E "^@gotcha|^@recovery" *.gdld

# Cross-file: every entry point across all systems
grep "^@entry" *.gdld

# Full deployment picture
grep -E "^@deploy-env|^@deploy-node|^@deploy-instance|^@infra-node" file.gdld

# Scenario overview
grep -E "^@scenario|^@override|^@exclude" file.gdld

# All critical issues across diagrams
grep "severity:critical" *.gdld
```

Prefer combined queries when you need multiple record types to answer a single question.

## Encoding Guide

When converting architecture knowledge to GDLD, use this to choose the right record type:

### Which record type?

| Source Concept | Use | NOT |
|---|---|---|
| Hard-won lesson, "don't do X", key principle | `@gotcha` | `@note` |
| What to do when something breaks | `@recovery` | `@gotcha` |
| "When to use" with a measurable threshold | `@use-when` | `@note` |
| "When NOT to use" or anti-pattern | `@use-not` | (don't omit — see below) |
| Config value, threshold, parameter | `@config` | `@note` |
| Design decision with rationale | `@decision` | `@note` |
| Narrative context, rationale, caveats | `@note` | `@gotcha` |
| Reusable pattern referenced by other diagrams | `@pattern` | `@note` |
| Cross-cutting classification (pii, tier1, internal) | `tags:` field | separate `@note` |
| Dev/prod/error variant of same diagram | `@scenario` + `@override` | separate files |
| Named filter for specific audience | `@view` | ad-hoc grep |
| Shared records from another diagram | `@include` | copy-paste |
| Infrastructure/deployment target | `@deploy-node` | `@node` |
| Component-to-server mapping | `@deploy-instance` | `@note` |
| Non-app infra (LB, WAF, CDN) | `@infra-node` | `@node` |
| Severity of a gotcha or recovery | `severity:` field | separate `@note` |

### The @use-not rule

Every diagram that has `@use-when` records SHOULD also have `@use-not` records. Anti-patterns prevent misuse and are the most common omission. Ask: "When would someone reach for this pattern but be wrong to?"

```gdld
# GOOD: explicit anti-patterns
@use-when|condition:processing 5+ documents|threshold:5+
@use-not|condition:single document processing|reason:state management overhead not justified
@use-not|condition:fast extraction under 2 minutes|reason:context compaction unlikely

# BAD: @use-when with no @use-not
@use-when|condition:processing 5+ documents|threshold:5+
# (missing — agents will hallucinate anti-patterns or say "none defined")
```

### Gotcha vs Note vs Recovery

The most common encoding mistake. Use this test:

- **Would another developer repeat this mistake?** → `@gotcha`
- **Did something break and here's how to fix it?** → `@recovery`
- **Is this just context or explanation?** → `@note`

Source headings don't matter. "Key Principles", "Lessons Learned", "Important Notes", "Caveats" — if they describe mistakes to avoid, encode as `@gotcha`.

## Example

```gdld
# Document Processing Pipeline

@diagram|id:doc-pipeline|type:flow|purpose:multi-stage processing with state

# === WHEN TO USE ===
@use-when|condition:large document sets|threshold:10+ files
@use-when|condition:resumability needed
@use-not|condition:single-item processing|reason:overhead not justified

# === THE FLOW ===
@group|id:entry|label:Entry Stage|file:scripts/run.py
@group|id:agent|label:Processing Agent|file:src/agents/processor.py
@node|id:Input|label:Input Folder|group:entry
@node|id:CheckState|label:State exists?|shape:diamond|group:agent|role:decision
@node|id:LoadState|label:Load existing state|group:agent
@node|id:InitState|label:Initialize state|group:agent

@edge|from:Input|to:CheckState
@edge|from:CheckState|to:LoadState|label:Yes|type:conditional
@edge|from:CheckState|to:InitState|label:No|type:conditional

# === KEY COMPONENTS ===
@component|name:Entry point|file:scripts/run.py|does:CLI and preprocessing
@component|name:Agent|file:src/agents/processor.py|does:Multi-turn processing

# === GOTCHAS ===
@gotcha|issue:Output size limits|detail:Large outputs may be truncated|fix:Write to files
@gotcha|issue:State ordering|detail:Write result before updating state

# === ENTRY POINTS ===
@entry|use-case:Full processing|command:python scripts/run.py /path/to/input
```

## Node Shapes

| Shape | Use For |
|-------|---------|
| `box` | Process, action (default) |
| `diamond` | Decision, condition |
| `circle` | Start/end point |
| `stadium` | Input/output |

## Edge Types

| Type | Use For |
|------|---------|
| `flow` | Normal flow (default) |
| `conditional` | Yes/No branches |
| `data` | Data transfer |
| `triggers` | Event trigger |

## Tool Functions

Source the helpers:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/gdld-tools.sh"
```

| Function | Usage | What it does |
|----------|-------|-------------|
| `gdld_gotchas` | `gdld_gotchas FILE` | List gotchas sorted by severity (SEVERITY\|ISSUE\|DETAIL\|FIX) |
| `gdld_nodes` | `gdld_nodes FILE [--group=G]` | List node ID\|LABEL pairs, optionally filtered by group |
| `gdld_components` | `gdld_components FILE` | List NAME\|FILE\|DOES |
| `gdld_subgraph` | `gdld_subgraph FILE GROUP` | Extract group + nodes + internal edges |
| `gdld_filter` | `gdld_filter FILE --scenario=N` | Apply scenario, output filtered GDLD |
| `gdld_view` | `gdld_view FILE --view=N` | Apply view filter, output filtered GDLD |

## Key Rules

- Each line is a complete, self-describing record
- `grep "^@type"` filters by record type
- `grep "from:X"` or `grep "to:X"` finds relationships
- Use `# === SECTION ===` comments for organization
- Quantify conditions with `threshold:` not vague prose
