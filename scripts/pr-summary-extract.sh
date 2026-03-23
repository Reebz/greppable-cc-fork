#!/usr/bin/env bash
# pr-summary-extract.sh — Structured data extraction for PR summaries
#
# Provides functions for:
#   - Escaping GDL field values (pipes, colons, backslashes)
#   - Formatting @pr-summary and @pr-file record lines
#   - Determining diff reading tier based on PR size
#   - Selecting top changed files for patch reading
#
# Usage: source scripts/pr-summary-extract.sh
#
# See: docs/plans/2026-02-05-pr-summary-design.md

# Escape a value for use in a GDL key:value field.
# Escapes: \ → \\, | → \|, : → \:
escape_gdl_value() {
    local val="$1"
    val="${val//\\/\\\\}"
    val="${val//|/\\|}"
    val="${val//:/\\:}"
    printf '%s\n' "$val"
}

# Format a @pr-summary GDL record line.
# Args: $1=PR JSON (from gh pr view --json), $2=summary, $3=areas, $4=action
format_pr_summary_line() {
    local json="$1" summary="$2" areas="$3" action="$4"

    local id title author ts additions deletions files commits branch base
    id=$(printf '%s' "$json" | jq -r '.number // ""')
    title=$(escape_gdl_value "$(printf '%s' "$json" | jq -r '.title // ""')")
    author=$(printf '%s' "$json" | jq -r '.author.login // ""')
    ts=$(printf '%s' "$json" | jq -r '.mergedAt // .createdAt // ""')
    additions=$(printf '%s' "$json" | jq -r '.additions // 0')
    deletions=$(printf '%s' "$json" | jq -r '.deletions // 0')
    files=$(printf '%s' "$json" | jq -r '.changedFiles // 0')
    commits=$(printf '%s' "$json" | jq -r '.commits | length')
    branch=$(escape_gdl_value "$(printf '%s' "$json" | jq -r '.headRefName // ""')")
    base=$(escape_gdl_value "$(printf '%s' "$json" | jq -r '.baseRefName // ""')")

    summary=$(escape_gdl_value "$summary")
    areas=$(escape_gdl_value "$areas")

    printf '%s\n' "@pr-summary|id:${id}|title:${title}|author:${author}|ts:${ts}|summary:${summary}|areas:${areas}|additions:${additions}|deletions:${deletions}|files:${files}|commits:${commits}|branch:${branch}|base:${base}|action:${action}"
}

# Format a @pr-file GDL record line.
# Args: $1=PR number, $2=file path, $3=additions, $4=deletions, $5=action, $6=change description
format_pr_file_line() {
    local pr="$1" file="$2" additions="$3" deletions="$4" action="$5" change="$6"
    file=$(escape_gdl_value "$file")
    change=$(escape_gdl_value "$change")
    printf '%s\n' "@pr-file|pr:${pr}|file:${file}|action:${action}|additions:${additions}|deletions:${deletions}|change:${change}"
}

# Determine which diff reading tier to use based on file count.
# Returns: "small" (<15), "medium" (15-40), "large" (40+)
determine_diff_tier() {
    local file_count="$1"
    if (( file_count < 15 )); then
        echo "small"
    elif (( file_count <= 40 )); then
        echo "medium"
    else
        echo "large"
    fi
}

# Return the top N files by total changes (additions + deletions).
# Args: $1=files JSON array, $2=N
# Output: newline-separated file paths
top_changed_files() {
    local files_json="$1" n="$2"
    echo "$files_json" | jq -r "sort_by(-(.additions + .deletions)) | .[:${n}] | .[].path"
}
