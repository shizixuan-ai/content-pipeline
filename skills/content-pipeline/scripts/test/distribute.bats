setup() {
    . "${BATS_TEST_DIRNAME}/../utils.sh"
    TEST_DIR="${BATS_TEST_TMPDIR}/article"
    mkdir -p "$TEST_DIR"
    echo "# 测试文章标题" > "$TEST_DIR/brief.md"
    printf '%s\n' '# 测试文章标题' '' '内容' > "$TEST_DIR/draft.md"
    printf '%s\n' '<h1>测试文章标题</h1><p>内容</p>' > "$TEST_DIR/draft.html"
}

make_curl_mock() {
    local mock="${BATS_TEST_TMPDIR}/curl"
    cat > "$mock" <<'MOCK'
#!/bin/bash
has_w=0; for a in "$@"; do echo "$a"|grep -q "%{http_code}" && has_w=1; done
o() { echo "$1"; [ "$has_w" = "1" ] && echo "200"; }
for a in "$@"; do
  case "$a" in
    *cgi-bin/token*) o '{"access_token":"mock","expires_in":7200}'; exit 0 ;;
    *cgi-bin/draft/add*) o '{"media_id":"mock_draft_123"}'; exit 0 ;;
    *cgi-bin/material/add_material*) o '{"media_id":"mock_cover"}'; exit 0 ;;
    *cgi-bin/media/uploadimg*) o '{"url":"https://mmbiz.qpic.cn/t"}'; exit 0 ;;
  esac
done
o '{}'; exit 0
MOCK
    chmod +x "$mock"
}

@test "distribute: 无文章目录时退出码为 1" {
    run "${BATS_TEST_DIRNAME}/../distribute.sh" "/nonexistent" "juejin"
    [ "$status" -eq 1 ]
}

@test "distribute: 无平台参数时退出码为 1" {
    run "${BATS_TEST_DIRNAME}/../distribute.sh" "$TEST_DIR"
    [ "$status" -eq 1 ]
}

@test "distribute: 平台脚本不存在时跳过" {
    export WECHAT_APPID="mock" WECHAT_SECRET="mock"
    make_curl_mock
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../distribute.sh" "$TEST_DIR" "nonexistent_platform"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "跳过"
}

@test "distribute: 微信分发成功" {
    export WECHAT_APPID="mock" WECHAT_SECRET="mock"
    touch "$TEST_DIR/cover.png"
    make_curl_mock
    PATH="${BATS_TEST_TMPDIR}:$PATH" run "${BATS_TEST_DIRNAME}/../distribute.sh" "$TEST_DIR" "wechat"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "全部分发成功"
}
