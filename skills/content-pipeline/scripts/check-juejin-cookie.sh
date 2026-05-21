#!/bin/bash
# check-juejin-cookie.sh — 检测并获取有效的掘金 Cookie
#
# 策略（按优先级）:
#   1. JUEJIN_COOKIE 环境变量 → 验证有效性
#   2. agent-browser session → 提取并验证
#   3. 都无效 → 提示用户运行 login-juejin.sh
#
# 使用方法:
#   eval "$(check-juejin-cookie.sh)"
#   # 之后 JUEJIN_COOKIE 环境变量即被设置
#
#   或在子进程中使用:
#   JUEJIN_COOKIE=$(check-juejin-cookie.sh --quiet) post-juejin.sh ...
#
# Exit codes:
#   0 — 已设置 JUEJIN_COOKIE 环境变量
#   1 — 所有方式均未获取到有效的 Cookie

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MODE="${1:-}"

# ─── 验证 Cookie 的函数 ──────────────────────────────────────
validate_cookie() {
    local cookie="$1"
    local source="$2"

    local RESPONSE
    RESPONSE=$(curl -s \
        -H "Cookie: ${cookie}" \
        -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
        -H "Referer: https://juejin.cn/" \
        --max-time 10 \
        "https://api.juejin.cn/user_api/v1/user/get" 2>/dev/null) || return 1

    local ERR_NO
    ERR_NO=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('err_no', -1))
except Exception:
    print(-1)
" 2>/dev/null) || return 1

    if [ "$ERR_NO" = "0" ]; then
        log_info "Cookie 有效（来源: $source）"
        return 0
    fi
    return 1
}

# ─── 策略 1: 环境变量 ─────────────────────────────────────────
COOKIE="${JUEJIN_COOKIE:-}"
if [ -n "$COOKIE" ]; then
    if validate_cookie "$COOKIE" "JUEJIN_COOKIE"; then
        if [ "$MODE" = "--quiet" ]; then
            echo "$COOKIE"
        else
            echo "export JUEJIN_COOKIE='$COOKIE'"
        fi
        exit 0
    fi
    log_warn "JUEJIN_COOKIE 已过期，尝试 agent-browser session..."
fi

# ─── 策略 2: agent-browser session ────────────────────────────
if command -v agent-browser &>/dev/null; then
    log_info "从 agent-browser session 提取 Cookie..."

    # 启动 session 恢复 Cookies
    AGENT_BROWSER_SESSION_NAME="juejin" \
        agent-browser open https://juejin.cn >/dev/null 2>&1 || {
        log_warn "无法启动 agent-browser session"
        exit 1
    }
    sleep 2

    COOKIE_JSON=$(AGENT_BROWSER_SESSION_NAME="juejin" \
        agent-browser cookies get --json 2>/dev/null || echo "")

    AGENT_BROWSER_SESSION_NAME="juejin" agent-browser close >/dev/null 2>&1 || true

    if [ -n "$COOKIE_JSON" ]; then
        COOKIE=$(echo "$COOKIE_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    cookies = data.get('data', {}).get('cookies', [])
    pairs = sorted([c['name'] + '=' + c['value'] for c in cookies])
    print('; '.join(pairs))
except Exception:
    sys.exit(1)
" 2>/dev/null) || COOKIE=""

        if [ -n "$COOKIE" ] && validate_cookie "$COOKIE" "agent-browser session"; then
            if [ "$MODE" = "--quiet" ]; then
                echo "$COOKIE"
            else
                echo "export JUEJIN_COOKIE='$COOKIE'"
            fi
            exit 0
        fi
    fi
else
    log_warn "agent-browser 未安装，无法自动获取 Cookie"
fi

# ─── 策略 3: 全部无效 ─────────────────────────────────────────
log_error "未找到有效的掘金 Cookie，请运行: login-juejin.sh"
echo "# 登录后，再运行此脚本获取 Cookie"
exit 1
