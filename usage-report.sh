#!/bin/bash
# usage-report.sh — 查看 Claude 用量歷史記錄
# 用法：
#   ./usage-report.sh              # 顯示最近 20 筆
#   ./usage-report.sh -n 50        # 顯示最近 50 筆
#   ./usage-report.sh -d 2026-04   # 篩選指定月份（前綴匹配）
#   ./usage-report.sh -s rate5     # 按 5h rate limit 降序排序
#   ./usage-report.sh -s rate7     # 按 7d rate limit 降序排序
#   ./usage-report.sh -s ctx       # 按 context 用量降序排序
#   ./usage-report.sh --stats      # 顯示統計摘要
#   ./usage-report.sh --help

LOG_FILE="${HOME}/.claude/usage-history.log"

show_help() {
    cat <<'EOF'
usage-report.sh — Claude 用量歷史查看工具

選項：
  -n <N>        顯示最近 N 筆記錄（預設 20）
  -d <prefix>   按日期前綴篩選，例如 -d 2026-04-04 或 -d 2026-04
  -s <field>    排序欄位：rate5 | rate7 | ctx（降序）
  --stats       顯示整體統計摘要
  --help        顯示此說明

TSV 欄位順序：
  timestamp  model  ctx_pct  ctx_usage  rate_5h_pct  rate_7d_pct
EOF
}

# 檢查日誌文件
check_log() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "找不到日誌文件：$LOG_FILE" >&2
        echo "請先執行一次 status-line.sh 以建立日誌。" >&2
        exit 1
    fi
    if [ ! -s "$LOG_FILE" ]; then
        echo "日誌文件是空的：$LOG_FILE" >&2
        exit 1
    fi
}

# 格式化輸出（含標題列）
print_header() {
    printf '%-25s %-30s %6s  %-12s %6s %6s\n' \
        "TIMESTAMP" "MODEL" "CTX%" "CTX_USAGE" "RATE5h" "RATE7d"
    printf '%s\n' "$(printf '%.0s-' {1..90})"
}

print_rows() {
    # 從 stdin 讀取 TSV，格式化輸出
    while IFS=$'\t' read -r ts model ctx_pct ctx_usage rate5 rate7; do
        printf '%-25s %-30s %6s  %-12s %6s %6s\n' \
            "$ts" "$model" "$ctx_pct" "$ctx_usage" "$rate5" "$rate7"
    done
}

print_header_inline() {
    print_header
    cat
}

show_stats() {
    check_log
    echo "=== 統計摘要 ==="
    echo "日誌路徑：$LOG_FILE"
    echo "總記錄筆數：$(wc -l < "$LOG_FILE")"
    echo ""

    # 最早與最新記錄
    echo "最早記錄：$(head -1 "$LOG_FILE" | cut -f1)"
    echo "最新記錄：$(tail -1 "$LOG_FILE" | cut -f1)"
    echo ""

    # 各模型出現次數
    echo "=== 模型使用統計 ==="
    cut -f2 "$LOG_FILE" | sort | uniq -c | sort -rn | \
        awk '{printf "  %-5s %s\n", $1, $2}'
    echo ""

    # rate_5h_pct 最高的 5 筆（排除 -- 欄位）
    echo "=== 5h Rate Limit 最高的 5 筆 ==="
    {
        awk -F'\t' '$5 ~ /^[0-9]+$/ {print $5"\t"$0}' "$LOG_FILE" | \
            sort -t$'\t' -k1 -rn | head -5 | cut -f2- | \
            print_header_inline | print_rows
    } 2>/dev/null || echo "(無數據)"
    echo ""

    # context 用量最高的 5 筆
    echo "=== Context 用量最高的 5 筆 ==="
    {
        awk -F'\t' '$3 ~ /^[0-9]+$/ {print $3"\t"$0}' "$LOG_FILE" | \
            sort -t$'\t' -k1 -rn | head -5 | cut -f2- | \
            print_header_inline | print_rows
    } 2>/dev/null || echo "(無數據)"
}

# 主邏輯
N=20
DATE_FILTER=""
SORT_FIELD=""
STATS=false

while [ $# -gt 0 ]; do
    case "$1" in
        -n)       N="$2"; shift 2 ;;
        -d)       DATE_FILTER="$2"; shift 2 ;;
        -s)       SORT_FIELD="$2"; shift 2 ;;
        --stats)  STATS=true; shift ;;
        --help)   show_help; exit 0 ;;
        *)        echo "未知選項：$1" >&2; show_help; exit 1 ;;
    esac
done

if $STATS; then
    show_stats
    exit 0
fi

check_log

# 決定排序欄位（awk 欄位索引：$1=ts $2=model $3=ctx $4=ctx_usage $5=rate5 $6=rate7）
case "$SORT_FIELD" in
    rate5) SORT_COL=5 ;;
    rate7) SORT_COL=6 ;;
    ctx)   SORT_COL=3 ;;
    "")    SORT_COL="" ;;  # 不排序，保持原始順序（按時間）
    *)     echo "未知排序欄位：$SORT_FIELD（可選：rate5, rate7, ctx）" >&2; exit 1 ;;
esac

# 建立處理管道
{
    if [ -n "$DATE_FILTER" ]; then
        grep "^${DATE_FILTER}" "$LOG_FILE"
    else
        cat "$LOG_FILE"
    fi
} | {
    if [ -n "$SORT_COL" ]; then
        # 排序前過濾掉該欄位為 -- 的行，並降序排列
        awk -F'\t' -v col="$SORT_COL" '$col ~ /^[0-9]+$/' | \
            sort -t$'\t' -k"${SORT_COL}" -rn
    else
        cat
    fi
} | tail -n "$N" | {
    print_header
    print_rows
}
