---
name: managing-gdlignore
description: Use when excluding files or directories from GDL scanning — generated code, node_modules, UI component libraries, or test fixtures that pollute code maps. Triggers on: 'ignore this directory', 'exclude from scanning', 'too much noise in GDL', '.gdlignore'. NOT for .gitignore management or general file filtering.
---

When the user asks to exclude files/directories from GDL scanning, or mentions .gdlignore:

1. Read the current `.gdlignore` if it exists
2. Determine what they want to exclude
3. Use the Edit or Write tool to update `.gdlignore`
4. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-lint.sh" .gdlignore` to validate
5. Confirm the change to the user
