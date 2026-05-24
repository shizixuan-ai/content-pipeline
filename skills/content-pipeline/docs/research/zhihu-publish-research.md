# 知乎文章发布方案调研

## 需求

在 content-pipeline 中实现知乎（zhihu）平台的文章发布支持，使其成为继掘金、微信、头条之后的第四个分发目标。

当前状态：`platforms/zhihu.md` 已定义平台配置，但 `auth-zhihu.sh` 和 `post-zhihu.sh` 均不存在，`distribute.sh` 中知乎分支会 fallback 到 `*` 并报 "unsupported platform"。

## 候选方案评估

### 候选 1: 知乎开放平台 OAuth API

- **端点**: `POST https://api.zhihu.com/api/v4/articles`
- **认证**: OAuth 2.0 Bearer Token
- **Scope**: 需要 `write_articles` 权限
- **通过**: 通过 developer.zhihu.com 注册应用 → 获取 Client ID/Secret → OAuth 授权码流程获取 Token
- **结果**: ❌ 不推荐
  - 写权限的申请门槛和审核流程不透明，个人开发者能否获批未知
  - OAuth 授权码模式需要可访问的回调 URI 服务器
  - 多数第三方文章描述的是读取接口（搜索、热榜），而非发布
  - 不确定性太高，不适合作为主要方案

### 候选 2: @wangehengyi/zhihu-cli (npm)

- **版本**: 1.0.0 (2026-03-09 发布), MIT 许可
- **依赖**: axios, commander（极轻量）
- **认证**: Cookie（手动设置或从 Chrome 自动提取）
- **发布命令**: `zhihu post`（宣称支持）
- **结果**: ⚠️ 可尝试但不可靠
  - 描述为"搜索、阅读知乎内容"，发布功能可能是次要的
  - 单一版本，缺乏社区验证
  - 发布可能依赖 OpenClaw 浏览器扩展，非纯 CLI
  - 优点是与现有 npm 工具链一致，依赖极轻量

### 候选 3: 纯 Cookie + REST API 逆向

- **思路**: 同掘金模式，提取 Cookie → 调用知乎内部 API
- **结果**: ❌ 不推荐
  - 知乎已弃用纯 Cookie 认证，采用 **X-Zse-96 动态请求头签名**
  - 签名算法随时可能更新，维护成本高
  - 一次性逆向不足以应对生产使用

### 候选 4: Playwright 浏览器自动化

- **思路**: 复用项目中已有的 playwright-core（来自 @openclaw-cn/toutiao-ops），通过 Playwright 操作知乎网页编辑器完成发布
- **认证**: Playwright persistent session（同掘金），首次扫码登录 → 自动持久化
- **结果**: ✅ 推荐
  - 项目已依赖 playwright-core，无需新增重量级依赖
  - 与掘金 session 管理复用同一基础设施
  - 与头条 `toutiao-ops` 的浏览器自动化模式一致
  - 不依赖不稳定或未公开的 API
  - 缺点：运行速度较慢（需启动浏览器），对知乎 DOM 变化敏感

## 决策

**Build** — 基于 Playwright 浏览器自动化实现知乎发布。

架构遵循 pipeline 已有的 adapter 模式：

| 组件 | 方式 | 类似参考 |
|------|------|---------|
| 认证 | playwright-core persistent session | 掘金 juejin-session.cjs |
| 登录 | headed 浏览器扫码 / 手机验证码 | 掘金 login-juejin.sh |
| 发布 | Playwright 操作网页编辑器，填充标题+内容+发布 | 头条 toutiao-ops publish |
| 图片 | 外链图片，无需上传 | 已在 zhihu.md 中定义 |

零新增平台依赖 — 全部复用项目已有基础设施。

## 后续步骤

1. `/prototype` (LOGIC) → 验证 Playwright 操作知乎编辑器的可行性
2. 验证通过 → `/tdd` → 实现生产脚本
