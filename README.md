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
- **多策略认证** — 环境变量 / Playwright session / Chrome CDP，自动降级
- **二次探活** — 分发后验证已发布 URL 可访问性
- **中断恢复** — 会话意外中断后自动检测断点继续
- **MD5 幂等** — 同一篇文章重复运行自动检测，不重复分发

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

| 平台 | 内容格式 | 认证方式 | 投递方式 | 图片策略 |
|------|---------|---------|---------|---------|
| 稀土掘金 | Markdown | Playwright session → Cookie | curl API | 外链 |
| 微信公众号 | 内联 HTML | appid + secret → access_token | curl API | 上传微信素材库 |
| 今日头条 | 富文本 JSON | OAuth ClientKey | toutiao-ops CLI | 外链 |
| 知乎 | RichText | Chrome CDP session → Cookie | CDP 浏览器操控 | 外链 |
| CSDN | Markdown | Playwright session → Cookie | curl API（HMAC 签名）| 外链 |
| 简书 | Markdown | Playwright session → Cookie | curl API（4 步流程）| 外链 |

---

## 平台人格化

每个平台配置了独立的读者画像，分发前 AI 自动改写内容：

- **掘金**：技术直白风，保留代码，开门见山。标题格式"技术栈 + 场景 + 结果"
- **微信**：深度洞察风，加入个人观点和踩坑记录，内容许可独立成文或二次创作
- **头条**：故事化风，第一人称，低信息密度，代码隐藏
- **知乎**：论证拆解风，多维对比，数据支撑，长文推理
- **CSDN**：专业分享风，偏实操，代码完整可复制
- **简书**：故事观点风，轻量阅读，避免密集代码

---

## 认证方式

分发引擎支持三种认证策略，按优先级自动降级：

```
auth-*.sh 统一逻辑:
  1. 环境变量（JUEJIN_COOKIE / WECHAT_APPID 等） → 验证
  2. Playwright persistent session（~/.juejin/browser-data/） → 提取 cookie → 验证
  3. 引导扫码登录（login-*.sh）
```

| 平台 | Session 存储 | 认证有效期 |
|------|-------------|-----------|
| 掘金 | `~/.juejin/browser-data/` | session 续期至 1 年 |
| 微信 | 无（每次通过 appid+secret 获取） | 2 小时 |
| 知乎 | `~/.zhihu/browser-data/` | 约 7 天 |
| CSDN | `~/.csdn/browser-data/` | 约 7 天 |
| 简书 | `~/.jianshu/browser-data/` | 约 7 天 |
| 头条 | OAuth token（环境变量） | 随 token |

---

## 分发流程

```
distribute.sh 对每个平台独立执行:
  1. 幂等检查   — draft.md MD5 比对 distribute-log.json
  2. 认证       — auth-*.sh，3 种策略自动降级
  3. 内容选择   — 先查 distribute/<platform>/ 定制版，fallback 到 draft
  4. 投递       — post-*.sh，API 或 CDP 浏览器操作
  5. 探活       — health-check.sh，HEAD 请求验证
  6. 写日志     — distribute-log.json
```

单平台失败不影响其他平台。

---

## 项目结构

```
skills/content-pipeline/
├── SKILL.md                      # 编排引擎
├── CHECKLIST.md                  # 审核标准（5 维度）
├── blacklist-words.md            # 黑话词库（27 组）
├── prompts/                      # 7 阶段 Prompt
│   ├── 01-drafting.md
│   ├── 02-outlining.md
│   ├── 03-writing.md
│   ├── 04-reviewing.md
│   ├── 05-polishing.md
│   └── 06-distributing.md
├── platforms/                    # 平台配置
│   ├── juejin.md / wechat.md / toutiao.md
│   └── zhihu.md / csdn.md / jianshu.md
├── templates/                    # 文章模板
│   ├── tutorial-rocket-model.md
│   ├── opinion-rocket-model.md
│   └── product-rocket-model.md
└── scripts/                      # 分发执行引擎
    ├── distribute.sh             # 编排引擎
    ├── auth-*.sh (×6)            # 按平台认证
    ├── post-*.sh (×6)            # 按平台投递
    ├── login-*.sh (×4)           # 扫码登录引导
    ├── lib/
    │   ├── pipeline.py           # Python CLI 工具
    │   ├── juejin-session.cjs    # Playwright session
    │   ├── zhihu-session.cjs     # Chrome CDP session
    │   ├── csdn-session.cjs      # Playwright session
    │   └── jianshu-session.cjs   # Playwright session
    ├── health-check.sh           # 二次探活
    ├── make-cover.sh             # 微信封面图
    ├── upload-wechat-image.sh    # 微信图片上传
    └── utils.sh                  # 日志 + 指数退避重试
```

---

## 文章产物

```
article/
├── .phase                    # 当前阶段
├── brief.md                  # 需求要点
├── outline.md                # 文章大纲
├── draft.md                  # Markdown 终稿
├── draft.html                # HTML 终稿（微信兼容）
├── review-report.md          # 审查报告
├── cover.png                 # 封面图
├── distribute/               # 平台分发产物
│   ├── juejin/article.md
│   ├── wechat/article.html
│   └── toutiao/article.json
└── distribute-log.json       # 分发历史（MD5 幂等）
```

---

## 开源协议

[MIT](LICENSE)

[GitHub: shizixuan-ai/wechat-skills](https://github.com/shizixuan-ai/wechat-skills)
