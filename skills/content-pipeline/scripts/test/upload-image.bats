setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"

    TEST_FILE="${BATS_TEST_TMPDIR}/test.png"
    touch "$TEST_FILE"
}

# 创建一个 mock curl，模拟 -w "\n%{http_code}" 行为
# usage: make_curl_mock "response_body" [http_code]
# 创建一个 mock curl，模拟 curl -s -w "\n%{http_code}" 行为
# 输出: <response_body>\n<http_code>
make_curl_mock() {
    local response="$1"
    local http_code="${2:-200}"
    local tmpdir="${BATS_TEST_TMPDIR}"
    # 写入响应体（带换行）+ HTTP 码，模拟 -w "\n%{http_code}"
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

@test "upload-image: 无参数时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../upload-image.sh"
    [ "$status" -eq 4 ]
}

@test "upload-image: 只有一个参数时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../upload-image.sh" "wechat"
    [ "$status" -eq 4 ]
}

@test "upload-image: 图片不存在时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../upload-image.sh" "wechat" "/nonexistent/path.png"
    [ "$status" -eq 4 ]
}

@test "upload-image: 图片大于 10MB 时退出码为 4" {
    # 创建一个超过 10MB 的文件
    local big_file="${BATS_TEST_TMPDIR}/big.png"
    dd if=/dev/zero of="$big_file" bs=1048576 count=11 2>/dev/null

    run "${BATS_TEST_DIRNAME}/../upload-image.sh" "wechat" "$big_file"
    [ "$status" -eq 4 ]
}

@test "upload-image: 掘金支持外链，返回 external" {
    run "${BATS_TEST_DIRNAME}/../upload-image.sh" "juejin" "$TEST_FILE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "external"
}

@test "upload-image: 头条支持外链，返回 external" {
    run "${BATS_TEST_DIRNAME}/../upload-image.sh" "toutiao" "$TEST_FILE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "external"
}

@test "upload-image: 知乎支持外链，返回 external" {
    run "${BATS_TEST_DIRNAME}/../upload-image.sh" "zhihu" "$TEST_FILE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "external"
}

@test "upload-image: 微信无 token 时退出码为 1" {
    unset WECHAT_ACCESS_TOKEN
    run "${BATS_TEST_DIRNAME}/../upload-image.sh" "wechat" "$TEST_FILE"
    [ "$status" -eq 1 ]
}

@test "upload-image: 微信上传成功返回图片 URL" {
    export WECHAT_ACCESS_TOKEN="fake_token_123"

    local mock_curl
    mock_curl=$(make_curl_mock '{"url":"https://mmbiz.qpic.cn/xxx"}')
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../upload-image.sh" "wechat" "$TEST_FILE"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "mmbiz.qpic.cn"
}

@test "upload-image: 微信上传失败时退出码为 3" {
    export WECHAT_ACCESS_TOKEN="fake_token_123"

    # mock curl: 返回错误 JSON（无 media_id）
    local mock_curl
    mock_curl=$(make_curl_mock '{"errcode":40001,"errmsg":"invalid credential"}')
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../upload-image.sh" "wechat" "$TEST_FILE"

    [ "$status" -eq 3 ]
}
