#!/bin/bash
# get-juejin-cookie.sh — 从 agent-browser session 提取 Cookie header
#
# 从持久化的 agent-browser session 中提取掘金 Cookie，
# 格式化为 HTTP Cookie header 字符串，输出到 stdout。
#
# 配合 post-juejin.sh 使用:
#   export JUEJIN_COOKIE=$(get-juejin-cookie.sh)
#
# 前置条件: 已运行 login-juejin.sh 完成扫码登录
#
# Exit codes:
#   0 — 成功输出 Cookie header
#   1 — agent-browser 不可用
#   2 — 未找到有效的登录 session

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

SESSION_NAME="juejin"

# ─── 前置检查 ────────────────────────────────────────────────
if ! command -v agent-browser &>/dev/null; then
    log_error "agent-browser 未安装，请先运行: npm i -g agent-browser && agent-browser install"
    exit 1
fi

# ─── 恢复 session 并提取 Cookie ──────────────────────────────
# 以静默模式（无窗口）打开页面，自动恢复之前保存的 state
AGENT_BROWSER_SESSION_NAME="$SESSION_NAME" \
    agent-browser open https://juejin.cn >/dev/null 2>&1 || {
    log_error "无法启动 browser session，请检查 agent-browser 是否正常运行"
    exit 2
}

# 等待页面和 cookie 加载
sleep 2

# 提取 cookies
COOKIE_JSON=$(AGENT_BROWSER_SESSION_NAME="$SESSION_NAME" \
    agent-browser cookies get --json 2>/dev/null || echo "")

# 关闭 browser
AGENT_BROWSER_SESSION_NAME="$SESSION_NAME" agent-browser close >/dev/null 2>&1 || true

if [ -z "$COOKIE_JSON" ]; then
    log_error "无法获取 Cookie，请先运行 login-juejin.sh"
    exit 2
fi

# ─── 格式化为 Cookie header ──────────────────────────────────
COOKIE_STR=$(echo "$COOKIE_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    cookies = data.get('data', {}).get('cookies', [])
    if not cookies:
        sys.exit(1)
    # 按 name 排序，保证输出稳定
    pairs = sorted([c['name'] + '=' + c['value'] for c in cookies])
    print('; '.join(pairs))
except Exception:
    sys.exit(1)
" 2>/dev/null) || {
    log_error "解析 Cookie 失败"
    exit 2
}

# ─── 验证 Cookie 有效性（检查 err_no，非 HTTP 状态码）───────
RESPONSE=$(curl -s \
    -H "Cookie: ${COOKIE_STR}" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
    -H "Referer: https://juejin.cn/" \
    --max-time 10 \
    "https://api.juejin.cn/user_api/v1/user/get" 2>/dev/null) || {
    log_error "网络错误，无法验证 Cookie"
    exit 2
}

ERR_NO=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('err_no', -1))
except Exception:
    print(-1)
" 2>/dev/null) || ERR_NO="-1"

if [ "$ERR_NO" != "0" ]; then
    log_warn "Cookie 无效或已过期，请重新登录: login-juejin.sh"
    exit 2
fi

echo "$COOKIE_STR"
