#!/bin/bash

# Status line: model name, context window usage (with progress bar), session cost

data=$(cat)

# Fallback if jq is not installed
if ! command -v jq &>/dev/null; then
    printf 'Claude Code | jq not installed\n'
    exit 0
fi

# --- Model ---
model=$(echo "$data" | jq -r '.model.display_name // .model.id // "Unknown Model"')

# --- Context window ---
max_ctx=$(echo "$data" | jq -r '.context_window.context_window_size // 200000')
used_pct=$(echo "$data" | jq -r '.context_window.used_percentage // empty')

# Color codes
BLUE='\033[34m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

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
rate_pct=$(echo "$data" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rate_resets=$(echo "$data" | jq -r '.rate_limits.five_hour.resets_at // empty')

if [ -z "$rate_pct" ] || [ "$rate_pct" = "null" ]; then
    rate_info="5h: --%"
else
    rate_pct_int=$(printf "%.0f" "$rate_pct" 2>/dev/null || echo "0")
    if [ -n "$rate_resets" ] && [ "$rate_resets" != "null" ]; then
        now=$(date +%s)
        diff=$(( rate_resets - now ))
        # Pace-based color
        PERIOD_5H=18000
        time_elapsed=$(( PERIOD_5H - diff ))
        if [ "$time_elapsed" -le 0 ]; then
            # Just reset: use absolute fallback
            [ "$rate_pct_int" -lt 20 ] && RATE_COLOR="$BLUE" || RATE_COLOR="$YELLOW"
        else
            expected=$(awk -v e="$time_elapsed" -v p="$PERIOD_5H" 'BEGIN { printf "%.0f", (e/p)*100 }')
            warn=$(awk -v e="$expected" 'BEGIN { printf "%.0f", e*1.5 }')
            if [ "$rate_pct_int" -le "$expected" ]; then
                RATE_COLOR="$BLUE"
            elif [ "$rate_pct_int" -le "$warn" ]; then
                RATE_COLOR="$YELLOW"
            else
                RATE_COLOR="$RED"
            fi
        fi
        if [ "$diff" -le 0 ]; then
            rate_reset_fmt="now"
        else
            h=$(( diff / 3600 ))
            m=$(( (diff % 3600) / 60 ))
            rate_reset_fmt="${h}h${m}m"
        fi
        rate_info="${RATE_COLOR}5h: ${rate_pct_int}% (↺${rate_reset_fmt})${RESET}"
    else
        # No resets_at: fallback to absolute threshold
        [ "$rate_pct_int" -gt 80 ] && RATE_COLOR="$RED" || RATE_COLOR="$BLUE"
        rate_info="${RATE_COLOR}5h: ${rate_pct_int}%${RESET}"
    fi
fi

# --- 7-day rate limit ---
week_pct=$(echo "$data" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_resets=$(echo "$data" | jq -r '.rate_limits.seven_day.resets_at // empty')

if [ -z "$week_pct" ] || [ "$week_pct" = "null" ]; then
    week_info="7d: --%"
else
    week_pct_int=$(printf "%.0f" "$week_pct" 2>/dev/null || echo "0")
    if [ -n "$week_resets" ] && [ "$week_resets" != "null" ]; then
        now=$(date +%s)
        diff=$(( week_resets - now ))
        # Pace-based color
        PERIOD_7D=604800
        time_elapsed=$(( PERIOD_7D - diff ))
        if [ "$time_elapsed" -le 0 ]; then
            # Just reset: use absolute fallback
            [ "$week_pct_int" -lt 20 ] && WEEK_COLOR="$BLUE" || WEEK_COLOR="$YELLOW"
        else
            expected=$(awk -v e="$time_elapsed" -v p="$PERIOD_7D" 'BEGIN { printf "%.0f", (e/p)*100 }')
            warn=$(awk -v e="$expected" 'BEGIN { printf "%.0f", e*1.5 }')
            if [ "$week_pct_int" -le "$expected" ]; then
                WEEK_COLOR="$BLUE"
            elif [ "$week_pct_int" -le "$warn" ]; then
                WEEK_COLOR="$YELLOW"
            else
                WEEK_COLOR="$RED"
            fi
        fi
        if [ "$diff" -le 0 ]; then
            week_reset_fmt="now"
        else
            d=$(( diff / 86400 ))
            h=$(( (diff % 86400) / 3600 ))
            m=$(( (diff % 3600) / 60 ))
            if [ "$d" -gt 0 ]; then
                week_reset_fmt="${d}d${h}h"
            else
                week_reset_fmt="${h}h${m}m"
            fi
        fi
        week_info="${WEEK_COLOR}7d: ${week_pct_int}% (↺${week_reset_fmt})${RESET}"
    else
        # No resets_at: fallback to absolute threshold
        [ "$week_pct_int" -gt 80 ] && WEEK_COLOR="$RED" || WEEK_COLOR="$BLUE"
        week_info="${WEEK_COLOR}7d: ${week_pct_int}%${RESET}"
    fi
fi

# --- Output ---
printf '%b\n' "${model} | ${context_info}"
printf '%b\n' "${rate_info} | ${week_info}"

# DEBUG: dump raw JSON (remove after inspection)
# echo "$data" > /tmp/statusline-debug.json
