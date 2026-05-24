# Content Pipeline 端到端测试方案

测试目标：从 idea 到发布，完整走通 7 阶段流水线，验证每个环节产出正确。

## 测试数据

- **测试文章**：用 Go 实现一个简单的 Rate Limiter
- **文章类型**：教程类（tutorial-rocket-model）
- **预期特征**：代码占比较高（约 40%），含流程图，2500-3500 字

---

## 阶段 0：环境准备

### 0.1 检查前置条件

- [ ] `node --version` >= 18
- [ ] `gh --version` — GitHub CLI 已安装
- [ ] `bats --version` — 测试框架就绪（v1.13.0）

### 0.2 重置测试状态

```bash
# 清空文章目录（保留 .gitkeep）
rm -rf article/* article/.phase
find article -type f ! -name '.gitkeep' -delete

# 确认已清除
ls -la article/        # 应只有 .gitkeep
```

### 0.3 运行单元测试

```bash
bats skills/content-pipeline/scripts/test/
```

- [ ] 全部 36 个测试通过

---

## 阶段 1：Drafting（需求分析）

### 操作

```
/content-pipeline
```

输入主题："用 Go 实现一个简单的 Rate Limiter，要求支持令牌桶算法，适用于 API 网关场景"

### 验证清单

- [ ] `article/brief.md` 文件已创建
- [ ] 包含以下要素：目标读者、核心功能列表、技术约束
- [ ] 识别出"教程类"模板
- [ ] 控制台输出显示 brief 摘要，并询问是否继续
- [ ] 回答 yes 后 `.phase` 内容更新为 `outlining`

---

## 阶段 2：Outlining（结构设计）

### 验证清单

- [ ] `article/outline.md` 文件已创建
- [ ] 按"五段火箭模型"组织：Why → What → How → Pitfalls → Summary
- [ ] 至少包含 5 个二级标题
- [ ] 各章节字数预估合理（总 2500-3500 字）
- [ ] 控制台输出大纲，等待确认
- [ ] 确认后 `.phase` → `writing`

---

## 阶段 3：Writing（内容撰写）

### 验证清单

- [ ] `article/draft.md` 文件已创建
- [ ] 包含完整的代码块（Go 语言，标注语言）
- [ ] 包含至少 1 个插图标记 `<!-- image: TYPE | DESC | NOTE -->`
  - 例如 `<!-- image: flowchart | 令牌桶算法流程 | -->`
- [ ] 字数在 2500-3500 范围
- [ ] 无 AI 黑话（检测 `blacklist-words.md` 中的禁用词）
- [ ] 确认后 `.phase` → `reviewing`

---

## 阶段 4：Reviewing（毒舌审查）

### 验证清单

- [ ] `article/review-report.md` 文件已创建
- [ ] 报告包含问题列表（按严重性分级）
- [ ] 至少检出 3 个问题
- [ ] 评分在 6-9 分之间
- [ ] 确认（或拒绝 + 修复）后 `.phase` → `polishing`

---

## 阶段 5：Polishing（排版输出）

### 验证清单

- [ ] `article/draft.html` 文件已创建
- [ ] 仅内联样式，无 `<style>` 块（微信兼容）
- [ ] 插图标记已替换为实际内容：
  - flowchart → 内联 SVG
  - diagram → HTML 卡片 / SVG
  - user-supply → 占位框
- [ ] HTML 结构完整 `<html><head><body>`
- [ ] Dark Mode 兼容（`data-no-dark` 属性在图片上）
- [ ] 验证后 `.phase` → `finalized`

---

## 阶段 6：Finalized（终稿锁定）

### 验证清单

- [ ] .phase 内容为 `finalized`
- [ ] 控制台询问"是否进入分发环节？"
- [ ] 回答 yes

---

## 阶段 7：Distributing（多平台分发）

### 7.1 Credential 检查

- [ ] 系统检查各平台凭据状态：

| 平台 | 预期行为 |
|------|---------|
| 稀土掘金 | 检查 `JUEJIN_TOKEN` → 未设置则提示输入或 skip |
| 微信公众号 | 检查 `WECHAT_APPID` + `WECHAT_SECRET` |
| 今日头条 | 检查 `TOUTIAO_CLIENT_KEY` + `TOUTIAO_CLIENT_SECRET` |
| 知乎 | 检查 `ZHIHU_TOKEN` |

- [ ] 输入 skip 跳过所有平台（本次仅验证流程）
- [ ] 或设置真实 token 投递到掘金

### 7.2 平台推荐

- [ ] 系统输出内容分析结果
- [ ] 推荐 2-3 个平台并默认勾选
- [ ] 手动确认/修改勾选

### 7.3 Persona Rewrite（人格化改写）

- [ ] `article/distribute/<platform>/tree.json` 已创建
- [ ] Block 结构与原文一致（仅 Content 字段变化）
- [ ] 掘金版标题改为"技术栈 + 场景 + 结果"风格
- [ ] 头条版标题包含情绪钩子

### 7.4 Format Degrade（格式降级）

- [ ] 控制台输出格式降级日志
- [ ] 不兼容要素已被正确处理

### 7.5 Render（渲染）

- [ ] `article/distribute/juejin/article.md` 已创建（Markdown）
- [ ] `article/distribute/wechat/article.html` 已创建（联 HTML）

### 7.6 Auth & Deliver（投递）

如果配置了真实凭据：

- [ ] `scripts/auth-juejin.sh` 返回 SUCCESS
- [ ] `scripts/post-juejin.sh` 返回文章 URL
- [ ] 指数退避重试逻辑触发（如果遇到限流）

### 7.7 Health Check（二次探活）

- [ ] 已发布 URL 返回 200 OK
- [ ] 草稿箱平台显示"跳过探活"

### 7.8 分发报告

- [ ] `article/distribute-log.json` 已创建
- [ ] 包含 `article_md5`、`distributed_at`、各平台状态
- [ ] 控制台输出结构化报告

---

## 阶段 8：幂等验证

### 8.1 重复分发保护

- [ ] 再次运行 `/content-pipeline`
- [ ] 系统提示"检测到这篇文章已在 {time} 分发过"
- [ ] 回答 no → 流程退出

### 8.2 强制重新分发

- [ ] 回答 yes → 覆盖写入新日志

---

## 测试结果记录

| 阶段 | 通过 | 失败 | 备注 |
|------|------|------|------|
| 0 环境准备 | □ | □ | |
| 1 Drafting | □ | □ | |
| 2 Outlining | □ | □ | |
| 3 Writing | □ | □ | |
| 4 Reviewing | □ | □ | |
| 5 Polishing | □ | □ | |
| 6 Finalized | □ | □ | |
| 7 Distributing | □ | □ | |
| 8 幂等验证 | □ | □ | |
| **总计** | **/9** | **/9** | |
