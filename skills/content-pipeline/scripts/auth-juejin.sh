#!/bin/bash
# auth-juejin.sh — 验证并获取有效的掘金 Cookie
#
# 策略（按优先级）:
#   1. JUEJIN_COOKIE 环境变量 → 验证有效性
#   2. agent-browser session → 提取并验证（自动续期）
#   3. 都无效 → 引导用户运行 login-juejin.sh
#
# 使用 eval 方式可在当前 shell 设置 JUEJIN_COOKIE:
#   eval "$(auth-juejin.sh)"
#   或
#   JUEJIN_COOKIE=$(auth-juejin.sh --quiet) post-juejin.sh ...
#
# Exit codes:
#   0 — 认证成功，Cookie 有效
#   1 — 认证失败（所有方式均无效）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MODE="${1:-}"

# ─── 验证 Cookie 的函数 ──────────────────────────────────────
validate_and_export() {
    local cookie="$1"
    local src="$2"

    local RESPONSE
    RESPONSE=$(curl -s \
        -H "Cookie: ${cookie}" \
        -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
        -H "Referer: https://juejin.cn/" \
        --max-time 10 \
        "https://api.juejin.cn/user_api/v1/user/get" 2>/dev/null) || return 1

    # 检查 err_no，只有 0 才是真正登录
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
        log_info "Cookie 有效（来源: ${src}）"
        if [ "$MODE" = "--quiet" ]; then
            echo "$cookie"
        else
            echo "export JUEJIN_COOKIE='$cookie'"
        fi
        return 0
    else
        return 1
    fi
}

# ─── 策略 1: 环境变量 ─────────────────────────────────────────
COOKIE="${JUEJIN_COOKIE:-}"
if [ -n "$COOKIE" ]; then
    if validate_and_export "$COOKIE" "JUEJIN_COOKIE 环境变量"; then
        exit 0
    fi
    log_warn "JUEJIN_COOKIE 已过期，尝试 agent-browser session..."
else
    log_info "JUEJIN_COOKIE 未设置，尝试 agent-browser session..."
fi

# ─── 策略 2: agent-browser session ────────────────────────────
if command -v agent-browser &>/dev/null; then
    log_info "启动 agent-browser 恢复 session..."

    AGENT_BROWSER_SESSION_NAME="juejin" \
        agent-browser open https://juejin.cn >/dev/null 2>&1 || {
        log_warn "无法启动 agent-browser"
        log_info "请安装 agent-browser: npm i -g agent-browser && agent-browser install"
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

        if [ -n "$COOKIE" ] && validate_and_export "$COOKIE" "agent-browser session"; then
            exit 0
        fi
    fi

    log_warn "agent-browser session 中的 Cookie 已过期"
else
    log_info "agent-browser 未安装，无法自动获取 Cookie"
fi

# ─── 全部无效 ─────────────────────────────────────────────────
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
