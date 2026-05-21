#!/bin/bash
# post-wechat.sh — 发布文章到微信公众号（草稿箱）
#
# 流程: 获取 access_token → 获取封面 → 处理正文图片 → 创建草稿
# 微信仅支持写入草稿箱，需登录 mp.weixin.qq.com 手动群发。
#
# 用法: post-wechat.sh <title> <content_file> [cover_image]
#   title        — 文章标题
#   content_file — HTML 文件路径（由 polishing 阶段产出）
#   cover_image  — 封面图本地路径（可选）
#
# Exit codes:
#   0 — 草稿创建成功
#   1 — 认证失败
#   2 — API 错误
#   3 — 网络错误
#   4 — 参数错误

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ─── 参数校验 ────────────────────────────────────────────────
if [ $# -lt 2 ]; then
    log_error "用法: post-wechat.sh <title> <content_file> [cover_image]"
    exit 4
fi

TITLE="$1"
CONTENT_FILE="$2"
COVER_IMAGE="${3:-}"

if [ ! -f "$CONTENT_FILE" ]; then
    log_error "内容文件不存在: $CONTENT_FILE"
    exit 4
fi

# ─── 获取 access_token ──────────────────────────────────────
log_info "获取 access_token..."
ACCESS_TOKEN=$(bash "${SCRIPT_DIR}/auth-wechat.sh" --quiet 2>/dev/null) || {
    log_error "微信认证失败，请检查 WECHAT_APPID 和 WECHAT_SECRET"
    exit 1
}

# ─── 获取封面图 media_id ─────────────────────────────────────
log_info "获取封面图..."
COVER_MEDIA_ID=$(bash "${SCRIPT_DIR}/make-cover.sh" "$TITLE" "$CONTENT_FILE" "$ACCESS_TOKEN" "$COVER_IMAGE") || {
    log_error "微信草稿需要封面图（thumb_media_id 为必填字段）"
    log_error "可通过以下方式提供："
    log_error "  1. 作为第三个参数传入本地图片路径"
    log_error "  2. 在文章 HTML 中包含一张图片"
    log_error "  3. 设置 UNSPLASH_ACCESS_KEY 环境变量启用自动搜索"
    exit 1
}
log_info "封面图就绪"

# ─── 处理正文图片 ───────────────────────────────────────────
# 微信图片策略为 must-upload，需将 HTML 中所有外链图片上传到微信素材库
CONTENT=$(cat "$CONTENT_FILE")

log_info "处理正文图片..."
PROCESSED_CONTENT=$(python3 -c "
import sys, json, re, subprocess, os, tempfile, urllib.request

token = sys.argv[1]
html = sys.stdin.read()

img_pattern = re.compile(r'<img[^>]+src=[\"\\']([^\"\\']+)[\"\\']')
matches = img_pattern.findall(html)

replacements = {}
for src in matches:
    if src.startswith('data:'):
        print(f'[WARN] 跳过 data:URI 图片，请替换为真实图片链接', file=sys.stderr)
        continue

    local_path = src
    is_temp = False
    if src.startswith('http'):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
            tmp.close()
            urllib.request.urlretrieve(src, tmp.name)
            local_path = tmp.name
            is_temp = True
        except Exception as e:
            print(f'[WARN] 下载图片失败: {src} - {e}', file=sys.stderr)
            continue

    try:
        result = subprocess.run(
            ['curl', '-s', '-X', 'POST',
             f'https://api.weixin.qq.com/cgi-bin/media/uploadimg?access_token={token}',
             '-F', f'media=@{local_path}',
             '--max-time', '60'],
            capture_output=True, text=True, timeout=120
        )
        resp = json.loads(result.stdout)
        if 'url' in resp:
            replacements[src] = resp['url']
            print(f'[INFO] 图片上传成功: {os.path.basename(src)}', file=sys.stderr)
        else:
            print(f'[WARN] 图片上传失败: {resp.get(\"errmsg\", \"unknown\")}', file=sys.stderr)
    except Exception as e:
        print(f'[WARN] 图片上传异常: {e}', file=sys.stderr)
    finally:
        if is_temp and os.path.exists(local_path):
            os.unlink(local_path)

def replace_img(match):
    tag = match.group(0)
    src = match.group(1)
    if src in replacements:
        return tag.replace(src, replacements[src])
    return tag

print(img_pattern.sub(replace_img, html), end='')
" "$ACCESS_TOKEN" 2>/dev/null <<< "$CONTENT") || {
    log_warn "图片处理出错，使用原始内容发布"
    PROCESSED_CONTENT="$CONTENT"
}

# ─── 创建草稿 ──────────────────────────────────────────────
log_info "创建微信草稿: $TITLE"

# 移除 HTML 中的标题 heading（微信 API 的 title 字段会单独显示，避免重复）
CONTENT_FOR_DRAFT=$(echo "$PROCESSED_CONTENT" | python3 -c "
import sys, re
html = sys.stdin.read()
title = re.escape(sys.argv[1])
html = re.sub(
    r'<!--\\s*={3,}\\s*.*?\\s*={3,}\\s*-->\\s*'
    r'<h[12][^>]*>\\s*' + title + r'\\s*</h[12]>\\s*',
    '',
    html,
    count=1
)
html = re.sub(
    r'<h[12][^>]*>\\s*' + title + r'\\s*</h[12]>\\s*',
    '',
    html,
    count=1
)
print(html, end='')
" "$TITLE" 2>/dev/null) || CONTENT_FOR_DRAFT="$PROCESSED_CONTENT"

DRAFT_DATA=$(python3 -c "
import sys, json

article = {
    'title': sys.argv[1],
    'content': sys.argv[2],
    'need_open_comment': 0,
    'only_fans_can_comment': 0,
}
cover = sys.argv[3]
if cover:
    article['thumb_media_id'] = cover

print(json.dumps({'articles': [article]}, ensure_ascii=False))
" "$TITLE" "$CONTENT_FOR_DRAFT" "$COVER_MEDIA_ID" 2>/dev/null)

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "https://api.weixin.qq.com/cgi-bin/draft/add?access_token=${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$DRAFT_DATA" \
    --max-time 30 2>/dev/null) || {
    log_error "网络请求失败（创建草稿）"
    exit 3
}

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

MEDIA_ID=$(echo "$BODY" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'media_id' in data:
        print(data['media_id'])
    else:
        print(f'ERROR: {data.get(\"errmsg\", \"未知错误\")}', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: 解析响应失败: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || {
    log_error "创建草稿失败 (HTTP $HTTP_CODE)"
    log_error "响应: $(echo "$BODY" | head -c 200)"
    exit 2
}

log_info "微信草稿创建成功"
echo "media_id: ${MEDIA_ID}"
echo "请登录 https://mp.weixin.qq.com 手动群发"
exit 0
