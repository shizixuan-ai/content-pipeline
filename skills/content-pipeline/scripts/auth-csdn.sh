#!/bin/bash
# auth-csdn.sh — 验证 CSDN Cookie 有效性
#
# 认证方式: Cookie（环境变量 CSDN_COOKIE）
# 验证方式: 尝试简单请求检查 Cookie 有效性
#
# 使用方法:
#   eval "$(auth-csdn.sh)"           # 设置 CSDN_COOKIE 到当前 shell
#   CSDN_COOKIE=$(auth-csdn.sh --quiet) post-csdn.sh ...  # 子进程模式
#
# Exit codes:
#   0 — 认证成功
#   1 — 认证失败（Cookie 无效或未设置）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MODE="${1:-}"

# ─── 内部: 从 Playwright persistent session 提取 Cookie ───────────
_playwright_csdn_cookie() {
    node "$SCRIPT_DIR/lib/csdn-session.cjs" get-cookies 2>/dev/null || return 1
}

# ─── 验证 Cookie 有效性 ──────────────────────────────────────────
_validate_csdn_cookie() {
    local cookie="$1"
    local final_url

    # 访问登录页，已登录会自动跳转到 www.csdn.net，未登录到 passport.csdn.net/login
    final_url=$(curl -s -o /dev/null -w "%{url_effective}" \
        -H "Cookie: ${cookie}" \
        -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
        --max-time 10 \
        -L "https://passport.csdn.net/account/login" 2>/dev/null) || return 1

    [[ "$final_url" != *"login"* ]]
}

# ─── 输出 Cookie ────────────────────────────────────────────────
_output_cookie() {
    local cookie="$1"
    if [ "$MODE" = "--quiet" ]; then
        echo "$cookie"
    else
        echo "export CSDN_COOKIE='$cookie'"
    fi
}

# ─── 主流程 ─────────────────────────────────────────────────────

# 策略 1: CSDN_COOKIE 环境变量
COOKIE="${CSDN_COOKIE:-}"
if [ -n "$COOKIE" ]; then
    if _validate_csdn_cookie "$COOKIE"; then
        log_info "Cookie 有效（来源: CSDN_COOKIE 环境变量）"
        _output_cookie "$COOKIE"
        exit 0
    fi
    log_warn "CSDN_COOKIE 已过期，尝试 Playwright session..."
fi

# 策略 2: Playwright persistent session
if command -v toutiao-ops &>/dev/null; then
    log_info "从 Playwright session 提取 Cookie..."

    PW_COOKIE=$(_playwright_csdn_cookie) || PW_COOKIE=""

    if [ -n "$PW_COOKIE" ] && _validate_csdn_cookie "$PW_COOKIE"; then
        log_info "Cookie 有效（来源: Playwright session）"
        _output_cookie "$PW_COOKIE"
        exit 0
    fi

    log_warn "Playwright session 中的 Cookie 无效或已过期"
fi

# 全部无效
log_error "未找到有效的 CSDN Cookie"
echo "" >&2
echo "请扫码登录以持久化 session:" >&2
echo "  ./scripts/login-csdn.sh" >&2
echo "" >&2
echo "或直接设置环境变量:" >&2
echo "  export CSDN_COOKIE=\"...\"" >&2
exit 1
