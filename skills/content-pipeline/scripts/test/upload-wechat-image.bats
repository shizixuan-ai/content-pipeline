setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"

    TEST_FILE="${BATS_TEST_TMPDIR}/test.png"
    touch "$TEST_FILE"
}

# mock curl: 从预写文件返回响应体 + HTTP 码
make_curl_mock() {
    local response="$1"
    local http_code="${2:-200}"
    local tmpdir="${BATS_TEST_TMPDIR}"
    printf '%s\n' "$response" > "${tmpdir}/curl_response.txt"
    printf '%s\n' "$http_code" > "${tmpdir}/curl_httpcode.txt"
    local mock_curl="${tmpdir}/curl"
    cat > "$mock_curl" <<MOCKEOF
#!/bin/bash
cat "${tmpdir}/curl_response.txt"
printf '%s\n' "$http_code"
exit 0
MOCKEOF
    chmod +x "$mock_curl"
    echo "$mock_curl"
}

@test "upload-wechat-image: 无参数时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../upload-wechat-image.sh"
    [ "$status" -eq 4 ]
}

@test "upload-wechat-image: 图片不存在时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../upload-wechat-image.sh" "/nonexistent/path.png"
    [ "$status" -eq 4 ]
}

@test "upload-wechat-image: 图片大于 10MB 时退出码为 4" {
    local big_file="${BATS_TEST_TMPDIR}/big.png"
    dd if=/dev/zero of="$big_file" bs=1048576 count=11 2>/dev/null

    run "${BATS_TEST_DIRNAME}/../upload-wechat-image.sh" "$big_file"
    [ "$status" -eq 4 ]
}

@test "upload-wechat-image: 无 token 时退出码为 1" {
    unset WECHAT_ACCESS_TOKEN
    run "${BATS_TEST_DIRNAME}/../upload-wechat-image.sh" "$TEST_FILE"
    [ "$status" -eq 1 ]
}

@test "upload-wechat-image: 上传成功返回图片 URL" {
    export WECHAT_ACCESS_TOKEN="fake_token_123"

    local mock_curl
    mock_curl=$(make_curl_mock '{"url":"https://mmbiz.qpic.cn/xxx"}')
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../upload-wechat-image.sh" "$TEST_FILE"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "mmbiz.qpic.cn"
}

@test "upload-wechat-image: API 返回错误时退出码为 3" {
    export WECHAT_ACCESS_TOKEN="fake_token_123"

    local mock_curl
    mock_curl=$(make_curl_mock '{"errcode":40001,"errmsg":"invalid credential"}')
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../upload-wechat-image.sh" "$TEST_FILE"

    [ "$status" -eq 3 ]
}
