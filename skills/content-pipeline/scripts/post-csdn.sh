#!/bin/bash
# post-csdn.sh — 发布文章到 CSDN
#
# 使用 HMAC-SHA256 签名认证 + Cookie
# 图片需上传到 CSDN OSS，不支持外链
#
# 用法: post-csdn.sh <title> <content_file> [tags] [categories] [read_type] [content_type]
#   title        — 文章标题
#   content_file — Markdown 文件路径
#   tags         — 标签，逗号分隔（可选，默认 "后端"）
#   categories   — 分类，逗号分隔（可选）
#   read_type    — 阅读权限: public|private|read_need_pay|read_need_vip（默认 public）
#   content_type — 文章类型: original|reproduced|translated（默认 original）
#
# Exit codes:
#   0 — 发布成功
#   1 — 认证失败（Cookie 无效）
#   2 — API 错误
#   3 — 网络错误
#   4 — 参数错误

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ─── 参数校验 ────────────────────────────────────────────────
if [ $# -lt 2 ]; then
    log_error "用法: post-csdn.sh <title> <content_file> [tags] [categories] [read_type] [content_type]"
    exit 4
fi

TITLE="$1"
CONTENT_FILE="$2"
TAGS="${3:-后端}"
CATEGORIES="${4:-}"
READ_TYPE="${5:-public}"
CONTENT_TYPE="${6:-original}"
COOKIE="${CSDN_COOKIE:-}"

if [ ! -f "$CONTENT_FILE" ]; then
    log_error "内容文件不存在: $CONTENT_FILE"
    exit 4
fi

if [ ! -s "$CONTENT_FILE" ]; then
    log_error "内容文件为空: $CONTENT_FILE"
    exit 4
fi

# ─── 自动发布 ────────────────────────────────────────────────
log_info "启动浏览器自动发布..."
log_info "标签: ${TAGS}"

node "${SCRIPT_DIR}/lib/csdn-session.cjs" publish "$TITLE" "$CONTENT_FILE" "$TAGS" 2>&1
EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
    log_error "CSDN 发布失败 (exit: ${EXIT_CODE})"
    exit 2
fi

exit 0
