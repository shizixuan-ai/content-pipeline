#!/bin/bash
# auth-zhihu.sh — 验证知乎认证状态，获取有效 Cookie
#
# 策略:
#   1. 优先 Playwright persistent session → 提取并验证 Cookie
#   2. ZHIHU_COOKIE 环境变量 → 备用（知乎已启用 X-Zse-96 签名，
#      纯 Cookie 方式仅用于简单验证）
#
# 使用方法:
#   eval "$(auth-zhihu.sh)"           # 设置 ZHIHU_COOKIE 到当前 shell
#   ZHIHU_COOKIE=$(auth-zhihu.sh --quiet) post-zhihu.sh ...
#
# Exit codes:
#   0 — 认证成功
#   1 — 认证失败（所有方式均无效）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MODE="${1:-}"

# ─── 输出 Cookie ────────────────────────────────────────────────
_output_cookie() {
    local cookie="$1"
    if [ "$MODE" = "--quiet" ]; then
        echo "$cookie"
    else
        echo "export ZHIHU_COOKIE='$cookie'"
    fi
}

# ─── 策略 1: Playwright persistent session ───────────────────────
if command -v toutiao-ops &>/dev/null; then
    log_info "从 Playwright session 提取 Cookie..."

    PW_COOKIE=$(node "$SCRIPT_DIR/lib/zhihu-session.cjs" get-cookies 2>/dev/null) || PW_COOKIE=""

    if [ -n "$PW_COOKIE" ]; then
        log_info "Session 有效"
        _output_cookie "$PW_COOKIE"
        exit 0
    fi

    log_warn "Playwright session 无效或已过期"
fi

# ─── 策略 2: ZHIHU_COOKIE 环境变量 ─────────────────────────────
COOKIE="${ZHIHU_COOKIE:-}"
if [ -n "$COOKIE" ]; then
    log_info "使用环境变量 Cookie"
    _output_cookie "$COOKIE"
    exit 0
fi

# ─── 全部无效 ────────────────────────────────────────────────────
log_error "未找到有效的知乎认证"
echo "" >&2
echo "请扫码登录以持久化 session:" >&2
echo "  ./scripts/login-zhihu.sh" >&2
echo "" >&2
echo "登录后 auth-zhihu.sh 会自动从 session 提取 Cookie。" >&2
exit 1
