setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"
}

make_toutiao_ops_mock() {
    local mock="${BATS_TEST_TMPDIR}/toutiao-ops"
    cat > "$mock" <<'MOCK'
#!/bin/bash
case "$1" in
    auth)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK
    chmod +x "$mock"
}

make_toutiao_ops_mock_fail() {
    local mock="${BATS_TEST_TMPDIR}/toutiao-ops"
    cat > "$mock" <<'MOCK'
#!/bin/bash
case "$1" in
    auth)
        exit 1
        ;;
    *)
        exit 1
        ;;
esac
MOCK
    chmod +x "$mock"
}

@test "auth-toutiao: toutiao-ops 未安装时退出码为 2" {
    run "${BATS_TEST_DIRNAME}/../auth-toutiao.sh"
    [ "$status" -eq 2 ]
}

@test "auth-toutiao: 已登录时退出码为 0" {
    make_toutiao_ops_mock
    export PATH="${BATS_TEST_TMPDIR}:$PATH"
    run "${BATS_TEST_DIRNAME}/../auth-toutiao.sh"
    [ "$status" -eq 0 ]
}

@test "auth-toutiao: 未登录时退出码为 1" {
    make_toutiao_ops_mock_fail
    export PATH="${BATS_TEST_TMPDIR}:$PATH"
    run "${BATS_TEST_DIRNAME}/../auth-toutiao.sh"
    [ "$status" -eq 1 ]
}

@test "auth-toutiao: --quiet 模式输出账号名" {
    make_toutiao_ops_mock
    export PATH="${BATS_TEST_TMPDIR}:$PATH"
    run "${BATS_TEST_DIRNAME}/../auth-toutiao.sh" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "default" ]
}
