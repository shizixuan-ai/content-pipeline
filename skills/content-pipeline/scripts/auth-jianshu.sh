#!/bin/bash
# auth-jianshu.sh — 验证简书 Cookie 有效性
#
# 认证方式: Cookie（环境变量 JIANSHU_COOKIE）
# 验证方式: GET /author/notebooks → 检查返回有效 JSON 数组
#
# 使用方法:
#   eval "$(auth-jianshu.sh)"           # 设置 JIANSHU_COOKIE 到当前 shell
#   JIANSHU_COOKIE=$(auth-jianshu.sh --quiet) post-jianshu.sh ...  # 子进程模式
#
# Exit codes:
#   0 — 认证成功
#   1 — 认证失败（Cookie 无效或未设置）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MODE="${1:-}"

# ─── 内部: 从 Playwright persistent session 提取 Cookie ───────────
_playwright_jianshu_cookie() {
    node "$SCRIPT_DIR/lib/jianshu-session.cjs" get-cookies 2>/dev/null || return 1
}

# ─── 验证 Cookie 有效性 ──────────────────────────────────────────
_validate_jianshu_cookie() {
    local cookie="$1"
    local response

    response=$(curl -s \
        -H "Cookie: ${cookie}" \
        -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
        -H "accept: application/json" \
        -H "Referer: https://www.jianshu.com/writer" \
        --max-time 10 \
        "https://www.jianshu.com/author/notebooks" 2>/dev/null) || return 1

    # 验证响应是 JSON 数组
    echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        sys.exit(0)
    else:
        sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null || return 1
}

# ─── 输出 Cookie ────────────────────────────────────────────────
_output_cookie() {
    local cookie="$1"
    if [ "$MODE" = "--quiet" ]; then
        echo "$cookie"
    else
        echo "export JIANSHU_COOKIE='$cookie'"
    fi
}

# ─── 主流程 ─────────────────────────────────────────────────────

# 策略 1: JIANSHU_COOKIE 环境变量
COOKIE="${JIANSHU_COOKIE:-}"
if [ -n "$COOKIE" ]; then
    if _validate_jianshu_cookie "$COOKIE"; then
        log_info "Cookie 有效（来源: JIANSHU_COOKIE 环境变量）"
        _output_cookie "$COOKIE"
        exit 0
    fi
    log_warn "JIANSHU_COOKIE 已过期，尝试 Playwright session..."
fi

# 策略 2: Playwright persistent session
if command -v toutiao-ops &>/dev/null; then
    log_info "从 Playwright session 提取 Cookie..."

    PW_COOKIE=$(_playwright_jianshu_cookie) || PW_COOKIE=""

    if [ -n "$PW_COOKIE" ] && _validate_jianshu_cookie "$PW_COOKIE"; then
        log_info "Cookie 有效（来源: Playwright session）"
        _output_cookie "$PW_COOKIE"
        exit 0
    fi

    log_warn "Playwright session 中的 Cookie 无效或已过期"
fi

# 全部无效
log_error "未找到有效的简书 Cookie"
echo "" >&2
echo "请扫码登录以持久化 session:" >&2
echo "  ./scripts/login-jianshu.sh" >&2
echo "" >&2
echo "或直接设置环境变量:" >&2
echo "  export JIANSHU_COOKIE=\"...\"" >&2
exit 1
