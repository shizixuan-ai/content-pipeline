#!/bin/bash
# auth-juejin.sh — 验证并获取有效的掘金 Cookie
#
# 策略（按优先级）:
#   1. JUEJIN_COOKIE 环境变量 → 验证有效性
#   2. Playwright persistent session → 提取并验证
#   3. 都无效 → 引导用户扫码登录
#
# 前置条件: @openclaw-cn/toutiao-ops 已安装（提供 playwright 依赖）
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

# ─── 内部: 从 Playwright persistent session 提取 Cookie ───────────
_playwright_juejin_cookie() {
    node "$SCRIPT_DIR/lib/juejin-session.cjs" get-cookies 2>/dev/null || return 1
}

# ─── 内部: 验证 Cookie 有效性 ──────────────────────────────────
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
    log_warn "JUEJIN_COOKIE 已过期，尝试 Playwright session..."
fi

# ─── 策略 2: Playwright persistent session ───────────────────────
if command -v toutiao-ops &>/dev/null; then
    log_info "从 Playwright session 提取 Cookie..."

    PW_COOKIE=$(_playwright_juejin_cookie) || PW_COOKIE=""

    if [ -n "$PW_COOKIE" ] && _validate_juejin_cookie "$PW_COOKIE"; then
        log_info "Cookie 有效（来源: Playwright session）"
        _output_cookie "$PW_COOKIE"
        exit 0
    fi

    log_warn "Playwright session 中的 Cookie 无效或已过期"
fi

# ─── 全部无效 ────────────────────────────────────────────────────
log_error "未找到有效的掘金 Cookie"
echo "" >&2
echo "请扫码登录以持久化 session:" >&2
echo "  ./scripts/login-juejin.sh" >&2
echo "" >&2
echo "登录后 auth-juejin.sh 会自动从 session 提取 Cookie。" >&2
exit 1
