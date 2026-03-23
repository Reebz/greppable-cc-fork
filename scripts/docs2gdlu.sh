#!/usr/bin/env bash
# docs2gdlu.sh — Parse markdown docs into GDLU index records
# Usage: docs2gdlu.sh <file.md> [--output=DIR] [--dry-run]
#   or:  docs2gdlu.sh --recursive <dir> [--output=DIR] [--dry-run] [--exclude=PATTERN]
set -uo pipefail

TARGET_FILE=""
TARGET_DIR=""
RECURSIVE=false
OUTPUT_DIR=""
DRY_RUN=false
EXCLUDE_PATTERN="CHANGELOG\.md|LICENSE\.md"
SCRIPT_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source gdl-tools for .gdlignore support (redirect stdout to avoid contaminating output)
source "$SCRIPT_DIR_SELF/gdl-tools.sh" >/dev/null 2>/dev/null || true

# Parse flags first, then positional args
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --output=*) OUTPUT_DIR="${arg#--output=}" ;;
    --recursive) RECURSIVE=true ;;
    --dry-run) DRY_RUN=true ;;
    --exclude=*) EXCLUDE_PATTERN="${arg#--exclude=}" ;;
    --help|-h)
      cat <<'USAGE'
docs2gdlu.sh — Parse markdown docs into GDLU index records

Usage: docs2gdlu.sh <file.md> [--output=DIR] [--dry-run]
   or: docs2gdlu.sh --recursive <dir> [--output=DIR] [--dry-run] [--exclude=PATTERN]

Parses markdown headings into @source, @section, and @extract records.

OPTIONS:
  --output=DIR       Write output to DIR/<slug>.docs.gdlu
  --recursive        Process all *.md files in directory
  --dry-run          Show what would be generated without writing
  --exclude=PATTERN  Regex of filenames to skip (default: CHANGELOG|LICENSE)
  --help             Show this help
USAGE
      exit 0 ;;
    -*) echo "Unknown flag: $arg. Run with --help for usage." >&2; exit 1 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

# Assign positional arg based on --recursive flag
if [[ ${#POSITIONAL[@]} -gt 0 ]]; then
  if [[ "$RECURSIVE" = true ]]; then
    TARGET_DIR="${POSITIONAL[0]}"
  else
    TARGET_FILE="${POSITIONAL[0]}"
  fi
fi

if [[ -z "$TARGET_FILE" ]] && [[ -z "$TARGET_DIR" ]]; then
  echo "Error: provide a markdown file or --recursive <dir>" >&2
  echo "Usage: docs2gdlu.sh <file.md> [--output=DIR] [--dry-run]" >&2
  exit 1
fi

TS=$(date -u +"%Y-%m-%dT%H:%M:%S")

# Process a single markdown file — awk produces ALL records (including @source)
process_md() {
  local filepath="$1"
  local fname
  fname=$(basename "$filepath")
  local slug
  slug=$(basename "$filepath" .md | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  local src_id="U-${slug}-001"

  awk -v src_id="$src_id" -v filepath="$fname" -v ts="$TS" -v slug="$slug" '
  BEGIN {
    sec_seq = 1; ext_seq = 1; in_code_block = 0
    title = ""; title_summary = ""
    pending_summary = 0
    parent_sec_id = ""
    # Buffer section records so @source can be output first
    rec_count = 0
  }

  # Strip Windows line endings
  { gsub(/\r$/, "") }

  # Flush any pending section summary before processing a new heading
  function flush_pending() {
    if (pending_summary) {
      section_recs[pending_idx] = section_recs[pending_idx] "(no summary)"
      pending_summary = 0
    }
  }

  # Track fenced code blocks — headings inside are ignored
  /^```/ || /^~~~/ {
    in_code_block = !in_code_block
    next
  }
  in_code_block { next }

  # Title (# heading) — becomes @source summary
  /^# [^#]/ && title == "" {
    title = substr($0, 3)
    gsub(/\|/, "\\|", title)
    next
  }

  # First paragraph after title — becomes source summary
  title != "" && title_summary == "" && !pending_summary && /^[^#]/ && !/^$/ && !/^[-*]/ {
    title_summary = $0
    gsub(/\|/, "\\|", title_summary)
    next
  }

  # Level-2 heading (## ) — top-level section
  /^## [^#]/ {
    flush_pending()
    heading = substr($0, 4)
    gsub(/[[:space:]]+#{1,}[[:space:]]*$/, "", heading)
    gsub(/\|/, "\\|", heading)
    sec_id = sprintf("S-%s-%03d", slug, sec_seq++)
    parent_sec_id = sec_id
    rec_count++
    section_recs[rec_count] = sprintf("@section|source:%s|id:%s|loc:L:%d|title:%s|summary:", src_id, sec_id, NR, heading)
    pending_summary = 1
    pending_idx = rec_count
    next
  }

  # Level-3 heading (### ) — nested section with parent
  /^### [^#]/ {
    flush_pending()
    heading = substr($0, 5)
    gsub(/[[:space:]]+#{1,}[[:space:]]*$/, "", heading)
    gsub(/\|/, "\\|", heading)
    sec_id = sprintf("S-%s-%03d", slug, sec_seq++)
    rec_count++
    section_recs[rec_count] = sprintf("@section|source:%s|id:%s|loc:L:%d|title:%s|parent:%s|summary:", src_id, sec_id, NR, heading, parent_sec_id)
    pending_summary = 1
    pending_idx = rec_count
    next
  }

  # First non-empty paragraph after a heading — becomes section summary
  pending_summary && /^[^#]/ && !/^$/ && !/^```/ && !/^~~~/ {
    summary = $0
    gsub(/\|/, "\\|", summary)
    section_recs[pending_idx] = section_recs[pending_idx] summary
    pending_summary = 0
    next
  }

  # Skip blank lines while waiting for summary content
  pending_summary && /^$/ {
    next
  }

  # Structured list items with bold keys → @extract
  /^[-*] \*\*[^*]+\*\*/ {
    line = $0
    bold_start = index(line, "**")
    if (bold_start > 0) {
      rest = substr(line, bold_start + 2)
      bold_end = index(rest, "**")
      if (bold_end > 0) {
        key = substr(rest, 1, bold_end - 1)
        after = substr(rest, bold_end + 2)
        gsub(/^[: —–\-]+/, "", after)
        value = after
        gsub(/\|/, "\\|", key)
        gsub(/\|/, "\\|", value)
        ext_id = sprintf("X-%s-%03d", substr(src_id, 3), ext_seq++)
        rec_count++
        section_recs[rec_count] = sprintf("@extract|source:%s|id:%s|kind:list-item|key:%s|value:%s", src_id, ext_id, key, value)
      }
    }
    next
  }

  END {
    flush_pending()
    # Output @source first
    src_summary = title
    if (title_summary != "") src_summary = title_summary
    if (src_summary == "") src_summary = slug
    printf "@source|id:%s|path:%s|format:md|type:documentation|agent:docs2gdlu|summary:%s|ts:%s\n", src_id, filepath, src_summary, ts
    # Output buffered section/extract records
    for (i = 1; i <= rec_count; i++) {
      print section_recs[i]
    }
  }
  ' "$filepath"
}

# Collect output
OUTPUT=""
if [[ "$RECURSIVE" = true ]] && [[ -n "$TARGET_DIR" ]]; then
  _tmp_filelist=$(mktemp)
  find "$TARGET_DIR" \
    -type d \( -name node_modules -o -name .git -o -name __pycache__ \
       -o -name .venv -o -name vendor -o -name target \
       -o -name dist -o -name build -o -name .next \
       -o -name .nuxt -o -name .output -o -name out \) -prune \
    -o -type f -name '*.md' -print0 | sort -z > "$_tmp_filelist"
  while IFS= read -r -d '' mdfile; do
    fname=$(basename "$mdfile")
    if echo "$fname" | grep -qE "$EXCLUDE_PATTERN"; then continue; fi
    # Check .gdlignore (look in git root if available, else TARGET_DIR)
    relpath="${mdfile#"$TARGET_DIR"/}"
    relpath="${relpath#./}"
    _gdlignore_dir=""
    _gdlignore_dir=$(cd "$TARGET_DIR" && git rev-parse --show-toplevel 2>/dev/null) || _gdlignore_dir="$TARGET_DIR"
    if gdl_should_exclude "$relpath" gdlu "$_gdlignore_dir/.gdlignore" 2>/dev/null; then continue; fi
    result=$(process_md "$mdfile")
    OUTPUT="${OUTPUT}${result}
"
  done < "$_tmp_filelist"
  rm -f "$_tmp_filelist"
elif [[ -n "$TARGET_FILE" ]]; then
  # Note: .gdlignore is only checked in --recursive mode.
  # Single-file mode is explicit user intent — no exclusion check.
  if [[ ! -f "$TARGET_FILE" ]]; then
    echo "Error: file '$TARGET_FILE' does not exist. Check path or run: ls *.md" >&2
    exit 1
  fi
  OUTPUT=$(process_md "$TARGET_FILE")
fi

if [[ -z "$OUTPUT" ]]; then
  echo "No markdown content found." >&2
  exit 0
fi

if [[ "$DRY_RUN" = true ]] || [[ -z "$OUTPUT_DIR" ]]; then
  printf '%s\n' "$OUTPUT"
else
  mkdir -p "$OUTPUT_DIR"
  _slug_input="${TARGET_FILE:-$TARGET_DIR}"
  # Resolve . and .. to actual directory name
  if [[ -d "$_slug_input" ]]; then
    _slug_input=$(cd "$_slug_input" && pwd)
  fi
  SLUG=$(basename "$_slug_input" .md | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  OUT_FILE="$OUTPUT_DIR/${SLUG}.docs.gdlu"
  # Atomic write: temp file + mv to avoid partial reads
  _tmp_out=$(mktemp "${OUTPUT_DIR}/.gdlu.XXXXXX") || { echo "Error: failed to create temp file in $OUTPUT_DIR" >&2; exit 1; }
  if printf '%s\n' "$OUTPUT" > "$_tmp_out" && mv "$_tmp_out" "$OUT_FILE"; then
    echo "Wrote $(echo "$OUTPUT" | grep -c '^@') records to $OUT_FILE" >&2
  else
    rm -f "$_tmp_out"
    echo "Error: failed to write $OUT_FILE" >&2
    exit 1
  fi
fi
