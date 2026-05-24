setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"
}

# curl mock: 控制 auth API 返回的 err_no
make_curl_mock() {
    local err_no="$1"
    local mock_curl="${BATS_TEST_TMPDIR}/curl"
    cat > "$mock_curl" <<MOCKEOF
#!/bin/bash
echo '{"err_no": ${err_no}, "err_msg": "mock", "data": {"user_id": "123"}}'
exit 0
MOCKEOF
    chmod +x "$mock_curl"
}

@test "auth-juejin: 无 JUEJIN_COOKIE 且无 toutiao-ops 时退出码为 1" {
    unset JUEJIN_COOKIE
    # PATH 只保留系统命令，不含 node/npm 路径 → toutiao-ops 不可达 → 策略 2 跳过
    PATH="/usr/bin:/bin" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh"
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
    # 限制 PATH 让 toutiao-ops 不可达，验证仅策略 1 失效后的行为
    PATH="/usr/bin:/bin" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh"
    [ "$status" -eq 1 ]
}

@test "auth-juejin: cookie 无效 (err_no=100) 时退出码为 1" {
    export JUEJIN_COOKIE="sessionid=forbidden;"
    make_curl_mock "100"
    PATH="/usr/bin:/bin" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh"
    [ "$status" -eq 1 ]
}

@test "auth-juejin: 全部无效时显示扫码登录指引" {
    unset JUEJIN_COOKIE
    # 不含 node/npm 路径 → toutiao-ops 不可达 → 策略 2 跳过 → 显示指引
    PATH="/usr/bin:/bin" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh"
    echo "$output" | grep -q "请扫码登录"
}

@test "auth-juejin: 指引中包含 login-juejin.sh" {
    unset JUEJIN_COOKIE
    PATH="/usr/bin:/bin" run "${BATS_TEST_DIRNAME}/../auth-juejin.sh"
    echo "$output" | grep -q "login-juejin.sh"
}
