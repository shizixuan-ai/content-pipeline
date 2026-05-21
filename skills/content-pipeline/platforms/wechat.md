# Platform: 微信公众号

## Identity

name: wechat
display: 微信公众号
homepage: https://mp.weixin.qq.com

## Persona

audience: 垂直领域长期关注者、同行专家
mindset: 深度阅读，看重个人 IP 和独特洞察
pain: 说明书式的技术堆砌、无个人观点的搬运

voice:
  title_format: "深度思考 + 行业趋势"
  example_title: "AI Agent 时代，程序员正在从'写代码'变成'工作流设计师'"
  opening: 引入个人踩坑经历或行业观察
  code: 精选关键片段，配合文字解释
  density: 中高，长叙事结构，注重排版
  taboo:
    - 说明书式语气
    - 无个人观点的纯翻译

## Auth

type: oauth2
source: env WECHAT_APPID + WECHAT_SECRET
script: scripts/auth-wechat.sh
description: 通过 appid + secret 换取 access_token，自动处理过期刷新

## Format Capabilities

markdown_features:
  heading: true
  bold: true
  italic: true
  link: limited
  image: false
  code_inline: true
  code_block: limited
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

html_capabilities:
  inline_style: true
  class_id: false
  script: false
  iframe: false
  custom_font: false
  dark_mode: true
  svg: limited

## Image Policy

policy: must-upload
transform: replace-url
upload_api: "POST https://api.weixin.qq.com/cgi-bin/material/add_material?type=image&access_token=${ACCESS_TOKEN}"
description: 必须上传到微信素材库，替换 draft.html 中的图片 URL 为微信 media_id

## Cover Image

微信草稿（cgi-bin/draft/add）要求 thumb_media_id 为必填字段，封面图获取策略按优先级如下：

1. **用户显式提供** — `post-wechat.sh` 第三个参数指定的本地图片路径
2. **正文首图提取** — 从 draft.html 中提取第一张 `<img>` 的 URL，下载后上传为封面
3. **自动搜索免费素材** — 以上均无时，根据文章标题提取 2-3 个中文关键词，调用免费图库 API 搜索下载。候选源：
   - Unsplash (`https://api.unsplash.com/search/photos?query=`) — 需 UNSPLASH_ACCESS_KEY 环境变量
   - 兜底：使用纯色 + 标题文字的占位封面（见 `scripts/make-cover.sh`）
4. **兜底** — 仍然失败时，日志警告并跳过该平台的分发

## API

publish:
  method: POST
  url: "https://api.weixin.qq.com/cgi-bin/draft/add?access_token=${ACCESS_TOKEN}"
  body:
    title: string
    content: string (HTML)
    need_open_comment: 0
    only_fans_can_comment: 0

## Rate Limit

max_retries: 3
backoff: "1s, 2s, 4s"

## Limitations

- 仅支持写入草稿箱，需手动群发
- 不支持外链图床
- 代码块无语法高亮，需转为纯文本 pre 包裹
- GitHub 等外链可能被限流
- SVG 仅支持简单图形
