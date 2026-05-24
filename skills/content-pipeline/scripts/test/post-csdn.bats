setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"

    CONTENT_FILE="${BATS_TEST_TMPDIR}/article.md"
    echo "# Test Article" > "$CONTENT_FILE"
}

@test "post-csdn: 参数不足 2 个时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../post-csdn.sh" "title"
    [ "$status" -eq 4 ]
}

@test "post-csdn: 内容文件不存在时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../post-csdn.sh" "title" "/nonexistent.md"
    [ "$status" -eq 4 ]
}

@test "post-csdn: CSDN_COOKIE 未设置时退出码为 1" {
    unset CSDN_COOKIE
    run "${BATS_TEST_DIRNAME}/../post-csdn.sh" "title" "$CONTENT_FILE"
    [ "$status" -eq 1 ]
}

@test "post-csdn: 内容为空时退出码为 4" {
    export CSDN_COOKIE="sessionid=valid;"
    local empty_file="${BATS_TEST_TMPDIR}/empty.md"
    touch "$empty_file"
    run "${BATS_TEST_DIRNAME}/../post-csdn.sh" "title" "$empty_file"
    [ "$status" -eq 4 ]
}

@test "post-csdn: pipeline.py csdn-sign 生成有效签名" {
    run python3 "${BATS_TEST_DIRNAME}/../lib/pipeline.py" csdn-sign
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert 'x-ca-key' in data
assert 'x-ca-nonce' in data
assert 'x-ca-timestamp' in data
assert 'x-ca-signature' in data
assert data['x-ca-key'] == '260196572'
assert len(data['x-ca-nonce']) > 0
assert len(data['x-ca-signature']) > 0
"
}
