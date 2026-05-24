#!/bin/bash
# post-jianshu.sh — 发布文章到简书
#
# 四步流程:
#   1. GET /author/notebooks → notebook_id
#   2. POST /author/notes → note_id
#   3. PUT /author/notes/{note_id} → 填充内容
#   4. POST /author/notes/{note_id}/publicize → 发布
#
# 用法: post-jianshu.sh <title> <content_file>
#
# Exit codes:
#   0 — 发布成功
#   1 — 认证失败（Cookie 无效）
#   2 — API 错误
#   3 — 网络错误
#   4 — 参数错误

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ─── 参数校验 ────────────────────────────────────────────────
if [ $# -lt 2 ]; then
    log_error "用法: post-jianshu.sh <title> <content_file>"
    exit 4
fi

TITLE="$1"
CONTENT_FILE="$2"
COOKIE="${JIANSHU_COOKIE:-}"

if [ ! -f "$CONTENT_FILE" ]; then
    log_error "内容文件不存在: $CONTENT_FILE"
    exit 4
fi

if [ -z "$COOKIE" ]; then
    log_error "JIANSHU_COOKIE 环境变量未设置"
    exit 1
fi

# ─── 检查内容非空 ───────────────────────────────────────────
if [ ! -s "$CONTENT_FILE" ]; then
    log_error "内容文件为空: $CONTENT_FILE"
    exit 4
fi

# ─── Cookie Jar（自动续期） ──────────────────────────────────
COOKIE_JAR=$(mktemp /tmp/jianshu_cookie_jar_XXXXXX)
trap 'rm -f "$COOKIE_JAR"' EXIT
python3 -c "
import sys
pairs = sys.argv[1].split(';')
for p in pairs:
    p = p.strip()
    if '=' in p:
        n, v = p.split('=', 1)
        # Netscape format: domain TAB flag TAB path TAB secure TAB expiry TAB name TAB value
        print(f'www.jianshu.com\tFALSE\t/\tFALSE\t0\t{n}\t{v}')
" "$COOKIE" > "$COOKIE_JAR"

# ─── 通用请求头 ─────────────────────────────────────────────
CURL_HEADERS=(
    -b "$COOKIE_JAR"
    -c "$COOKIE_JAR"
    -H "Content-Type: application/json; charset=utf-8"
    -H "accept: application/json"
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    -H "Referer: https://www.jianshu.com/writer"
    -H "Origin: https://www.jianshu.com"
    --max-time 30
)

# ─── Step 1: 获取作品集（notebook）─────────────────────────
log_info "Step 1/4: 获取作品集..."

NOTEBOOK_RESPONSE=$(curl -s \
    "${CURL_HEADERS[@]}" \
    "https://www.jianshu.com/author/notebooks" 2>/dev/null) || {
    log_error "网络请求失败（获取作品集）"
    exit 3
}

NOTEBOOK_ID=$(echo "$NOTEBOOK_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) > 0:
        print(data[0]['id'])
    else:
        print('ERROR: 无可用作品集', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || {
    log_error "获取作品集失败"
    exit 2
}

log_info "作品集 ID: $NOTEBOOK_ID"

# ─── Step 2: 创建空笔记 ──────────────────────────────────
log_info "Step 2/4: 创建笔记..."

CREATE_PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'title': sys.argv[1],
    'notebook_id': int(sys.argv[2]),
    'at_bottom': True
}))
" "$TITLE" "$NOTEBOOK_ID")

CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "https://www.jianshu.com/author/notes" \
    "${CURL_HEADERS[@]}" \
    -d "$CREATE_PAYLOAD" 2>/dev/null) || {
    log_error "网络请求失败（创建笔记）"
    exit 3
}

CREATE_HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -1)
CREATE_BODY=$(echo "$CREATE_RESPONSE" | sed '$d')

NOTE_ID=$(echo "$CREATE_BODY" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, dict) and 'id' in data:
        print(data['id'])
    else:
        print('ERROR: 创建笔记失败', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || {
    log_error "创建笔记失败 (HTTP $CREATE_HTTP_CODE)"
    echo "$CREATE_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  resp={d}')" 2>/dev/null || true
    exit 2
}

NOTE_SLUG=$(echo "$CREATE_BODY" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('slug', ''))
" 2>/dev/null || echo "")

log_info "笔记 ID: $NOTE_ID"

# ─── Step 3: 填充笔记内容 ─────────────────────────────────
log_info "Step 3/4: 填充内容..."

UPDATE_PAYLOAD=$(python3 -c "
import json, sys
with open(sys.argv[2], 'r', encoding='utf-8') as f:
    content = f.read()
print(json.dumps({
    'id': int(sys.argv[1]),
    'title': sys.argv[3],
    'content': content,
    'autosave_control': 1
}))
" "$NOTE_ID" "$CONTENT_FILE" "$TITLE")

UPDATE_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X PUT "https://www.jianshu.com/author/notes/${NOTE_ID}" \
    "${CURL_HEADERS[@]}" \
    -d "$UPDATE_PAYLOAD" 2>/dev/null) || {
    log_error "网络请求失败（填充内容）"
    exit 3
}

UPDATE_HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -1)

if [ "$UPDATE_HTTP_CODE" != "200" ]; then
    log_warn "填充内容返回 HTTP $UPDATE_HTTP_CODE"
fi

log_info "内容填充完成"

# ─── Step 4: 发布笔记 ──────────────────────────────────────
log_info "Step 4/4: 发布笔记..."

PUBLISH_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "https://www.jianshu.com/author/notes/${NOTE_ID}/publicize" \
    "${CURL_HEADERS[@]}" \
    --max-time 60 2>/dev/null) || {
    log_error "网络请求失败（发布笔记）"
    exit 3
}

PUBLISH_HTTP_CODE=$(echo "$PUBLISH_RESPONSE" | tail -1)
PUBLISH_BODY=$(echo "$PUBLISH_RESPONSE" | sed '$d')

if [ "$PUBLISH_HTTP_CODE" = "200" ]; then
    ARTICLE_URL="https://www.jianshu.com/p/${NOTE_SLUG}"
    log_info "简书发布成功: $ARTICLE_URL"
    echo "$ARTICLE_URL"
    exit 0
else
    log_error "发布失败 (HTTP $PUBLISH_HTTP_CODE)"
    echo "$PUBLISH_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  resp={d}')" 2>/dev/null || true
    exit 2
fi
