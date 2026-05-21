#!/bin/bash
# auth-wechat.sh — 获取微信公众号 access_token
#
# 通过 appid + secret 获取全局 access_token（有效期 7200 秒）。
# 每次调用都会请求新 token，不缓存。
#
# 使用方法:
#   eval "$(auth-wechat.sh)"
#   # 之后 WECHAT_ACCESS_TOKEN 环境变量即被设置
#
#   WECHAT_ACCESS_TOKEN=$(auth-wechat.sh --quiet) post-wechat.sh ...
#
# Exit codes:
#   0 — 认证成功
#   1 — 环境变量未设置
#   2 — API 错误 / 网络错误

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MODE="${1:-}"

APPID="${WECHAT_APPID:-}"
SECRET="${WECHAT_SECRET:-}"

if [ -z "$APPID" ] || [ -z "$SECRET" ]; then
    log_error "请设置 WECHAT_APPID 和 WECHAT_SECRET 环境变量"
    echo "" >&2
    echo "获取方式（微信公众平台）:" >&2
    echo "  1. 登录 https://mp.weixin.qq.com" >&2
    echo "  2. 设置与开发 → 基本配置" >&2
    echo "  3. 开发者ID(AppID) — 直接复制" >&2
    echo "  4. 开发者密码(AppSecret) — 点击生成/重置，复制保存" >&2
    echo "" >&2
    echo "注意:" >&2
    echo "  - 需要已认证的公众号（订阅号/服务号均可）" >&2
    echo "  - 若启用了 IP 白名单，需将服务器 IP 加入白名单" >&2
    echo "  - AppSecret 只显示一次，丢失需重置" >&2
    echo "" >&2
    echo "设置环境变量:" >&2
    echo "  export WECHAT_APPID=\"your_appid\"" >&2
    echo "  export WECHAT_SECRET=\"your_secret\"" >&2
    exit 1
fi

RESPONSE=$(curl -s \
    "https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=${APPID}&secret=${SECRET}" \
    --max-time 10 2>/dev/null) || {
    log_error "网络请求失败（获取 access_token）"
    exit 2
}

ACCESS_TOKEN=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'access_token' in data:
        print(data['access_token'])
    else:
        errmsg = data.get('errmsg', 'unknown error')
        print(f'ERROR: {errmsg}', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: 解析响应失败: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || {
    log_error "获取 access_token 失败"
    log_error "响应: $(echo "$RESPONSE" | head -c 200)"
    echo "" >&2
    echo "常见原因:" >&2
    echo "  - AppID 或 AppSecret 填写错误 → 登录 mp.weixin.qq.com 检查" >&2
    echo "  - IP 白名单未配置 → 设置与开发 → 基本配置 → IP 白名单" >&2
    echo "  - 公众号未认证 → 部分接口需要认证（订阅号可获取 token）" >&2
    exit 2
}

if [ "$MODE" = "--quiet" ]; then
    echo "$ACCESS_TOKEN"
else
    echo "export WECHAT_ACCESS_TOKEN='$ACCESS_TOKEN'"
fi
exit 0
