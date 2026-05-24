#!/bin/bash
# post-toutiao.sh — 头条号文章发布
#
# 基于 @openclaw-cn/toutiao-ops 的浏览器自动化发布。
# 支持 Markdown 富文本排版、封面图、头条首发、合集。
#
# 用法: post-toutiao.sh <title> <content_file> [cover]
#   title        — 文章标题（2-30 字）
#   content_file — Markdown 文件路径
#   cover        — 封面图片路径（可选，建议提供）
#
# 环境变量:
#   TOUTIAO_ACCOUNT     — 头条号账号名（默认 default）
#   TOUTIAO_HEADLESS    — 设为 false 可观察浏览器操作（默认 true）
#
# Exit codes:
#   0 — 发布成功
#   1 — toutiao-ops 未安装
#   2 — 头条号未登录
#   3 — 发布失败
#   4 — 参数错误

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ─── 参数 ───────────────────────────────────────────────────────
TITLE="${1:-}"
CONTENT_FILE="${2:-}"
COVER="${3:-}"

ACCOUNT="${TOUTIAO_ACCOUNT:-default}"
HEADLESS="${TOUTIAO_HEADLESS:-true}"

if [ -z "$TITLE" ] || [ -z "$CONTENT_FILE" ]; then
    log_error "用法: post-toutiao.sh <title> <content_file> [cover]"
    exit 4
fi

if [ ! -f "$CONTENT_FILE" ]; then
    log_error "内容文件不存在: ${CONTENT_FILE}"
    exit 4
fi

if [ -n "$COVER" ] && [ ! -f "$COVER" ]; then
    log_warn "封面文件不存在: ${COVER}，使用占位封面"
    COVER=""
fi

# ─── 封面兜底 ──────────────────────────────────────────────────
# toutiao-ops 要求 --cover 为必填。未提供封面时生成临时占位图。
if [ -z "$COVER" ]; then
    COVER="/tmp/toutiao-cover-$$.png"
    python3 2>/dev/null << PYEOF
import struct, zlib
w, h = 1200, 630
def chunk(t, d):
    c = t + d
    return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
with open('${COVER}', 'wb') as f:
    f.write(b'\x89PNG\r\n\x1a\n')
    f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)))
    f.write(chunk(b'IDAT', zlib.compress(b'\x07\xc1\x60' * w * h)))
    f.write(chunk(b'IEND', b''))
PYEOF
    log_info "已生成占位封面: ${COVER}"
fi

# ─── 检查 toutiao-ops ──────────────────────────────────────────
if ! command -v toutiao-ops &>/dev/null; then
    log_error "toutiao-ops 未安装。请运行: npm install -g @openclaw-cn/toutiao-ops"
    exit 1
fi

# ─── 检查登录状态 ──────────────────────────────────────────────
log_info "检查头条号登录状态..."
AUTH_CHECK=$(toutiao-ops auth check --account "$ACCOUNT" 2>&1) || {
    log_warn "头条号未登录，请先运行: toutiao-ops auth login"
    exit 2
}

# ─── 发布 ───────────────────────────────────────────────────────
log_info "发布文章到头条号..."

TTOUTIAO_OPTS=(
    --title "$TITLE"
    --content-file "$CONTENT_FILE"
    --account "$ACCOUNT"
)

[ -n "$COVER" ] && TTOUTIAO_OPTS+=(--cover "$COVER")
[ "$HEADLESS" = "true" ] && TTOUTIAO_OPTS+=(--headless)

# 默认行为：不同步微头条
TTOUTIAO_OPTS+=(--no-weitoutiao)

OUTPUT=$(toutiao-ops publish article "${TTOUTIAO_OPTS[@]}" 2>&1) || {
    exit_code=$?
    log_error "头条发布失败 (exit: ${exit_code})"
    echo "$OUTPUT" | while IFS= read -r line; do log_error "  ${line}"; done
    exit 3
}

# ─── 解析结果 ───────────────────────────────────────────────────
RESULT_URL=$(echo "$OUTPUT" | python3 -c "
import sys, json
try:
    text = sys.stdin.read()
    data = json.loads(text)
    url = data.get('url', '')
    print(url)
except Exception:
    # fallback: 取最后一行 stdout
    lines = [l.strip() for l in sys.stdin.read().splitlines() if l.strip()]
    print(lines[-1] if lines else '')
" 2>/dev/null)

log_info "头条发布成功"
if [ -n "$RESULT_URL" ]; then
    echo "url: ${RESULT_URL}"
fi

exit 0
