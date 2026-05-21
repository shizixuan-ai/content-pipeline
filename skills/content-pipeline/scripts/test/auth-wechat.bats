setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"
}

# curl mock: token API 返回指定响应
make_curl_mock() {
    local response="$1"
    local mock_curl="${BATS_TEST_TMPDIR}/curl"
    cat > "$mock_curl" <<MOCKEOF
#!/bin/bash
echo '${response}'
exit 0
MOCKEOF
    chmod +x "$mock_curl"
}

@test "auth-wechat: 无 WECHAT_APPID 时退出码为 1" {
    unset WECHAT_APPID
    export WECHAT_SECRET="secret"
    PATH="${BATS_TEST_TMPDIR}" run "${BATS_TEST_DIRNAME}/../auth-wechat.sh"
    [ "$status" -eq 1 ]
}

@test "auth-wechat: 无 WECHAT_SECRET 时退出码为 1" {
    export WECHAT_APPID="appid"
    unset WECHAT_SECRET
    PATH="${BATS_TEST_TMPDIR}" run "${BATS_TEST_DIRNAME}/../auth-wechat.sh"
    [ "$status" -eq 1 ]
}

@test "auth-wechat: 成功获取 token 时退出码为 0" {
    export WECHAT_APPID="mock_appid"
    export WECHAT_SECRET="mock_secret"
    make_curl_mock '{"access_token":"mock_token_abc","expires_in":7200}'
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-wechat.sh"
    [ "$status" -eq 0 ]
}

@test "auth-wechat: 成功时输出 export WECHAT_ACCESS_TOKEN" {
    export WECHAT_APPID="mock_appid"
    export WECHAT_SECRET="mock_secret"
    make_curl_mock '{"access_token":"mock_token_abc","expires_in":7200}'
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-wechat.sh"
    echo "$output" | grep -q "export WECHAT_ACCESS_TOKEN"
}

@test "auth-wechat: --quiet 输出原始 token" {
    export WECHAT_APPID="mock_appid"
    export WECHAT_SECRET="mock_secret"
    make_curl_mock '{"access_token":"mock_token_abc","expires_in":7200}'
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-wechat.sh" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "mock_token_abc" ]
}

@test "auth-wechat: API 返回错误时退出码为 2" {
    export WECHAT_APPID="mock_appid"
    export WECHAT_SECRET="mock_secret"
    make_curl_mock '{"errcode":40013,"errmsg":"invalid appid"}'
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../auth-wechat.sh"
    [ "$status" -eq 2 ]
}
