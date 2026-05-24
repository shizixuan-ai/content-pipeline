#!/bin/bash
# distribute.sh — 多平台分发编排引擎
#
# 编排认证 → 投递 → 探活 → 写日志的完整流程。
# 每个平台独立执行，单平台失败不影响其他平台。
#
# 用法: distribute.sh <article_root> <platform...>
#   article_root — 文章目录根路径
#   platform     — 平台名称列表（juejin wechat ...）
#
# 环境变量（平台特定）:
#   JUEJIN_CATEGORY_ID  — 掘金分类 ID（默认 6809637769959178254=后端）
#   JUEJIN_TAG_IDS      — 掘金标签 ID，逗号分隔
#   TOUTIAO_ACCOUNT     — 头条号账号名（默认 default）
#   TOUTIAO_HEADLESS    — 头条浏览器模式（默认 true，无头运行）
#
# Exit codes:
#   0 — 全部分发成功
#   1 — 部分或全部分发失败

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ARTICLE_ROOT="${1:?用法: distribute.sh <article_root> <platform...>}"
shift
PLATFORMS=("$@")

TITLE_FILE="${ARTICLE_ROOT}/brief.md"
DRAFT_MD="${ARTICLE_ROOT}/draft.md"
DRAFT_HTML="${ARTICLE_ROOT}/draft.html"
LOG_FILE="${ARTICLE_ROOT}/distribute-log.json"
COVER_IMAGE="${ARTICLE_ROOT}/cover.png"

if [ ${#PLATFORMS[@]} -eq 0 ]; then
    log_error "请指定至少一个平台: juejin wechat toutiao zhihu csdn jianshu"
    exit 1
fi

if [ ! -f "$DRAFT_MD" ] && [ ! -f "$DRAFT_HTML" ]; then
    log_error "未找到文章终稿，请先完成 writing 管线: ${ARTICLE_ROOT}"
    exit 1
fi

# ─── 从 brief.md 提取标题（首行）────────────────────────────
TITLE=""
if [ -f "$TITLE_FILE" ]; then
    TITLE=$(head -1 "$TITLE_FILE" 2>/dev/null | sed 's/^#* *//' | sed 's/^[# ]*//')
fi
if [ -z "$TITLE" ] && [ -f "$DRAFT_MD" ]; then
    TITLE=$(head -1 "$DRAFT_MD" 2>/dev/null | sed 's/^#* *//')
fi
if [ -z "$TITLE" ]; then
    log_error "无法提取文章标题，请检查 ${TITLE_FILE}"
    exit 1
fi

# ─── 幂等检查 ─────────────────────────────────────────────────
if [ -f "$LOG_FILE" ]; then
    PREV_MD5=$(python3 -c "
import sys, json
try:
    print(json.load(open(sys.argv[1])).get('article_md5', ''))
except Exception:
    pass
" "$LOG_FILE" 2>/dev/null || echo "")

    if [ -n "$PREV_MD5" ] && [ -f "$DRAFT_MD" ]; then
        CURR_MD5=$(md5 -r "$DRAFT_MD" 2>/dev/null | cut -d' ' -f1)

        if [ "$PREV_MD5" = "$CURR_MD5" ]; then
            PREV_TIME=$(python3 -c "
import sys, json
try:
    print(json.load(open(sys.argv[1])).get('distributed_at', 'unknown'))
except Exception:
    print('unknown')
" "$LOG_FILE" 2>/dev/null || echo "unknown")

            log_warn "检测到文章已在 ${PREV_TIME} 分发过（MD5 一致）"
            if [ "${DISTRIBUTE_FORCE:-}" != "1" ]; then
                log_warn "重新分发将覆盖已有分发记录。继续？(y/N)"
                read -r confirm </dev/tty || confirm="n"
                if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                    log_info "已取消分发"
                    exit 0
                fi
            fi
        fi
    fi
fi

# ─── 初始化结果集 ─────────────────────────────────────────────
RESULTS='{}'

# ─── 平台分发循环 ─────────────────────────────────────────────
for PLATFORM in "${PLATFORMS[@]}"; do
    AUTH_SCRIPT="${SCRIPT_DIR}/auth-${PLATFORM}.sh"
    POST_SCRIPT="${SCRIPT_DIR}/post-${PLATFORM}.sh"

    echo ""
    log_info "━━━ 开始分发: ${PLATFORM} ━━━"

    if [ ! -f "$POST_SCRIPT" ]; then
        log_warn "未找到投递脚本: ${POST_SCRIPT}，跳过"
        RESULTS=$(echo "$RESULTS" | "${SCRIPT_DIR}/lib/pipeline.py" record-result --platform "$PLATFORM" --status SKIP --message "post script not found")
        continue
    fi

    # --- 认证 ---
    if [ -f "$AUTH_SCRIPT" ]; then
        log_info "认证 ${PLATFORM}..."
        ACCESS_RESULT=$(bash "$AUTH_SCRIPT" --quiet 2>/dev/null) || {
            log_warn "${PLATFORM} 认证失败，跳过"
            RESULTS=$(echo "$RESULTS" | "${SCRIPT_DIR}/lib/pipeline.py" record-result --platform "$PLATFORM" --status FAIL --message "auth failed")
            continue
        }
        # 认证成功，某些脚本需在环境变量中设置凭据
        if [ "$PLATFORM" = "juejin" ]; then
            export JUEJIN_COOKIE="$ACCESS_RESULT"
        fi
        if [ "$PLATFORM" = "wechat" ]; then
            export WECHAT_ACCESS_TOKEN="$ACCESS_RESULT"
        fi
        if [ "$PLATFORM" = "zhihu" ]; then
            export ZHIHU_COOKIE="$ACCESS_RESULT"
        fi
    fi

    # --- 确定内容文件 ---
    case "$PLATFORM" in
        wechat)
            CONTENT_FILE="${ARTICLE_ROOT}/distribute/${PLATFORM}/article.html"
            [ ! -f "$CONTENT_FILE" ] && CONTENT_FILE="$DRAFT_HTML"
            COVER="${COVER_IMAGE}"
            [ ! -f "$COVER" ] && COVER=""
            ;;
        juejin)
            CONTENT_FILE="${ARTICLE_ROOT}/distribute/${PLATFORM}/article.md"
            [ ! -f "$CONTENT_FILE" ] && CONTENT_FILE="$DRAFT_MD"
            CATEGORY_ID="${JUEJIN_CATEGORY_ID:-6809637769959178254}"
            TAG_IDS="${JUEJIN_TAG_IDS:-6809640407484334093}"
            ;;
        toutiao)
            CONTENT_FILE="${ARTICLE_ROOT}/distribute/${PLATFORM}/article.md"
            [ ! -f "$CONTENT_FILE" ] && CONTENT_FILE="$DRAFT_MD"
            COVER="${COVER_IMAGE}"
            [ ! -f "$COVER" ] && COVER=""
            ;;
        csdn)
            CONTENT_FILE="${ARTICLE_ROOT}/distribute/${PLATFORM}/article.md"
            [ ! -f "$CONTENT_FILE" ] && CONTENT_FILE="$DRAFT_MD"
            ;;
        zhihu)
            CONTENT_FILE="${ARTICLE_ROOT}/distribute/${PLATFORM}/article.md"
            [ ! -f "$CONTENT_FILE" ] && CONTENT_FILE="$DRAFT_MD"
            ;;
        jianshu)
            CONTENT_FILE="${ARTICLE_ROOT}/distribute/${PLATFORM}/article.md"
            [ ! -f "$CONTENT_FILE" ] && CONTENT_FILE="$DRAFT_MD"
            ;;
        *)
            CONTENT_FILE="$DRAFT_MD"
            ;;
    esac

    if [ ! -f "$CONTENT_FILE" ]; then
        log_warn "未找到内容文件: ${CONTENT_FILE}，跳过 ${PLATFORM}"
        RESULTS=$(echo "$RESULTS" | "${SCRIPT_DIR}/lib/pipeline.py" record-result --platform "$PLATFORM" --status SKIP --message "content file not found")
        continue
    fi

    # --- 投递 ---
    log_info "投递到 ${PLATFORM}..."

    case "$PLATFORM" in
        wechat)
            POST_OUTPUT=$(bash "$POST_SCRIPT" "$TITLE" "$CONTENT_FILE" "$COVER" 2>/dev/null) || {
                exit_code=$?
                log_warn "${PLATFORM} 投递失败 (exit: ${exit_code})"
                RESULTS=$(echo "$RESULTS" | "${SCRIPT_DIR}/lib/pipeline.py" record-result --platform "$PLATFORM" --status FAIL --message "post failed with exit ${exit_code}")
                continue
            }
            MEDIA_ID=$(echo "$POST_OUTPUT" | grep "media_id:" | head -1 | awk '{print $2}')
            RESULT_URL="草稿箱"
            log_info "微信草稿已创建: media_id=${MEDIA_ID}"
            ;;
        juejin)
            if [ -z "$TAG_IDS" ]; then
                log_warn "JUEJIN_TAG_IDS 未设置，可能导致发布异常"
            fi
            POST_OUTPUT=$(bash "$POST_SCRIPT" "$TITLE" "$CONTENT_FILE" "$CATEGORY_ID" "$TAG_IDS" 2>/dev/null) || {
                exit_code=$?
                log_warn "${PLATFORM} 投递失败 (exit: ${exit_code})"
                RESULTS=$(echo "$RESULTS" | "${SCRIPT_DIR}/lib/pipeline.py" record-result --platform "$PLATFORM" --status FAIL --message "post failed with exit ${exit_code}")
                continue
            }
            RESULT_URL=$(echo "$POST_OUTPUT" | tail -1)
            log_info "掘金发布成功: ${RESULT_URL}"
            ;;
        toutiao)
            POST_OUTPUT=$(bash "$POST_SCRIPT" "$TITLE" "$CONTENT_FILE" "$COVER" 2>/dev/null) || {
                exit_code=$?
                log_warn "${PLATFORM} 投递失败 (exit: ${exit_code})"
                RESULTS=$(echo "$RESULTS" | "${SCRIPT_DIR}/lib/pipeline.py" record-result --platform "$PLATFORM" --status FAIL --message "post failed with exit ${exit_code}")
                continue
            }
            RESULT_URL=$(echo "$POST_OUTPUT" | grep "^url:" | head -1 | awk '{print $2}')
            log_info "头条发布成功: ${RESULT_URL}"
            ;;
        csdn)
            POST_OUTPUT=$(bash "$POST_SCRIPT" "$TITLE" "$CONTENT_FILE" \
                "${CSDN_TAGS:-后端}" "" "${CSDN_READ_TYPE:-public}" "${CSDN_CONTENT_TYPE:-original}" 2>/dev/null) || {
                exit_code=$?
                log_warn "${PLATFORM} 投递失败 (exit: ${exit_code})"
                RESULTS=$(echo "$RESULTS" | "${SCRIPT_DIR}/lib/pipeline.py" record-result --platform "$PLATFORM" --status FAIL --message "post failed with exit ${exit_code}")
                continue
            }
            RESULT_URL=$(echo "$POST_OUTPUT" | tail -1)
            log_info "CSDN 发布成功: ${RESULT_URL}"
            ;;
        zhihu)
            POST_OUTPUT=$(bash "$POST_SCRIPT" "$TITLE" "$CONTENT_FILE" 2>/dev/null) || {
                exit_code=$?
                log_warn "${PLATFORM} 投递失败 (exit: ${exit_code})"
                RESULTS=$(echo "$RESULTS" | "${SCRIPT_DIR}/lib/pipeline.py" record-result --platform "$PLATFORM" --status FAIL --message "post failed with exit ${exit_code}")
                continue
            }
            RESULT_URL=$(echo "$POST_OUTPUT" | tail -1)
            log_info "知乎发布成功: ${RESULT_URL}"
            ;;
        jianshu)
            POST_OUTPUT=$(bash "$POST_SCRIPT" "$TITLE" "$CONTENT_FILE" 2>/dev/null) || {
                exit_code=$?
                log_warn "${PLATFORM} 投递失败 (exit: ${exit_code})"
                RESULTS=$(echo "$RESULTS" | "${SCRIPT_DIR}/lib/pipeline.py" record-result --platform "$PLATFORM" --status FAIL --message "post failed with exit ${exit_code}")
                continue
            }
            RESULT_URL=$(echo "$POST_OUTPUT" | tail -1)
            log_info "简书发布成功: ${RESULT_URL}"
            ;;
        *)
            log_warn "不支持的平台: ${PLATFORM}"
            RESULTS=$(echo "$RESULTS" | "${SCRIPT_DIR}/lib/pipeline.py" record-result --platform "$PLATFORM" --status SKIP --message "unsupported platform")
            continue
            ;;
    esac

    # --- 探活 ---
    HEALTH_RESULT="skip"
    if [ "$PLATFORM" = "juejin" ] && [ -n "${RESULT_URL:-}" ]; then
        HEALTH_RESULT=$("${SCRIPT_DIR}/health-check.sh" "$RESULT_URL" 2>/dev/null) || true
        case "$HEALTH_RESULT" in
            0) HEALTH_MSG="200 OK"; HEALTH_STATUS="SUCCESS" ;;
            1) HEALTH_MSG="异常状态码"; HEALTH_STATUS="WARN" ;;
            2) HEALTH_MSG="超时/网络错误"; HEALTH_STATUS="WARN" ;;
            *) HEALTH_MSG="skip"; HEALTH_STATUS="SUCCESS" ;;
        esac
        log_info "探活结果: ${HEALTH_MSG}"
    fi

    # --- 记录结果 ---
    RESULTS=$(echo "$RESULTS" | "${SCRIPT_DIR}/lib/pipeline.py" record-result --platform "$PLATFORM" --status SUCCESS --url "${RESULT_URL:-}" --health-check "${HEALTH_MSG:-skip}")
done

# ─── 写分发日志 ─────────────────────────────────────────────
CURR_MD5=$(md5 -r "$DRAFT_MD" 2>/dev/null | cut -d' ' -f1 || echo "")

LOG_DATA=$(python3 -c "
import sys, json, datetime
results = json.loads(sys.argv[1])
log = {
    'article_md5': sys.argv[2],
    'distributed_at': datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S+08:00'),
    'platforms': results,
}
print(json.dumps(log, indent=2, ensure_ascii=False))
" "$RESULTS" "$CURR_MD5" 2>/dev/null)

echo "$LOG_DATA" > "$LOG_FILE"
log_info "分发日志已写入: ${LOG_FILE}"

# ─── 输出汇总 ─────────────────────────────────────────────────
echo ""
log_info "━━━ 分发汇总 ━━━"
echo "$RESULTS" | python3 -c "
import sys, json
r = json.load(sys.stdin)
for platform, info in r.items():
    status_icon = {'SUCCESS': '✓', 'FAIL': '✗', 'SKIP': '—'}
    icon = status_icon.get(info.get('status', ''), '?')
    url = info.get('url', '')
    msg = info.get('message', '')
    extra = f' ({msg})' if msg else ''
    print(f'  {icon} {platform}: {info.get(\"status\", \"UNKNOWN\")}{extra}')
    if url:
        print(f'    → {url}')
"

# 统计
TOTAL=${#PLATFORMS[@]}
SUCCESS_COUNT=$(echo "$RESULTS" | python3 -c "
import sys, json
r = json.load(sys.stdin)
print(sum(1 for v in r.values() if v.get('status') == 'SUCCESS'))
")
if [ "$SUCCESS_COUNT" -eq "$TOTAL" ]; then
    log_info "全部分发成功 (${TOTAL}/${TOTAL})"
    exit 0
else
    log_warn "分发完成: ${SUCCESS_COUNT}/${TOTAL} 成功"
    exit 1
fi
