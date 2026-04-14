---
description: Check GDL health and diagnose issues — platform diagnostics, root resolution, setup status, scope conflicts, artifact inventory, and interactive investigation tools
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
---

# /greppable:status — Health Check

Check GDL configuration, platform compatibility, and artifact health for the current project.
Before running any bash blocks, tell the user: "Gathering status information..."

Run the bash block below, then present the results as a **condensed summary table** (one row per category: Platform, Root, Mode, Version, Artifacts, Duplicates, Hooks, Setup). Keep it tight — the user wants a quick health check, not verbose output.

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
POST_LINT="${PLUGIN_ROOT}/hooks/post-gdl-lint.sh"
[[ -f "$HOOKS_JSON" ]] && echo "  hooks.json: OK" || echo "  hooks.json: MISSING"
[[ -f "$POST_LINT" ]] && echo "  post-gdl-lint.sh: OK" || echo "  post-gdl-lint.sh: MISSING"
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
if find "$ARTIFACT_DIR" \( -name '*.gdls' -o -name '*.gdla' -o -name '*.gdld' -o -name '*.gdl' \) -print -quit 2>/dev/null | grep -q .; then
  echo "  Discovery: complete"
else
  echo "  Discovery: not done -- Run /greppable:discover"
fi
```

## Interactive Investigation

After presenting the status dump above, offer the user these investigation options:

---

### Want to investigate further?

**[1] Check hooks firing** -- execute post-gdl-lint.sh and report output/errors
**[2] Check latest version** -- fetch latest GitHub release and compare (requires gh auth or public repo)
**[3] GDL validation (lint check)** -- run format validation across all artifacts

Wait for the user to pick an option before running anything below.

## Option 1: Check Hooks Firing

Run this bash script and report the results to the user:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(ls -d ~/.claude/plugins/cache/greppable*/greppable/[0-9]* 2>/dev/null | sort -V | tail -1)}"
if [[ -z "$PLUGIN_ROOT" || ! -d "$PLUGIN_ROOT" ]]; then echo "Error: plugin root not found" >&2; exit 1; fi
source "${PLUGIN_ROOT}/lib/session-context.sh"
echo "### Hook Firing Test"
echo ""
POST_LINT="${PLUGIN_ROOT}/hooks/post-gdl-lint.sh"
if [ -f "$POST_LINT" ]; then
  echo "Found post-gdl-lint.sh..."
else
  echo "BLOCKED: post-gdl-lint.sh not found at $POST_LINT"
  echo "  Reinstall greppable plugin"
  exit 1
fi
HOOKS_JSON="${PLUGIN_ROOT}/hooks/hooks.json"
if [ -f "$HOOKS_JSON" ]; then
  echo "Found hooks.json..."
else
  echo "BLOCKED: hooks.json not found at $HOOKS_JSON"
  echo "  Reinstall greppable plugin"
  exit 1
fi
echo ""
echo "Hook files present and accessible"
echo ""
if [ -x "$POST_LINT" ]; then
  echo "post-gdl-lint.sh: executable"
else
  echo "WARNING: post-gdl-lint.sh is not executable -- chmod +x $POST_LINT"
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
      echo "Release notes: https://github.com/greppable/greppable-cc-plugin/releases/tag/v${LATEST}"
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

## Option 3: GDL Validation (Lint Check)

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
