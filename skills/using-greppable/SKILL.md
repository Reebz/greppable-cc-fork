---
name: using-greppable
description: "REQUIRED before ANY .gdlc, .gdlm, .gdld, .gdls, .gdla, or .gdl file operation. Also triggers on structural questions about code, past decisions, service architecture, or data: 'what did we decide about X', 'how is Y structured', 'what depends on Z', 'what endpoints does W expose', exploring unfamiliar code areas, or choosing between implementation alternatives. This project has pre-indexed knowledge that answers these in one grep. NOT for pure implementation tasks like writing functions, fixing bugs, or styling."
disable-model-invocation: false
context: fork
allowed-tools: Read, Grep, Glob, Bash
---

Artifact inventory (live): !`bash -c 'source "${CLAUDE_PLUGIN_ROOT}/lib/session-context.sh" 2>/dev/null && gdl_scan_artifacts docs/gdl 2>/dev/null || echo "total:0"'`

This project has pre-indexed knowledge. Indexed artifacts answer in one tool call what raw exploration takes 10+.

**You MUST check the index before reaching for Glob, Grep, or Read to explore.** Not after. Before. The index exists so you don't have to traverse the filesystem to answer structural questions.

| When you're about to | Stop. Check this first |
|---------------------|----------------------|
| Explore code — "what's in src/", "where is X defined", "what depends on Y" | `grep` the `.gdlc` code map. File paths, exports, imports, dependencies — already indexed. |
| Investigate history — "what did we decide", "why was X built this way", "any prior context on Y" | `grep` the `.gdlm` memory files. Decisions, observations, errors from prior sessions — indexed by concept. |
| Trace connections — "how does X talk to Y", "what's the request flow", "blast radius of changing Z" | `grep` the `.gdld` diagrams. Architecture flows, sequences, topology — already mapped. |
| Check API shapes — "what endpoints exist", "what auth does Y need", "request/response for Z" | `grep` the `.gdla` contracts. Endpoints, schemas, parameters, auth — already extracted. |
| Scan database — "what tables exist", "what's the schema for X" | `grep` the `.gdls` schema maps. Tables, columns, PKs, FKs — already indexed. |

Invoke the format-specific skill for detailed grep patterns, tool functions, and write formats.

## Red Flags

If you catch yourself doing any of these, you skipped the index:

- **Launching an Explore/research agent to understand code structure** — the `.gdlc` already has every file path, export, and import dependency. One grep on the code map replaces a 30+ tool-call agent. Only use agents after the index proves insufficient.
- **Running `ls` or `Glob` to map directory structure** — the `.gdlc` already has every file path, language, and export. You're duplicating work that's done.
- **Running `Grep` across dozens of files to find a function** — the `.gdlc` indexes exports. One grep on the code map, not a codebase-wide search.
- **Saying "I don't have context on past decisions"** — the `.gdlm` memory files exist specifically for this. Grep by topic or anchor before assuming you're starting cold.
- **Tracing imports manually to understand how modules connect** — the `.gdld` diagrams map these relationships. Check before you trace.
- **Making an implementation choice without checking history** — prior sessions may have tried and rejected the approach you're about to take. Check `.gdlm` first.

## Guardrails

- **zsh**: Source tool scripts via `bash -c 'source scripts/... && ...'` — zsh has bash incompatibilities
- **Lint**: Runs automatically after every GDL file change via PostToolUse hook
- **Memory**: Captured automatically at session end — no manual writes needed
