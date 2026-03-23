---
description: Check GDL health and diagnose issues — platform diagnostics, root resolution, setup status, scope conflicts, artifact inventory, and interactive investigation tools
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
---

# /greppable:status — Health Check

Check GDL configuration, platform compatibility, and artifact health for the current project.
Before running any bash blocks, tell the user: "Gathering status information..."

Run the bash block below, then present the results as a **condensed summary table** (one row per category: Platform, Root, Mode, Version, Artifacts, Memory, Duplicates, Hooks, Setup). Keep it tight — the user wants a quick health check, not verbose output.

## Status Dump

```bash
# Resolve plugin root with fallback (MUST be before any source calls)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(ls -d ~/.claude/plugins/cache/greppable*/greppable/[0-9]* 2>/dev/null | sort -V | tail -1)}"
if [[ -z "$PLUGIN_ROOT" || ! -d "$PLUGIN_ROOT" ]]; then
  echo "Error: Cannot resolve plugin root (CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT:-unset}, cache lookup failed)." >&2
  echo "  Reinstall greppable: claude plugins install greppable" >&2
  exit 1
fi
source "${PLUGIN_ROOT}/lib/session-context.sh"
RESOLVED_ROOT=$(gdl_find_root ".")
PROJECT_CFG="$RESOLVED_ROOT/.claude/greppable.local.md"
GLOBAL_CFG="$HOME/.claude/greppable.local.md"
echo "=== GDL Status ==="
echo ""
echo "## Platform"
OS=$(uname -s)
case "$OS" in
  MINGW*|MSYS*) echo "  OS: Windows (Git Bash)" ;;
  Darwin*)      echo "  OS: macOS" ;;
  Linux*)       echo "  OS: Linux" ;;
  *)            echo "  OS: $OS" ;;
esac
echo "  Bash: $BASH_VERSION"
if command -v node &>/dev/null; then
  echo "  Node.js: $(node --version)"
else
  echo "  Node.js: not found (needed for session2gdlm)"
fi
CLAUDE_PATH="not found"
if command -v claude &>/dev/null; then
  CLAUDE_PATH=$(command -v claude)
elif command -v claude.exe &>/dev/null; then
  CLAUDE_PATH=$(command -v claude.exe)
fi
echo "  Claude CLI: $CLAUDE_PATH"
echo ""
echo "## Root Resolution"
echo "  CWD: $(pwd)"
echo "  Resolved root: $RESOLVED_ROOT"
if [[ -f "$RESOLVED_ROOT/.claude/greppable.local.md" ]]; then
  echo "  Method: config-walk (.claude/greppable.local.md found)"
elif git -C "$RESOLVED_ROOT" rev-parse --show-toplevel &>/dev/null; then
  echo "  Method: git-root fallback"
else
  echo "  Method: cwd-fallback (no config or git repo found)"
fi
echo ""
echo "## Configuration"
if [[ -f "$GLOBAL_CFG" ]]; then
  echo "  Global config: $GLOBAL_CFG"
  echo "    gdl_root: $(gdl_config_val "$GLOBAL_CFG" gdl_root)"
else
  echo "  Global config: not found"
fi
if [[ -f "$PROJECT_CFG" ]]; then
  echo "  Project config: $PROJECT_CFG (wins on conflict)"
  echo "    gdl_root: $(gdl_config_val "$PROJECT_CFG" gdl_root)"
else
  echo "  Project config: not found"
fi
echo ""
echo "## Hook Health"
HOOKS_JSON="${PLUGIN_ROOT}/hooks/hooks.json"
SESSION_START="${PLUGIN_ROOT}/hooks/session-start.sh"
HOOK_MJS="${PLUGIN_ROOT}/scripts/session2gdlm/dist/hook.mjs"
[[ -f "$HOOKS_JSON" ]] && echo "  hooks.json: OK" || echo "  hooks.json: MISSING"
[[ -f "$SESSION_START" ]] && echo "  session-start.sh: OK" || echo "  session-start.sh: MISSING"
[[ -f "$HOOK_MJS" ]] && echo "  hook.mjs (bundle): OK" || echo "  hook.mjs (bundle): MISSING"
echo ""
PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"
if [[ -f "$PLUGIN_JSON" ]]; then
  VERSION=$(grep '"version"' "$PLUGIN_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  echo "## Version: $VERSION"
else
  echo "## Version: unknown"
fi
echo ""
echo "## Scope Check"
PLUGIN_CACHE_BASE=$(dirname "${PLUGIN_ROOT}" 2>/dev/null)
if [[ -d "$PLUGIN_CACHE_BASE" ]]; then
  INSTALLED_VERSIONS=()
  INSTALLED_PATHS=()
  while IFS= read -r ver_dir; do
    [[ -z "$ver_dir" ]] && continue
    ver_pj="$ver_dir/.claude-plugin/plugin.json"
    if [[ -f "$ver_pj" ]]; then
      ver=$(grep '"version"' "$ver_pj" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
      INSTALLED_VERSIONS+=("$ver")
      INSTALLED_PATHS+=("$ver_dir")
    fi
  done <<< "$(find "$PLUGIN_CACHE_BASE" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)"
  if (( ${#INSTALLED_VERSIONS[@]} > 1 )); then
    echo "  Multiple installations detected:"
    for i in "${!INSTALLED_VERSIONS[@]}"; do
      active=""
      [[ "${INSTALLED_PATHS[$i]}" == "${PLUGIN_ROOT}" ]] && active=" <- active"
      echo "    v${INSTALLED_VERSIONS[$i]} at ${INSTALLED_PATHS[$i]}${active}"
    done
  elif (( ${#INSTALLED_VERSIONS[@]} == 1 )); then
    echo "  v${INSTALLED_VERSIONS[0]} -- single installation, no conflicts"
  else
    echo "  Could not detect installed versions"
  fi
else
  echo "  Plugin cache not accessible"
fi
echo ""
SCOPE=""
if [[ -f "$PROJECT_CFG" ]]; then
  SCOPE="project"
elif [[ -f "$GLOBAL_CFG" ]]; then
  SCOPE="global"
fi
echo "## Scope"
if [[ -z "$SCOPE" ]]; then
  echo "  Config: unconfigured (auto-enabled if artifacts exist)"
else
  echo "  Config: $SCOPE scope"
fi
echo ""
echo "## Artifacts"
GDL_ROOT_VAL=$(gdl_config_val "$PROJECT_CFG" gdl_root 2>/dev/null)
[[ -z "$GDL_ROOT_VAL" ]] && GDL_ROOT_VAL=$(gdl_config_val "$GLOBAL_CFG" gdl_root 2>/dev/null)
[[ -z "$GDL_ROOT_VAL" ]] && GDL_ROOT_VAL="docs/gdl"
ARTIFACT_DIR="$RESOLVED_ROOT/$GDL_ROOT_VAL"
echo "  Root: $ARTIFACT_DIR"
gdl_scan_artifacts "$ARTIFACT_DIR"
echo ""
echo "## Memory Extraction"
MEMORY_VAL=""
if [[ -f "$PROJECT_CFG" ]]; then
  MEMORY_VAL=$(gdl_config_val "$PROJECT_CFG" memory 2>/dev/null)
fi
if [[ -z "$MEMORY_VAL" && -f "$GLOBAL_CFG" ]]; then
  MEMORY_VAL=$(gdl_config_val "$GLOBAL_CFG" memory 2>/dev/null)
fi
SESSION_GDLM_COUNT=$(find "$ARTIFACT_DIR" -name '*.session.gdlm' 2>/dev/null | wc -l | tr -d ' ')
if [ "$MEMORY_VAL" = "true" ]; then
  if (( SESSION_GDLM_COUNT > 0 )); then
    echo "  Memory extraction: working ($SESSION_GDLM_COUNT .session.gdlm files)"
  else
    echo "  Memory extraction: enabled but not yet active (no .session.gdlm files)"
  fi
else
  echo "  Memory extraction: disabled (memory: ${MEMORY_VAL:-unset}) -- toggle with /greppable:memory"
fi
echo ""
echo "## Duplicate Detection"
DUPES=$(find "$RESOLVED_ROOT" -type d -name "gdl" -path "*/docs/gdl" 2>/dev/null | grep -v "$GDL_ROOT_VAL" || true)
if [[ -n "$DUPES" ]]; then
  echo "  WARNING: GDL artifact directories found outside resolved root:"
  echo "$DUPES" | sed 's/^/    /'
else
  echo "  No duplicate artifact directories found"
fi
echo ""
echo "## Setup Status"
if [[ -f "$PROJECT_CFG" ]] || [[ -f "$RESOLVED_ROOT/.claude/greppable.project.md" ]]; then
  echo "  Onboarding: complete"
else
  echo "  Onboarding: not done -- Run /greppable:onboard"
fi
if find "$ARTIFACT_DIR" \( -name '*.gdlc' -o -name '*.gdls' \) -print -quit 2>/dev/null | grep -q .; then
  echo "  Discovery: complete"
else
  echo "  Discovery: not done -- Run /greppable:discover"
fi
```

## Interactive Investigation

After presenting the status dump above, offer the user these investigation options:

---

### Want to investigate further?

**[1] Check hooks firing** -- execute session-start.sh and report output/errors
**[2] Check latest version** -- fetch latest GitHub release and compare (requires gh auth or public repo)
**[3] Inspect memory extraction** -- review session2gdlm logs and recent extraction output
**[4] Check stale code maps** -- scan .gdlc files against source for staleness
**[5] GDL validation (lint check)** -- run format validation across all artifacts

Wait for the user to pick an option before running anything below.

## Option 1: Check Hooks Firing

Run this bash script and report the results to the user:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(ls -d ~/.claude/plugins/cache/greppable*/greppable/[0-9]* 2>/dev/null | sort -V | tail -1)}"
if [[ -z "$PLUGIN_ROOT" || ! -d "$PLUGIN_ROOT" ]]; then echo "Error: plugin root not found" >&2; exit 1; fi
source "${PLUGIN_ROOT}/lib/session-context.sh"
echo "### Hook Firing Test"
echo ""
SESSION_START="${PLUGIN_ROOT}/hooks/session-start.sh"
if [ -f "$SESSION_START" ]; then
  echo "Executing session-start.sh..."
else
  echo "BLOCKED: session-start.sh not found at $SESSION_START"
  echo "  Reinstall greppable plugin"
  exit 1
fi
echo ""
START_TIME=$(date +%s%N 2>/dev/null || date +%s)
OUTPUT=$(bash "$SESSION_START" 2>&1)
EXIT_CODE=$?
END_TIME=$(date +%s%N 2>/dev/null || date +%s)
if [[ "$START_TIME" =~ ^[0-9]{10,}$ ]]; then
  DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
  echo "Duration: ${DURATION_MS}ms"
else
  echo "Duration: <1s"
fi
echo "Exit code: $EXIT_CODE"
echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
  echo "Hook executed successfully"
  echo ""
  if [ -z "$OUTPUT" ]; then
    echo "No output (normal for new/unconfigured projects -- hook exits silently when no config found)"
  else
    echo "Output preview:"
    echo "$OUTPUT" | head -30
    echo ""
    if echo "$OUTPUT" | grep -q "hookSpecificOutput"; then
      echo "Output contains hookSpecificOutput (context injection working)"
    else
      echo "WARNING: Output present but missing hookSpecificOutput -- context may not be injected"
    fi
  fi
else
  echo "Hook FAILED (exit code $EXIT_CODE)"
  echo ""
  echo "Error output:"
  echo "$OUTPUT"
  echo ""
  if echo "$OUTPUT" | grep -qi "permission denied"; then
    echo "Diagnosis: Permission denied -- chmod +x $SESSION_START"
  elif echo "$OUTPUT" | grep -qi "command not found"; then
    echo "Diagnosis: Missing dependency -- a required command is not installed"
  elif echo "$OUTPUT" | grep -qi "CLAUDE_PLUGIN_ROOT"; then
    echo "Diagnosis: CLAUDE_PLUGIN_ROOT not set (see greppable#77)"
  elif echo "$OUTPUT" | grep -qi "No such file"; then
    echo "Diagnosis: File not found -- plugin installation may be incomplete"
  else
    echo "Diagnosis: Unknown error -- review the output above"
  fi
fi
```

## Option 2: Check Latest Version

Run this bash script and report the results to the user. Note: requires `gh` CLI authenticated against the greppable repo (works once repo is public, or if user has private access).

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(ls -d ~/.claude/plugins/cache/greppable*/greppable/[0-9]* 2>/dev/null | sort -V | tail -1)}"
if [[ -z "$PLUGIN_ROOT" || ! -d "$PLUGIN_ROOT" ]]; then echo "Error: plugin root not found" >&2; exit 1; fi
echo "### Version Check"
echo ""
PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"
INSTALLED="unknown"
if [ -f "$PLUGIN_JSON" ]; then
  INSTALLED=$(grep '"version"' "$PLUGIN_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi
echo "Installed: $INSTALLED"
if command -v gh &>/dev/null; then
  LATEST_JSON=$(gh api repos/greppable/greppable/releases/latest 2>/dev/null)
  if [ -n "$LATEST_JSON" ]; then
    LATEST=$(echo "$LATEST_JSON" | node -e "process.stdin.on('data',d=>{try{console.log(JSON.parse(d).tag_name.replace(/^v/,''))}catch{console.log('unknown')}})" 2>/dev/null)
    echo "Latest:    $LATEST"
    echo ""
    if [ "$INSTALLED" = "$LATEST" ]; then
      echo "You are running the latest version"
    elif [ "$LATEST" != "unknown" ]; then
      echo "Update available"
      echo ""
      echo "To upgrade, run:"
      echo "  claude plugins update greppable"
      echo ""
      echo "Release notes: https://github.com/greppable/greppable/releases/tag/v${LATEST}"
      echo ""
      echo "Note: Local patches (e.g. Windows fixes from greppable#76) will be overwritten."
    fi
  else
    echo "Latest:    could not fetch (no GitHub releases found, or repo is private)"
    echo "  Requires: gh auth with repo access, and at least one GitHub Release"
  fi
else
  echo "Latest:    cannot check (gh CLI not available)"
fi
```

## Option 3: Inspect Memory Extraction

Run this bash script and report the results to the user:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(ls -d ~/.claude/plugins/cache/greppable*/greppable/[0-9]* 2>/dev/null | sort -V | tail -1)}"
if [[ -z "$PLUGIN_ROOT" || ! -d "$PLUGIN_ROOT" ]]; then echo "Error: plugin root not found" >&2; exit 1; fi
source "${PLUGIN_ROOT}/lib/session-context.sh"
echo "### Memory Extraction Inspector"
echo ""
RESOLVED_ROOT=$(gdl_find_root ".")
PROJECT_CFG="$RESOLVED_ROOT/.claude/greppable.local.md"
GLOBAL_CFG="$HOME/.claude/greppable.local.md"
MEMORY_ENABLED="false"
if [ -f "$PROJECT_CFG" ]; then
  val=$(gdl_config_val "$PROJECT_CFG" memory 2>/dev/null)
  [ -n "$val" ] && MEMORY_ENABLED="$val"
fi
if [ "$MEMORY_ENABLED" = "false" ] && [ -f "$GLOBAL_CFG" ]; then
  val=$(gdl_config_val "$GLOBAL_CFG" memory 2>/dev/null)
  [ -n "$val" ] && MEMORY_ENABLED="$val"
fi
echo "Memory enabled: $MEMORY_ENABLED"
if [ "$MEMORY_ENABLED" != "true" ]; then
  echo "  Memory extraction is OFF. Enable with /greppable:memory"
  echo ""
fi
LOG_FILE="$RESOLVED_ROOT/.claude/session2gdlm.log"
test -f "$LOG_FILE" || LOG_FILE="$HOME/.claude/session2gdlm.log"
if [ -f "$LOG_FILE" ]; then
  echo "Log file: $LOG_FILE"
  LINE_COUNT=$(wc -l < "$LOG_FILE" | tr -d ' ')
  echo "Log lines: $LINE_COUNT"
  echo ""
  HOOK_STARTS=$(grep -c "hook started" "$LOG_FILE" 2>/dev/null || echo "0")
  echo "Total hook starts: $HOOK_STARTS"
  SUCCESSES=$(grep -ci "wrote.*session.gdlm" "$LOG_FILE" 2>/dev/null || echo "0")
  echo "Successful extractions: $SUCCESSES"
  FALLBACKS=$(grep -c "fallback\|LLM.*unavailable\|Auto-extracted" "$LOG_FILE" 2>/dev/null || echo "0")
  if [ "$FALLBACKS" -gt 0 ]; then
    echo "WARNING: Fallback stubs: $FALLBACKS (LLM summarisation failed)"
  fi
  RACE_SKIPS=$(grep -c "skipped.*lock\|EEXIST" "$LOG_FILE" 2>/dev/null || echo "0")
  if [ "$RACE_SKIPS" -gt 0 ]; then
    echo "Lock skips: $RACE_SKIPS (expected — dedup working correctly)"
  fi
  META_SKIPS=$(grep -c "meta-session\|self-exclusion\|extraction marker" "$LOG_FILE" 2>/dev/null || echo "0")
  if [ "$META_SKIPS" -gt 0 ]; then
    echo "Meta-session skips: $META_SKIPS (correctly self-excluded)"
  fi
  echo ""
  echo "Last 10 log entries:"
  tail -10 "$LOG_FILE"
else
  echo "Log file: not found"
  echo "  Memory extraction may not have run yet."
  echo "  Expected locations:"
  echo "    $RESOLVED_ROOT/.claude/session2gdlm.log"
  echo "    $HOME/.claude/session2gdlm.log"
fi
echo ""
GDL_ROOT_VAL=$(gdl_config_val "$PROJECT_CFG" gdl_root 2>/dev/null)
test -z "$GDL_ROOT_VAL" && GDL_ROOT_VAL=$(gdl_config_val "$GLOBAL_CFG" gdl_root 2>/dev/null)
test -z "$GDL_ROOT_VAL" && GDL_ROOT_VAL="docs/gdl"
MEMORY_DIR="$RESOLVED_ROOT/$GDL_ROOT_VAL/memory/active"
echo "Memory output dir: $MEMORY_DIR"
if [ -d "$MEMORY_DIR" ]; then
  SESSION_FILES=$(find "$MEMORY_DIR" -name '*.session.gdlm' 2>/dev/null | sort -t/ -k99 | tail -5)
  SEED_FILES=$(find "$MEMORY_DIR" -name '*.seed.gdlm' 2>/dev/null)
  test -n "$SEED_FILES" && echo "  Seed files: $(echo "$SEED_FILES" | wc -l | tr -d ' ')"
  if [ -n "$SESSION_FILES" ]; then
    echo "  Session files (most recent 5):"
    while IFS= read -r f; do
      test -z "$f" && continue
      RECORDS=$(grep -c '^@memory' "$f" 2>/dev/null || echo "0")
      CONFIDENCE=$(grep -o 'confidence:[a-z]*' "$f" 2>/dev/null | sort | uniq -c | tr '\n' ', ' | sed 's/, $//')
      echo "    $(basename "$f") -- $RECORDS records ($CONFIDENCE)"
    done <<< "$SESSION_FILES"
  else
    echo "  No .session.gdlm files found"
  fi
else
  echo "  Directory does not exist"
  echo "  Run /greppable:discover to create the directory structure"
fi
```

## Option 4: Check Stale Code Maps

Run this bash script and report the results to the user. Note: this can take a while on large projects as it scans source directories for each .gdlc module.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(ls -d ~/.claude/plugins/cache/greppable*/greppable/[0-9]* 2>/dev/null | sort -V | tail -1)}"
if [[ -z "$PLUGIN_ROOT" || ! -d "$PLUGIN_ROOT" ]]; then echo "Error: plugin root not found" >&2; exit 1; fi
source "${PLUGIN_ROOT}/lib/session-context.sh"
echo "### Stale Code Map Detection"
echo ""
RESOLVED_ROOT=$(gdl_find_root ".")
PROJECT_CFG="$RESOLVED_ROOT/.claude/greppable.local.md"
GLOBAL_CFG="$HOME/.claude/greppable.local.md"
GDL_ROOT_VAL=$(gdl_config_val "$PROJECT_CFG" gdl_root 2>/dev/null)
test -z "$GDL_ROOT_VAL" && GDL_ROOT_VAL=$(gdl_config_val "$GLOBAL_CFG" gdl_root 2>/dev/null)
test -z "$GDL_ROOT_VAL" && GDL_ROOT_VAL="docs/gdl"
ARTIFACT_DIR="$RESOLVED_ROOT/$GDL_ROOT_VAL"
stale_count=0
total_count=0
while IFS= read -r gdlc_file; do
  [ -z "$gdlc_file" ] && continue
  total_count=$((total_count + 1))
  while IFS= read -r mod_line; do
    [ -z "$mod_line" ] && continue
    mod_path=$(echo "$mod_line" | sed 's/^@D //' | sed 's/|.*//')
    [ -z "$mod_path" ] && continue
    abs_mod_path="$RESOLVED_ROOT/$mod_path"
    test -d "$abs_mod_path" || test -f "$abs_mod_path" || continue
    newest_source=$(find "$abs_mod_path" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.py' -o -name '*.go' -o -name '*.java' -o -name '*.rs' -o -name '*.rb' -o -name '*.php' -o -name '*.cs' -o -name '*.c' -o -name '*.cpp' -o -name '*.kt' -o -name '*.swift' \) -newer "$gdlc_file" 2>/dev/null | head -1)
    if [ -n "$newest_source" ]; then
      echo "  STALE: $(basename "$gdlc_file") -- source in $mod_path is newer"
      stale_count=$((stale_count + 1))
      break
    fi
  done <<< "$(grep '^@D ' "$gdlc_file" 2>/dev/null || true)"
done <<< "$(find "$ARTIFACT_DIR" -name '*.gdlc' 2>/dev/null || true)"
echo ""
if [ "$stale_count" -eq 0 ]; then
  echo "All $total_count .gdlc code maps are current"
else
  echo "$stale_count of $total_count code map(s) are stale -- consider re-running /greppable:discover"
fi
```

## Option 5: GDL Validation (Lint Check)

Run this bash script and report the results to the user. Note: validates every line of every GDL artifact file — can be slow on large projects.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(ls -d ~/.claude/plugins/cache/greppable*/greppable/[0-9]* 2>/dev/null | sort -V | tail -1)}"
if [[ -z "$PLUGIN_ROOT" || ! -d "$PLUGIN_ROOT" ]]; then echo "Error: plugin root not found" >&2; exit 1; fi
source "${PLUGIN_ROOT}/lib/session-context.sh"
echo "### GDL Validation (Lint Check)"
echo ""
RESOLVED_ROOT=$(gdl_find_root ".")
PROJECT_CFG="$RESOLVED_ROOT/.claude/greppable.local.md"
GLOBAL_CFG="$HOME/.claude/greppable.local.md"
GDL_ROOT_VAL=$(gdl_config_val "$PROJECT_CFG" gdl_root 2>/dev/null)
test -z "$GDL_ROOT_VAL" && GDL_ROOT_VAL=$(gdl_config_val "$GLOBAL_CFG" gdl_root 2>/dev/null)
test -z "$GDL_ROOT_VAL" && GDL_ROOT_VAL="docs/gdl"
ARTIFACT_DIR="$RESOLVED_ROOT/$GDL_ROOT_VAL"
if [ -d "$ARTIFACT_DIR" ]; then
  echo "Scanning: $ARTIFACT_DIR"
  echo ""
  bash "${PLUGIN_ROOT}/scripts/gdl-lint.sh" --all "$ARTIFACT_DIR" --strict --exclude='*/tests/fixtures/*' 2>&1
else
  echo "No artifact directory found at $ARTIFACT_DIR"
fi
```
