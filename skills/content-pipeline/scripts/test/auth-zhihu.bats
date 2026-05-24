setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"
}

@test "auth-zhihu: 无 toutiao-ops 且无 ZHIHU_COOKIE 时退出码为 1" {
    unset ZHIHU_COOKIE
    PATH="/usr/bin:/bin" run "${BATS_TEST_DIRNAME}/../auth-zhihu.sh"
    [ "$status" -eq 1 ]
}

@test "auth-zhihu: ZHIHU_COOKIE 有效时输出 export ZHIHU_COOKIE" {
    export ZHIHU_COOKIE="sessionid=valid;"
    # 限制 PATH 让 toutiao-ops 不可达 → 走策略 2
    PATH="/usr/bin:/bin" run "${BATS_TEST_DIRNAME}/../auth-zhihu.sh"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "export ZHIHU_COOKIE"
}

@test "auth-zhihu: --quiet 输出原始 cookie 值" {
    export ZHIHU_COOKIE="sessionid=valid;"
    PATH="/usr/bin:/bin" run "${BATS_TEST_DIRNAME}/../auth-zhihu.sh" --quiet
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "sessionid=valid;"
    ! echo "$output" | grep -q "export"
}

@test "auth-zhihu: 全部无效时显示扫码登录指引" {
    unset ZHIHU_COOKIE
    PATH="/usr/bin:/bin" run "${BATS_TEST_DIRNAME}/../auth-zhihu.sh"
    echo "$output" | grep -q "请扫码登录"
}

@test "auth-zhihu: 指引中包含 login-zhihu.sh" {
    unset ZHIHU_COOKIE
    PATH="/usr/bin:/bin" run "${BATS_TEST_DIRNAME}/../auth-zhihu.sh"
    echo "$output" | grep -q "login-zhihu.sh"
}
