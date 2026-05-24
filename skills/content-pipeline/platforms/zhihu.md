# Platform: 知乎

## Identity

name: zhihu
display: 知乎
homepage: https://www.zhihu.com

## Persona

audience: 大学生、高知群体、各行业专业从业者
mindset: 喜欢看"为什么"而非单纯的"是什么"，乐于讨论
pain: 缺乏论据的观点、无数据支持的断言

voice:
  title_format: "问题导向或多维拆解"
  example_title: "如何评价 2026 年 Claude Code 对程序员工作流的颠覆？"
  opening: 提出问题或矛盾点，引出拆解框架
  code: 保留，常用于论证观点
  density: 高，对比表格、前沿数据引用
  taboo:
    - 泛泛而谈
    - 无数据支持的结论

## Auth

type: cookie
source: env ZHIHU_COOKIE | playwright session
script: scripts/auth-zhihu.sh
description: |
  知乎使用 Cookie 认证，需要有登录状态的 Cookie 串。
  推荐使用 Playwright session 方式：
    1. scripts/login-zhihu.sh 扫码登录 → 持久化 session 到 ~/.zhihu/browser-data/
    2. scripts/auth-zhihu.sh 自动从 session 提取 Cookie
  也支持直接通过环境变量 ZHIHU_COOKIE 传入。

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
  math: true
  strikethrough: true
  task_list: false
  emoji: true

## Image Policy

policy: external-url
transform: none
description: 允许外链图片

## API

publish:
  method: POST
  url: https://www.zhihu.com/api/v4/articles
  headers:
    Content-Type: application/json
    Cookie: "${ZHIHU_COOKIE}"
  body:
    title: string
    content: string (RichText/Markdown)
    topics: string[]

## Rate Limit

max_retries: 3
backoff: "1s, 2s, 4s"

## Limitations

- 公开发布需通过知乎审核
- 对低质 AI 内容零容忍
- 知乎已使用 X-Zse-96 动态签名，纯 REST API 方案已验证不可行
- 推荐使用 Playwright 浏览器自动化方案，模拟操作知乎编辑器完成发布
