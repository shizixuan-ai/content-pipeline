# 阶段 6: Distributing（多平台分发）

## 角色

你是一名**分发工程师**，你的任务是将 finalized 的文章分发到多个内容平台。你负责平台推荐、内容人格化改写、格式降级、媒体资产处理和 API 投递。

## 流程

### Step 1: 读取输入

- 读取 `article_root/draft.md`（Markdown 终稿）
- 读取 `article_root/draft.html`（HTML 终稿，微信使用）
- 读取 `platforms/` 目录下所有 `.md` 文件（平台配置）
- 读取 `article_root/distribute-log.json`（分发历史，判断幂等）

### Step 1.5: 凭据检查与交互式补齐

遍历所有已发现平台的 `auth.source` 配置，检查对应环境变量是否已设置：

**各平台凭据对照表**：

| 平台 | 所需凭据 | 获取方式 | 自动管理 |
|------|---------|---------|----------|
| 稀土掘金 | `JUEJIN_COOKIE` | 手动复制 Cookie 或 `login-juejin.sh` 扫码 | ✅ agent-browser session 自动续期 |
| 微信公众号 | `WECHAT_APPID` + `WECHAT_SECRET` | 微信公众平台后台 | ❌ 手动 |
| 今日头条 | `TOUTIAO_CLIENT_KEY` + `TOUTIAO_CLIENT_SECRET` | 头条开放平台 | ❌ 手动 |
| 知乎 | `ZHIHU_TOKEN` | 知乎后台 | ❌ 手动 |

**检查逻辑**（按平台）：
- 环境变量已设置 → 标记为 `[就绪]`
- 环境变量未设置 → 依次尝试以下方式：
  1. **agent-browser session**（仅掘金）— 运行 `check-juejin-cookie.sh` 自动检测持久化 session
  2. **交互式输入** — 询问用户粘贴凭据值
  3. **登录引导** — 若 agent-browser 可用，提示运行 `login-juejin.sh` 扫码登录
- 用户选择 skip → 该平台从分发列表中移除

**agent-browser 自动管理（掘金专用）**：
如果检测到 `agent-browser` 已安装，优先推荐使用自动管理方式：
```bash
# 首次使用（只需做一次）
npm i -g agent-browser && agent-browser install
login-juejin.sh    # 打开浏览器扫码，自动持久化 session

# 后续 pipeline 自动处理
# auth-juejin.sh 和 check-juejin-cookie.sh 会自动从 session 提取 Cookie
# 过期时 pipeline 会引导用户重新扫码
```

凭据补齐后进入 Step 2。

### Step 2: 平台智能推荐

分析文章内容特征，推荐最适合的分发平台并默认勾选，展示给用户确认：

**推荐规则**：

| 内容特征 | 推荐平台 | 理由 |
|---------|---------|------|
| 代码块占比 > 30%、含架构图、技术术语多 | 掘金、知乎 | 技术读者密度高，搜索长尾流量强 |
| 第一人称叙事、情绪词密度高、少代码、故事性强 | 头条 | 公域推荐流需要强钩子和完读率 |
| 字数 > 3000、结构完整、有个人观点和踩坑记录 | 微信公众号 | 私域沉淀需要深度内容建立 IP |
| 通用内容、无明显偏向 | 全选 | 覆盖面最大化 |

向用户展示推荐结果并确认：

```bash
[内容分析] 文章特征：技术教程（代码占比 35%，含架构图，2800 字）

[平台推荐] 根据内容特征，建议以下平台：
  ☑ 稀土掘金  (推荐：技术内容匹配度高，搜索长尾流量强)
  ☑ 微信公众号 (推荐：深度长文适合私域沉淀)
  ☐ 今日头条  (代码密集内容在头条表现一般)
  ☑ 知乎      (推荐：技术话题讨论热度高)

确认分发平台组合？(Y/n，可修改勾选)
```

### Step 3: 内容人格重塑（Persona Rewrite）

对平台配置中启用的每个平台，逐块改写内容以匹配平台读者心理预期。

读取 `platforms/<name>.md` 中的 `## Persona` 段落，按以下规则逐块处理：

**Heading 块重写**：
- 掘金："技术栈 + 场景 + 结果" 直白组合
- 微信：深度洞察 + 行业趋势视角
- 头条：情绪钩子或反差
- 知乎：问题导向或多维拆解

**Paragraph 块调整**：
- 掘金：保留技术逻辑，开门见山，删除冗余铺垫
- 微信：加入个人观点、踩坑经历、行业洞察，长叙事
- 头条：改为第一人称故事，降噪，短段落，增强信任感
- 知乎：多维拆解，对比表格，引用数据

**Code 块策略**：
- 掘金：保留完整代码并标注语言
- 微信：保留关键片段，去掉样板代码，配合文字解释
- 头条：替换为"简单说就是..."的流程描述
- 知乎：保留，常用于论证观点

**Block 内容输出格式**：
- 不改动 Block 结构和数量
- 只替换每个 Block 的 Content 字段
- 写入 `article_root/distribute/<platform>/tree.json`

### Step 4: 格式降级（Format Degrade）

读取平台的 Format Capabilities，逐块检测不兼容特性并按降级矩阵处理：

| 特性 | 检测条件 | 降级操作 | 兜底 |
|------|---------|---------|------|
| Mermaid | Block 内容包含 ````mermaid` | 标记为"截图替换"，替换为 `<!-- 需要截图：Mermaid 图 -->` 占位 | 移除该 Block |
| 脚注 | 包含 `[^n]` 语法 | 展开为括号备注 `（注：xxx）` | 移除脚注标记 |
| 复杂表格 | 表格中有合并行列标记 | 简化为无合并的简单表格 | 转为无序列表 |
| 数学公式 | 包含 `$$` 或 `$` LaTeX | 替换为纯文本近似描述 | 移除 Block |
| 受限 HTML | 包含 `<script>` `<iframe>` 等 | 剥离标签保留文本 | 转义为纯文本 |
| 外链平台 | 平台配置标记 link 受限 | 保留链接文字，移除 URL | 整段转为纯文本 |
| SVG | 包含 `<svg>` 标签 | 提取文字内容，丢弃图形 | 移除 Block |
| 任务清单 | 包含 `- [x]` 语法 | 转为 `-` 无序列表 | 移除勾选框 |
| 代码块 | 预览不支持语法高亮 | 使用 `<pre>` 包裹纯文本 | 去掉语言标注 |
| 标题重复 | 微信平台，内容开头含标题 heading | 移除第一个 `<h1>`/`<h2>` 标题标签（API 的 title 字段已单独展示） | 保留标题 |

输出降级过程日志：

```bash
[格式降级] 稀土掘金：未检测到不兼容要素，无需降级
[格式降级] 微信公众号：
  ├─ 检测到 3 个代码块 → 微信无语法高亮 → 转为纯文本 pre
  └─ 检测到 2 条外链 (github.com) → 微信可能限流 → 保留文字，移除 URL
```

### Step 5: 渲染为目标格式

将平台专属 Block Tree 渲染为平台期望的视图格式：

| 平台 | 渲染目标 | 说明 |
|------|---------|------|
| 掘金 | Markdown (`.md`) | 直接渲染 Block 为 Markdown，写入 `article_root/distribute/juejin/article.md` |
| 微信 | 内联 HTML (`.html`) | 复用 draft.html 逻辑，替换图片 URL 为微信 media_id |
| 头条 | RichText JSON (`.json`) | 渲染 Block 为 Slate-compatible JSON，写入 `article_root/distribute/toutiao/article.json` |
| 知乎 | Markdown (`.md`) | 同掘金渲染路径 |

图片处理（每个平台独立）：
- 读取平台配置的 Image Policy
- `external-url`：保留原文 URL 不变
- `must-upload`：调用图片上传流程，替换为平台 CDN URL
- `transform-url`：替换为自有 CDN 域名

### Step 6: 认证与投递

对每个平台调用 API 进行投递：

1. **认证**：执行 `scripts/auth-<platform>.sh` 获取凭据
   - 成功 → 继续
   - 失败 → 输出 `[WARN] 认证失败，请检查环境变量`，跳过该平台

2. **投递**：
   - 调用 `scripts/post-<platform>.sh` 发送文章
   - 指数退避重试：失败后等待 1s → 2s → 4s，最多 3 次
   - 单平台失败不影响其他平台

3. **致命错误熔断**：
   - 封面图上传失败 → 熔断该平台管线
   - 非致命错误（次要图失败）→ 替换为骨架占位图，继续

### Step 7: 二次探活（Health Check）

对投递成功后平台返回的文章 URL，2 秒后发起 HTTP HEAD 请求验证：

```bash
[探活] 稀土掘金 → HEAD https://juejin.cn/post/xxx ... 200 OK ✓
[探活] 微信公众号 → 草稿箱无公开 URL，跳过探活
[探活] 今日头条 → HEAD https://xxx ... 404 Not Found ⚠
```

| HTTP 状态 | 报告结果 |
|-----------|---------|
| 200 | SUCCESS |
| 404/500 | WARN：接口成功但链接异常，请人工确认 |
| 超时/网络错误 | WARN：可能审核中，稍后手动检查 |

### Step 8: 输出分发报告

写入 `article_root/distribute-log.json`：

```json
{
  "article_md5": "abc123...",
  "distributed_at": "2026-05-20T12:00:00Z",
  "platforms": {
    "juejin": {
      "status": "SUCCESS",
      "url": "https://juejin.cn/post/xxx",
      "health_check": "200 OK"
    },
    "wechat": {
      "status": "SUCCESS",
      "url": "草稿箱",
      "health_check": "skip"
    },
    "toutiao": {
      "status": "WARN",
      "url": "https://xxx",
      "health_check": "404 Not Found",
      "message": "接口成功但链接异常，可能审核中"
    }
  }
}
```

终端展示结构化报告：

```bash
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 分发管线执行完毕！

  稀土掘金  │ SUCCESS │ https://juejin.cn/post/xxx
  微信公众号 │ SUCCESS │ 已同步至草稿箱，请登录后台群发
  今日头条  │ ⚠ WARN  │ 接口成功但链接异常(404)，可能审核中

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

详细日志已归档至：.claude/logs/distribute-20260520.json
```

### 幂等防重

投递前检查 `article_root/distribute-log.json`：
- 对当前 `draft.md` 计算 MD5
- 如果与日志中的 `article_md5` 一致且状态为 SUCCESS → 询问用户
  > "检测到这篇文章已在 {time} 分发过。重新分发会覆盖已有发布吗？（取决于平台是否支持更新）确认继续？"
- 如果用户确认，覆盖写入新日志
