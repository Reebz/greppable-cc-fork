---
name: navigating-gdlc-code-maps
description: "Use when exploring codebase structure or understanding module dependencies using the .gdlc file-level code index — finding which file exports a symbol, tracing import relationships, or getting oriented in an unfamiliar codebase. Triggers on: \"where is X defined\", \"what depends on Y\", \"show me the project structure\", getting an overview of the codebase, finding files by directory or language, or direct .gdlc file operations. NOT for reading or searching source code implementations, running bridge tools (src2gdlc), .gdls schema maps, or .gdla API contracts."
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
context: fork
---

# GDLC Code Map Reference

## Available Code Maps

!`bash -c 'find docs/gdl -name "*.gdlc" -maxdepth 3 2>/dev/null | while read f; do count=$(grep -c "^@F" "$f" 2>/dev/null || echo 0); echo "- $f ($count files indexed)"; done'`

## Format

Two record types, one line each:

```
@D directory-path|description
@F file-path|lang|exports|imports|description
```

| Field | Content |
|-------|---------|
| `exports` | Comma-separated symbols exported by the file |
| `imports` | Comma-separated modules/packages imported |
| `lang` | Language identifier (ts, py, go, rs, etc.) |
| `description` | First sentence of the file's doc comment (may be empty) |

Files are grouped under their `@D` directory header. The file starts with `# @VERSION` and `# @FORMAT` comment headers.

## Tool Functions

Source the helpers for exact-match lookups (prefer these over raw grep for symbol queries):

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/gdlc-tools.sh"
```

| Function | Usage | What it does |
|----------|-------|-------------|
| `gdlc_files` | `gdlc_files [DIR_PREFIX] [file.gdlc]` | List @F records, optionally filtered by directory prefix |
| `gdlc_exports` | `gdlc_exports SYMBOL [file.gdlc]` | Find files exporting a symbol (exact match) |
| `gdlc_imports` | `gdlc_imports MODULE [file.gdlc]` | Find files importing a module (exact match) |
| `gdlc_dirs` | `gdlc_dirs [file.gdlc]` | List all @D directory records |
| `gdlc_lang` | `gdlc_lang LANG [file.gdlc]` | List files by language (exact match, `ts` won't match `tsx`) |

## Grep Patterns

Quick fuzzy searches (for exact matching, use the tool functions above):

```bash
# All files in a directory
grep "^@F apps/server/src/lib/" project.gdlc

# Fuzzy find a symbol (matches anywhere in the record)
grep "^@F.*symbolName" project.gdlc

# Find all files that import a module
grep "^@F.*|.*moduleName" project.gdlc

# All TypeScript files
grep "^@F.*|ts|" project.gdlc

# All directories
grep "^@D " project.gdlc

# Count files
grep -c "^@F " project.gdlc
```

## Combined Queries

```bash
# Full dependency picture: who imports X and what does X export?
grep "moduleName" project.gdlc

# All files in a package with their exports
grep "^@F packages/widget/" project.gdlc

# Cross-reference: files that export A and import B
grep "^@F" project.gdlc | grep "A" | grep "B"
```

## Bridge Tools

| Source | Bridge | Output |
|--------|--------|--------|
| Source code (14 languages) | `src2gdlc.sh` | `.gdlc` code map |
| GDLC code map | `gdlc2gdld.sh` | `.gdld` diagram |

```bash
# Generate code map from source
bash "${CLAUDE_PLUGIN_ROOT}/scripts/src2gdlc.sh" src/ --recursive --output=project.gdlc

# Visualize as Mermaid: GDLC → GDLD → Mermaid
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdlc2gdld.sh" project.gdlc > /tmp/code.gdld
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdld2mermaid.sh" /tmp/code.gdld
```

## Cross-Layer Search

Use `/greppable:about TOPIC` to search across all GDL layers (code maps, schemas, diagrams, memory, APIs, documents) in a single query.

## Usage Guidance

The code map is a **file-level index** of the entire codebase. For most structural questions (what apps exist, what a module exports, who imports what), the code map alone is sufficient.

- Read the code map first. Answer from it if possible.
- Only open source files when the code map genuinely lacks the needed information (e.g., function implementations, config values, error handling details).
- The exports and imports fields show the dependency graph — trace connections without opening files.
