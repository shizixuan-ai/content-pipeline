setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"
}

# curl mock: 控制 notebook 查询 API 返回的 JSON 数组
make_notebooks_mock() {
    local json="$1"
    local mock_curl="${BATS_TEST_TMPDIR}/curl"
    cat > "$mock_curl" <<MOCKEOF
#!/bin/bash
echo '$json'
exit 0
MOCKEOF
    chmod +x "$mock_curl"
}

@test "auth-jianshu: JIANSHU_COOKIE 未设置时退出码为 1" {
    unset JIANSHU_COOKIE
    run "${BATS_TEST_DIRNAME}/../auth-jianshu.sh"
    [ "$status" -eq 1 ]
}

@test "auth-jianshu: cookie 有效时退出码为 0" {
    export JIANSHU_COOKIE="sessionid=valid;"
    make_notebooks_mock '[{"id": 123, "name": "default"}]'
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-jianshu.sh"
    [ "$status" -eq 0 ]
}

@test "auth-jianshu: cookie 有效时输出 export JIANSHU_COOKIE" {
    export JIANSHU_COOKIE="sessionid=valid;"
    make_notebooks_mock '[{"id": 123, "name": "default"}]'
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-jianshu.sh"
    echo "$output" | grep -q "export JIANSHU_COOKIE"
}

@test "auth-jianshu: --quiet 输出原始 cookie 值" {
    export JIANSHU_COOKIE="sessionid=valid;"
    make_notebooks_mock '[{"id": 123, "name": "default"}]'
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-jianshu.sh" --quiet
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "sessionid=valid;"
    ! echo "$output" | grep -q "export"
}

@test "auth-jianshu: 空作品集（空数组）时 Cookie 仍有效" {
    export JIANSHU_COOKIE="sessionid=empty;"
    make_notebooks_mock '[]'
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-jianshu.sh"
    [ "$status" -eq 0 ]
}

@test "auth-jianshu: 非 JSON 响应时退出码为 1" {
    export JIANSHU_COOKIE="sessionid=expired;"
    make_notebooks_mock 'not json'
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-jianshu.sh"
    [ "$status" -eq 1 ]
}

@test "auth-jianshu: curl 失败时退出码为 1" {
    export JIANSHU_COOKIE="sessionid=valid;"
    # 不提供 curl mock → 系统 curl 会返回实际请求错误，但 PATH 中有系统 curl
    # 用空 PATH 让 curl 不可用
    PATH="/dev/null" run "${BATS_TEST_DIRNAME}/../auth-jianshu.sh"
    [ "$status" -eq 1 ]
}
