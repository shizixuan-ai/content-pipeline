#!/bin/bash
# post-wechat.sh — 发布文章到微信公众号（草稿箱）
#
# 流程: 获取 access_token → 上传封面图 → 处理正文图片 → 创建草稿
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

# ─── 获取封面图 media_id（订阅号 API 要求 thumb_media_id）──────
# 封面图通过 add_material 上传获取 media_id
get_cover_media_id() {
    local image_path="$1"
    local resp
    resp=$(curl -s -X POST "https://api.weixin.qq.com/cgi-bin/material/add_material?type=image&access_token=${ACCESS_TOKEN}" \
        -F "media=@${image_path}" --max-time 60 2>/dev/null) || return 1
    local mid
    mid=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('media_id',''))" 2>/dev/null)
    [ -n "$mid" ] && echo "$mid" && return 0
    return 1
}

# search_cover_by_title — 根据文章标题自动搜索封面图
# 优先级: Unsplash API → 生成占位图
search_cover_by_title() {
    local title="$1"
    local tmp_cover

    # 提取关键词（取标题前 10 个字作为搜索词）
    local keywords
    keywords=$(echo "$title" | python3 -c "
import sys, re
t = sys.stdin.read().strip()
t = re.sub(r'[：:：\"\'\-“”]', ' ', t)[:15]
print(t.strip() or 'cover')
" 2>/dev/null)

    # 尝试 Unsplash（需 UNSPLASH_ACCESS_KEY 环境变量）
    if [ -n "${UNSPLASH_ACCESS_KEY:-}" ]; then
        log_info "搜索 Unsplash: $keywords"
        local unsplash_resp
        unsplash_resp=$(curl -s -L \
            "https://api.unsplash.com/search/photos?query=${keywords}&per_page=1&orientation=landscape" \
            -H "Authorization: Client-ID ${UNSPLASH_ACCESS_KEY}" \
            --max-time 15 2>/dev/null) || { log_warn "Unsplash 请求失败"; unsplash_resp=""; }

        if [ -n "$unsplash_resp" ]; then
            local img_url
            img_url=$(echo "$unsplash_resp" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    urls = data.get('results', [])
    if urls:
        print(urls[0]['urls']['regular'])
except: pass
" 2>/dev/null)

            if [ -n "$img_url" ]; then
                tmp_cover=$(mktemp /tmp/wechat-cover-XXXXXX.jpg)
                if curl -s -L --max-time 15 -o "$tmp_cover" "$img_url" 2>/dev/null; then
                    local mid
                    mid=$(get_cover_media_id "$tmp_cover") && { rm -f "$tmp_cover"; echo "$mid"; return 0; }
                fi
                rm -f "$tmp_cover"
            fi
        fi
    fi

    # 兜底：生成纯色占位封面
    log_info "生成占位封面图..."
    tmp_cover=$(mktemp /tmp/wechat-cover-XXXXXX.png)
    python3 -c "
import struct, zlib

def create_png(width, height, r, g, b):
    def chunk(ctype, data):
        c = ctype + data
        crc = struct.pack('>I', zlib.crc32(c) & 0xffffffff)
        return struct.pack('>I', len(data)) + c + crc
    sig = b'\\x89PNG\\r\\n\\x1a\\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    raw = b''
    for y in range(height):
        raw += b'\\x00'
        for x in range(width):
            raw += bytes([r, g, b])
    idat = chunk(b'IDAT', zlib.compress(raw))
    iend = chunk(b'IEND', b'')
    return sig + ihdr + idat + iend

with open('${tmp_cover}', 'wb') as f:
    f.write(create_png(1200, 630, 7, 193, 96))
" 2>/dev/null || { rm -f "$tmp_cover"; return 1; }

    local mid
    mid=$(get_cover_media_id "$tmp_cover") || { rm -f "$tmp_cover"; return 1; }
    rm -f "$tmp_cover"
    echo "$mid"
    return 0
}

COVER_MEDIA_ID=""
if [ -n "$COVER_IMAGE" ] && [ -f "$COVER_IMAGE" ]; then
    log_info "上传封面图..."
    COVER_MEDIA_ID=$(get_cover_media_id "$COVER_IMAGE") || {
        log_error "封面图上传失败: $COVER_IMAGE"
        exit 1
    }
    log_info "封面图上传成功"
fi

# 如果未提供封面图，尝试从正文中提取第一张图片作为封面
if [ -z "$COVER_MEDIA_ID" ]; then
    CONTENT_RAW=$(cat "$CONTENT_FILE")
    FIRST_IMG=$(echo "$CONTENT_RAW" | python3 -c "
import sys, re
html = sys.stdin.read()
m = re.search(r'<img[^>]+src=[\"\\']([^\"\\']+)[\"\\']', html)
if m:
    src = m.group(1)
    if not src.startswith('data:'):
        print(src)
" 2>/dev/null)

    if [ -n "$FIRST_IMG" ]; then
        log_info "使用正文第一张图片作为封面..."
        local_path="$FIRST_IMG"
        is_temp=false
        if echo "$FIRST_IMG" | grep -q '^https\?://'; then
            tmpf=$(mktemp /tmp/wechat-cover-XXXXXX)
            if curl -s -L --max-time 15 -o "$tmpf" "$FIRST_IMG" 2>/dev/null; then
                local_path="$tmpf"
                is_temp=true
            fi
        fi
        if [ -f "$local_path" ]; then
            COVER_MEDIA_ID=$(get_cover_media_id "$local_path") || true
            $is_temp && rm -f "$local_path"
        fi
    fi
fi

# 仍然没有封面图 → 尝试根据标题自动搜索
if [ -z "$COVER_MEDIA_ID" ]; then
    log_info "未找到封面图，尝试根据标题自动搜索..."
    COVER_MEDIA_ID=$(search_cover_by_title "$TITLE") || {
        log_error "微信草稿需要封面图（thumb_media_id 为必填字段）"
        log_error "可通过以下方式提供："
        log_error "  1. 作为第三个参数传入本地图片路径"
        log_error "  2. 在文章 HTML 中包含一张图片"
        log_error "  3. 设置 UNSPLASH_ACCESS_KEY 环境变量启用自动搜索"
        exit 1
    }
fi

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
    # 跳过 data:URI 和已处理的微信链接
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
# 移除带注释包装的标题（如 <!-- ===== 头部：标题 ===== --> <h2>...</h2>）
html = re.sub(
    r'<!--\\s*={3,}\\s*.*?\\s*={3,}\\s*-->\\s*'
    r'<h[12][^>]*>\\s*' + title + r'\\s*</h[12]>\\s*',
    '',
    html,
    count=1
)
# 也移除裸标题（无注释包装，仅第一次出现）
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
