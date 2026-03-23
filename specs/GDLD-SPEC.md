# Diagram Specification v1.1

**GDL Diagram Layer** - A GDL-based format for encoding visual knowledge (architecture flows, patterns, concept maps) in a grep-native, agent-queryable structure.

## Purpose

The Diagram layer captures visual knowledge that agents and humans use to understand systems, patterns, and relationships. Unlike rendered diagrams (Mermaid, SVG), GDL Diagrams are:

- **Grep-native** - Query relationships directly with `grep "@edge|from:X"`
- **Self-describing** - Every record carries its field names
- **Prose-preserving** - Structured records for components, gotchas, and conditions alongside the graph

Diagrams are not for deterministic business data (that's GDL) or agent memory (that's Memory). Diagrams encode architectural knowledge, patterns, and visual structures.

## Optimal Agent Prompts

**Tier 1 — Reading/Querying (~50 tokens):**
```
GDLD: Diagram records with key:value fields. Core: @diagram, @node, @edge, @group.
grep "^@node" file.gdld for nodes. grep "^@edge" for relationships.
grep "^@gotcha" for lessons learned. grep "^@decision" for arch decisions.
```

**Tier 2 — Writing Flow Diagrams (~80 tokens):**
```
GDLD flow diagram generation:
- @diagram|id:ID|type:flow|purpose:DESC (one per file)
- @group|id:ID|label:LABEL (optional subgraph)
- @node|id:ID|label:LABEL|group:GRP|shape:box|role:process
- @edge|from:ID|to:ID|label:TEXT|type:data|style:solid
- Edge types: data, control, flow. Shapes: box, diamond, cylinder, circle
- @gotcha|issue:SHORT|detail:LONG|severity:high|fix:HOW
```

**Tier 2 — Writing Sequence Diagrams (~60 tokens):**
```
GDLD sequence diagram generation:
- @diagram|id:ID|type:sequence|purpose:DESC
- @participant|id:ID|label:NAME|role:agent
- @msg|from:ID|to:ID|label:TEXT|type:request
- @block|id:ID|type:alt|label:CONDITION and @endblock|id:ID
- Message types: request, response, async, self
```

**Tier 2 — Writing Deployment Diagrams (~70 tokens):**
```
GDLD deployment diagram generation:
- @diagram|id:ID|type:deployment|profile:deployment|purpose:DESC
- @deploy-env|id:ID|label:LABEL|provider:aws
- @deploy-node|id:ID|label:LABEL|env:ENV|technology:TECH|tags:TAGS
- @deploy-instance|component:NAME|node:NODE_ID|instances:N
- @infra-node|id:ID|label:LABEL|node:PARENT|technology:TECH
- @edge for network flows between deploy-nodes
```

**Tier 2 — Writing Knowledge Diagrams (~70 tokens):**
```
GDLD knowledge diagram generation:
- @diagram|id:ID|type:pattern|profile:knowledge|purpose:DESC
- @gotcha|issue:SHORT|detail:LONG|severity:high|fix:HOW
- @recovery|issue:COND|means:WHAT|fix:ACTION
- @decision|id:ADR-N|title:WHAT|status:accepted|reason:WHY
- @pattern|name:NAME|for:WHEN|file:PATH
- @use-when|condition:WHEN|threshold:VALUE
- @use-not|condition:WHEN|reason:WHY
```

---

## Format

Diagram records use the GDL `@type|key:value` format with diagram-specific record types:

```
@diagram|id:{id}|type:{type}|purpose:{description}
@node|id:{id}|label:{label}|group:{group}
@edge|from:{source}|to:{target}|label:{label}
```

### File Extension

| Convention | Value |
|------------|-------|
| Extension | `.gdld` |
| Encoding | UTF-8 |
| Line ending | LF |
| Comments | Lines starting with `#` or `//` |
| Blank lines | Allowed (ignored) |

### Escaping

GDLD inherits GDL's escaping rules. When values contain `|` or `:`, escape with backslash:

| Character | Escape | Example |
|-----------|--------|---------|
| `\|` | `\|` | `label:Input\|Output Stage` |
| `:` | `\:` | `source:config.py\:42` |
| `\` | `\\` | `label:path\\to\\file` |

```gdld
@config|param:model|value:claude-sonnet-4|source:config.py\:42
@node|id:IOStage|label:Input\|Output Stage
```

---

## Record Types

### Core Graph Records

#### @diagram - File Metadata

Declares a diagram file. One per file.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `id` | Yes | Unique identifier | `document-pipeline` |
| `type` | Yes | Diagram type | `flow`, `pattern`, `concept`, `state`, `decision` |
| `purpose` | Yes | What this diagram captures | `document processing with resumability` |
| `direction` | No | Layout direction | `TD` (top-down), `LR` (left-right) |
| `version` | No | Diagram version | `1.0`, `2.1` |
| `profile` | No | Diagram profile | `flow`, `sequence`, `deployment`, `knowledge` |

```gdld
@diagram|id:search-pipeline|type:flow|purpose:multi-tier search architecture|direction:TD
```

#### @group - Subgraph/Grouping

Groups related nodes together.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `id` | Yes | Group identifier | `preprocessing` |
| `label` | Yes | Display label | `Preprocessing Stage` |
| `file` | No | Associated file | `src/preprocessing.py` |
| `parent` | No | Parent group (for nesting) | `pipeline` |
| `pattern` | No | Pattern this group implements | `file-based-state` |

```gdld
@group|id:pipeline|label:Main Pipeline|file:src/pipeline.py
@group|id:processing|label:Processing Loop|parent:pipeline
```

#### @node - Graph Node

A node in the diagram.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `id` | Yes | Node identifier | `CheckState` |
| `label` | Yes | Display label | `State exists?` |
| `group` | No | Parent group | `pipeline` |
| `shape` | No | Node shape | `box`, `diamond`, `circle`, `stadium` |
| `role` | No | Semantic role | `entry`, `decision`, `process`, `output` |
| `status` | No | Node lifecycle status | `active` (default), `deprecated`, `planned` |
| `pattern` | No | Pattern this node implements | `large-file-navigation` |
| `tags` | No | Comma-separated classification tags | `database,tier1,pii` |

```gdld
@node|id:CheckState|label:State exists?|shape:diamond|group:pipeline|role:decision
@node|id:Process|label:Process document|group:processing|role:process
@node|id:UserDB|label:User Database|group:persistence|tags:database,tier1,pii
```

#### @edge - Relationship

A directed connection between nodes.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `from` | Yes | Source node ID | `CheckState` |
| `to` | Yes | Target node ID | `LoadState` |
| `label` | No | Edge label | `Yes` |
| `type` | No | Relationship type | `flow`, `conditional`, `data`, `triggers` |
| `style` | No | Line style | `solid`, `dashed`, `dotted` |
| `bidirectional` | No | Two-way relationship | `true` |
| `status` | No | Edge lifecycle status | `active` (default), `deprecated`, `planned` |
| `tags` | No | Comma-separated classification tags | `internal,encrypted` |

```gdld
@edge|from:CheckState|to:LoadState|label:Yes|type:conditional
@edge|from:CheckState|to:InitState|label:No|type:conditional
@edge|from:API|to:UserDB|label:queries|type:data|tags:jdbc,internal
```

#### Cross-File References

To reference a node defined in another `.gdld` file, qualify the ID with the diagram ID and `#`:

```gdld
@edge|from:search-pipeline#Index|to:Ingest|label:feeds into|type:data
```

The pattern `diagram-id#node-id` allows grep to find cross-file relationships:

```bash
# Find all references to nodes in search-pipeline
grep "search-pipeline#" *.gdld
```

#### @include - File Inclusion

Includes records from another `.gdld` file into this diagram. The included file's records are logically part of this diagram for grep and rendering purposes. Agents should read the included file when they encounter an `@include` record.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `file` | Yes | Path to included file | `patterns/file-based-state.gdld` |
| `records` | No | Which record types to include | `@node,@edge` (default: all) |
| `prefix` | No | ID prefix to avoid collisions | `shared-` |

```gdld
# Include shared pattern definitions
@include|file:patterns/file-based-state.gdld
@include|file:common/team-components.gdld|records:@component

# Include with prefix to avoid ID collisions
@include|file:shared/common-nodes.gdld|prefix:shared-
```

**Design constraint:** `@include` is a directive for agents and renderers, not a build step. The included file must exist as a standalone `.gdld` file. Grep queries across `*.gdld` will naturally find records in both the parent and included files.

Grep for includes:
```bash
grep "^@include" file.gdld           # What files does this diagram include?
grep "^@include" *.gdld              # All cross-file inclusions
```

---

### Context Records

#### @use-when - Applicability Condition

When to use this diagram/pattern.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `condition` | Yes | The condition | `large document sets` |
| `threshold` | No | Quantified threshold | `10+ files, multi-MB each` |
| `detail` | No | Additional context | `long-running processes` |

```gdld
@use-when|condition:large document sets|threshold:10+ files
@use-when|condition:context window limits|threshold:processes >10min
@use-when|condition:resumability needed
```

#### @use-not - When NOT to Use

Negative conditions.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `condition` | Yes | When to avoid | `single-item processing` |
| `reason` | No | Why | `no progress to track` |
| `threshold` | No | Quantified threshold | `<2 minutes` |

```gdld
@use-not|condition:single-item processing|reason:no progress to track
@use-not|condition:fast operations|threshold:<2 minutes|reason:overhead not justified
```

---

### Reference Records

#### @component - Key Component

Maps components to files and responsibilities.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `name` | Yes | Component name | `Entry point` |
| `file` | Yes | File path | `scripts/run.py` |
| `does` | Yes | Responsibility | `CLI, preprocessing` |

```gdld
@component|name:Entry point|file:scripts/run.py|does:CLI and preprocessing
@component|name:Agent|file:src/agents/processor.py|does:Multi-turn processing with state
```

#### @config - Configuration Parameter

Documents configuration values.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `param` | Yes | Parameter name | `max_turns` |
| `value` | Yes | Value | `100` |
| `source` | No | Where defined | `config.py\:42` |
| `note` | No | Additional context | `Allows for large batches` |

```gdld
@config|param:model|value:claude-sonnet-4|source:config.py
@config|param:max_turns|value:100|source:config.py|note:Headroom for large batches
```

#### @entry - Entry Point

How to use/invoke.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `use-case` | Yes | The use case | `Full processing` |
| `command` | No | Command to run | `python scripts/run.py ...` |
| `endpoint` | No | API endpoint | `POST /api/process` |
| `params` | No | Parameters | `mode=auto` |

```gdld
@entry|use-case:Full processing|command:python scripts/run.py /path/to/input --output ./output
@entry|use-case:API call|endpoint:POST /api/process|params:mode=auto
```

---

### Deployment Records

#### @deploy-env - Deployment Environment

Defines a deployment environment (dev, staging, production).

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `id` | Yes | Environment identifier | `production` |
| `label` | Yes | Display label | `Production (AWS us-east-1)` |
| `provider` | No | Cloud/infra provider | `aws`, `gcp`, `azure`, `on-prem` |

```gdld
@deploy-env|id:production|label:Production|provider:aws
@deploy-env|id:staging|label:Staging|provider:aws
@deploy-env|id:development|label:Local Development|provider:on-prem
```

#### @deploy-node - Deployment Target

A deployment target (server, cluster, region, service).

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `id` | Yes | Node identifier | `ecs-cluster` |
| `label` | Yes | Display label | `ECS Cluster` |
| `env` | Yes | Parent environment ID | `production` |
| `parent` | No | Parent deploy-node (nesting) | `us-east-1` |
| `technology` | No | Technology/platform | `AWS ECS`, `Kubernetes`, `Docker` |
| `tags` | No | Classification tags | `compute,autoscaled` |

```gdld
@deploy-node|id:aws-region|label:us-east-1|env:production|technology:AWS Region
@deploy-node|id:ecs-cluster|label:ECS Cluster|env:production|parent:aws-region|technology:AWS ECS|tags:compute,autoscaled
@deploy-node|id:rds|label:RDS Instance|env:production|parent:aws-region|technology:PostgreSQL 15|tags:database,tier1
```

#### @deploy-instance - Container-to-Node Mapping

Maps a logical component to a deployment node.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `component` | Yes | Component name or node ID | `API` |
| `node` | Yes | Deploy-node ID | `ecs-cluster` |
| `instances` | No | Instance count or range | `3`, `2..N` |
| `config` | No | Deploy-specific config | `cpu:2vCPU,mem:4GB` |

```gdld
@deploy-instance|component:API|node:ecs-cluster|instances:3|config:cpu\:2vCPU,mem\:4GB
@deploy-instance|component:Worker|node:ecs-cluster|instances:2..N
@deploy-instance|component:Database|node:rds|instances:1
```

#### @infra-node - Non-Application Infrastructure

Infrastructure elements that are not application components (load balancers, firewalls, CDNs).

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `id` | Yes | Node identifier | `alb` |
| `label` | Yes | Display label | `Application Load Balancer` |
| `node` | Yes | Parent deploy-node | `aws-region` |
| `technology` | No | Technology | `AWS ALB` |
| `tags` | No | Classification tags | `networking,public-facing` |

```gdld
@infra-node|id:alb|label:Application Load Balancer|node:aws-region|technology:AWS ALB|tags:networking,public-facing
@infra-node|id:waf|label:Web Application Firewall|node:aws-region|technology:AWS WAF|tags:security
```

Grep for deployment:
```bash
grep "^@deploy-env" file.gdld              # All environments
grep "^@deploy-node.*env:production" file.gdld  # Production infrastructure
grep "^@deploy-instance" file.gdld          # All component-to-node mappings
grep "^@infra-node" file.gdld              # All infrastructure elements
grep "tags:.*autoscaled" file.gdld          # Autoscaled resources
```

---

### Knowledge Records

#### @gotcha - Lesson Learned

Hard-won knowledge.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `issue` | Yes | The issue | `Output size limits` |
| `detail` | Yes | Explanation/consequence | `Large outputs may be truncated` |
| `fix` | No | How to address | `Write to files instead` |
| `severity` | No | Impact level | `critical`, `warning`, `info` |

```gdld
@gotcha|issue:Output size limits|detail:Large outputs may be truncated|fix:Write to files instead|severity:critical
@gotcha|issue:State ordering|detail:Write result before updating state ensures no data loss|severity:warning
```

#### @recovery - Failure Handling

How to recover from failures.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `issue` | Yes | Failure condition | `in_progress status on restart` |
| `means` | Yes | What it indicates | `Process crashed mid-operation` |
| `fix` | Yes | Recovery action | `Reset to pending` |
| `severity` | No | Impact level | `critical`, `warning`, `info` |

```gdld
@recovery|issue:in_progress status|means:Process crashed mid-operation|fix:Reset to pending|severity:critical
@recovery|issue:complete but missing output|means:State updated before write|fix:Reset to pending|severity:warning
```

#### @decision - Architectural Decision

Records a design decision with rationale. Pairs with `@gotcha` (what went wrong) to capture *why we chose this*.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `id` | Yes | Decision identifier | `ADR-001` |
| `title` | Yes | What was decided | `Use file-based state over database` |
| `status` | Yes | Decision status | `accepted`, `proposed`, `superseded`, `deprecated` |
| `date` | No | When decided | `2026-01-15` |
| `supersedes` | No | Decision this replaces | `ADR-003` |
| `reason` | No | Why this was chosen | `Simpler recovery, no DB dependency` |

```gdld
@decision|id:ADR-001|title:Use file-based state over database|status:accepted|date:2026-01-15|reason:Simpler recovery, no DB dependency
@decision|id:ADR-002|title:Opus for extraction, Haiku for classification|status:accepted|reason:Cost-accuracy tradeoff
@decision|id:ADR-003|title:Single-threaded processing|status:superseded|supersedes:ADR-001
```

Grep for decisions:
```bash
grep "^@decision" file.gdld                  # All decisions
grep "@decision.*status:accepted" file.gdld   # Active decisions
grep "@decision.*status:superseded" *.gdld    # Superseded across files
```

#### @pattern - Reusable Pattern Reference

Links to related patterns.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `name` | Yes | Pattern name | `Large File Navigation` |
| `for` | No | When to use it | `>500K char files` |
| `file` | No | Pattern file | `patterns/large-file.gdld` |

```gdld
@pattern|name:Large File Navigation|for:>500K char files
@pattern|name:File-Based State Management|for:multi-item processing
```

---

### Freeform Records

#### @note - Freeform Prose

For genuinely unstructured content that resists quantification.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `context` | Yes | What kind of note | See values below |
| `text` | Yes | The content | Any prose |

**Standard context values:**

| Value | Use For |
|-------|---------|
| `caveat` | Warnings, limitations, assumptions |
| `future` | Planned changes, roadmap notes |
| `thematic` | Conceptual or narrative context |
| `rationale` | Why something was designed this way |
| `todo` | Outstanding work items |

Custom values are permitted. Use lowercase, single-word conventions for grep consistency.

```gdld
@note|context:thematic|text:The map is not the territory, but a good map changes how you see it
@note|context:future|text:Part 1 establishes the protagonist's ordinary world
@note|context:caveat|text:This pattern assumes single-threaded execution
```

---

### Sequence Records

#### @participant - Sequence Actor

An actor in a sequence diagram.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `id` | Yes | Unique identifier | `orchestrator` |
| `label` | Yes | Display label | `Orchestrator Agent` |
| `role` | No | Participant type | `agent`, `system`, `api`, `user`, `database` |
| `file` | No | Implementation file | `src/agents/orchestrator.py` |

```gdld
@participant|id:orch|label:Orchestrator|role:agent|file:src/agents/orchestrator.py
@participant|id:snowflake|label:Snowflake API|role:system
```

#### @msg - Ordered Message

A message between participants. Line order = message order.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `from` | Yes | Sender participant ID | `orchestrator` |
| `to` | Yes | Receiver participant ID | `sf-agent` |
| `label` | Yes | Message description | `Query GL_ACCOUNT` |
| `type` | No | Message type | `request`, `response`, `async`, `self` |
| `status` | No | Result status | `ok`, `error`, `timeout` |
| `activate` | No | Activates target | `true` |
| `deactivate` | No | Deactivates sender | `true` |

```gdld
@msg|from:orch|to:sf|label:Get current GL_ACCOUNT schema|type:request|activate:true
@msg|from:sf|to:orch|label:Schema has 13 columns|type:response|deactivate:true
```

#### @block / @endblock - Conditional/Loop Blocks

Groups messages into conditional, optional, loop, or parallel blocks.

**@block fields:**

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `id` | Yes | Block identifier | `cache-miss` |
| `type` | Yes | Block type | `alt`, `opt`, `loop`, `par` |
| `label` | Yes | Block condition | `Schema not in local cache` |

**@endblock fields:**

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `id` | Yes | Matching block identifier | `cache-miss` |

```gdld
@block|id:cache-miss|type:opt|label:Schema not in local cache
@msg|from:sf|to:snowflake|label:DESCRIBE TABLE GL_ACCOUNT|type:request
@msg|from:snowflake|to:sf|label:13 columns returned|type:response|status:ok
@endblock|id:cache-miss
```

#### @seq-note - Sequence Annotation

A note attached to one or more participants.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `over` | Yes | Participant(s) covered | `sf-agent` or `sf-agent,snowflake` |
| `text` | Yes | Annotation | `Agent caches schema for 5min` |

```gdld
@seq-note|over:sf|text:Agent caches schema for 5min
@seq-note|over:sf,snowflake|text:Connection uses read-only credentials
```

---

### Scenario Records

#### @scenario - Diagram Variant

Defines a named variant of the base diagram. Scenarios inherit all records from the base and override specific elements. This allows dev/prod/error views without file duplication.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `id` | Yes | Scenario identifier | `production` |
| `label` | Yes | Display label | `Production Environment` |
| `inherits` | No | Base to inherit from | `base` (default) or another scenario ID |

#### @override - Element Override

Overrides a field on a specific element within a scenario. Must appear after the `@scenario` it belongs to.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `scenario` | Yes | Parent scenario ID | `production` |
| `target` | Yes | Element ID to override | `server` |
| `field` | Yes | Field to change | `label`, `status`, `tags` |
| `value` | Yes | New value | `Prod Cluster (10 instances)` |

#### @exclude - Remove Element from Scenario

Removes an element from a specific scenario.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `scenario` | Yes | Parent scenario ID | `production` |
| `target` | Yes | Element ID to exclude | `debug-logger` |

```gdld
# Base diagram defines the full system
@diagram|id:api-gateway|type:flow|purpose:API gateway architecture

@node|id:server|label:API Server|group:backend
@node|id:db|label:Database|group:persistence
@node|id:debug-logger|label:Debug Logger|group:observability
@edge|from:server|to:db|label:queries
@edge|from:server|to:debug-logger|label:logs

# Production variant: different labels, no debug logger
@scenario|id:production|label:Production Environment
@override|scenario:production|target:server|field:label|value:Prod Cluster (10 instances)
@override|scenario:production|target:db|field:label|value:PostgreSQL RDS Multi-AZ
@override|scenario:production|target:db|field:tags|value:database,tier1,production
@exclude|scenario:production|target:debug-logger

# Development variant: different config
@scenario|id:development|label:Development Environment
@override|scenario:development|target:server|field:label|value:Dev Server (localhost:8000)
@override|scenario:development|target:db|field:label|value:SQLite (local)

# Staging inherits production overrides, then customises further
@scenario|id:staging|label:Staging Environment|inherits:production
@override|scenario:staging|target:server|field:label|value:Staging Cluster (2 instances)
```

Grep for scenarios:
```bash
grep "^@scenario" file.gdld                     # All scenarios
grep "@override.*scenario:production" file.gdld  # All production overrides
grep "@exclude.*scenario:production" file.gdld   # Elements excluded from production
```

---

### View Records

#### @view - Named Perspective

Defines a named view (filter/projection) of the diagram. Views are instructions for renderers and agents — they do not change the underlying data.

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `id` | Yes | View identifier | `security-view` |
| `label` | Yes | Display label | `Security & PII Elements` |
| `filter` | No | Comma-separated tag filters | `tags:pii,tags:encrypted` |
| `includes` | No | Comma-separated group IDs to show (cascades to nested child groups) | `backend,persistence` |
| `excludes` | No | Comma-separated group IDs to hide (cascades to nested child groups) | `observability,debug` |
| `level` | No | Abstraction level | `node` (default), `group` |
| `scenario` | No | Scenario to apply | `production` |

```gdld
# Named views for different audiences
@view|id:security|label:Security & PII Elements|filter:tags:pii,tags:encrypted
@view|id:happy-path|label:Happy Path|includes:entry,processing|excludes:error-handling
@view|id:system-context|label:System Context|level:group
@view|id:prod-overview|label:Production Overview|scenario:production|level:group
```

Agent workflow:
```bash
# 1. What views are available?
grep "^@view" pipeline.gdld

# 2. What does the security view show?
grep "@view|id:security" pipeline.gdld
# → @view|id:security|label:Security & PII Elements|filter:tags:pii,tags:encrypted

# 3. Apply it: find matching elements
grep -E "tags:.*pii|tags:.*encrypted" pipeline.gdld
```

When `level:group` is set, renderers should:
1. Collapse nodes into their parent groups
2. Derive group-to-group edges from node-to-node edges
3. Show group labels instead of individual node labels

---

## Diagram Types

| Type | Use For | Typical Records |
|------|---------|-----------------|
| `flow` | Architecture, processing pipelines | `@group`, `@node`, `@edge`, `@component` |
| `pattern` | Reusable methodology | `@use-when`, `@use-not`, `@gotcha`, `@entry` |
| `concept` | Knowledge graphs, relationships | `@node`, `@edge` with semantic `type:` |
| `state` | State machines, lifecycles | `@node` (states), `@edge` (transitions) |
| `decision` | Business rules, routing | `@node` with `shape:diamond`, conditional `@edge` |
| `sequence` | Agent interactions, API flows, debug traces | `@participant`, `@msg`, `@block`, `@seq-note` |
| `deployment` | Infrastructure, environments | `@deploy-env`, `@deploy-node`, `@deploy-instance`, `@infra-node` |

Any diagram type can include `@scenario`, `@override`, and `@exclude` records to define variants.

---

## Profiles

The optional `profile` field on `@diagram` declares which subset of record types a diagram uses. Profiles are advisory — they guide agents and enable linter warnings but do not restrict which records can appear.

| Profile | Core Types | Typical Use |
|---------|-----------|-------------|
| `flow` | `@group`, `@node`, `@edge`, `@component`, `@config`, `@entry`, `@gotcha`, `@recovery`, `@pattern`, `@decision`, `@use-when`, `@use-not` | Architecture, pipelines |
| `sequence` | `@participant`, `@msg`, `@block`, `@endblock`, `@seq-note`, `@gotcha` | Interactions, API flows |
| `deployment` | `@deploy-env`, `@deploy-node`, `@deploy-instance`, `@infra-node`, `@node`, `@edge` | Infrastructure |
| `knowledge` | `@gotcha`, `@recovery`, `@decision`, `@pattern`, `@use-when`, `@use-not`, `@node`, `@edge` | Lessons learned |

`@diagram` is implicitly required in all profiles (one per file). Cross-cutting records are allowed in all profiles: `@scenario`, `@override`, `@exclude`, `@view`, `@include`, `@note`.

No `profile` field = all record types allowed (backward compatible). Custom profile values are permitted (linter skips validation for unknown profiles).

Grep for profiles:
```bash
grep "@diagram.*profile:" *.gdld         # All profiled diagrams
grep "@diagram.*profile:flow" *.gdld     # Flow diagrams
```

---

## File Structure

```
diagrams/
├── flows/
│   ├── document-ingestion.gdld
│   ├── search-pipeline.gdld
│   └── data-processing.gdld
├── patterns/
│   ├── file-based-state.gdld
│   └── large-file-navigation.gdld
├── concepts/
│   ├── character-relationships.gdld
│   └── cross-project-patterns.gdld
├── states/
│   └── order-lifecycle.gdld
└── sequences/                 # Sequence/interaction diagrams
    └── agent-handoff.gdld
```

---

## Grep Patterns

### Graph Queries

| Question | Command |
|----------|---------|
| All diagrams | `grep "^@diagram" *.gdld` |
| Nodes in a group | `grep "@node.*group:pipeline" file.gdld` |
| What connects to X? | `grep "@edge|to:X" file.gdld` |
| What does X connect to? | `grep "@edge|from:X" file.gdld` |
| All decision points | `grep "@node.*shape:diamond" file.gdld` |
| Bidirectional relationships | `grep "@edge.*bidirectional:true" file.gdld` |
| Elements with a specific tag | `grep "tags:.*pii" file.gdld` |
| All tagged elements | `grep "tags:" file.gdld` |

### Context Queries

| Question | Command |
|----------|---------|
| When to use this? | `grep "^@use-when" file.gdld` |
| When NOT to use? | `grep "^@use-not" file.gdld` |
| What are the gotchas? | `grep "^@gotcha" file.gdld` |
| How do I run this? | `grep "^@entry" file.gdld` |
| What components exist? | `grep "^@component" file.gdld` |
| What config values? | `grep "^@config" file.gdld` |
| What decisions were made? | `grep "^@decision" file.gdld` |
| Active decisions only | `grep "@decision.*status:accepted" file.gdld` |
| Critical issues only | `grep "severity:critical" file.gdld` |
| All severity-tagged records | `grep "severity:" file.gdld` |

### Cross-File Queries

| Question | Command |
|----------|---------|
| All gotchas across diagrams | `grep "^@gotcha" *.gdld` |
| Diagrams about processing | `grep "@diagram.*processing" *.gdld` |
| All uses of a file | `grep "file:.*processor" *.gdld` |
| Patterns for large files | `grep "@use-when.*large" *.gdld` |

> **Node ID convention:** Avoid IDs that are prefixes of other IDs (e.g., use `check-state` and `check-size` rather than `Check` and `CheckState`). Pipe-anchored patterns (`@edge|from:X`) are more precise than wildcard patterns (`@edge.*from:X`) and avoid false positives from label content.

### Sequence Queries

| Question | Command |
|----------|---------|
| All sequence diagrams | `grep "@diagram.*type:sequence" *.gdld` |
| All participants | `grep "^@participant" file.gdld` |
| All messages in order | `grep "^@msg" file.gdld` |
| Messages from X | `grep "@msg\|from:X" file.gdld` |
| Messages to X | `grep "@msg\|to:X" file.gdld` |
| Error responses | `grep "@msg.*status:error" file.gdld` |
| All conditional blocks | `grep "^@block" file.gdld` |

---

## Design Principles

1. **GDL-native** - Same `@type|key:value` format as GDL. Same grep patterns work.
2. **Self-describing** - Every record carries field names. No schema lookup needed.
3. **Structured prose** - Conditions, gotchas, components are explicit records, not paragraphs.
4. **Graph + context** - Nodes and edges for structure, plus reference records for knowledge.
5. **Freeform escape hatch** - `@note` for genuinely unstructured content.
6. **Grep-first** - `grep "^@gotcha"` finds all gotchas. `grep "@edge|from:X"` finds relationships.
7. **Embeddable** - GDLD snippets in markdown fenced code blocks (` ```gdld `) are greppable across `.md` files using the same patterns. Agents should search both `*.gdld` and `*.md` files when doing cross-file knowledge queries.

### Versioning and Deprecation

Use `version:` on `@diagram` to track diagram evolution. Use `status:deprecated` or `status:planned` on nodes and edges to mark lifecycle state:

```gdld
@diagram|id:pipeline-v2|type:flow|purpose:updated pipeline|version:2.0
@node|id:OldProcessor|label:Legacy Processor|status:deprecated
@node|id:NewProcessor|label:New Processor|status:planned
@edge|from:OldProcessor|to:NewProcessor|label:migration|type:data|status:planned
```

Grep for lifecycle state:
```bash
grep "status:deprecated" file.gdld
grep "status:planned" file.gdld
```

---

## Relationship to Other Layers

| Layer | Format | Purpose | Extension |
|-------|--------|---------|-----------|
| Schema | GDLS | External system structure | `.gdls` |
| Data | GDL | Business records | `.gdl` |
| Memory | GDL + memory vocab | Agent knowledge | `.gdlm` |
| **Diagram** | **GDL + diagram vocab** | **Visual knowledge** | **`.gdld`** |
| Code | GDLC | File-level code index | `.gdlc` |
| API | GDLA | API contract maps | `.gdla` |
| Documents | GDLU | Unstructured content index | `.gdlu` |

All seven layers capture knowledge in the same grep-native style. GDLC provides code structure that can be visualized as diagrams via `gdlc2gdld.sh`. GDLA maps API contracts (endpoints, schemas, auth) via `gdla2gdld.sh`. GDLU indexes unstructured content (PDFs, transcripts, media) via `gdlu2gdld.sh`.

---

## Rendering (Optional)

GDL Diagrams can be rendered to Mermaid for human visualization:

```bash
# Convert to Mermaid (tooling)
gdld-to-mermaid pipeline.gdld > pipeline.mmd
```

The `.gdld` file is the source of truth. Mermaid is a generated view.

---

## Example: Sequence Diagram

```gdld
# Agent Handoff: Schema Analysis
@diagram|id:gl-account-analysis|type:sequence|purpose:orchestrator delegates to sub-agent

# === PARTICIPANTS ===
@participant|id:user|label:Human User|role:user
@participant|id:orch|label:Orchestrator|role:agent|file:src/agents/orchestrator.py
@participant|id:sf|label:Snowflake Agent|role:agent|file:src/agents/snowflake.py
@participant|id:snowflake|label:Snowflake API|role:system

# === THE SEQUENCE ===
@msg|from:user|to:orch|label:Analyze GL_ACCOUNT table|type:request|activate:true
@msg|from:orch|to:sf|label:Get current GL_ACCOUNT schema|type:request|activate:true

@block|id:cache-miss|type:opt|label:Schema not in local cache
@msg|from:sf|to:snowflake|label:DESCRIBE TABLE GL_ACCOUNT|type:request
@msg|from:snowflake|to:sf|label:13 columns returned|type:response|status:ok
@endblock|id:cache-miss

@msg|from:sf|to:orch|label:Schema has 13 columns, REGION_CODE is new|type:response|deactivate:true
@msg|from:orch|to:user|label:Analysis complete|type:response|deactivate:true

# === GOTCHAS ===
@gotcha|issue:Line order is message order|detail:Do not reorder @msg records without understanding temporal implications
```

---

## Example: Complete Diagram File

```gdld
# Document Processing Pipeline
# Multi-stage processing with state management and resumability

@diagram|id:document-pipeline|type:flow|purpose:document processing with resumability|direction:TD

# === WHEN TO USE ===
@use-when|condition:large document sets|threshold:10+ files
@use-when|condition:context window limits|threshold:processes >10min
@use-when|condition:resumability needed
@use-not|condition:single-item processing|reason:no progress to track
@use-not|condition:fast operations|threshold:<2min|reason:overhead not justified

# === THE FLOW ===

# Entry Stage
@group|id:entry|label:Entry Stage|file:scripts/run.py
@node|id:Input|label:Input Folder|group:entry
@node|id:Preprocess|label:Preprocess Files|group:entry
@node|id:Inventory|label:Create Inventory|group:entry
@node|id:StartAgent|label:Start Agent|group:entry

@edge|from:Input|to:Preprocess
@edge|from:Preprocess|to:Inventory
@edge|from:Inventory|to:StartAgent|label:workspace path

# Agent Stage
@group|id:agent|label:Processing Agent|file:src/agents/processor.py
@node|id:ReadInventory|label:Read Inventory|group:agent
@node|id:CheckState|label:State exists?|shape:diamond|group:agent|role:decision
@node|id:LoadState|label:Load existing state|group:agent
@node|id:InitState|label:Initialize state|group:agent

@edge|from:StartAgent|to:ReadInventory
@edge|from:ReadInventory|to:CheckState
@edge|from:CheckState|to:LoadState|label:Yes|type:conditional
@edge|from:CheckState|to:InitState|label:No|type:conditional
@edge|from:LoadState|to:ProcessLoop
@edge|from:InitState|to:ProcessLoop

# Processing Loop
@group|id:ProcessLoop|label:For Each Pending Item|parent:agent|pattern:File-Based State Management
@node|id:CheckSize|label:Large file?|shape:diamond|group:ProcessLoop
@node|id:LargeFile|label:Process in chunks|group:ProcessLoop
@node|id:SmallFile|label:Process entire file|group:ProcessLoop
@node|id:Extract|label:Extract data|group:ProcessLoop
@node|id:WriteBatch|label:Write batch output|group:ProcessLoop
@node|id:UpdateState|label:Update state|group:ProcessLoop

@edge|from:CheckSize|to:LargeFile|label:Yes|type:conditional
@edge|from:CheckSize|to:SmallFile|label:No|type:conditional
@edge|from:LargeFile|to:Extract
@edge|from:SmallFile|to:Extract
@edge|from:Extract|to:WriteBatch
@edge|from:WriteBatch|to:UpdateState

# === KEY COMPONENTS ===
@component|name:Entry point|file:scripts/run.py|does:CLI and preprocessing
@component|name:Agent|file:src/agents/processor.py|does:Multi-turn processing with state
@component|name:Prompts|file:prompts/*.md|does:Modular prompt templates
@component|name:Schema|file:src/models/schema.py|does:Pydantic models for validation

# === CONFIGURATION ===
@config|param:model|value:claude-sonnet-4|source:config.py
@config|param:max_turns|value:100|source:config.py|note:Headroom for large batches
@config|param:allowed_tools|value:Read,Grep,Glob,Write|source:config.py

# === RECOVERY LOGIC ===
@recovery|issue:in_progress status|means:Process crashed mid-operation|fix:Reset to pending
@recovery|issue:complete but missing output|means:State updated before write|fix:Reset to pending
@recovery|issue:corrupted state file|means:Parse error|fix:Delete state, restart

# === GOTCHAS ===
@gotcha|issue:Output size limits|detail:Large outputs may be truncated|fix:Write to files instead
@gotcha|issue:State ordering|detail:Write result before updating state ensures no data loss
@gotcha|issue:Iteration limits|detail:Default limits may be too low for large batches|fix:Increase max_turns

# === PATTERNS ===
@pattern|name:File-Based State Management|for:multi-item processing with resumability
@pattern|name:Large File Navigation|for:files >500K chars|file:patterns/large-file.gdld

# === ENTRY POINTS ===
@entry|use-case:Full processing|command:python scripts/run.py /path/to/input --output ./output
@entry|use-case:Validate output|command:python scripts/validate.py /path/to/workspace
@entry|use-case:Run tests|command:pytest tests/ -v

# === DECISIONS ===
@decision|id:ADR-001|title:File-based state over database|status:accepted|date:2026-01-15|reason:Simpler recovery, no DB dependency
@decision|id:ADR-002|title:Chunk large files at 500K chars|status:accepted|reason:Context window limits

# === DEPLOYMENT ===
@deploy-env|id:production|label:Production|provider:aws
@deploy-node|id:ecs|label:ECS Cluster|env:production|technology:AWS ECS|tags:compute
@deploy-instance|component:Agent|node:ecs|instances:1|config:cpu\:4vCPU,mem\:8GB

# === SCENARIOS ===
@scenario|id:production|label:Production Environment
@override|scenario:production|target:Extract|field:tags|value:gpu-accelerated

# === VIEWS ===
@view|id:onboarding|label:Onboarding View|includes:entry
@view|id:system-context|label:System Overview|level:group
```
