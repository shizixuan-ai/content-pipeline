setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"
}

# curl mock: 支持 -w 输出 HTTP 状态码
make_curl_mock() {
    local mock_curl="${BATS_TEST_TMPDIR}/curl"
    cat > "$mock_curl" <<'MOCKEOF'
#!/bin/bash
# 检测是否有 -w %{http_code} 标志
has_w=0
for arg in "$@"; do
    if echo "$arg" | grep -q "%{http_code}"; then
        has_w=1
        break
    fi
done

output_body() {
    local body="$1"
    echo "$body"
    if [ "$has_w" = "1" ]; then
        echo "200"
    fi
}

for arg in "$@"; do
    case "$arg" in
        *cgi-bin/token*)
            output_body '{"access_token":"mock_token_abc","expires_in":7200}'
            exit 0
            ;;
        *cgi-bin/media/uploadimg*)
            output_body '{"url":"https://mmbiz.qpic.cn/test"}'
            exit 0
            ;;
        *cgi-bin/material/add_material*)
            output_body '{"media_id":"mock_cover_id","url":"https://mmbiz.qpic.cn/cover"}'
            exit 0
            ;;
        *cgi-bin/draft/add*)
            output_body '{"media_id":"mock_draft_123"}'
            exit 0
            ;;
    esac
done
output_body '{}'
exit 0
MOCKEOF
    chmod +x "$mock_curl"
}

@test "post-wechat: 参数不足 2 个时退出码为 4" {
    export WECHAT_APPID="mock_appid"
    export WECHAT_SECRET="mock_secret"
    make_curl_mock
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../post-wechat.sh" "只有标题"
    [ "$status" -eq 4 ]
}

@test "post-wechat: 内容文件不存在时退出码为 4" {
    export WECHAT_APPID="mock_appid"
    export WECHAT_SECRET="mock_secret"
    make_curl_mock
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../post-wechat.sh" "标题" "/nonexistent/file.html"
    [ "$status" -eq 4 ]
}

@test "post-wechat: 认证失败时退出码为 1" {
    unset WECHAT_APPID
    make_curl_mock
    # 需要先创建内容文件，因为文件检查在认证之前
    echo "<html><body>内容</body></html>" > "${BATS_TEST_TMPDIR}/content.html"
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../post-wechat.sh" "标题" "${BATS_TEST_TMPDIR}/content.html"
    [ "$status" -eq 1 ]
}

@test "post-wechat: 成功创建草稿时退出码为 0" {
    export WECHAT_APPID="mock_appid"
    export WECHAT_SECRET="mock_secret"
    make_curl_mock

    cat > "${BATS_TEST_TMPDIR}/content.html" <<'EOF'
<!DOCTYPE html>
<html><body>
<h1>测试文章</h1>
<p>这是文章内容。</p>
</body></html>
EOF
    # 创建测试封面图
    touch "${BATS_TEST_TMPDIR}/cover.png"

    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../post-wechat.sh" \
        "测试文章" "${BATS_TEST_TMPDIR}/content.html" "${BATS_TEST_TMPDIR}/cover.png"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "media_id:"
}
