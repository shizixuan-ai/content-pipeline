#!/bin/bash
# auth-juejin.sh — 验证并获取有效的掘金 Cookie
#
# 策略（按优先级）:
#   1. JUEJIN_COOKIE 环境变量 → 验证有效性
#   2. agent-browser session → 提取并验证
#   3. 都无效 → 引导用户扫码登录
#
# 使用方法:
#   eval "$(auth-juejin.sh)"          # 设置 JUEJIN_COOKIE 到当前 shell
#   JUEJIN_COOKIE=$(auth-juejin.sh --quiet) post-juejin.sh ...  # 子进程模式
#
# Exit codes:
#   0 — 认证成功
#   1 — 认证失败（所有方式均无效）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MODE="${1:-}"

# ─── 内部: 从 agent-browser session 提取 Cookie ─────────────────
# 成功时 stdout 输出 Cookie header，退出码 0
# 失败时无输出，退出码 1
_agent_browser_juejin_cookie() {
    local session_name="juejin"

    AGENT_BROWSER_SESSION_NAME="$session_name" \
        agent-browser open https://juejin.cn >/dev/null 2>&1 || return 1

    sleep 2

    local cookie_json
    cookie_json=$(AGENT_BROWSER_SESSION_NAME="$session_name" \
        agent-browser cookies get --json 2>/dev/null || echo "")

    AGENT_BROWSER_SESSION_NAME="$session_name" agent-browser close >/dev/null 2>&1 || true

    [ -z "$cookie_json" ] && return 1

    echo "$cookie_json" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    cookies = data.get('data', {}).get('cookies', [])
    if not cookies:
        sys.exit(1)
    pairs = sorted([c['name'] + '=' + c['value'] for c in cookies])
    print('; '.join(pairs))
except Exception:
    sys.exit(1)
" 2>/dev/null || return 1
}

# ─── 内部: 验证 Cookie 有效性 ──────────────────────────────────
# 通过掘金 API 检查 err_no 是否为 0
_validate_juejin_cookie() {
    local cookie="$1"
    local response err_no

    response=$(curl -s \
        -H "Cookie: ${cookie}" \
        -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
        -H "Referer: https://juejin.cn/" \
        --max-time 10 \
        "https://api.juejin.cn/user_api/v1/user/get" 2>/dev/null) || return 1

    err_no=$(echo "$response" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('err_no', -1))
except Exception:
    print(-1)
" 2>/dev/null) || return 1

    [ "$err_no" = "0" ]
}

# ─── 内部: 输出 Cookie（按 MODE 格式）───────────────────────────
_output_cookie() {
    local cookie="$1"
    if [ "$MODE" = "--quiet" ]; then
        echo "$cookie"
    else
        echo "export JUEJIN_COOKIE='$cookie'"
    fi
}

# ─── 策略 1: JUEJIN_COOKIE 环境变量 ─────────────────────────────
COOKIE="${JUEJIN_COOKIE:-}"
if [ -n "$COOKIE" ]; then
    if _validate_juejin_cookie "$COOKIE"; then
        log_info "Cookie 有效（来源: JUEJIN_COOKIE 环境变量）"
        _output_cookie "$COOKIE"
        exit 0
    fi
    log_warn "JUEJIN_COOKIE 已过期，尝试 agent-browser session..."
fi

# ─── 策略 2: agent-browser session ──────────────────────────────
if command -v agent-browser &>/dev/null; then
    log_info "从 agent-browser session 提取 Cookie..."

    AGENT_COOKIE=$(_agent_browser_juejin_cookie) || AGENT_COOKIE=""

    if [ -n "$AGENT_COOKIE" ] && _validate_juejin_cookie "$AGENT_COOKIE"; then
        log_info "Cookie 有效（来源: agent-browser session）"
        _output_cookie "$AGENT_COOKIE"
        exit 0
    fi

    log_warn "agent-browser session 中的 Cookie 无效或已过期"
fi

# ─── 全部无效 ────────────────────────────────────────────────────
log_error "未找到有效的掘金 Cookie"
echo "" >&2
echo "有两种方式解决：" >&2
echo "" >&2
echo "方案 A（推荐）— 使用 agent-browser 扫码登录，自动管理 Cookie:" >&2
echo "  npm i -g agent-browser && agent-browser install" >&2
echo "  ./scripts/login-juejin.sh" >&2
echo "  之后 auth-juejin.sh 会自动从 session 提取有效 Cookie" >&2
echo "" >&2
echo "方案 B — 手动从浏览器复制 Cookie:" >&2
echo "  登录 juejin.cn → F12 → Network → 任意请求 → Request Headers → Cookie" >&2
echo "  export JUEJIN_COOKIE=\"sessionid=xxx; ...\"" >&2
exit 1
