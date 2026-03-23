---
name: managing-gdlignore
description: Use when the user mentions excluding files or directories from scanning, ignoring UI components, or managing .gdlignore patterns
---

When the user asks to exclude files/directories from GDL scanning, or mentions .gdlignore:

1. Read the current `.gdlignore` if it exists
2. Determine what they want to exclude
3. Use the Edit or Write tool to update `.gdlignore`
4. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gdl-lint.sh" .gdlignore` to validate
5. Confirm the change to the user
