#!/bin/bash
# upload-wechat-image.sh — 上传图片到微信素材库
#
# 上传本地图片到微信永久素材库，返回可用的图片 URL。
# 用于替换 draft.html 中的外链图片地址。
#
# 用法: upload-wechat-image.sh <local_path> [description]
#   local_path  — 本地图片路径
#   description — 图片描述（可选）
#
# 环境变量: WECHAT_ACCESS_TOKEN（通过 auth-wechat.sh 获取）
#
# Exit codes:
#   0 — 上传成功，stdout 输出图片 URL
#   1 — 认证失败（token 未设置）
#   3 — 网络错误 / API 错误
#   4 — 参数错误（图片不存在、超大小限制）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

if [ $# -lt 1 ]; then
    log_error "用法: upload-wechat-image.sh <local_path> [description]"
    exit 4
fi

LOCAL_PATH="$1"
DESCRIPTION="${2:-}"

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

TOKEN="${WECHAT_ACCESS_TOKEN:-}"
if [ -z "$TOKEN" ]; then
    log_error "WECHAT_ACCESS_TOKEN 环境变量未设置"
    log_error "请先运行: eval \$(./scripts/auth-wechat.sh)"
    exit 1
fi

log_info "上传图片到微信: $(basename "$LOCAL_PATH")"

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "https://api.weixin.qq.com/cgi-bin/media/uploadimg?access_token=${TOKEN}" \
    -F "media=@${LOCAL_PATH}" \
    --max-time 60 2>/dev/null) || {
    log_error "图片上传网络失败"
    exit 3
}

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

URL=$(echo "$BODY" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'url' in data:
        print(data['url'])
    else:
        print(f'ERROR: {data.get(\"errmsg\", \"未知错误\")}', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: 解析响应失败: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || {
    log_error "微信图片上传失败 (HTTP $HTTP_CODE)"
    log_error "响应: $(echo "$BODY" | head -c 200)"
    exit 3
}

echo "$URL"
log_info "微信图片上传成功"
exit 0
