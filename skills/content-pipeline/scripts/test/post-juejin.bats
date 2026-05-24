setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"

    CONTENT_FILE="${BATS_TEST_TMPDIR}/article.md"
    echo "# Test Article" > "$CONTENT_FILE"
}

@test "post-juejin: 参数不足 4 个时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../post-juejin.sh" "title"
    [ "$status" -eq 4 ]
}

@test "post-juejin: 内容文件不存在时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../post-juejin.sh" "title" "/nonexistent.md" "cat_id" "tag1"
    [ "$status" -eq 4 ]
}

@test "post-juejin: JUEJIN_COOKIE 未设置时退出码为 1" {
    unset JUEJIN_COOKIE
    run "${BATS_TEST_DIRNAME}/../post-juejin.sh" "title" "$CONTENT_FILE" "cat_id" "tag1"
    [ "$status" -eq 1 ]
}
