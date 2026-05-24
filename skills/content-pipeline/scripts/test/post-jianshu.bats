setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"

    CONTENT_FILE="${BATS_TEST_TMPDIR}/article.md"
    echo "# Test Article" > "$CONTENT_FILE"
}

# curl mock: 依次处理 4 步 API 的响应
make_curl_mock() {
    local notebooks_response="$1"  # Step 1: GET /author/notebooks
    local create_response="$2"     # Step 2: POST /author/notes
    local update_code="$3"         # Step 3: PUT 返回的 HTTP code
    local publish_code="$4"        # Step 4: POST /publicize 返回的 HTTP code

    local mock_curl="${BATS_TEST_TMPDIR}/curl"
    cat > "$mock_curl" <<MOCKEOF
#!/bin/bash

# 从参数分辨是哪个请求
if echo "\$*" | grep -q "/author/notebooks" && [ "\$1" != "-s" ]; then
    # curl 多参数，-s 可能在任意位置
    :
fi

# 用 URL 区分请求
for arg in "\$@"; do
    case "\$arg" in
        */author/notebooks)
            echo '$notebooks_response'
            exit 0
            ;;
        */author/notes)
            # Step 2 是 POST，Step 3 是 PUT
            echo '$create_response'
            if [ -n "$update_code" ]; then
                # 如果有 update_code 参数，下一个 curl 是 step 3
                exit 0
            fi
            exit 0
            ;;
        */publicize)
            echo ""
            exit 0
            ;;
    esac
done

# 默认行为
echo ""
exit 0
MOCKEOF
    chmod +x "$mock_curl"
}

@test "post-jianshu: 参数不足 2 个时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../post-jianshu.sh" "title"
    [ "$status" -eq 4 ]
}

@test "post-jianshu: 内容文件不存在时退出码为 4" {
    run "${BATS_TEST_DIRNAME}/../post-jianshu.sh" "title" "/nonexistent.md"
    [ "$status" -eq 4 ]
}

@test "post-jianshu: JIANSHU_COOKIE 未设置时退出码为 1" {
    unset JIANSHU_COOKIE
    run "${BATS_TEST_DIRNAME}/../post-jianshu.sh" "title" "$CONTENT_FILE"
    [ "$status" -eq 1 ]
}

@test "post-jianshu: 内容为空时退出码为 4" {
    export JIANSHU_COOKIE="sessionid=valid;"
    local empty_file="${BATS_TEST_TMPDIR}/empty.md"
    touch "$empty_file"
    run "${BATS_TEST_DIRNAME}/../post-jianshu.sh" "title" "$empty_file"
    [ "$status" -eq 4 ]
}
