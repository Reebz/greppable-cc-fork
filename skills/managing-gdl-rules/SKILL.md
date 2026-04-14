---
name: managing-gdl-rules
description: "Use when creating, reviewing, or maintaining @rule records in rules.gdl files — provides format reference, quality criteria for what makes a rule worth writing, severity calibration, and the gdl_rules_for_file helper. Triggers on: rules.gdl files, 'add a rule', 'create a coding rule', 'enforce this convention', observing a strong codebase convention. NOT for general code review."
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
context: fork
---

# GDL Rules Reference

## Current Rules

!`bash -c 'if [ -f rules.gdl ]; then echo "From rules.gdl:"; echo ""; grep "^@rule" rules.gdl 2>/dev/null; else echo "No rules.gdl found in project root."; fi'`

## What Makes a Rule Worth Writing

A rule captures a **project-specific convention with codebase evidence**. Not a generic best practice.

| Good rule (project-specific) | Bad rule (generic) |
|---|---|
| "API routes must validate input with zod schemas" | "Use descriptive variable names" |
| "Never modify existing migrations — create new ones" | "Write clean code" |
| "React components use PascalCase filenames" | "Follow naming conventions" |

**The test:** Can you point to 3+ files that follow this convention? If yes, it's a rule. If it's advice you'd give on any project, it's not.

## When to Write vs Observe

- **Write a @rule** when: you've seen the convention in 3+ files, or the user explicitly confirms it
- **Write a @memory observation** when: you've noticed a pattern but aren't sure it's intentional
- **Don't write anything** when: it's a language-level best practice that any linter would catch

## Format

```
@rule|scope:GLOB|severity:LEVEL|desc:TEXT
```

| Field | Values | Meaning |
|-------|--------|---------|
| `scope` | Glob pattern (`*.ts`, `src/api/**`, `**/*.test.*`) | Which files this rule applies to |
| `severity` | `error` | Will break things if violated — wrong behavior, data loss, security |
| | `warn` | Convention that should be followed — consistency, maintainability |
| | `info` | Team preference — style, approach |
| `desc` | Free text | What the rule requires (imperative form) |

## Tool Function

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-tools.sh"

# Check which rules apply to a file
gdl_rules_for_file "src/api/routes.ts" rules.gdl
```

## Grep Patterns

```bash
# All rules
grep "^@rule" rules.gdl

# Rules for a specific scope
grep "^@rule|scope:src/api" rules.gdl

# All error-severity rules
grep "severity:error" rules.gdl

# Rules matching a file (fuzzy)
grep "^@rule" rules.gdl | grep "\.ts"
```

## Where Rules Live

`<gdl_root>/data/rules.gdl` or `rules.gdl` in the project root.

## Lifecycle

1. **Discovery** — agent proposes initial rules based on observed conventions, user confirms
2. **Sessions** — Claude notices a strong convention while working, proposes a rule
3. **Review** — user or agent adjusts severity, scope, or removes outdated rules
