---
name: content-pipeline
description: 内容创作与多平台分发流水线。支持文章写作（教程/观点/产品发布）、黑话修正、毒舌审查、平台人格化改写、格式降级与 API 投递。七阶段生命周期管理，中断恢复。当用户提到写公众号、写文章、分发内容、多平台发布、自媒体写作时使用此 skill。
metadata:
  version: "2.0.0"
---

# Content Pipeline — 内容创作与多平台分发流水线

将内容创作拆解为 7 个可追溯的阶段，支持中断恢复、用户确认流转和多平台智能分发。

## 文章生命周期

```
drafting → outlining → writing → reviewing → polishing → finalized → distributing
```

- 每个阶段有独立的角色和产出文件
- 每个阶段完成后，展示产出并**等待用户确认**再推进
- 中断后可恢复，从断点继续
- finalized 后自动进入分发环节

## 文章目录结构

文章数据存放在 `<article_root>/` 目录下（默认 `./article/`，用户可自定义；不存在则自动创建）：

```
article/
├── .phase                      # 当前阶段（文件内容即为阶段名）
├── brief.md                    # Drafting 产出：文章要点
├── outline.md                  # Outlining 产出：大纲
├── draft.md                    # Writing 产出：初稿
├── review-report.md            # Reviewing 产出：审查报告
├── draft.html                  # Polishing 产出：HTML 终稿
├── blacklist-words.md          # 可配置黑话词库（首次运行自动生成）
├── style-guide.md              # 写作风格配置（可选，由用户创建）
├── reference/                  # 参考资料目录
├── distribute-log.json         # 分发日志（MD5 幂等 + 历史记录）
└── distribute/                 # 分发产物
    ├── juejin/
    │   ├── tree.json           # 平台专属 Block Tree
    │   └── article.md          # 渲染后 Markdown
    ├── wechat/
    │   ├── tree.json
    │   └── article.html
    └── toutiao/
        ├── tree.json
        └── article.json
```

## 启动流程

运行 `/content-pipeline` 时：

1. **检查文章目录**：检测 `article_root`（默认 `./article/`）是否存在，不存在则创建
2. **检测未完成工作**：
   - 如果 `.phase` 存在且内容不是 `finalized` → 询问用户：
     > "检测到未完成的文章（当前在 `{phase}` 阶段），继续写还是重新开始？"
   - 如果 `.phase` 内容为 `finalized` → 检测 `distribute-log.json`：
     - 存在且记录显示已分发 → 询问"重新分发还是从 drafting 重新开始？"
     - 不存在或记录显示未分发 → 询问"是否进入分发环节？"
   - 如果 `.phase` 不存在 → 从 `drafting` 开始
3. **加载阶段 prompt**：读取 `prompts/` 下对应阶段的 prompt 文件
4. **执行阶段任务**：严格按阶段 prompt 执行
5. **阶段完成**：更新 `.phase` 到下一阶段，展示产出物，询问用户是否继续
6. **用户确认后**：载入下一阶段 prompt 继续
7. **循环直至分发完成**

## 阶段映射

| 阶段 | prompt 文件 | 角色 | 产出文件 |
|------|-----------|------|---------|
| drafting | `prompts/01-drafting.md` | 需求分析师 | `brief.md` |
| outlining | `prompts/02-outlining.md` | 内容架构师 | `outline.md` |
| writing | `prompts/03-writing.md` | 技术写作专家 | `draft.md` |
| reviewing | `prompts/04-reviewing.md` | 毒舌主编 | `review-report.md` |
| polishing | `prompts/05-polishing.md` | 排版师 | `draft.html` |
| finalized | — | — | 终稿（分发的输入） |
| distributing | `prompts/06-distributing.md` | 分发工程师 | 分发报告 + 平台链接 |

## 阶段流转命令

- 默认自动流转（每阶段完成后等待用户确认）
- 支持从指定阶段启动：`/content-pipeline --from writing`
- 支持跳过分发：`/content-pipeline --no-distribute`
- 如果是重新开始，清空所有产物文件（保留 `blacklist-words.md`）

## 平台配置

平台差异统一收敛到配置文件，每个平台独立声明：

```
platforms/
├── juejin.md     # 稀土掘金
├── wechat.md     # 微信公众号
├── toutiao.md    # 今日头条
└── zhihu.md      # 知乎
```

每个配置文件包含：
- **Persona**：受众画像、心理预期、表达规范
- **Auth**：认证方式与凭据来源
- **Format Capabilities**：支持的格式特性
- **Image Policy**：图片处理策略

## 工具脚本

分发中调用的 API 交互脚本统一放在：

```
scripts/
├── auth-juejin.sh       # 掘金认证
├── post-juejin.sh       # 掘金文章发布
├── upload-image.sh      # 通用图片上传
├── health-check.sh      # 二次探活
└── utils.sh             # 通用函数
```

## 文章类型

| 类型 | 模板文件 | 适用场景 |
|------|---------|---------|
| 教程类 | `templates/tutorial-rocket-model.md` | 教学、操作指南、最佳实践 |
| 观点分析类 | `templates/opinion-rocket-model.md` | 行业分析、趋势解读、观点输出 |
| 产品发布类 | `templates/product-rocket-model.md` | 新产品/功能发布、更新公告 |

## 引用格式

在写文章时引用文件路径，使用相对于 `article_root` 的路径，或者读取 `article_root` 中的文件内容。
