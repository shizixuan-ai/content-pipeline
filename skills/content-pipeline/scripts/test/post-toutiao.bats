setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"

    CONTENT_FILE="${BATS_TEST_TMPDIR}/article.md"
    echo "# Test Article" > "$CONTENT_FILE"
}

make_toutiao_ops_mock() {
    local mock="${BATS_TEST_TMPDIR}/toutiao-ops"
    cat > "$mock" <<'MOCK'
#!/bin/bash
case "$1" in
    auth)
        # auth check --account default
        exit 0
        ;;
    publish)
        # publish article --title ... --content-file ... --headless ...
        echo '{"success":true,"action":"published","title":"Test Article","url":"https://mp.toutiao.com/article/12345/"}'
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK
    chmod +x "$mock"
}

@test "post-toutiao: 参数不足 2 个时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../post-toutiao.sh" "title"
    [ "$status" -eq 4 ]
}

@test "post-toutiao: 内容文件不存在时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../post-toutiao.sh" "title" "/nonexistent.md"
    [ "$status" -eq 4 ]
}

@test "post-toutiao: toutiao-ops 未安装时退出码为 1" {
    run "${BATS_TEST_DIRNAME}/../post-toutiao.sh" "title" "$CONTENT_FILE"
    [ "$status" -eq 1 ]
}

@test "post-toutiao: 发布成功" {
    make_toutiao_ops_mock
    export PATH="${BATS_TEST_TMPDIR}:$PATH"
    run "${BATS_TEST_DIRNAME}/../post-toutiao.sh" "Test Article" "$CONTENT_FILE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "url:"
}

@test "post-toutiao: 封面文件不存在时警告但仍继续" {
    make_toutiao_ops_mock
    export PATH="${BATS_TEST_TMPDIR}:$PATH"
    run "${BATS_TEST_DIRNAME}/../post-toutiao.sh" "Test Article" "$CONTENT_FILE" "/nonexistent/cover.png"
    [ "$status" -eq 0 ]
}
