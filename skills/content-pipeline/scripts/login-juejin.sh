#!/bin/bash
# login-juejin.sh — 扫码登录掘金并持久化 session
#
# 使用 Playwright 的 launchPersistentContext() 保存 Chromium profile，
# 后续 auth-juejin.sh 可在 headless 模式下直接提取 cookie，无需重复登录。
#
# 前置条件: @openclaw-cn/toutiao-ops 已安装 (npm i -g @openclaw-cn/toutiao-ops)
#
# 用法:
#   login-juejin.sh
#
# Exit codes:
#   0 — 登录成功
#   1 — toutiao-ops 未安装
#   2 — 登录超时/失败

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ─── 检查 toutiao-ops（提供 playwright 依赖）─────────────────────
if ! command -v toutiao-ops &>/dev/null; then
    log_error "toutiao-ops 未安装。请运行: npm install -g @openclaw-cn/toutiao-ops"
    exit 1
fi

log_info "打开掘金登录页面。请扫码登录..."

node "$SCRIPT_DIR/lib/juejin-session.cjs" login 2>&1 || {
    exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        log_error "登录超时，请重试"
    else
        log_error "登录失败 (exit: ${exit_code})"
    fi
    exit "$exit_code"
}

log_info "登录成功，session 已持久化到 ~/.juejin/browser-data/"
exit 0
