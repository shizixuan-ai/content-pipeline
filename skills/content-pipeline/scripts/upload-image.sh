#!/bin/bash
# upload-image.sh — 通用图片上传脚本
#
# 将本地图片上传到指定平台图床，返回平台可用的 URL 或 media_id
#
# 用法: upload-image.sh <platform> <local_path> [description]
#   platform   — 平台名称 (juejin/wechat/toutiao/zhihu)
#   local_path — 本地图片路径
#   description — 图片描述（可选）
#
# Exit codes:
#   0 — 上传成功
#   1 — 认证失败
#   2 — 平台不支持此 API
#   3 — 网络错误
#   4 — 图片不存在

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

if [ $# -lt 2 ]; then
    log_error "用法: upload-image.sh <platform> <local_path> [description]"
    exit 4
fi

PLATFORM="$1"
LOCAL_PATH="$2"
DESCRIPTION="${3:-}"

# 检查图片是否存在
if [ ! -f "$LOCAL_PATH" ]; then
    log_error "图片不存在: $LOCAL_PATH"
    exit 4
fi

# 文件大小检查（微信限制 10MB）
FILE_SIZE=$(stat -f%z "$LOCAL_PATH" 2>/dev/null || stat --format=%s "$LOCAL_PATH" 2>/dev/null)
MAX_SIZE=$((10 * 1024 * 1024))
if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
    log_error "图片超过 10MB 限制: $LOCAL_PATH"
    exit 4
fi

log_info "正在上传图片 ($PLATFORM): $(basename "$LOCAL_PATH")"

case "$PLATFORM" in
    wechat)
        TOKEN="${WECHAT_ACCESS_TOKEN:-}"
        if [ -z "$TOKEN" ]; then
            log_error "WECHAT_ACCESS_TOKEN 环境变量未设置"
            exit 1
        fi
        UPLOAD_URL="https://api.weixin.qq.com/cgi-bin/media/uploadimg?access_token=${TOKEN}"
        RESPONSE=$(curl -s -w "\n%{http_code}" \
            -X POST "$UPLOAD_URL" \
            -F "media=@${LOCAL_PATH}" \
            --max-time 60 2>/dev/null) || {
            log_error "图片上传网络失败"
            exit 3
        }
        HTTP_CODE=$(echo "$RESPONSE" | tail -1)
        BODY=$(echo "$RESPONSE" | sed '$d')
        if echo "$BODY" | grep -q '"url"'; then
            URL=$(echo "$BODY" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)
            echo "$URL"
            log_info "微信图片上传成功"
            exit 0
        else
            log_error "微信图片上传失败: $BODY"
            exit 3
        fi
        ;;
    juejin|toutiao|zhihu)
        # 这些平台接受外链，不需要上传
        log_info "$PLATFORM 支持外链，无需上传"
        echo "external"
        exit 0
        ;;
    *)
        log_error "不支持的平台: $PLATFORM"
        exit 2
        ;;
esac
