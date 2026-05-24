# 简书 Cookie 自动续期研究

## 问题

简书 JIANSHU_COOKIE 有效期短，需频繁手动浏览器登录续期。

## 技术背景

简书基于 Ruby on Rails，认证依赖两个 Cookie：

| Cookie | 类型 | 行为 |
|--------|------|------|
| `_m7e_session` | Rails 会话 Cookie | 浏览器关闭即失效 |
| `remember_user_token` | 持久化 "记住我" Token | 跨会话保持，内嵌 bcrypt 哈希 + 时间戳 |

Rails 内置 **滑动过期 (Sliding Expiration)** 机制：
- 每次携带有效 Cookie 的请求到达时，服务器检查 token 剩余有效期
- 低于内部阈值 → 签发新 `remember_user_token`，通过 `Set-Cookie` 响应头下发
- 这套逻辑完全由后端控制，客户端只需正常发送/接收 Cookie

## 验证方法

查看 API 响应头中是否包含 `Set-Cookie`：

```bash
curl -s -D - \
  -H "Cookie: $JIANSHU_COOKIE" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
  -H "Referer: https://www.jianshu.com/" \
  "https://www.jianshu.com/author/notebooks" | head -30
```

关键行: `set-cookie: remember_user_token=...;`

## 修复方案

### 方案 A：curl cookie jar（推荐，改动最小）

在 `post-jianshu.sh` 和 `auth-jianshu.sh` 中，curl 命令加上 `-c cookie_jar.txt -b cookie_jar.txt`：

```bash
CURL_HEADERS=(
    -c /tmp/jianshu_jar.txt
    -b /tmp/jianshu_jar.txt
    ...
)
```

- curl 的 `-c` (cookie jar) 自动保存响应中的 `Set-Cookie`
- curl 的 `-b` 自动从 jar 读取 Cookie 发送请求
- 每次 API 调用即续期，无需额外逻辑

### 方案 B：Playwright 定时访问

若服务端仅在浏览器页面渲染时触发续期（而非 API 请求），需定时 headless 访问简书首页。

## 验证结论 (2026-05-24)

✅ **所有步骤通过：**

| 步骤 | 方法 | 状态 |
|------|------|------|
| GET /author/notebooks | curl | ✅ 200 |
| POST /author/notes | curl | ✅ 200 |
| PUT /author/notes/{id} | curl | ✅ 200 |
| POST publicize | curl | ✅ 200 |

**发现的关键问题：**
1. POST/PUT 需要 `accept: application/json` header，否则返回 302
2. Referer 需设为 `https://www.jianshu.com/writer` 而非 `/`
3. 文章 URL 用 `slug`（如 `4dc678bd2eba`）不是 `note_id`

**Set-Cookie 自动续期已验证：**
- 每个 API 响应都带回 `set-cookie: _m7e_session_core=...`（6h 滑动过期）
- `remember_user_token` 不每次刷新（只在临近过期时）
- curl cookie jar (`-c`/`-b`) 方案有效

**已修复文件：**
- `scripts/post-jianshu.sh` — 加 accept+referer header、cookie jar、slug URL
- `scripts/auth-jianshu.sh` — 加 accept header、修复 referer
- `scripts/lib/jianshu-session.cjs` — 改用 Playwright page 验证 cookie

**剩余问题：**
- `login-jianshu.sh` / `modeLogin()` 需要用户在 Playwright 浏览器中手动登录
- 更好的思路：提供 JIANSHU_COOKIE 环境变量，跳过 Playwright 登录流程
