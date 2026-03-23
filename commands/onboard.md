---
description: Set up or update greppable configuration for this project — creates config, directory structure, and .gitignore entries
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# /greppable:onboard — Setup or Update GDL Configuration

## First Run Flow

If no `.claude/greppable.local.md` exists (project or global):

1. **Display welcome banner** — Output the banner directly as conversation text (do NOT use Bash — the output panel clips tall content). Display this exactly as a code block:

```
$ grep -rn "greppable" /dev/universe

 ██████╗ ██████╗ ███████╗██████╗ ██████╗  █████╗ ██████╗ ██╗     ███████╗
██╔════╝ ██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║     ██╔════╝
██║  ███╗██████╔╝█████╗  ██████╔╝██████╔╝███████║██████╔╝██║     █████╗
██║   ██║██╔══██╗██╔══╝  ██╔═══╝ ██╔═══╝ ██╔══██║██╔══██╗██║     ██╔══╝
╚██████╔╝██║  ██║███████╗██║     ██║     ██║  ██║██████╔╝███████╗███████╗
 ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝     ╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝
                                                                        .ai

 1 match · the grep-native language for agentic systems
```

Then say: **Welcome! Let's set up greppable for this project.**

2. **Check for existing config** — read `~/.claude/greppable.local.md` (global) and `.claude/greppable.local.md` (project). If either exists, enter Update Mode (below).

3. **Ask: project or global scope?**
   - Project (default): config in `.claude/greppable.local.md`, affects only this repo
   - Global: config in `~/.claude/greppable.local.md`, affects all repos without project config

4. **Ask: which layers to enable?** Default: v1 set (GDLC, GDLM, GDLD, GDL).
   - Always enabled: GDLC (code maps), GDLM (memory), GDLD (diagrams), GDL (data/rules)
   - Conditional (auto-detected): GDLS (schemas — if Prisma/SQL detected), GDLA (API contracts — if OpenAPI/GraphQL detected)
   - Available but not default: GDLU (unstructured docs — manual use only)

5. **If GDLM layer is enabled, ask: enable automatic memory extraction?**
   - Yes (default): When a new session starts, the previous session's transcript is automatically processed into `.gdlm` memory records via the Agent SDK. Requires `node` on PATH.
   - No: Session transcripts are not processed. Memory files can still be created manually.

   Explain clearly: "This uses a lightweight LLM call (Haiku) at session start to extract decisions, errors, and patterns from the previous session into searchable memory records. No API key needed — it inherits from the host Claude Code process. Runs in a detached background process so it won't slow down startup."

6. **Ask: where should GDL artifacts live?** Default: `docs/gdl`

7. **Run prescan for exclusion suggestions** (if GDLC layer is enabled):
   - Run: `bash scripts/gdl-prescan.sh <project_dir> --json`
   - If `suggested_exclusions` is non-empty in the JSON output:
     - Show: "Detected [framework] at [path]. Recommend excluding from code mapping."
     - Ask: "Add suggested exclusions to .gdlignore? You can edit this later with /greppable:ignore"
     - If yes, collect patterns and pass as `--gdlignore-patterns=gdlc:pattern1,gdlc:pattern2,...`
   - If empty: skip silently

8. **Run the setup script** with the user's choices from steps 3-7:

```bash
bash scripts/gdl-onboard.sh \
  --scope=<project|global> \
  --gdl-root=<path> \
  --layers=<comma-separated> \
  --memory=<true|false> \
  --gdlignore-patterns=<comma-separated>
```

This single command handles all deterministic steps:
- Creates the config file (`.claude/greppable.local.md` or `~/.claude/greppable.local.md`)
- Adds `.claude/*.local.md` to `.gitignore` (if not present)
- Creates the `gdl_root` directory structure with per-layer subdirectories
- Creates `.gdlignore` with detected exclusion patterns (if any)

Add `--skip-gitignore` flag if the user requests skipping that step.

9. **If memory was enabled**, tell the user: "Memory extraction is now active. Any prior session transcripts will be processed in the background. Future sessions will automatically extract memories at startup."

10. **Check for existing artifacts**: If no greppable files detected in `gdl_root`, suggest: "No greppable artifacts found. Run `/greppable:discover` to scan the codebase."

## Update Mode

If config already exists:

1. Show current settings: "Current config: all layers enabled, memory extraction: on, project scope, artifacts in docs/gdl"
2. Ask what to change (not a full re-run)
3. Re-run `gdl-onboard.sh` with updated flags to apply changes

## Scope Interactions

- Running project-scope then global-scope (or vice versa) works — project always wins on conflict
- Re-running in same scope enters Update Mode
