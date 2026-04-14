---
name: using-greppable
description: "REQUIRED before ANY .gdld, .gdls, .gdla, or .gdl file operation. Also triggers on structural questions about service architecture or data: 'how is Y structured', 'what depends on Z', 'what endpoints does W expose', or choosing between implementation alternatives. This project has pre-indexed knowledge that answers these in one grep. NOT for pure implementation tasks like writing functions, fixing bugs, or styling."
disable-model-invocation: false
context: fork
allowed-tools: Read, Grep, Glob, Bash
---

Artifact inventory (live): !`bash -c 'source "${CLAUDE_PLUGIN_ROOT}/lib/session-context.sh" 2>/dev/null && gdl_scan_artifacts docs/gdl 2>/dev/null || echo "total:0"'`

This project has pre-indexed knowledge. Indexed artifacts answer in one tool call what raw exploration takes 10+.

**You MUST check the index before reaching for Glob, Grep, or Read to explore.** Not after. Before. The index exists so you don't have to traverse the filesystem to answer structural questions.

| When you're about to | Stop. Check this first |
|---------------------|----------------------|
| Trace connections — "how does X talk to Y", "what's the request flow", "blast radius of changing Z" | `grep` the `.gdld` diagrams. Architecture flows, sequences, topology — already mapped. |
| Check API shapes — "what endpoints exist", "what auth does Y need", "request/response for Z" | `grep` the `.gdla` contracts. Endpoints, schemas, parameters, auth — already extracted. |
| Scan database — "what tables exist", "what's the schema for X" | `grep` the `.gdls` schema maps. Tables, columns, PKs, FKs — already indexed. |

Invoke the format-specific skill for detailed grep patterns, tool functions, and write formats.

## Red Flags

If you catch yourself doing any of these, you skipped the index:

- **Tracing service connections manually to understand how modules connect** — the `.gdld` diagrams map these relationships. Check before you trace.

## Guardrails

- **zsh**: Source tool scripts via `bash -c 'source scripts/... && ...'` — zsh has bash incompatibilities
- **Lint**: Runs automatically after every GDL file change via PostToolUse hook
