# Content Pipeline — Claude Code 内容创作与多平台分发流水线

[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-07c160)](https://claude.ai/code)
[![GitHub](https://img.shields.io/github/stars/shizixuan-ai/wechat-skills?style=social)](https://github.com/shizixuan-ai/wechat-skills)

**一次创作，多平台人格化分发。从构思到发布，一条命令全自动。**

`/content-pipeline` 是一个 Claude Code Skill，将内容创作与分发拆解为 7 个可控阶段：**需求分析 → 结构设计 → 内容撰写 → 毒舌审查 → 排版输出 → 终稿 → 多平台分发**。支持平台人格化改写、格式降级、图床适配和 API 投递。

---

## 解决的问题

| 问题 | 后果 |
|------|------|
| 每次都要手把手教 AI 格式、口吻、结构 | 写作 1 小时，调教 30 分钟 |
| 同一篇文章手动复制到多个平台 | 重复劳动，费力不讨好 |
| 各平台读者预期完全不同 | 文章在 A 平台火，在 B 平台无人问津 |
| AI 痕迹重，触发平台风控 | 降权、限流、封禁 |
| Claude 会话中断进度丢失 | 重复劳动 |

---

## 核心功能

- **7 阶段流水线** — 从需求挖掘到多平台分发，每步可追溯、可确认
- **3 种文章模板** — 教程类（五段火箭模型）、观点分析类、产品发布类
- **平台智能推荐** — finalized 后根据内容特征自动推荐最适合的平台
- **人格化改写** — 按平台读者心理预期自动重写标题和调整语气
- **格式降级** — 检测并降级平台不支持的格式（Mermaid、脚注、表格等）
- **插图自动生成** — Writing 阶段标记，Polishing 阶段自动生成 SVG/HTML 卡片
- **黑话修正双重防线** — Writing 预防 + Reviewing 检测，内置 27 组词库
- **API 直连投递** — 纯 API 驱动，拒绝浏览器模拟，降低风控风险
- **二次探活** — 分发后验证已发布 URL 可访问性
- **中断恢复** — 会话意外中断后自动检测断点继续

---

## 安装

```bash
npx skills@latest add shizixuan-ai/wechat-skills
```

安装时选择 `/content-pipeline` 即可。

### 前置条件

- [Claude Code](https://claude.ai/code) 已安装并登录
- Node.js 18+

---

## 使用

```bash
/content-pipeline
```

然后告诉 AI 你想写什么。finalized 后会自动进入分发环节，AI 推荐平台后你确认即可。

### 跳过分发

```bash
/content-pipeline --no-distribute
```

### 从指定阶段启动

```bash
/content-pipeline --from writing
```

---

## 7 阶段流水线

```
drafting → outlining → writing → reviewing → polishing → finalized → distributing
```

| 阶段 | 角色 | 产出 |
|------|------|------|
| drafting | 需求分析师 | `brief.md` |
| outlining | 内容架构师 | `outline.md` |
| writing | 技术写作专家 | `draft.md`（含插图标记） |
| reviewing | 毒舌主编 | `review-report.md` |
| polishing | 排版师 | `draft.html` |
| finalized | — | 终稿 |
| distributing | 分发工程师 | 分发报告 + 平台链接 |

---

## 支持的分发平台

| 平台 | 内容格式 | 认证方式 | 图片策略 |
|------|---------|---------|---------|
| 稀土掘金 | Markdown | X-Token | 外链 |
| 微信公众号 | 内联 HTML | appid + secret | 上传微信素材库 |
| 今日头条 | 富文本 JSON | OAuth ClientKey | 外链 |
| 知乎 | Markdown | Token | 外链 |

---

## 平台人格化

每个平台配置了独立的读者画像，分发前 AI 自动改写内容：

- **掘金**：技术直白风，保留代码，开门见山
- **微信**：深度洞察风，加入个人观点和踩坑记录
- **头条**：故事化风，第一人称，低信息密度
- **知乎**：论证拆解风，多维对比，数据支撑

---

## 项目结构

```
skills/content-pipeline/
├── SKILL.md                      # 编排引擎
├── CHECKLIST.md                  # 审核标准
├── blacklist-words.md            # 黑话词库
├── prompts/                      # 7 阶段 Prompt
│   ├── 01-drafting.md
│   ├── 02-outlining.md
│   ├── 03-writing.md
│   ├── 04-reviewing.md
│   ├── 05-polishing.md
│   └── 06-distributing.md
├── platforms/                    # 平台配置
│   ├── juejin.md
│   ├── wechat.md
│   ├── toutiao.md
│   └── zhihu.md
├── scripts/                      # 工具脚本
│   ├── auth-juejin.sh
│   ├── post-juejin.sh
│   ├── upload-wechat-image.sh
│   ├── health-check.sh
│   └── utils.sh
└── templates/                    # 文章模板
    ├── tutorial-rocket-model.md
    ├── opinion-rocket-model.md
    └── product-rocket-model.md
```

---

## 开源协议

[MIT](LICENSE)

[GitHub: shizixuan-ai/wechat-skills](https://github.com/shizixuan-ai/wechat-skills)
