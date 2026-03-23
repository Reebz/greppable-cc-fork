# GDLC Specification v2.0

**GDL Code** — A file-level code index for agent navigation. One record per source file, one `.gdlc` per project. Grep finds any file, export, or import in a single call.

## Purpose

GDLC v2 is a file-level index. It tells agents what each file does, what it exports, and what it imports. It does NOT index functions, methods, or class members — source code and tree-sitter on-demand handle that.

An agent reading a v2 `.gdlc` can answer: "Which file exports this symbol?", "What does this directory contain?", "What are the dependencies of this file?" — all with grep.

---

## Version Header

Every `.gdlc` file begins with a version header and format header:

```
# @VERSION spec:gdlc v:2.0.0 generated:YYYY-MM-DD source:tree-sitter source-hash:HASH
# @FORMAT PATH|LANG|EXPORTS|IMPORTS|DESCRIPTION
```

The `source-hash` is a content hash of the source tree at generation time. Used by `--check` to detect drift.

---

## Core Format

Two record types only:

### Directory Record

```
@D directory_path|description
```

Groups the `@F` records that follow. Scope continues until the next `@D` or end-of-file.

### File Record

```
@F path|lang|exports|imports|description
```

Five positional fields, pipe-delimited:

| Position | Field | Type | Example |
|----------|-------|------|---------|
| 1 | PATH | Relative file path | `src/lib/parsers/gdls-parser.ts` |
| 2 | LANG | Language identifier | `ts` |
| 3 | EXPORTS | Comma-separated exported symbols | `parseGdls,GdlsFile,GdlsTable` |
| 4 | IMPORTS | Comma-separated imported modules (base names, not paths) | `shared,types` |
| 5 | DESCRIPTION | Human-readable summary | `Parses GDLS schema files into structured types` |

**LANG identifiers:** `ts`, `tsx`, `js`, `jsx`, `py`, `go`, `java`, `rs`, `rb`, `c`, `cpp`, `cs`, `kt`, `swift`, `php`, `bash`, `sh`

**Empty fields:** Use consecutive pipes `||` for empty values. All 5 positions are always present.

**EXPORTS field:** Lists the public API surface — exported functions, classes, types, constants. Tree-sitter extracts these deterministically. Comma-separated, no spaces.

**IMPORTS field:** Lists module base names this file imports from (not full paths, not individual symbols). `import { foo } from './shared'` becomes `shared`. Comma-separated, no spaces.

**DESCRIPTION field:** One-line summary of the file's purpose. May be empty in skeleton output (filled by agent enrichment or `--enrich`).

---

## Grep Patterns

| Task | Command |
|------|---------|
| Find which file exports a symbol | `grep "OrderService" project.gdlc` |
| All TypeScript files | `grep "^@F [^|]*|ts|" project.gdlc` |
| All files in a directory | `grep "^@F src/lib/parsers/" project.gdlc` |
| What imports the parser? | `grep "\|.*gdls-parser" project.gdlc` |
| Files needing descriptions | `grep "\|$" project.gdlc` |
| All directory summaries | `grep "^@D" project.gdlc` |

---

## What v2 Removes

| v1 Feature | v2 Status | Rationale |
|------------|-----------|-----------|
| `@T` module records | Replaced by `@F` | Files, not classes, are the indexing unit |
| Member lines (6-field positional) | Removed | Source code + tree-sitter on-demand |
| `@R` relationships | Moved to GDLD | Architecture views belong in diagrams |
| `@PATH` flow chains | Moved to GDLD | Architecture views belong in diagrams |
| `@E` constrained values | Removed | Too granular for file-level index |
| Skeleton/enrichment overlay | Removed | Descriptions edited in-place, no merge system |
| One `.gdlc` per source file | One per project | Density is the point |

---

## Generation

`src2gdlc.sh` produces v2 output via tree-sitter shallow parse:

1. Walk the source tree, respecting `.gdlignore`
2. For each file, tree-sitter extracts: language, exported symbols, imported modules
3. Emit `@D` records from directory structure
4. Emit `@F` records with PATH, LANG, EXPORTS, IMPORTS fields populated
5. DESCRIPTION field is left empty in skeleton mode (trailing `|`)
6. `--enrich` flag triggers agent pass to fill descriptions

The output is a single `.gdlc` file per project. Deterministic given the same source tree.

---

## Cross-Layer Integration

| From | To | How |
|------|----|-----|
| GDLC | GDLD | `gdlc2gdld.sh` converts file records to diagram nodes, imports to edges |
| GDLC | GDLS | Grep both to trace code-to-data: `grep "UserService" *.gdlc && grep "USER_ACCOUNT" *.gdls` |
| GDLC | GDLA | Match API endpoint handlers to their source files |
| GDLC | GDLM | Memory records can reference file paths from GDLC |

---

## Escaping

Same `\|` convention as all GDL formats. Pipes within field values are escaped as `\|`.

```gdlc
@F src/utils/types.ts|ts|Result,Option,Either\|None||Generic utility types with pipe unions
```

Commas, angle brackets, parentheses, and colons within fields do not need escaping.

---

## File Conventions

| Convention | Value |
|------------|-------|
| Extension | `.gdlc` |
| Encoding | UTF-8 |
| Line ending | LF |
| Comments | Lines starting with `#` |
| Blank lines | Allowed between sections for readability |
| Empty fields | Consecutive pipes: `\|\|` |
| Files per project | One (density is the point) |

---

## Reserved Flags

These flags are defined for future implementation:

| Flag | Purpose |
|------|---------|
| `--deep` | Expand to member-level detail for selected files |
| `--enrich` | Agent pass to fill empty DESCRIPTION fields |
| `--since` | Incremental update — only re-scan files changed since a timestamp or commit |
| `--check` | Drift detection — compare source-hash against current source tree |
| `--shard` | Split large projects into multiple `.gdlc` files by directory |

---

## Example

```gdlc
# @VERSION spec:gdlc v:2.0.0 generated:2026-03-11 source:tree-sitter source-hash:abc123
# @FORMAT PATH|LANG|EXPORTS|IMPORTS|DESCRIPTION

@D src/lib/parsers|Parser modules for GDL format family

@F src/lib/parsers/gdls-parser.ts|ts|parseGdls,GdlsFile,GdlsTable|shared,types|Parses GDLS schema files into structured types
@F src/lib/parsers/gdlc-parser.ts|ts|parseGdlc,GdlcFile|shared,types|Parses GDLC code index files
@F src/lib/parsers/shared.ts|ts|parseVersionHeader,getField,splitPipeFields|types|Common parsing utilities across all format parsers
@F src/lib/parsers/index.ts|ts|extractEntities|gdls-parser,gdlc-parser,shared|Entity extraction dispatcher for all GDL formats

@D src/components/gdld|GDLD diagram visualization

@F src/components/gdld/flowchart-viewer.tsx|tsx|FlowchartViewer|mermaid,gdld-parser|Renders GDLD diagrams as interactive Mermaid flowcharts
@F src/components/gdld/gdld-viewer.tsx|tsx|GdldViewer|flowchart-viewer,sequence-viewer|Main GDLD viewer with diagram type switching
```
