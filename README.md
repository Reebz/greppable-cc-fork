# Greppable (Alpha)

The grep-native language for agentic systems. Your AI agent gets structured knowledge about your codebase, schemas, APIs, architecture, and decisions — all searchable with `grep`.

## Install

```
/plugin marketplace add greppable/greppable-plugin-alpha
/plugin install greppable@greppable-alpha
```

Restart Claude Code after installing.

## Setup (2 minutes)

### 1. Onboard your project

```
/greppable:onboard
```

Walks you through configuration: which layers to enable, where to store artifacts, whether to enable automatic session memory. Defaults are good for most projects.

### 2. Discover your codebase

```
/greppable:discover
```

Scans your project and generates GDL artifacts. This takes a few minutes depending on codebase size. It creates:

- **Code index** (`.gdlc`) — every file, export, and import in your project
- **Architecture diagrams** (`.gdld`) — system flows and dependencies
- **Schema maps** (`.gdls`) — database tables and relationships (if SQL/Prisma detected)
- **API contracts** (`.gdla`) — endpoints, schemas, auth (if OpenAPI/GraphQL detected)

### 3. Check it's working

```
/greppable:status
```

Shows artifact counts, active layers, and health. You should see non-zero counts for at least GDLC and GDLD.

## Is It Actually Helping?

The easiest way to check: **ask Claude.**

After working with greppable enabled for a session or two, try:

- "Are you using GDL artifacts in this session?"
- "How are the greppable indexes helping you?"
- "What would you have done differently without the GDL index?"

Claude will tell you directly whether it's referencing the indexed knowledge or falling back to raw file exploration. If it's using the index, you'll see faster responses and fewer tool calls for structural questions.

You can also check the session start output — greppable injects an artifact inventory at the top of every session showing what's loaded.

## Commands

| Command | What it does |
|---------|-------------|
| `/greppable:onboard` | Set up config and directory structure |
| `/greppable:discover` | Full codebase scan — generates all artifacts |
| `/greppable:about` | Cross-layer search ("about authentication") |
| `/greppable:diagram` | Create architecture diagrams from conversation |
| `/greppable:status` | Health check — inventory, stale detection |
| `/greppable:pr-summary` | PR summaries with change-flow diagrams |
| `/greppable:memory` | Toggle automatic session memory extraction |
| `/greppable:ignore` | Manage .gdlignore exclusion patterns |

## Feedback

This is an alpha — we want to hear what's working and what isn't. File issues on this repo or reach out directly.
