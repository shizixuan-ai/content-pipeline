#!/bin/bash
# post-juejin.sh — 发布文章到稀土掘金
#
# 两步流程: 创建草稿 → 发布草稿
# 认证方式: Cookie（环境变量 JUEJIN_COOKIE，完整 Cookie 串）
#
# 用法: post-juejin.sh <title> <content_file> <category_id> <tag_ids>
#   title        — 文章标题
#   content_file — Markdown 文件路径
#   category_id  — 分类 ID（字符串，如 "6809637769959178254"=后端）
#   tag_ids      — 标签 ID，逗号分隔（如 "6809640364677267469,6809640408797167623"）
#
# Exit codes:
#   0 — 发布成功
#   1 — 认证失败（cookie 无效）
#   2 — API 限流
#   3 — 网络错误 / API 错误
#   4 — 参数错误

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ─── 参数校验 ────────────────────────────────────────────────
if [ $# -lt 4 ]; then
    log_error "用法: post-juejin.sh <title> <content_file> <category_id> <tag_ids>"
    exit 4
fi

TITLE="$1"
CONTENT_FILE="$2"
CATEGORY_ID="$3"
TAG_IDS="$4"
COOKIE="${JUEJIN_COOKIE:-}"

if [ ! -f "$CONTENT_FILE" ]; then
    log_error "内容文件不存在: $CONTENT_FILE"
    exit 4
fi

if [ -z "$COOKIE" ]; then
    log_error "JUEJIN_COOKIE 环境变量未设置"
    exit 1
fi

# ─── 读取内容并生成摘要 ──────────────────────────────────────
CONTENT=$(cat "$CONTENT_FILE")

# 用 Python 生成 brief（纯文本前 100 字）和构造 JSON
JSON_DATA=$(python3 -c "
import sys, json

title = sys.argv[1]
content = sys.argv[2]
category_id = sys.argv[3]
tag_ids_str = sys.argv[4]

# 解析 tag_ids
tag_ids = [t.strip() for t in tag_ids_str.split(',') if t.strip()]

# 生成摘要：去除 markdown 标记，取前 100 字
plain = content
import re
plain = re.sub(r'\`\`\`[\s\S]*?\`\`\`', '', plain)
plain = re.sub(r'[#*>\`\[\]]', '', plain)
plain = re.sub(r'\s+', ' ', plain).strip()
brief = plain[:100] if len(plain) > 100 else plain

payload = {
    'category_id': category_id,
    'tag_ids': tag_ids,
    'link_url': '',
    'cover_image': '',
    'title': title,
    'brief_content': brief,
    'edit_type': 10,
    'html_content': 'deprecated',
    'mark_content': content,
    'theme_ids': [],
    'column_ids': [],
}

# 检查字段长度限制
if len(title) > 80:
    print('[WARN] 标题超过 80 字，掘金可能截断', file=sys.stderr)

print(json.dumps(payload))
" "$TITLE" "$CONTENT" "$CATEGORY_ID" "$TAG_IDS" 2>/dev/null)

# ─── 通用请求头 ─────────────────────────────────────────────
CURL_HEADERS=(
    -H "Content-Type: application/json; charset=utf-8"
    -H "Cookie: ${COOKIE}"
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    -H "Referer: https://juejin.cn/"
    -H "Origin: https://juejin.cn"
    --max-time 30
)

# ─── Step 1: 创建草稿 ──────────────────────────────────────
log_info "创建草稿: $TITLE"

DRAFT_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "https://juejin.cn/content_api/v1/article_draft/create" \
    "${CURL_HEADERS[@]}" \
    -d "$JSON_DATA" 2>/dev/null) || {
    log_error "网络请求失败（创建草稿）"
    exit 3
}

DRAFT_HTTP_CODE=$(echo "$DRAFT_RESPONSE" | tail -1)
DRAFT_BODY=$(echo "$DRAFT_RESPONSE" | sed '$d')

# 解析 draft_id
DRAFT_ID=$(echo "$DRAFT_BODY" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('err_no') == 0:
        print(data['data']['id'])
    else:
        print(f'ERROR: {data.get(\"err_msg\", \"未知错误\")}', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: 解析响应失败: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || {
    log_error "创建草稿失败"
    echo "$DRAFT_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"  err_no={d.get('err_no')}, err_msg={d.get('err_msg')}\")" 2>/dev/null || true
    case "$DRAFT_HTTP_CODE" in
        429|403) exit 2 ;;
        401|402) exit 1 ;;
        *) exit 3 ;;
    esac
}

log_info "草稿创建成功，draft_id: $DRAFT_ID"

# ─── Step 2: 发布草稿 ──────────────────────────────────────
log_info "发布草稿..."

PUBLISH_DATA=$(python3 -c "
import json
print(json.dumps({
    'draft_id': '$DRAFT_ID',
    'sync_to_org': False,
    'column_ids': [],
    'theme_ids': [],
}))
")

PUBLISH_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "https://juejin.cn/content_api/v1/article/publish" \
    "${CURL_HEADERS[@]}" \
    -d "$PUBLISH_DATA" 2>/dev/null) || {
    log_error "网络请求失败（发布草稿）"
    exit 3
}

PUBLISH_HTTP_CODE=$(echo "$PUBLISH_RESPONSE" | tail -1)
PUBLISH_BODY=$(echo "$PUBLISH_RESPONSE" | sed '$d')

# 解析 article_id
ARTICLE_ID=$(echo "$PUBLISH_BODY" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('err_no') == 0:
        print(data['data']['article_id'])
    else:
        print(f'ERROR: {data.get(\"err_msg\", \"未知错误\")}', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: 解析响应失败: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || {
    log_warn "草稿已创建但发布失败，请在掘金编辑器中手动发布"
    echo "草稿地址: https://juejin.cn/editor/drafts/$DRAFT_ID"
    exit 3
}

ARTICLE_URL="https://juejin.cn/post/$ARTICLE_ID"
log_info "掘金发布成功: $ARTICLE_URL"
echo "$ARTICLE_URL"
exit 0
