#!/bin/bash
# health-check.sh — HTTP HEAD 二次探活
#
# 对分发出的文章 URL 发起 HEAD 请求，验证可访问性
#
# 用法: health-check.sh <url> [timeout]
#   url     — 文章 URL
#   timeout — 超时秒数（默认 10）
#
# Exit codes:
#   0 — 200 OK
#   1 — 404/500 等异常
#   2 — 超时/网络错误
#   3 — 跳过

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

URL="${1:-}"
TIMEOUT="${2:-10}"

if [ -z "$URL" ] || [ "$URL" = "草稿箱" ] || [ "$URL" = "skip" ]; then
    log_info "跳过探活（草稿箱或无公开 URL）"
    exit 3
fi

log_info "正在检测: $URL"

sleep 2

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --head -L \
    --max-time "$TIMEOUT" \
    --user-agent "Mozilla/5.0" \
    "$URL" 2>/dev/null) || {
    log_warn "探活请求超时或网络错误"
    exit 2
}

case "$HTTP_CODE" in
    200|201|202)
        log_info "链接正常 (HTTP $HTTP_CODE)"
        exit 0
        ;;
    301|302)
        REDIRECT_URL=$(curl -s -o /dev/null -w "%{redirect_url}" -L --max-time "$TIMEOUT" "$URL" 2>/dev/null)
        log_info "链接已跳转 → $REDIRECT_URL"
        exit 0
        ;;
    404|410)
        log_warn "链接不可访问 (HTTP $HTTP_CODE)，页面不存在"
        exit 1
        ;;
    500|502|503)
        log_warn "服务端异常 (HTTP $HTTP_CODE)，可能审核中"
        exit 1
        ;;
    *)
        log_warn "未知状态码 (HTTP $HTTP_CODE)"
        exit 1
        ;;
esac
