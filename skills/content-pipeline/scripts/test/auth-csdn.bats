setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"
}

# curl mock
make_curl_mock() {
    local http_code="$1"
    local body="${2:-{\"code\":200}}"
    local mock_curl="${BATS_TEST_TMPDIR}/curl"
    cat > "$mock_curl" <<MOCKEOF
#!/bin/bash
# 如果 URL 包含 getUserInfo → auth 验证
if echo "\$@" | grep -q "getUserInfo"; then
    echo "$body"
    echo "$http_code"
    exit 0
fi
# 默认行为
echo '{}'
echo "200"
exit 0
MOCKEOF
    chmod +x "$mock_curl"
}

@test "auth-csdn: CSDN_COOKIE 未设置时退出码为 1" {
    unset CSDN_COOKIE
    run "${BATS_TEST_DIRNAME}/../auth-csdn.sh"
    [ "$status" -eq 1 ]
}

@test "auth-csdn: cookie 有效时退出码为 0" {
    export CSDN_COOKIE="sessionid=valid;"
    make_curl_mock "200"
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-csdn.sh"
    [ "$status" -eq 0 ]
}

@test "auth-csdn: cookie 有效时输出 export CSDN_COOKIE" {
    export CSDN_COOKIE="sessionid=valid;"
    make_curl_mock "200"
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-csdn.sh"
    echo "$output" | grep -q "export CSDN_COOKIE"
}

@test "auth-csdn: --quiet 输出原始 cookie 值" {
    export CSDN_COOKIE="sessionid=valid;"
    make_curl_mock "200"
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-csdn.sh" --quiet
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "sessionid=valid;"
    ! echo "$output" | grep -q "export"
}

@test "auth-csdn: cookie 无效（非 200）时退出码为 1" {
    export CSDN_COOKIE="sessionid=invalid;"
    make_curl_mock "401"
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-csdn.sh"
    [ "$status" -eq 1 ]
}

@test "auth-csdn: curl 失败时退出码为 1" {
    export CSDN_COOKIE="sessionid=valid;"
    run "${BATS_TEST_DIRNAME}/../auth-csdn.sh"
    [ "$status" -eq 1 ]
}
