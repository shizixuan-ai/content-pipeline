setup() {
    # shellcheck source=../utils.sh
    . "${BATS_TEST_DIRNAME}/../utils.sh"
}

@test "retry_with_backoff: 命令成功时不重试，返回 0" {
    run retry_with_backoff "true" 3
    [ "$status" -eq 0 ]
}

@test "retry_with_backoff: 命令始终失败，重试 3 次后返回非零" {
    run retry_with_backoff "false" 3
    [ "$status" -ne 0 ]
}

@test "retry_with_backoff: 命令第 2 次成功，应不再重试" {
    local count_file
    count_file=$(mktemp)
    echo "0" > "$count_file"

    run retry_with_backoff "
        c=\$(cat \"$count_file\")
        c=\$((c + 1))
        echo \"\$c\" > \"$count_file\"
        [ \"\$c\" -ge 2 ]
    " 3

    [ "$status" -eq 0 ]
    local final_count
    final_count=$(cat "$count_file")
    [ "$final_count" -eq 2 ]
    rm -f "$count_file"
}

@test "md5_of: 计算文件 MD5 值正确" {
    local tmp_file
    tmp_file=$(mktemp)
    echo -n "hello world" > "$tmp_file"

    run md5_of "$tmp_file"

    [ "$status" -eq 0 ]
    # "hello world" 的 MD5 = 5eb63bbbe01eeed093cb22bb8f5acdc3
    [ "$output" = "5eb63bbbe01eeed093cb22bb8f5acdc3" ]
    rm -f "$tmp_file"
}

@test "md5_of: 空文件 MD5 正确" {
    local tmp_file
    tmp_file=$(mktemp)
    : > "$tmp_file"

    run md5_of "$tmp_file"

    [ "$status" -eq 0 ]
    # 空文件的 MD5 = d41d8cd98f00b204e9800998ecf8427e
    [ "$output" = "d41d8cd98f00b204e9800998ecf8427e" ]
    rm -f "$tmp_file"
}
