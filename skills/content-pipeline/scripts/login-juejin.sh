#!/bin/bash
# login-juejin.sh — 通过 agent-browser 扫码登录掘金并持久化 session
#
# 前置条件: agent-browser 已安装 (npm i -g agent-browser)
#
# 使用方法:
#   login-juejin.sh
#
# 流程:
#   1. 检查 agent-browser 是否可用
#   2. 打开浏览器到 juejin.cn（带界面让用户扫码）
#   3. 轮询检测登录状态
#   4. 登录成功后保存 session，测试 Cookie 有效性
#
# Exit codes:
#   0 — 登录成功，session 已持久化
#   1 — agent-browser 不可用
#   2 — 登录超时/失败

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

SESSION_NAME="juejin"
POLL_INTERVAL=3
TIMEOUT=120  # 最长等待 2 分钟

# ─── 前置检查 ────────────────────────────────────────────────
if ! command -v agent-browser &>/dev/null; then
    log_error "agent-browser 未安装，请先运行: npm i -g agent-browser && agent-browser install"
    exit 1
fi

log_info "打开掘金登录页面..."

# 打开浏览器（显示窗口，用户扫码）
AGENT_BROWSER_SESSION_NAME="$SESSION_NAME" agent-browser --headed open https://juejin.cn &

BROWSER_PID=$!

# 等待页面加载
sleep 3

log_info "请在浏览器中扫码登录掘金"
log_info "等待登录中..."

# ─── 轮询检测登录状态 ─────────────────────────────────────────
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))

    # 通过 agent-browser cookies 提取 Cookie，然后调用 auth API 验证
    COOKIE_JSON=$(AGENT_BROWSER_SESSION_NAME="$SESSION_NAME" \
        agent-browser cookies get --json 2>/dev/null || echo "")

    if [ -z "$COOKIE_JSON" ]; then
        continue
    fi

    # 提取所有 cookie 的 name=value 拼成 Cookie header
    COOKIE_STR=$(echo "$COOKIE_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    cookies = data.get('data', {}).get('cookies', [])
    pairs = [f'{c[\"name\"]}={c[\"value\"]}' for c in cookies]
    print('; '.join(pairs))
except Exception:
    pass
" 2>/dev/null || echo "")

    if [ -n "$COOKIE_STR" ]; then
        # 调用 auth API 验证
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Cookie: ${COOKIE_STR}" \
            -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
            -H "Referer: https://juejin.cn/" \
            --max-time 5 \
            "https://api.juejin.cn/user_api/v1/user/get" 2>/dev/null)

        if [ "$HTTP_CODE" = "200" ]; then
            log_info "登录成功！session 已持久化 (session-name: $SESSION_NAME)"
            log_info "可通过以下命令查看 Cookie 有效性:"
            echo "  AGENT_BROWSER_SESSION_NAME=$SESSION_NAME agent-browser cookies get"
            echo ""
            log_info "发布文章时，pipeline 会自动使用此 session"

            # 关闭浏览器
            AGENT_BROWSER_SESSION_NAME="$SESSION_NAME" agent-browser close 2>/dev/null || true

            # 验证 session 持久化
            STATE_DIR=$(agent-browser state list --json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for s in data:
        if '$SESSION_NAME' in s.get('name', '') or '$SESSION_NAME' in s.get('session', ''):
            print(s.get('path', ''))
            break
except Exception:
    pass
" 2>/dev/null || echo "")

            if [ -n "$STATE_DIR" ]; then
                log_info "Session 已保存到: $STATE_DIR"
            fi

            exit 0
        fi
    fi

    # 进度提示（每分钟一次）
    if [ $((ELAPSED % 30)) -eq 0 ]; then
        log_info "等待扫码登录... (已等待 ${ELAPSED}s)"
    fi
done

# ─── 超时处理 ─────────────────────────────────────────────────
log_error "登录超时（${TIMEOUT}s），请重试"
AGENT_BROWSER_SESSION_NAME="$SESSION_NAME" agent-browser close 2>/dev/null || true
exit 2
