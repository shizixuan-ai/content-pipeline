# Platform: CSDN

## Identity

name: csdn
display: CSDN
homepage: https://blog.csdn.net

## Persona

audience: 国内开发者、技术初学者、IT 从业者
mindset: 遇到问题找解决方案，关注职业发展
pain: 纯翻译文、无实践验证的教程、广告文

voice:
  title_format: "技术栈 + 问题 + 解决方案"
  example_title: "Spring Boot 集成 Redis 实现分布式缓存完整指南"
  opening: 直接给出问题和解决思路
  code: 保留并高亮，鼓励完整可运行代码
  density: 中，允许大段代码但需配合解释
  taboo:
    - 广告推荐
    - 无实质内容的总结

## Auth

type: cookie
source: env CSDN_COOKIE
script: scripts/auth-csdn.sh
description: |
  CSDN Cookie（需含 UserToken/UserInfo/SESSION 等 httpOnly 字段）。
  无法通过 document.cookie 获取，需通过浏览器 DevTools → Network 复制完整 Cookie 串。
  登录方式：
    1. 浏览器打开 https://blog.csdn.net 并登录
    2. 打开 DevTools → Network → 刷新 → 点任意请求 → 复制请求头中的 Cookie 值
    3. 设为环境变量: export CSDN_COOKIE="...long cookie string..."

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
  table: basic
  footnotes: false
  mermaid: false
  math: false
  strikethrough: true
  task_list: false
  emoji: true

## Image Policy

policy: must-upload
transform: replace-url
upload_api: POST https://bizapi.csdn.net/resource-api/v1/image/direct/upload/signature
description: 上传到华为云 OBS（CSDN 素材库），替换 Markdown 中的图片 URL

## API

publish:
  method: POST
  url: "https://bizapi.csdn.net/blog-console-api/v3/mdeditor/saveArticle"
  headers:
    Content-Type: application/json;charset=UTF-8
    Cookie: "${CSDN_COOKIE}"
    x-ca-key: "260196572"
    x-ca-signature: HMAC-SHA256
    x-ca-nonce: UUID
    x-ca-timestamp: timestamp
  body:
    title: string
    markdowncontent: string
    content: string
    tags: string (逗号分隔)
    readType: "public | private | read_need_pay | read_need_vip"
    type: "original | reproduced | translated"
    categories: string (逗号分隔)
    coverImages: string[]
    status: 0

## Rate Limit

max_retries: 3
backoff: "1s, 2s, 4s"

## Limitations

- AI 内容检测严格，低质 AI 生成可能被降权或不收录
- 图片需上传到 CSDN OSS，不支持外链
- 不支持 Mermaid、数学公式、脚注
