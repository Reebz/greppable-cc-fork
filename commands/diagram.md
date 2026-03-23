---
description: Create a new GDLD architecture diagram from current conversation context — flows, patterns, sequences, gotchas
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# /greppable:diagram — Create/Update GDLD Diagram

Create or update a GDLD architecture diagram from current context.

## Usage

`/greppable:diagram [description of what to diagram]`

## Workflow

1. **Analyze the subject**: Identify what needs diagramming from the conversation context or provided description.

2. **Choose diagram type**: flow, sequence, architecture, dependency, or pattern.

3. **Identify elements**:
   - Nodes (systems, modules, components)
   - Edges (relationships, data flows, calls)
   - Groups (logical containers)
   - Gotchas (known issues, warnings)

4. **Generate GDLD output** following the spec in `specs/GDLD-SPEC.md`:

```
@diagram|id:{id}|type:{type}|purpose:{description}
@node|id:{n}|label:{label}|group:{group}
@edge|from:{source}|to:{target}|label:{description}|style:{style}
@group|id:{g}|label:{label}
@gotcha|severity:{1-3}|area:{area}|symptom:{symptom}|fix:{fix}
```

5. **Validate**: `bash scripts/gdl-lint.sh <output.gdld>`

6. **Render preview**: `bash scripts/gdld2mermaid.sh <output.gdld>`

7. **Write to file**: Save to `docs/gdl/diagrams/<name>.gdld` (or user-specified path).

## Conversion Shortcut

Can also convert existing formats to diagrams:
- `.gdlc` → `.gdld`: `bash scripts/gdlc2gdld.sh <file.gdlc>`
- `.gdls` → `.gdld`: `bash scripts/gdls2gdld.sh <file.gdls>`
- `.gdlu` → `.gdld`: `bash scripts/gdlu2gdld.sh <file.gdlu>`

## Examples

```
/greppable:diagram the authentication flow
/greppable:diagram architecture of the API layer
/greppable:diagram this module's dependency graph
```
