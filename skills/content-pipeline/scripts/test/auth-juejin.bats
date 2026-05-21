setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"
}

# curl mock: 输出 JSON 响应（auth 脚本现在解析 err_no 字段）
make_curl_mock() {
    local err_no="$1"  # 0=成功, 其他=失败
    local mock_curl="${BATS_TEST_TMPDIR}/curl"
    cat > "$mock_curl" <<MOCKEOF
#!/bin/bash
echo '{"err_no": ${err_no}, "err_msg": "mock", "data": {"user_id": "123"}}'
exit 0
MOCKEOF
    chmod +x "$mock_curl"
}

# agent-browser 返回空 cookie（模拟未登录或不可用）
make_agent_browser_empty_mock() {
    local mock_browser="${BATS_TEST_TMPDIR}/agent-browser"
    cat > "$mock_browser" <<MOCKEOF
#!/bin/bash
if [ "\$1" = "cookies" ] && [ "\$2" = "get" ] && [ "\$3" = "--json" ]; then
    echo '{"success":true,"data":{"cookies":[]}}'
elif [ "\$1" = "open" ] || [ "\$1" = "close" ]; then
    :
fi
exit 0
MOCKEOF
    chmod +x "$mock_browser"
}

# agent-browser 返回指定 cookie（模拟有效 session）
make_agent_browser_mock() {
    local cookie_json="${1:-{\"success\":true,\"data\":{\"cookies\":[{\"name\":\"sessionid\",\"value\":\"mock_session\",\"domain\":\".juejin.cn\"}]}}}"
    local mock_browser="${BATS_TEST_TMPDIR}/agent-browser"
    cat > "$mock_browser" <<MOCKEOF
#!/bin/bash
if [ "\$1" = "cookies" ] && [ "\$2" = "get" ] && [ "\$3" = "--json" ]; then
    echo '${cookie_json}'
elif [ "\$1" = "open" ] || [ "\$1" = "close" ]; then
    :
fi
exit 0
MOCKEOF
    chmod +x "$mock_browser"
}

@test "auth-juejin: 无 JUEJIN_COOKIE 且无 agent-browser 时退出码为 1" {
    unset JUEJIN_COOKIE
    PATH="${BATS_TEST_TMPDIR}" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh"
    [ "$status" -eq 1 ]
}

@test "auth-juejin: cookie 有效时退出码为 0" {
    export JUEJIN_COOKIE="sessionid=valid;"
    make_curl_mock "0"
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh"
    [ "$status" -eq 0 ]
}

@test "auth-juejin: cookie 有效时输出 export JUEJIN_COOKIE" {
    export JUEJIN_COOKIE="sessionid=valid;"
    make_curl_mock "0"
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh"
    echo "$output" | grep -q "export JUEJIN_COOKIE"
}

@test "auth-juejin: cookie 有效时 --quiet 输出原始 cookie 值" {
    export JUEJIN_COOKIE="sessionid=valid;"
    make_curl_mock "0"
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh" --quiet
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "sessionid=valid;"
    ! echo "$output" | grep -q "export"
}

@test "auth-juejin: cookie 无效 (err_no=2) 时退出码为 1" {
    export JUEJIN_COOKIE="sessionid=invalid;"
    make_curl_mock "2"
    make_agent_browser_empty_mock
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh"
    [ "$status" -eq 1 ]
}

@test "auth-juejin: cookie 无效 (err_no=100) 时退出码为 1" {
    export JUEJIN_COOKIE="sessionid=forbidden;"
    make_curl_mock "100"
    make_agent_browser_empty_mock
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh"
    [ "$status" -eq 1 ]
}

@test "auth-juejin: 全部无效时显示方案指引" {
    unset JUEJIN_COOKIE
    make_agent_browser_empty_mock
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh"
    echo "$output" | grep -q "方案 A"
}

@test "auth-juejin: 手动指引中包含 login-juejin.sh" {
    unset JUEJIN_COOKIE
    make_agent_browser_empty_mock
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh"
    echo "$output" | grep -q "login-juejin.sh"
}
