setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"

    CONTENT_FILE="${BATS_TEST_TMPDIR}/article.md"
    echo "# Test Article" > "$CONTENT_FILE"
}

@test "post-zhihu: 参数不足 2 个时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../post-zhihu.sh" "title"
    [ "$status" -eq 4 ]
}

@test "post-zhihu: 内容文件不存在时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../post-zhihu.sh" "title" "/nonexistent.md"
    [ "$status" -eq 4 ]
}

@test "post-zhihu: 内容为空时退出码为 4" {
    local empty_file="${BATS_TEST_TMPDIR}/empty.md"
    touch "$empty_file"
    run "${BATS_TEST_DIRNAME}/../post-zhihu.sh" "title" "$empty_file"
    [ "$status" -eq 4 ]
}
