setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"
}

# mock curl: output status code to stdout (模拟 curl -w "%{http_code}")
make_curl_mock() {
    local http_code="$1"
    local tmpdir="${BATS_TEST_TMPDIR}"
    printf '%s' "$http_code" > "${tmpdir}/curl_httpcode.txt"
    local mock_curl="${tmpdir}/curl"
    cat > "$mock_curl" <<MOCKEOF
#!/bin/bash
cat "${tmpdir}/curl_httpcode.txt"
exit 0
MOCKEOF
    chmod +x "$mock_curl"
}

@test "health-check: 空 URL 跳过探活，退出码 3" {
    run "${BATS_TEST_DIRNAME}/../health-check.sh" ""
    [ "$status" -eq 3 ]
}

@test "health-check: 草稿箱跳过探活，退出码 3" {
    run "${BATS_TEST_DIRNAME}/../health-check.sh" "草稿箱"
    [ "$status" -eq 3 ]
}

@test "health-check: skip 跳过探活，退出码 3" {
    run "${BATS_TEST_DIRNAME}/../health-check.sh" "skip"
    [ "$status" -eq 3 ]
}

@test "health-check: HTTP 200 返回 0" {
    make_curl_mock "200"
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../health-check.sh" "https://example.com"
    [ "$status" -eq 0 ]
}

@test "health-check: HTTP 404 返回 1" {
    make_curl_mock "404"
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../health-check.sh" "https://example.com"
    [ "$status" -eq 1 ]
}

@test "health-check: HTTP 500 返回 1" {
    make_curl_mock "500"
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../health-check.sh" "https://example.com"
    [ "$status" -eq 1 ]
}

@test "health-check: HTTP 302 重定向返回 0" {
    local tmpdir="${BATS_TEST_TMPDIR}"
    local mock_curl="${tmpdir}/curl"
    cat > "$mock_curl" <<MOCKEOF
#!/bin/bash
if echo "\$@" | grep -q "redirect_url"; then
    echo "https://redirected.example.com"
else
    echo "302"
fi
exit 0
MOCKEOF
    chmod +x "$mock_curl"

    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../health-check.sh" "https://example.com"
    [ "$status" -eq 0 ]
}

@test "health-check: curl 失败（超时）返回 2" {
    local tmpdir="${BATS_TEST_TMPDIR}"
    local mock_curl="${tmpdir}/curl"
    cat > "$mock_curl" <<MOCKEOF
#!/bin/bash
exit 1
MOCKEOF
    chmod +x "$mock_curl"

    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../health-check.sh" "https://example.com"
    [ "$status" -eq 2 ]
}
