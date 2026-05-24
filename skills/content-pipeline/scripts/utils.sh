#!/bin/bash
# utils.sh — 通用函数库（日志、重试、退避）
# 被其他 scripts/ 脚本 source 使用

# 日志
log_info()  { echo "[INFO] $*" >&2; }
log_warn()  { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# 带指数退避的重试
# 用法: retry_with_backoff "command arg1 arg2" max_retries
retry_with_backoff() {
    local cmd="$1"
    local max_retries="${2:-3}"
    local attempt=1
    local delay=1

    while [ $attempt -le "$max_retries" ]; do
        if eval "$cmd"; then
            return 0
        fi
        if [ $attempt -lt "$max_retries" ]; then
            log_warn "第 $attempt 次尝试失败，${delay}s 后重试..."
            sleep "$delay"
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done

    log_error "重试 $max_retries 次后仍然失败"
    return 1
}

# 计算文件 MD5
# 用法: md5_of "file_path"
md5_of() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" | cut -d' ' -f1
    else
        md5 -r "$1" | cut -d' ' -f1
    fi
}
