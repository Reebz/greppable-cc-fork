#!/usr/bin/env bash
# gdlm-compact.sh — Compact aging GDLM memories from active to archive/history
# Usage: gdlm-compact.sh <memory_dir> [--threshold=DAYS] [--max-lines=N] [--dry-run]
#
# Implements MEMORY-SPEC.md compaction rules:
#   - Groups aging memories by subject, generates summary records
#   - Moves originals to history/{YYYY-MM}/
#   - Writes summaries to archive/
#   - Removes compacted records from active/
#
# Rules:
#   - Latest wins: multiple updates to same fact → keep latest only
#   - Decisions persist: always preserved in summary
#   - Error + resolution: compress to resolution
#   - Unresolved errors: promoted back to active (not compacted)
#   - Deletions: moved to history only (no summary)

set -euo pipefail

# --- Argument parsing ---
MEMORY_DIR=""
THRESHOLD_DAYS=30
MAX_LINES=1000
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --threshold=*) THRESHOLD_DAYS="${arg#--threshold=}" ;;
        --max-lines=*) MAX_LINES="${arg#--max-lines=}" ;;
        --dry-run) DRY_RUN=true ;;
        -*) echo "Unknown flag: $arg. Valid flags: --dry-run, --threshold=DAYS, --max-lines=N" >&2; exit 1 ;;
        *) MEMORY_DIR="$arg" ;;
    esac
done

if [[ -z "$MEMORY_DIR" ]]; then
    echo "Usage: gdlm-compact.sh <memory_dir> [--threshold=DAYS] [--max-lines=N] [--dry-run]" >&2
    echo "" >&2
    echo "  memory_dir    Directory containing active/, archive/, and history/ subdirs" >&2
    echo "  --threshold   Days before a memory is eligible for compaction (default: 30)" >&2
    echo "  --max-lines   Compact when active file exceeds this many lines (default: 1000)" >&2
    echo "  --dry-run     Show what would be compacted without making changes" >&2
    exit 1
fi

ACTIVE_DIR="$MEMORY_DIR/active"
ARCHIVE_DIR="$MEMORY_DIR/archive"
HISTORY_DIR="$MEMORY_DIR/history"

if [[ ! -d "$ACTIVE_DIR" ]]; then
    echo "Error: active directory not found: $ACTIVE_DIR" >&2
    exit 1
fi

# --- Compute cutoff date ---
# macOS date vs GNU date
if date -v -1d >/dev/null 2>&1; then
    CUTOFF=$(date -u -v "-${THRESHOLD_DAYS}d" +"%Y-%m-%dT%H:%M:%SZ")
    PERIOD=$(date -u +"%Y-%m")
else
    CUTOFF=$(date -u -d "${THRESHOLD_DAYS} days ago" +"%Y-%m-%dT%H:%M:%SZ")
    PERIOD=$(date -u +"%Y-%m")
fi

echo "=== GDLM Compaction ==="
echo "  Memory dir: $MEMORY_DIR"
echo "  Threshold: $THRESHOLD_DAYS days (cutoff: $CUTOFF)"
echo "  Max lines: $MAX_LINES"
echo "  Dry run: $DRY_RUN"
echo ""

compacted_total=0
promoted_total=0
deleted_total=0
summary_total=0

# --- Process each active file ---
for active_file in "$ACTIVE_DIR"/*.gdlm; do
    [[ -f "$active_file" ]] || continue
    fname=$(basename "$active_file")
    category="${fname%.gdlm}"

    # Count memory lines
    mem_count=$(grep -c "^@memory" "$active_file" 2>/dev/null || echo "0")
    mem_count=$(echo "$mem_count" | tr -d '[:space:]')
    total_lines=$(wc -l < "$active_file" | tr -d ' ')

    if [[ "$mem_count" -eq 0 ]]; then
        continue
    fi

    echo "--- Processing: $fname ($mem_count memories, $total_lines lines) ---"

    # Collect eligible records (older than cutoff)
    eligible_lines=""
    keep_lines=""
    comment_lines=""

    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Preserve comments
        if [[ "$line" == \#* ]]; then
            comment_lines="${comment_lines}${line}
"
            continue
        fi

        # Skip non-memory lines
        if [[ "$line" != @memory* ]]; then
            keep_lines="${keep_lines}${line}
"
            continue
        fi

        # Extract timestamp
        ts=$(echo "$line" | grep -o 'ts:[^|]*' | cut -d: -f2- || echo "")

        if [[ -z "$ts" ]]; then
            # No timestamp — keep in active
            keep_lines="${keep_lines}${line}
"
            continue
        fi

        # Compare timestamps (lexicographic works for ISO 8601)
        if [[ "$ts" < "$CUTOFF" ]]; then
            eligible_lines="${eligible_lines}${line}
"
        else
            keep_lines="${keep_lines}${line}
"
        fi
    done < "$active_file"

    # Volume-based trigger: if file exceeds MAX_LINES and time-based compaction
    # didn't select enough records, compact oldest records to bring under limit.
    if [[ "$total_lines" -gt "$MAX_LINES" ]]; then
        keep_count=0
        if [[ -n "$keep_lines" ]]; then
            keep_count=$(echo "$keep_lines" | grep -c "^@memory" || true)
            keep_count=${keep_count:-0}
        fi

        if [[ "$keep_count" -gt "$MAX_LINES" ]]; then
            echo "  Volume trigger: $total_lines lines > $MAX_LINES max (after time pass: $keep_count remain)"
            excess=$((keep_count - MAX_LINES))
            volume_eligible=$(echo "$keep_lines" | grep "^@memory" | head -n "$excess" || true)

            skip_ids=""
            while IFS= read -r eline; do
                [[ -z "$eline" ]] && continue
                eid=$(echo "$eline" | grep -o 'id:[^|]*' | cut -d: -f2- || true)
                skip_ids="$skip_ids|$eid|"
            done <<< "$volume_eligible"

            eligible_lines="${eligible_lines}${volume_eligible}
"
            new_keep=""
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                if [[ "$line" != @memory* ]]; then
                    new_keep="${new_keep}${line}
"
                    continue
                fi
                lid=$(echo "$line" | grep -o 'id:[^|]*' | cut -d: -f2- || true)
                case "$skip_ids" in
                    *"|$lid|"*) ;;
                    *) new_keep="${new_keep}${line}
" ;;
                esac
            done <<< "$keep_lines"
            keep_lines="$new_keep"
        fi
    fi

    # Count eligible
    eligible_count=0
    if [[ -n "$eligible_lines" ]]; then
        eligible_count=$(echo "$eligible_lines" | grep -c "^@memory" || true)
        eligible_count=${eligible_count:-0}
    fi

    if [[ "$eligible_count" -eq 0 ]]; then
        echo "  No eligible records (all newer than cutoff)"
        echo ""
        continue
    fi

    echo "  Eligible for compaction: $eligible_count"

    # --- Classify records ---
    # Separate: deletions, unresolved errors, decisions, regular observations
    deletion_lines=""
    unresolved_lines=""
    decision_lines=""
    regular_lines=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" != @memory* ]] && continue

        # Check for status:deleted
        if echo "$line" | grep -q "status:deleted"; then
            deletion_lines="${deletion_lines}${line}
"
            continue
        fi

        # Check for unresolved errors
        if echo "$line" | grep -q "type:error" && echo "$line" | grep -q "status:unresolved"; then
            unresolved_lines="${unresolved_lines}${line}
"
            continue
        fi

        # Check for decisions
        if echo "$line" | grep -q "type:decision"; then
            decision_lines="${decision_lines}${line}
"
            continue
        fi

        regular_lines="${regular_lines}${line}
"
    done <<< "$eligible_lines"

    # Count each category
    deletion_count=0
    unresolved_count=0
    decision_count=0
    regular_count=0
    [[ -n "$deletion_lines" ]] && deletion_count=$(echo "$deletion_lines" | grep -c "^@memory" || echo "0")
    [[ -n "$unresolved_lines" ]] && unresolved_count=$(echo "$unresolved_lines" | grep -c "^@memory" || echo "0")
    [[ -n "$decision_lines" ]] && decision_count=$(echo "$decision_lines" | grep -c "^@memory" || echo "0")
    [[ -n "$regular_lines" ]] && regular_count=$(echo "$regular_lines" | grep -c "^@memory" || echo "0")

    echo "  Deletions (history only): $deletion_count"
    echo "  Unresolved errors (promote): $unresolved_count"
    echo "  Decisions (preserve in summary): $decision_count"
    echo "  Regular observations: $regular_count"

    # --- Group regular records by subject ---
    subjects=""
    if [[ -n "$regular_lines" ]]; then
        subjects=$(echo "$regular_lines" | grep "^@memory" | grep -o 'subject:[^|]*' | cut -d: -f2- | sort -u)
    fi

    # Also get decision subjects
    decision_subjects=""
    if [[ -n "$decision_lines" ]]; then
        decision_subjects=$(echo "$decision_lines" | grep "^@memory" | grep -o 'subject:[^|]*' | cut -d: -f2- | sort -u)
    fi

    # --- Build summaries ---
    summaries=""
    ts_now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Summarize regular observations by subject (latest wins)
    if [[ -n "$subjects" ]]; then
        while IFS= read -r subj; do
            [[ -z "$subj" ]] && continue

            # Get all records for this subject, take the latest (last line)
            subj_records=$(echo "$regular_lines" | grep -F "subject:${subj}|" || echo "$regular_lines" | grep -F "subject:${subj}$" || true)
            subj_count=$(echo "$subj_records" | grep -c "^@memory" || echo "0")
            latest=$(echo "$subj_records" | grep "^@memory" | tail -1)

            # Extract agents and IDs for provenance
            agents=$(echo "$subj_records" | grep "^@memory" | grep -o 'agent:[^|]*' | cut -d: -f2- | sort -u | tr '\n' ',' | sed 's/,$//')
            ids=$(echo "$subj_records" | grep "^@memory" | grep -o 'id:[^|]*' | cut -d: -f2- | tr '\n' ',' | sed 's/,$//')
            latest_detail=$(echo "$latest" | grep -o 'detail:[^|]*' | cut -d: -f2-)

            summary_line="@memory|id:MC-${PERIOD}-${category}-${subj}|agent:compactor|type:summary|subject:${subj}|detail:${subj_count} observations compacted. Latest: ${latest_detail}|source:compacted|relates:${ids}|ts:${ts_now}"
            summaries="${summaries}${summary_line}
"
            summary_total=$((summary_total + 1))
        done <<< "$subjects"
    fi

    # Summarize decisions (always preserved)
    if [[ -n "$decision_subjects" ]]; then
        while IFS= read -r subj; do
            [[ -z "$subj" ]] && continue

            subj_records=$(echo "$decision_lines" | grep -F "subject:${subj}|" || echo "$decision_lines" | grep -F "subject:${subj}$" || true)
            subj_count=$(echo "$subj_records" | grep -c "^@memory" || echo "0")
            latest=$(echo "$subj_records" | grep "^@memory" | tail -1)
            ids=$(echo "$subj_records" | grep "^@memory" | grep -o 'id:[^|]*' | cut -d: -f2- | tr '\n' ',' | sed 's/,$//')
            latest_detail=$(echo "$latest" | grep -o 'detail:[^|]*' | cut -d: -f2-)

            summary_line="@memory|id:MC-${PERIOD}-${category}-${subj}|agent:compactor|type:decision-summary|subject:${subj}|detail:Decision preserved. ${subj_count} record(s). ${latest_detail}|source:compacted|relates:${ids}|ts:${ts_now}"
            summaries="${summaries}${summary_line}
"
            summary_total=$((summary_total + 1))
        done <<< "$decision_subjects"
    fi

    # --- Apply changes ---
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would write summaries to archive/$fname"
        echo "  [DRY RUN] Would move $eligible_count records to history/$PERIOD/$fname"
        echo "  [DRY RUN] Would promote $unresolved_count unresolved errors back to active"
        if [[ -n "$summaries" ]]; then
            echo "  [DRY RUN] Summaries that would be created:"
            echo "$summaries" | grep "^@memory" | while IFS= read -r s; do
                echo "    $s"
            done
        fi
    else
        # Create directories
        mkdir -p "$ARCHIVE_DIR"
        mkdir -p "$HISTORY_DIR/$PERIOD"

        # Write all eligible originals to history (temp file then move for crash safety)
        history_file="$HISTORY_DIR/$PERIOD/$fname"
        tmp_history=$(mktemp "${history_file}.XXXXXX" 2>/dev/null || mktemp /tmp/gdlm-history.XXXXXX)
        if [[ -f "$history_file" ]]; then
            cat "$history_file" > "$tmp_history"
        fi
        echo "$eligible_lines" | grep "^@memory" >> "$tmp_history" 2>/dev/null || true
        mv "$tmp_history" "$history_file"

        # Write summaries to archive (temp file then move)
        archive_file="$ARCHIVE_DIR/$fname"
        tmp_archive=$(mktemp "${archive_file}.XXXXXX" 2>/dev/null || mktemp /tmp/gdlm-archive.XXXXXX)
        if [[ -f "$archive_file" ]]; then
            cat "$archive_file" > "$tmp_archive"
        fi
        if [[ -n "$summaries" ]]; then
            echo "$summaries" | grep "^@memory" >> "$tmp_archive" 2>/dev/null || true
        fi
        mv "$tmp_archive" "$archive_file"

        # Rebuild active file: comments + kept records + promoted unresolved errors
        tmp_active=$(mktemp "${active_file}.XXXXXX" 2>/dev/null || mktemp /tmp/gdlm-active.XXXXXX)
        # Write comments first
        if [[ -n "$comment_lines" ]]; then
            printf "%s" "$comment_lines" > "$tmp_active"
        else
            : > "$tmp_active"
        fi
        # Write kept records
        if [[ -n "$keep_lines" ]]; then
            echo "$keep_lines" | grep "^@" >> "$tmp_active" 2>/dev/null || true
        fi
        # Promote unresolved errors back to active
        if [[ -n "$unresolved_lines" ]]; then
            echo "$unresolved_lines" | grep "^@memory" >> "$tmp_active" 2>/dev/null || true
        fi
        mv "$tmp_active" "$active_file"
    fi

    compacted_total=$((compacted_total + eligible_count))
    promoted_total=$((promoted_total + unresolved_count))
    deleted_total=$((deleted_total + deletion_count))

    echo ""
done

# --- Summary ---
echo "=== Compaction complete ==="
echo "  Records compacted: $compacted_total"
echo "  Summaries created: $summary_total"
echo "  Unresolved errors promoted: $promoted_total"
echo "  Deletions archived: $deleted_total"
echo "  Dry run: $DRY_RUN"
