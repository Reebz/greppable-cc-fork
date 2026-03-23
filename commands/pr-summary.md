---
description: "Generate GDL pull request summary with change-flow diagram — use when PR is created or merged. Posts Mermaid to GitHub."
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# PR Summary Skill

Generate greppable PR summaries as GDL records + GDLD sequence diagrams.

## Invocation

```
/greppable:pr-summary 20            # Single PR
/greppable:pr-summary --all         # All merged PRs (skip existing)
/greppable:pr-summary --all --force # Regenerate all
```

## What You Produce

For each PR, generate two files:

### 1. `prs/{n}.gdl` — Summary + per-file records

```gdl
@pr-summary|id:{n}|title:{escaped}|author:{login}|ts:{ISO8601}|summary:{agent-generated}|areas:{comma-list}|additions:{n}|deletions:{n}|files:{n}|commits:{n}|branch:{head}|base:{base}|action:{merged|draft}
@pr-file|pr:{n}|file:{path}|action:{added|modified|deleted|renamed}|additions:{n}|deletions:{n}|change:{agent-generated}
```

### 2. `prs/{n}.gdld` — Sequence diagram of change flow

```gdld
@diagram|id:PR-{n}|type:sequence|purpose:{one-line PR description}
@participant|id:{component}|label:{Component Name}|role:{role}
@msg|from:{src}|to:{tgt}|label:{what happened}
```

### 3. Mermaid comment on GitHub PR

After generating the GDLD, convert to Mermaid in `/tmp`, post to the PR, then discard. The `.gdld` is the source of truth — the Mermaid lives on the PR comment.

```bash
scripts/gdld2mermaid.sh prs/{n}.gdld --mmd -o /tmp/pr-{n}.diagram.md
{
  echo '## PR Change Flow'
  echo ''
  echo '```mermaid'
  cat /tmp/pr-{n}.mmd
  echo '```'
} | gh pr comment {n} --body-file -
rm -f /tmp/pr-{n}.diagram.md /tmp/pr-{n}.mmd
```

## How To Read The PR

### Step 1: Get PR metadata

```bash
gh pr view {n} --json number,title,author,body,mergedAt,createdAt,additions,deletions,changedFiles,commits,files,headRefName,baseRefName,state
```

### Step 2: Determine diff tier

| File count | Strategy |
|------------|----------|
| <15 files | Read full diff: `gh pr diff {n}` |
| 15-40 files | PR body + commit messages + top 10 file patches |
| 40+ files | PR body + commit messages + top 5 file patches |

For medium/large PRs, get individual file patches:

```bash
gh pr diff {n} -- path/to/specific/file.ts
```

Use the helper to find top changed files:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/pr-summary-extract.sh"
FILES_JSON=$(gh pr view {n} --json files --jq '.files')
top_changed_files "$FILES_JSON" 10
```

### Step 3: Read commit messages for intent

```bash
gh pr view {n} --json commits --jq '.commits[].messageHeadline'
```

## Escaping Rules

**CRITICAL:** Agent-generated fields (summary, areas, change) MUST escape:
- Literal `|` → `\|`
- Literal `:` → `\:`
- Literal `\` → `\\`

Use the helper: `source "${CLAUDE_PLUGIN_ROOT}/scripts/pr-summary-extract.sh"` and call `escape_gdl_value`.

Or apply manually: avoid literal pipes and colons in summaries. Rephrase if needed.

## GDLD Diagram Guidelines

- **Participants are logical components**, not individual files
  - Good: `parser`, `ui`, `spec`, `tests`
  - Bad: `gdls-parser.ts`, `table-detail.tsx`
- **Messages describe what happened**, not file-level diffs
  - Good: `Add @E enum parsing logic`
  - Bad: `Modified gdls-parser.ts lines 40-120`
- **Keep it readable** — 3-8 participants, 5-15 messages
- **Role field** on participants: `backend`, `frontend`, `test`, `docs`, `tooling`, `infra`

## Helper Script

Source `scripts/pr-summary-extract.sh` for these functions:

| Function | Args | Returns |
|----------|------|---------|
| `escape_gdl_value` | `value` | Escaped string |
| `format_pr_summary_line` | `json summary areas action` | Complete `@pr-summary` line |
| `format_pr_file_line` | `pr file additions deletions action change` | Complete `@pr-file` line |
| `determine_diff_tier` | `file_count` | `small`, `medium`, or `large` |
| `top_changed_files` | `files_json n` | Top N file paths by change volume |

## Retroactive Mode

When running `--all`:

1. List merged PRs: `gh pr list --state merged --json number --jq '.[].number'`
2. For each PR number, check if `prs/{n}.gdl` exists
3. Skip existing (unless `--force`)
4. Generate each PR sequentially

## Grep Patterns (for verifying output)

```bash
grep "^@pr-summary" prs/*.gdl                    # All summaries
grep "^@pr-summary.*areas:.*parser" prs/*.gdl     # PRs touching parser
grep "^@pr-file.*action:added" prs/*.gdl          # New files across PRs
grep "^@pr-file.*table-detail" prs/*.gdl          # History of a specific file
grep "^@pr-summary.*id:20" prs/20.gdl             # Specific PR
```
