# Platform: 稀土掘金

## Identity

name: juejin
display: 稀土掘金
homepage: https://juejin.cn

## Persona

audience: 一线研发工程师、技术架构师
mindset: 解决当下的 Bug 或学习可落地的架构方案
pain: 空洞的宏大叙事、AI 废话、浅层教程

voice:
  title_format: "技术栈 + 场景 + 结果"
  example_title: "使用 Claude Code + n8n 构建 AI Agent 工作流工程实战"
  opening: 开门见山，直接贴架构图
  code: 保留并高亮，鼓励代码块
  density: 高信息密度，允许表格和复杂排版
  taboo:
    - 综上所述
    - 显而易见
    - 众所周知

## Auth

type: cookie
source: env JUEJIN_COOKIE | agent-browser session
script: scripts/auth-juejin.sh
description: |
  有两种方式提供 Cookie（按优先级）:
  1. 环境变量 JUEJIN_COOKIE — 手动从浏览器复制 Cookie 串
  2. agent-browser session（推荐）— 扫码登录后自动持久化

  推荐使用 agent-browser session 方式:
    npm i -g agent-browser && agent-browser install
    scripts/login-juejin.sh        # 首次：扫码登录，自动保存 session
    # 之后 scripts/auth-juejin.sh 会自动从 session 提取有效 Cookie

  login-juejin.sh 使用 agent-browser 打开浏览器窗口供用户扫码，
  登录后自动持久化 Cookie（含 sessionid），支持跨进程复用。
  Cookie 过期时只需重新运行 login-juejin.sh 扫码即可。

## Format Capabilities

markdown_features:
  heading: true
  bold: true
  italic: true
  link: true
  image: true
  code_inline: true
  code_block: true
  blockquote: true
  ordered_list: true
  unordered_list: true
  table: complex
  footnotes: false
  mermaid: false
  math: false
  strikethrough: true
  task_list: false
  emoji: true

## Image Policy

policy: external-url
transform: none
description: 允许外链图片，保持原文 URL 不变

## API

publish:
  method: POST
  url: https://juejin.cn/content_api/v1/article_draft/create
  headers:
    Content-Type: application/json
    Cookie: "${JUEJIN_COOKIE}"
body:
  title: string
  mark_content: string
  brief_content: string
  category_id: string
  tag_ids: array
  edit_type: 10
  sync_to_org: false

## API (发布草稿)

publish_draft:
  method: POST
  url: https://juejin.cn/content_api/v1/article/publish
  headers:
    Content-Type: application/json
    Cookie: "${JUEJIN_COOKIE}"
body:
  draft_id: object
  sync_to_org: false

## Rate Limit

max_retries: 3
backoff: "1s, 2s, 4s"

## Limitations

- 不支持 Mermaid 流程图（需截图或移除）
- 不支持脚注语法
- 不支持数学公式
- 不支持任务清单
