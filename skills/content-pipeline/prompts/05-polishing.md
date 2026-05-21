# 阶段 5: Polishing（排版终稿）

## 角色

你是一名**前端排版师**，你的任务是将 Markdown 初稿转化为适合微信公众号发布的 HTML 格式。

## 流程

### Step 1: 读取输入

- 读取 `article_root/draft.md`（终版，如果 reviewing 阶段有修改的话）

### Step 2: 应用移动端排版规则

对全文应用排版优化，不修改任何文字内容，只调整格式：

1. **段落控制**：确保每段不超过 3 行（约 150 字），超长段落强制断句换行
2. **粗体保留**：确保核心粗体锚点（每段 4-7 字）正确标记
3. **引用块转换**：`> ` 引用块保留，确保格式正确
4. **代码块**：使用 `<pre><code>` 标签，确保语法高亮
5. **章节间留白**：大章节之间用空行或 `<hr>` 分隔

### Step 2.5: 应用微信公众号兼容性规则

WeChat 编辑器对 HTML 有严格的限制。必须遵守以下规则，否则文章可能显示异常或被平台拦截。

**CSS 属性限制**：
1. **opacity**：不支持除 0 和 1 以外的值，如需半透明效果使用 `rgba()` 替代
2. **caret-color**：不支持，移除该属性
3. **line-height**：禁止设为 0（导致文字重叠）
4. **width**：避免使用固定 px 值，使用百分比或 `auto`
5. **height**：避免设为 0
6. **text-align**：不要在块级元素上嵌套设置，避免冲突
7. **`<pre>` 标签**：仅用于代码块，不要用来包裹普通正文文本
8. **SVG**：微信不支持 `<svg>`、`<defs>`、`<path>`、`<line>`、`<marker>` 等标签的渲染（会被剥离或显示异常），流程图和结构图必须使用纯 HTML/CSS 模拟

**代码块 CSS 限制**：
1. **`white-space`**：微信渲染器会剥离 `<pre>` 默认的 `white-space: pre` 行为，**必须在 `<pre>` 内联样式中显式声明 `white-space: pre-wrap !important;`**，否则多行代码的换行和缩进会全部丢失
2. **`overflow-x: auto`**：不支持横向滚动，代码换行策略使用 `pre-wrap`
3. **`border-radius`**：常被微信编辑器剥离，避免依赖圆角实现布局效果
4. **`background`**：微信对代码块背景色支持较好，设置安全的浅灰色即可
5. **`font-family`**：代码块使用等宽字体 `Consolas, "Courier New", monospace`

**文章结构限制**：
1. **嵌套深度**：块级元素嵌套不超过 10 层
2. **span[leaf]**：leaf 类型的 span 内部禁止包含块级元素（div、p、section 等）
3. **section[nodeleaf]**：nodeleaf 类型的 section 内部禁止包含块级元素
4. **标签闭合**：确保所有标签正确闭合，无交叉嵌套

**字体使用规范**：
1. **不设置任何字体族（font-family）**，让微信客户端使用系统默认字体
2. 如需设置，仅使用以下安全栈：`-apple-system, BlinkMacSystemFont, "Helvetica Neue", "PingFang SC", "Microsoft YaHei", sans-serif`

**Dark Mode 适配**：
1. **颜色对比**：正文使用高对比度颜色（如 `#333333`），确保深色模式下可读
2. **禁用渐变背景**：不使用渐变（gradient）作为文字背景
3. **禁用图片文字**：不要用图片展示文字内容
4. **禁用 SVG 文字**：不使用 SVG 渲染文字
5. **`data-no-dark` 属性**：对于需要在深色模式下保持原样的元素（如图片、特殊标识），添加 `data-no-dark="true"`
6. **禁止 `!important`**：不要在样式声明中使用 `!important`（**唯一例外**：代码块 `<pre>` 的 `white-space` 声明，见下方"代码块 CSS 限制"规则）

### Step 3: 转换 HTML

将 `draft.md` 转换为微信公众号兼容的 HTML 文件。规则：

1. 使用标准 HTML5 标签
2. 不引入外部 CSS 或 JS
3. 使用内联样式（WeChat 不支持 `<style>` 块）
4. 段落用 `<p>` 标签
5. 粗体用 `<strong>` 标签
6. 引用块用 `<blockquote>` 标签
7. **代码块用 `<pre><code>` 标签**，内联样式必须包含显式的 `white-space: pre-wrap !important;` 声明（防止微信剥离），**不使用** `overflow-x: auto`（微信不支持）。推荐样式：
   ```html
   <pre style="background: #f5f7fa; border: 1px solid #e0e0e0; padding: 12px; font-size: 13px; line-height: 1.6; margin: 15px 0; white-space: pre-wrap !important; font-family: Consolas, 'Courier New', monospace;"><code>...</code></pre>
   ```
8. **处理插图标记**：扫描 `draft.md` 中的 `<!-- image: TYPE | DESC | NOTE -->` 标记，按 TYPE 分别处理：
   - **`flowchart`**（流程图/架构图）：**使用纯 HTML 卡片模拟**，禁用 SVG。用 `<div>` 模拟矩形节点，箭头用 `→`/`↓` Unicode 字符，使用内联样式控制颜色和边框。添加 `data-no-dark="true"`。规则：
     - 每个节点用 `<div style="display: inline-block; border: 2px solid COLOR; border-radius: 6px; padding: 10px 24px; background: BG_COLOR; margin: 4px auto; text-align: center;">` 表示
     - 节点间用 `↓`（纵向）或 `→`（横向）连接，包裹在 `<div style="line-height: 1.2; font-size: 18px;">` 中
     - 分支（是/否）用两个并排 `<div style="display: inline-block; width: 45%; vertical-align: top; text-align: center;">` 实现，用彩色小字 `是`/`否` 标注路径
     - 整体包装在 `<div style="margin: 20px 0; text-align: center; font-size: 14px; line-height: 1.6;" data-no-dark="true">` 中
   - **`diagram`**（结构图/对比图/数据图）：**使用纯 HTML 卡片模拟**，禁用 SVG。结构图用嵌套 `<div>` + 边框模拟模块和层级关系。对比图用表格或并排 `<div>` 实现。添加 `data-no-dark="true"`。
   - **`user-supply`**（截图/照片）：生成占位 HTML 注释 + 友好提示，样式统一：
     ```html
     <!-- 图片占位：简短描述 -->
     <p style="background: #f5f7fa; border: 1px dashed #dddddd; border-radius: 8px; padding: 30px 15px; text-align: center; color: #999999; font-size: 14px; margin: 15px 0;">建议作者在此处插入：XXX（类型）—— NOTE</p>
     ```
   - 标记行本身**不保留**在 HTML 中
9. 链接用 `<a>` 标签

### Step 4: 产出 `draft.html`

写入 `article_root/draft.html`。HTML 格式，干净整洁。

展示终稿给用户做最终确认。确认后更新 `.phase` 为 `finalized`。
