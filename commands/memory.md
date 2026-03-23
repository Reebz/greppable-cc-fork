---
description: Toggle automatic session memory extraction on or off — shows current status and updates greppable.local.md config
disable-model-invocation: false
allowed-tools: Read, Bash, Edit
---

# /greppable:memory — Toggle Session Memory Extraction

## Usage

`/greppable:memory` — show current status
`/greppable:memory on` — enable memory extraction
`/greppable:memory off` — disable memory extraction

## Flow

1. **Read current config** — check `.claude/greppable.local.md` (project) and `~/.claude/greppable.local.md` (global) for `memory` key. Use:

```bash
project_val=$(grep -m1 '^memory:' .claude/greppable.local.md 2>/dev/null | awk '{print $2}')
global_val=$(grep -m1 '^memory:' ~/.claude/greppable.local.md 2>/dev/null | awk '{print $2}')
val="${project_val:-$global_val}"
[[ "$val" == "true" ]] && echo "enabled" || echo "disabled"
```

2. **If no argument (status only):**
   - Report: "Session memory extraction is currently **enabled/disabled**."
   - If enabled, show where memories are written: `<gdl_root>/memory/active/`
   - If disabled, explain: "Run `/greppable:memory on` to enable. When a new session starts, the previous session's transcript is processed into searchable .gdlm memory records."

3. **If argument is `on`:**
   - Find the config file. Prefer project-scope (`.claude/greppable.local.md`). If only global exists, use that. If neither exists, tell user to run `/greppable:onboard` first.
   - If `memory:` key exists and value is `false`, change `memory: false` → `memory: true` using Edit tool.
   - If `memory:` key exists and value is already `true`, confirm: "Memory extraction is already **enabled**."
   - If `memory:` key doesn't exist, add `memory: true` on a new line after `discovery_auto_prompt:` using Edit tool.
   - Confirm: "Memory extraction **enabled**. When your next session starts, the previous session will be processed into `.gdlm` records. Restart Claude Code for changes to take effect."

4. **If argument is `off`:**
   - Same config detection as `on`.
   - If `memory:` key exists and value is `true`, change `memory: true` → `memory: false` using Edit tool.
   - If `memory:` key exists and value is already `false`, confirm: "Memory extraction is already **disabled**."
   - If `memory:` key doesn't exist, add `memory: false` on a new line after `discovery_auto_prompt:` using Edit tool.
   - Confirm: "Memory extraction **disabled**. Session transcripts will no longer be processed. Restart Claude Code for changes to take effect."

5. **If argument is anything else:**
   - "Usage: `/greppable:memory [on|off]`"

## Notes

- Always remind user that config changes require a Claude Code restart.
- The `memory` key is independent of `layers_gdlm` — you can have GDLM layer enabled (for manual memory files) without auto-extraction.
