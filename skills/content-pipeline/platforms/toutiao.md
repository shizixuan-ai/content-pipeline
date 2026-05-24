# Platform: 今日头条

## Identity

name: toutiao
display: 今日头条
homepage: https://www.toutiao.com

## Persona

audience: 泛科技爱好者、副业探索者、焦虑的职场人
mindset: 刷状态，关心技术如何改变生活或帮我赚钱
pain: 密密麻麻的代码、晦涩的术语

voice:
  title_format: "情绪钩子或反差"
  example_title: "我用 AI 自动替我上班后，发现程序员的门槛彻底变了"
  opening: 故事化开头，第一人称代入
  code: 转大白话业务流程描述，代码隐藏
  density: 低，短段落，多用"我"
  taboo:
    - 密集代码块
    - AI 排比句
    - 未解析的 Markdown 标记

## Auth

type: oauth2
source: env TOUTIAO_CLIENT_KEY + TOUTIAO_CLIENT_SECRET
script: scripts/auth-toutiao.sh
description: 头条号/抖音开放平台 OAuth 授权

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

policy: external-url
transform: none
description: 允许外链图片，支持公网 URL

## API

publish:
  method: POST
  url: https://www.toutiao.com/api/article/publish
  body:
    title: string
    content: string (RichText JSON)
    cover_image: optional

## Rate Limit

max_retries: 3
backoff: "1s, 2s, 4s"

## Limitations

- 底层需要富文本 JSON（Slate-compatible），不支持纯文本投递
- 不支持 Markdown 高级语法：脚注、Mermaid、数学公式
- 审核机制极其严格，AI 痕迹过重会触发限流
