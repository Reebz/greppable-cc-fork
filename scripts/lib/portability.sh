#!/usr/bin/env bash
# Portable comm wrapper — avoids process substitution for Git Bash compatibility.
# Usage: _gdl_comm_sorted <comm-flag> <string1> <string2>
#   comm-flag: -12, -23, -13, etc.
_gdl_comm_sorted() {
    local flag="$1" s1="$2" s2="$3"
    local tmp1 tmp2
    tmp1=$(mktemp) tmp2=$(mktemp)
    echo "$s1" | sort > "$tmp1"
    echo "$s2" | sort > "$tmp2"
    comm "$flag" "$tmp1" "$tmp2"
    rm -f "$tmp1" "$tmp2"
}
