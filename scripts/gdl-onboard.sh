#!/usr/bin/env bash
# gdl-onboard.sh — Deterministic (non-AI) onboard setup for GDL projects
#
# Usage: gdl-onboard.sh [--scope=project|global]
#                        [--gdl-root=PATH] [--layers=LAYER1,LAYER2,...]
#                        [--skip-gitignore]
#                        [--gdlignore-patterns=PATTERN1,PATTERN2,...]
#
# Performs the deterministic steps of /greppable:onboard:
#   1. Create config file at chosen scope
#   2. Update .gitignore (unless --skip-gitignore)
#   3. Create gdl_root directory structure
#
# All config is via flags — no interactive questions asked.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Defaults ---
SCOPE="project"
GDL_ROOT="docs/gdl"
LAYERS="gdl,gdls,gdld"
SKIP_GITIGNORE=false
GDLIGNORE_PATTERNS=""

# --- Usage ---
usage() {
    cat >&2 <<'EOF'
Usage: gdl-onboard.sh [OPTIONS]

Options:
  --scope=project|global   Config file location (default: project)
  --gdl-root=PATH          Where GDL artifacts live (default: docs/gdl)
  --layers=LAYER1,...       Comma-separated layers to enable (default: gdl,gdls,gdld)
  --skip-gitignore         Skip .gitignore update
  --gdlignore-patterns=P   Comma-separated .gdlignore patterns to write
  --help                   Show this help message

Layers: gdl, gdls, gdla, gdld, gdlu

Examples:
  gdl-onboard.sh
  gdl-onboard.sh --scope=global
  gdl-onboard.sh --gdl-root=.gdl --layers=gdls,gdla,gdld
EOF
    exit 1
}

# --- Parse flags ---
for arg in "$@"; do
    case "$arg" in
        --scope=*)
            SCOPE="${arg#--scope=}"
            if [[ "$SCOPE" != "project" && "$SCOPE" != "global" ]]; then
                echo "Error: --scope must be 'project' or 'global'" >&2
                exit 1
            fi
            ;;
        --mode=*)
            # Accepted for backward compatibility but ignored
            ;;
        --gdl-root=*)
            GDL_ROOT="${arg#--gdl-root=}"
            ;;
        --layers=*)
            LAYERS="${arg#--layers=}"
            ;;
        --skip-gitignore)
            SKIP_GITIGNORE=true
            ;;
        --skip-autopilot)
            # Accepted for backward compatibility but ignored (autopilot file removed)
            ;;
        --gdlignore-patterns=*)
            GDLIGNORE_PATTERNS="${arg#--gdlignore-patterns=}"
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Error: unknown flag '$arg'" >&2
            usage
            ;;
    esac
done

# --- Validate layers ---
ALL_VALID_LAYERS="gdl gdls gdla gdld gdlu"
IFS=',' read -r -a layer_arr <<< "$LAYERS"
for layer in "${layer_arr[@]}"; do
    valid=false
    for v in $ALL_VALID_LAYERS; do
        if [[ "$layer" == "$v" ]]; then
            valid=true
            break
        fi
    done
    if [[ "$valid" == "false" ]]; then
        echo "Error: unknown layer '$layer'. Valid layers: $ALL_VALID_LAYERS" >&2
        exit 1
    fi
done

# --- Helper: check if layer is enabled ---
layer_enabled() {
    local check="$1"
    for layer in "${layer_arr[@]}"; do
        if [[ "$layer" == "$check" ]]; then
            return 0
        fi
    done
    return 1
}

# --- Step 1: Create config file ---
echo "Setting up GDL configuration..." >&2

# Build YAML content
config_content="---
enabled: true
layers_gdl: $(layer_enabled gdl && echo true || echo false)
layers_gdls: $(layer_enabled gdls && echo true || echo false)
layers_gdla: $(layer_enabled gdla && echo true || echo false)
layers_gdld: $(layer_enabled gdld && echo true || echo false)
layers_gdlu: $(layer_enabled gdlu && echo true || echo false)
gdl_root: \"${GDL_ROOT}\"
discovery_auto_prompt: true
---

# GDL Configuration
# Scope: ${SCOPE}
"

if [[ "$SCOPE" == "global" ]]; then
    config_path="$HOME/.claude/greppable.local.md"
    mkdir -p "$HOME/.claude"
else
    config_path=".claude/greppable.local.md"
    mkdir -p ".claude"
fi

tmp_config=$(mktemp)
printf '%s' "$config_content" > "$tmp_config"
mv "$tmp_config" "$config_path"
echo "  Created config: $config_path" >&2

# --- Step 2: Update .gitignore ---
if [[ "$SKIP_GITIGNORE" == "false" ]]; then
    gitignore_entry=".claude/*.local.md"

    if [[ -f ".gitignore" ]]; then
        if ! grep -qF "$gitignore_entry" ".gitignore"; then
            echo "" >> ".gitignore"
            echo "# GDL local config (not committed)" >> ".gitignore"
            echo "$gitignore_entry" >> ".gitignore"
            echo "  Added $gitignore_entry to .gitignore" >&2
        else
            echo "  .gitignore already contains $gitignore_entry (skipped)" >&2
        fi
    else
        cat > ".gitignore" <<GITIGNORE
# GDL local config (not committed)
${gitignore_entry}
GITIGNORE
        echo "  Created .gitignore with $gitignore_entry" >&2
    fi
fi

# --- Step 3: Create gdl_root directory structure ---
# Map layers to subdirectories
layer_dirs=""
layer_enabled gdla && layer_dirs="$layer_dirs api"
layer_enabled gdls && layer_dirs="$layer_dirs schema"
layer_enabled gdld && layer_dirs="$layer_dirs diagrams"
layer_enabled gdl  && layer_dirs="$layer_dirs data"
layer_enabled gdlu && layer_dirs="$layer_dirs unstructured"

for dir in $layer_dirs; do
    mkdir -p "${GDL_ROOT}/${dir}"
done
echo "  Created directory structure: ${GDL_ROOT}/" >&2

# --- Step 3b: Sensitive information advisory ---
echo "" >&2
echo "  Note: GDL artifacts will contain architectural details about your" >&2
echo "  project (schema structure, endpoint paths, module dependencies," >&2
echo "  decision rationale). Review generated files before committing" >&2
echo "  to public repositories." >&2

# --- Step 4: Create .gdlignore if patterns provided ---
if [[ -n "${GDLIGNORE_PATTERNS:-}" ]]; then
  GDLIGNORE_FILE=".gdlignore"
  if [[ ! -f "$GDLIGNORE_FILE" ]]; then
    {
      echo "# .gdlignore — Exclude patterns for GDL bridge scanning"
      echo "#"
      echo "# Format: [format:]pattern"
      echo "#   No prefix = applies to all bridges"
      echo "#   gdlu: = document indexes only"
      echo "#"
      echo "# Patterns:"
      echo "#   dir/          Match directory anywhere in tree"
      echo "#   /dir/         Match directory at project root only"
      echo "#   **/*.ext      Match files by extension anywhere"
      echo ""
      IFS=',' read -ra patterns <<< "$GDLIGNORE_PATTERNS"
      for p in "${patterns[@]}"; do
        echo "$p"
      done
    } > "$GDLIGNORE_FILE"
    echo "  Created $GDLIGNORE_FILE" >&2
  else
    echo "  .gdlignore already exists, skipping" >&2
  fi
fi

echo "" >&2
echo "GDL onboard complete." >&2
echo "  Scope: ${SCOPE}" >&2
echo "  GDL root: ${GDL_ROOT}" >&2
echo "  Layers: ${LAYERS}" >&2
