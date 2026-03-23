---
description: Search all 7 GDL layers for a topic with cross-layer formatted output. Use for quick lookups across the knowledge base.
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
---

# /greppable:about — Cross-Layer Search

Search across all 7 GDL layers for a topic. Returns formatted results grouped by layer.

## Usage

`/greppable:about TOPIC [directory] [--layer=LAYER] [--exclude-layer=LAYERS] [--summary] [--regex] [--ignore-case]`

## Implementation

Source the tools and call `gdl_about`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-tools.sh"
gdl_about "$TOPIC" "${DIR:-.}" ${SUMMARY:+--summary} ${REGEX:+--regex} ${IGNORE_CASE:+--ignore-case} ${EXCLUDE_LAYER:+--exclude-layer=$EXCLUDE_LAYER}
```

## Arguments

- `TOPIC` (required): The search term — literal string by default, regex pattern with `--regex`
- `directory` (optional): Search scope, defaults to current directory
- `--layer=LAYER`: Filter to specific layer (gdl, gdls, gdlc, gdla, gdld, gdlm, gdlu)
- `--exclude-layer=LAYERS`: Skip comma-separated layers (e.g., `--exclude-layer=gdlm,gdlu`). Complement of `--layer`.
- `--summary`: Compact output with counts only
- `--regex` / `-E`: Use extended regex instead of literal matching (enables patterns like `(auth|security)`, `^@T.*TOPIC`, `type:decision`)
- `--ignore-case` / `-i`: Case-insensitive search (finds `GL_ACCOUNT` when searching `gl_account`)

## Progressive Disclosure

1. First show summary (which layers matched, count per layer)
2. If user asks for more detail, show full matching records
3. If user asks about a specific layer, drill into that layer's tool functions

## Examples

```
/greppable:about GL_ACCOUNT
/greppable:about authentication --layer=gdlc
/greppable:about GL_ACCOUNT --summary
```

## Pattern Recipes

```bash
# Find entities matching a prefix
/greppable:about 'GL_[A-Z]+' . --regex

# Multi-keyword search (OR)
/greppable:about '(auth|security|access)' . --regex --ignore-case

# Filter to specific record types
/greppable:about '^@T.*Customer' . --regex --layer=gdls

# Find field values across layers
/greppable:about 'type:decision' . --regex --layer=gdlm

# Case-insensitive entity lookup
/greppable:about parser . --ignore-case

# Search everything except memory and diagrams
/greppable:about 'Customer' . --exclude-layer=gdlm,gdld
```
