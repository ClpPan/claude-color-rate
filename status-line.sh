#!/bin/bash

# Status line: model name, context window usage (with progress bar), session cost

data=$(cat)

# Fallback if jq is not installed
if ! command -v jq &>/dev/null; then
    printf 'Claude Code | jq not installed\n'
    exit 0
fi

# Color codes
BLUE='\033[34m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

# --- Helper functions ---

# Calculate pace-based color and format rate limit info
# Args: used_pct, resets_at (unix timestamp), period (seconds), label (e.g., "5h", "7d")
# Returns: formatted string with color and time remaining
calc_rate_info() {
    local used_pct=$1 resets_at=$2 period=$3 label=$4

    if [ -z "$used_pct" ] || [ "$used_pct" = "null" ]; then
        printf '%s: %%s\n' "$label" "-"
        return
    fi

    local pct_int=$(printf "%.0f" "$used_pct" 2>/dev/null || echo "0")

    if [ -n "$resets_at" ] && [ "$resets_at" != "null" ]; then
        local now=$(date +%s)
        local diff=$(( resets_at - now ))
        local time_elapsed=$(( period - diff ))
        local color rate_info_str reset_fmt

        if [ "$time_elapsed" -le 0 ]; then
            # Just reset: use absolute fallback
            color=$([ "$pct_int" -lt 20 ] && echo "$BLUE" || echo "$YELLOW")
        else
            # Pace-based color calculation
            local expected=$(awk -v e="$time_elapsed" -v p="$period" 'BEGIN { printf "%.0f", (e/p)*100 }')
            local warn=$(awk -v e="$expected" 'BEGIN { printf "%.0f", e*1.5 }')

            if [ "$pct_int" -le "$expected" ]; then
                color="$BLUE"
            elif [ "$pct_int" -le "$warn" ]; then
                color="$YELLOW"
            else
                color="$RED"
            fi
        fi

        # Format time remaining
        if [ "$diff" -le 0 ]; then
            reset_fmt="now"
        elif [ "$period" -eq 604800 ]; then
            # 7-day format: Xd Xh
            local d=$(( diff / 86400 ))
            local h=$(( (diff % 86400) / 3600 ))
            if [ "$d" -gt 0 ]; then
                reset_fmt="${d}d${h}h"
            else
                local m=$(( (diff % 3600) / 60 ))
                reset_fmt="${h}h${m}m"
            fi
        else
            # 5-hour format: Xh Xm
            local h=$(( diff / 3600 ))
            local m=$(( (diff % 3600) / 60 ))
            reset_fmt="${h}h${m}m"
        fi

        printf '%b%s: %d%% (↺%s)%b' "$color" "$label" "$pct_int" "$reset_fmt" "$RESET"
    else
        # No resets_at: fallback to absolute threshold
        local color=$([ "$pct_int" -gt 80 ] && echo "$RED" || echo "$BLUE")
        printf '%b%s: %d%%%b' "$color" "$label" "$pct_int" "$RESET"
    fi
}

# --- Parse all JSON fields in a single jq call (performance optimization) ---
IFS=$'\t' read -r model max_ctx used_pct rate_pct rate_resets week_pct week_resets <<< \
  "$(echo "$data" | jq -r '[
    .model.display_name // .model.id // "Unknown Model",
    .context_window.context_window_size // 200000,
    .context_window.used_percentage // "",
    .rate_limits.five_hour.used_percentage // "",
    .rate_limits.five_hour.resets_at // "",
    .rate_limits.seven_day.used_percentage // "",
    .rate_limits.seven_day.resets_at // ""
  ] | @tsv')"

if [ -z "$used_pct" ] || [ "$used_pct" = "null" ]; then
    context_info="○○○○○○○○○○ --"
else
    pct=$(printf "%.0f" "$used_pct" 2>/dev/null || echo "0")
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    used_k=$(( max_ctx * pct / 100 / 1000 ))
    max_k=$(( max_ctx / 1000 ))

    bar=""
    filled=$(( pct / 10 ))

    if [ "$pct" -gt 60 ]; then
        COLOR="$RED"
    else
        COLOR="$BLUE"
    fi

    for i in 0 1 2 3 4 5 6 7 8 9; do
        if [ "$i" -lt "$filled" ]; then
            bar="${bar}${COLOR}●${RESET}"
        else
            bar="${bar}○"
        fi
    done

    context_info="${bar} ${used_k}k/${max_k}k (${pct}%)"
fi

# --- Rate limit (Pro plan: 5-hour window) ---
# rate_pct and rate_resets already parsed from jq above
rate_info=$(calc_rate_info "$rate_pct" "$rate_resets" 18000 "5h")

# --- 7-day rate limit ---
# week_pct and week_resets already parsed from jq above
week_info=$(calc_rate_info "$week_pct" "$week_resets" 604800 "7d")

# --- History logging ---
_log_file="${HOME}/.claude/usage-history.log"
_log_dir=$(dirname "$_log_file")

if [ ! -d "$_log_dir" ]; then
    mkdir -p "$_log_dir" 2>/dev/null || true
fi

if [ -d "$_log_dir" ] && [ -w "$_log_dir" ]; then
    _ts=$(date +"%Y-%m-%dT%H:%M:%S%z")
    _ctx_pct="${pct:---}"
    _ctx_usage="${used_k:---}k/${max_k:---}k"
    _rate="${rate_pct_int:---}"
    _week="${week_pct_int:---}"

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$_ts" "$model" "$_ctx_pct" "$_ctx_usage" "$_rate" "$_week" \
        >> "$_log_file" 2>/dev/null || true
fi

# --- Output ---
printf '%b\n' "${model} | ${context_info}"
printf '%b\n' "${rate_info} | ${week_info}"

# DEBUG: dump raw JSON (remove after inspection)
# echo "$data" > /tmp/statusline-debug.json
