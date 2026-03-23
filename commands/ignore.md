---
description: Manage .gdlignore exclusion patterns — add, remove, list, or detect patterns to exclude from GDL bridge scanning
disable-model-invocation: false
allowed-tools: Read, Bash, Write, Edit, Glob, Grep, AskUserQuestion
---

# /greppable:ignore — Manage Bridge Exclusion Patterns

## Subcommands

### `/greppable:ignore add [format:]<pattern>`
Append a pattern to `.gdlignore`. Creates the file with header comments if it doesn't exist.
- Example: `/greppable:ignore add gdlc:components/ui/`
- Example: `/greppable:ignore add **/*.stories.tsx`

### `/greppable:ignore remove <pattern>`
Remove a matching line from `.gdlignore`. Match is exact (including any format prefix).

### `/greppable:ignore list`
Show current `.gdlignore` contents grouped by scope:
1. All bridges (unprefixed patterns)
2. Per-format sections (grouped by prefix)

If no `.gdlignore` exists, say so and suggest `/greppable:ignore detect`.

### `/greppable:ignore detect`
Run prescan detection for UI frameworks and generated code:
```bash
bash scripts/gdl-prescan.sh . --json
```
Parse `suggested_exclusions` from JSON output. For each suggestion, show the pattern and reason, then ask the user whether to add it. If the user confirms, write to `.gdlignore`.

## After Any Edit
Run lint validation on the file:
```bash
bash scripts/gdl-lint.sh .gdlignore
```

## File Format Reference
- Lines starting with `#` are comments
- Blank lines are ignored
- `pattern` (no prefix) applies to all bridges
- `gdlc:pattern` applies only to code map scanning
- `gdlu:pattern` applies only to document indexing
- Trailing `/` means directory-only match
- `*` matches within a path segment, `**` matches across segments
- Leading `/` means root-relative (only matches at project root)
