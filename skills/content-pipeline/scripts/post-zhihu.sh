#!/bin/bash
# post-zhihu.sh — 发布文章到知乎
#
# 使用 Playwright 浏览器自动化操作知乎编辑器。
# 需要先运行 login-zhihu.sh 扫码登录。
#
# 用法: post-zhihu.sh <title> <content_file> [headless]
#   title        — 文章标题
#   content_file — Markdown 文件路径
#   headless     — 无头模式（默认 true，设为 false 可观察浏览器操作）
#
# 环境变量:
#   ZHIHU_HEADLESS — 无头模式（默认 true）
#
# Exit codes:
#   0 — 发布成功
#   1 — toutiao-ops 未安装
#   2 — 登录 session 无效
#   3 — 发布失败
#   4 — 参数错误

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ─── 参数 ───────────────────────────────────────────────────────
TITLE="${1:-}"
CONTENT_FILE="${2:-}"
HEADLESS="${3:-${ZHIHU_HEADLESS:-true}}"

if [ -z "$TITLE" ] || [ -z "$CONTENT_FILE" ]; then
    log_error "用法: post-zhihu.sh <title> <content_file> [headless]"
    exit 4
fi

if [ ! -f "$CONTENT_FILE" ]; then
    log_error "内容文件不存在: ${CONTENT_FILE}"
    exit 4
fi

if [ ! -s "$CONTENT_FILE" ]; then
    log_error "内容文件为空: ${CONTENT_FILE}"
    exit 4
fi

# ─── 检查 toutiao-ops ──────────────────────────────────────────
if ! command -v toutiao-ops &>/dev/null; then
    log_error "toutiao-ops 未安装。请运行: npm install -g @openclaw-cn/toutiao-ops"
    exit 1
fi

# ─── 检查 session ──────────────────────────────────────────────
log_info "检查知乎登录状态..."
if ! node "$SCRIPT_DIR/lib/zhihu-session.cjs" get-cookies &>/dev/null; then
    log_error "知乎 session 无效，请先运行: ./scripts/login-zhihu.sh"
    exit 2
fi
log_info "Session 有效"

# ─── 发布 ───────────────────────────────────────────────────────
log_info "发布文章到知乎..."
log_info "标题: ${TITLE}"

OUTPUT=$(node "$SCRIPT_DIR/lib/zhihu-session.cjs" publish "$TITLE" "$CONTENT_FILE" "$HEADLESS" 2>&1) || {
    exit_code=$?
    log_error "知乎发布失败 (exit: ${exit_code})"
    echo "$OUTPUT" | while IFS= read -r line; do log_error "  ${line}"; done
    exit 3
}

# ─── 解析结果 ───────────────────────────────────────────────────
RESULT_URL=$(echo "$OUTPUT" | tail -1)

if [ -n "$RESULT_URL" ]; then
    log_info "知乎发布成功: ${RESULT_URL}"
    echo "$RESULT_URL"
else
    log_warn "发布完成，但未获取到文章 URL"
fi

exit 0
