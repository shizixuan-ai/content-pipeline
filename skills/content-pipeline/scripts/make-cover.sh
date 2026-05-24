#!/bin/bash
# make-cover.sh — 获取微信封面图 media_id
#
# 优先级策略（按序尝试直到成功）:
#   1. 用户提供的本地图片路径
#   2. 从正文 HTML 中提取第一张图片
#   3. 根据标题搜索 Unsplash
#   4. 生成纯色占位图
#
# 用法: make-cover.sh <title> <content_file> <access_token> [cover_image]
#   title        — 文章标题
#   content_file — HTML 文件路径（从中提取首图）
#   access_token — 微信 access_token
#   cover_image  — 封面图本地路径（可选）
#
# Exit codes:
#   0 — 成功，stdout 输出 media_id
#   1 — 全部封面获取方式均失败

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

if [ $# -lt 3 ]; then
    log_error "用法: make-cover.sh <title> <content_file> <access_token> [cover_image]"
    exit 1
fi

TITLE="$1"
CONTENT_FILE="$2"
ACCESS_TOKEN="$3"
COVER_IMAGE="${4:-}"

# ─── 上传本地图片到微信素材库，返回 media_id ──────────────────
_upload_cover() {
    local image_path="$1"
    local resp mid

    resp=$(curl -s -X POST "https://api.weixin.qq.com/cgi-bin/material/add_material?type=image&access_token=${ACCESS_TOKEN}" \
        -F "media=@${image_path}" --max-time 60 2>/dev/null) || return 1
    mid=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('media_id',''))" 2>/dev/null)
    [ -n "$mid" ] && echo "$mid" && return 0
    return 1
}

# ─── 策略 1: 用户提供的封面图 ──────────────────────────────────
if [ -n "$COVER_IMAGE" ] && [ -f "$COVER_IMAGE" ]; then
    log_info "使用用户提供的封面图..."
    COVER_MEDIA_ID=$(_upload_cover "$COVER_IMAGE") && {
        echo "$COVER_MEDIA_ID"
        exit 0
    }
    log_warn "用户封面图上传失败: $COVER_IMAGE"
fi

# ─── 策略 2: 从正文提取第一张图片 ──────────────────────────────
if [ -f "$CONTENT_FILE" ]; then
    FIRST_IMG=$(python3 -c "
import sys, re
html = sys.stdin.read()
m = re.search(r'<img[^>]+src=[\"\\']([^\"\\']+)[\"\\']', html)
if m:
    src = m.group(1)
    if not src.startswith('data:'):
        print(src)
" 2>/dev/null < "$CONTENT_FILE")

    if [ -n "$FIRST_IMG" ]; then
        log_info "使用正文第一张图片作为封面..."
        local_path="$FIRST_IMG"
        cleanup=""
        if echo "$FIRST_IMG" | grep -q '^https\?://'; then
            tmpf=$(mktemp /tmp/wechat-cover-XXXXXX)
            curl -s -L --max-time 15 -o "$tmpf" "$FIRST_IMG" 2>/dev/null || { rm -f "$tmpf"; local_path=""; }
            if [ -n "$local_path" ]; then
                local_path="$tmpf"
                cleanup="$tmpf"
            fi
        fi
        if [ -f "$local_path" ]; then
            COVER_MEDIA_ID=$(_upload_cover "$local_path") || true
            [ -n "$cleanup" ] && rm -f "$cleanup"
            if [ -n "$COVER_MEDIA_ID" ]; then
                echo "$COVER_MEDIA_ID"
                exit 0
            fi
        fi
    fi
fi

# ─── 策略 3: 根据标题搜索 Unsplash ─────────────────────────────
if [ -n "${UNSPLASH_ACCESS_KEY:-}" ]; then
    keywords=$(echo "$TITLE" | python3 -c "
import sys, re
t = sys.stdin.read().strip()
t = re.sub(r'[：:：\"\'\-“”]', ' ', t)[:15]
print(t.strip() or 'cover')
" 2>/dev/null)

    log_info "搜索 Unsplash: $keywords"
    unsplash_resp=$(curl -s -L \
        "https://api.unsplash.com/search/photos?query=${keywords}&per_page=1&orientation=landscape" \
        -H "Authorization: Client-ID ${UNSPLASH_ACCESS_KEY}" \
        --max-time 15 2>/dev/null) || unsplash_resp=""

    if [ -n "$unsplash_resp" ]; then
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
                COVER_MEDIA_ID=$(_upload_cover "$tmp_cover") && { rm -f "$tmp_cover"; echo "$COVER_MEDIA_ID"; exit 0; }
            fi
            rm -f "$tmp_cover"
        fi
    fi
fi

# ─── 策略 4: 生成纯色占位图 ─────────────────────────────────────
log_info "生成占位封面图..."
tmp_cover=$(mktemp /tmp/wechat-cover-XXXXXX.png)
python3 -c "
import struct, zlib

def create_png(width, height, r, g, b):
    def chunk(ctype, data):
        c = ctype + data
        crc = struct.pack('>I', zlib.crc32(c) & 0xffffffff)
        return struct.pack('>I', len(data)) + c + crc
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    raw = b''
    for y in range(height):
        raw += b'\x00'
        for x in range(width):
            raw += bytes([r, g, b])
    idat = chunk(b'IDAT', zlib.compress(raw))
    iend = chunk(b'IEND', b'')
    return sig + ihdr + idat + iend

with open('${tmp_cover}', 'wb') as f:
    f.write(create_png(1200, 630, 7, 193, 96))
" 2>/dev/null || { rm -f "$tmp_cover"; log_error "占位图生成失败"; exit 1; }

COVER_MEDIA_ID=$(_upload_cover "$tmp_cover") || { rm -f "$tmp_cover"; log_error "占位封面上传失败"; exit 1; }
rm -f "$tmp_cover"
echo "$COVER_MEDIA_ID"
exit 0
