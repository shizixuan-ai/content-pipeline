#!/bin/bash
# auth-toutiao.sh — 验证头条号登录状态
#
# 基于 @openclaw-cn/toutiao-ops 的登录态检测。
#
# 用法:
#   auth-toutiao.sh              # 交互模式
#   auth-toutiao.sh --quiet      # 静默模式（stdout 输出账号名，供后续脚本使用）
#
# 环境变量:
#   TOUTIAO_ACCOUNT — 头条号账号名（默认 default）
#
# Exit codes:
#   0 — 已登录
#   1 — 未登录
#   2 — toutiao-ops 未安装

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

MODE="${1:-}"
ACCOUNT="${TOUTIAO_ACCOUNT:-default}"

if ! command -v toutiao-ops &>/dev/null; then
    log_error "toutiao-ops 未安装。请运行: npm install -g @openclaw-cn/toutiao-ops"
    exit 2
fi

if ! toutiao-ops auth check --account "$ACCOUNT" 2>/dev/null; then
    log_error "头条号「${ACCOUNT}」未登录"
    echo "" >&2
    echo "请运行以下命令扫码登录：" >&2
    echo "  toutiao-ops auth login --account ${ACCOUNT}" >&2
    exit 1
fi

if [ "$MODE" = "--quiet" ]; then
    echo "$ACCOUNT"
else
    log_info "头条号「${ACCOUNT}」已登录"
fi
