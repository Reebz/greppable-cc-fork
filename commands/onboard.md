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

4. **Ask: which layers to enable?** Default: GDLS, GDLD, GDL.
   - Always enabled: GDLS (schemas), GDLD (diagrams), GDL (data/rules)
   - Conditional (auto-detected): GDLA (API contracts — if OpenAPI/GraphQL detected)
   - Available but not default: GDLU (unstructured docs — manual use only)

5. **Ask: where should GDL artifacts live?** Default: `docs/gdl`

6. **Run the setup script** with the user's choices from steps 3-5:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-onboard.sh" \
  --scope=<project|global> \
  --gdl-root=<path> \
  --layers=<comma-separated>
```

This single command handles all deterministic steps:
- Creates the config file (`.claude/greppable.local.md` or `~/.claude/greppable.local.md`)
- Adds `.claude/*.local.md` to `.gitignore` (if not present)
- Creates the `gdl_root` directory structure with per-layer subdirectories

Add `--skip-gitignore` flag if the user requests skipping that step.

7. **Check for existing artifacts**: If no greppable files detected in `gdl_root`, suggest: "No greppable artifacts found. Run `/greppable:discover` to scan the codebase."

## Update Mode

If config already exists:

1. Show current settings: "Current config: all layers enabled, project scope, artifacts in docs/gdl"
2. Ask what to change (not a full re-run)
3. Re-run `gdl-onboard.sh` with updated flags to apply changes

## Scope Interactions

- Running project-scope then global-scope (or vice versa) works — project always wins on conflict
- Re-running in same scope enters Update Mode
