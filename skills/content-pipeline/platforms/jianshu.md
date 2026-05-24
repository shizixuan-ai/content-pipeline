# Platform: 简书

## Identity

name: jianshu
display: 简书
homepage: https://www.jianshu.com

## Persona

audience: 泛阅读者、文艺青年、自由职业者
mindset: 享受阅读和写作，轻量级获取知识
pain: 太长不看、学术化语言、无配图

voice:
  title_format: "故事化或情感共鸣"
  example_title: "从焦虑到从容：一个程序员的 2026 年度复盘"
  opening: 个人故事或场景代入
  code: 精简核心片段，配合故事讲解
  density: 中低，短段落，配图多
  taboo:
    - 大段无分节的代码
    - 教科书式论述

## Auth

type: cookie
source: env JIANSHU_COOKIE
script: scripts/auth-jianshu.sh
description: |
  简书使用 Cookie 认证。从浏览器登录后复制 Cookie 串：
    1. 浏览器打开 https://www.jianshu.com 并登录
    2. 打开 DevTools → Application → Cookies → 复制完整 Cookie 串
    3. 设为环境变量: export JIANSHU_COOKIE="..."
  后续 auth-jianshu.sh 会验证 Cookie 有效性。

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
description: 简书支持外链图片，不上传也可正常运行

## API

简书发布为四步流程，需顺序执行：

1. GET https://www.jianshu.com/author/notebooks
   → 获取作品集列表，取第一个 notebook_id

2. POST https://www.jianshu.com/author/notes
   Body: {"title": "...", "notebook_id": "...", "at_bottom": true}
   → 创建空笔记，返回 note_id

3. PUT https://www.jianshu.com/author/notes/{note_id}
   Body: {"id": note_id, "title": "标题", "content": "内容", "autosave_control": 1}
   → 填充笔记内容

4. POST https://www.jianshu.com/author/notes/{note_id}/publicize
   → 发布笔记

## Rate Limit

max_retries: 3
backoff: "1s, 2s, 4s"

## Limitations

- 多步骤流程（4 步），非幂等
- Cookie 有效期较短，可能需要频繁重新登录
- 不支持 Mermaid、数学公式、脚注
- 封面图需单独设置，暂不支持
