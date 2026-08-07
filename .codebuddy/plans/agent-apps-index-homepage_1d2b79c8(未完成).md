---
name: agent-apps-index-homepage
overview: 为 agent/apps/index.html 编写软件 startup 主页，展示软件功能总结与功能模块入口，样式严格遵循 agent/apps/styles/kb.css 的设计令牌（含 .app 布局、.card/.card--x 彩色卡片、.btn、.tag、明暗主题）。
design:
  architecture:
    framework: html
  styleKeywords:
    - VS Code 风格
    - 卡片化
    - 明暗双主题
    - 简洁专业
    - 一致视觉
  fontSystem:
    fontFamily: Segoe UI
    heading:
      size: 22px
      weight: 700
    subheading:
      size: 16px
      weight: 600
    body:
      size: 14px
      weight: 400
  colorSystem:
    primary:
      - "#007acc"
      - "#0067b8"
    background:
      - "#ffffff"
      - "#f5f5f5"
      - "#1e1e1e"
    text:
      - "#1e1e1e"
      - "#6a6a6a"
      - "#d4d4d4"
    functional:
      - "#007acc"
      - "#107c10"
      - "#6b5bcf"
      - "#ca5010"
todos:
  - id: write-index-html
    content: 编写 index.html：引入 kb.css、内联主题脚本、.app 骨架与总结卡片
    status: pending
  - id: add-module-entries
    content: 添加 6 个功能模块入口彩色卡片与侧栏导航链接
    status: pending
    dependencies:
      - write-index-html
  - id: add-capability-tags
    content: 添加底层 R 能力标签云并校验样式一致性
    status: pending
    dependencies:
      - add-module-entries
---

## 用户需求

为基于 LLM 的科研数据分析 agent 智能体工作站编写图形化外壳的 startup 主页 `agent/apps/index.html`。

## 产品概述

一个面向科研人员的 LLM 驱动数据分析工作站。用户通过图形化外壳（WinForm + WebView2）进入主页，主页向用户展示软件的整体能力与各个功能模块的入口，引导用户进入对应功能页面。

## 核心功能

- 顶部一段文字总结软件能力：以 LLM agent 为核心，结合模块化 R 脚本（差异分析、富集分析、多组学、机器学习、可视化等）自主搭建科研数据分析流程，并配套文献知识库、数据集定义、结果浏览、Venn 图、文件查看与参数配置等辅助模块。
- 提供功能模块入口卡片，复用 `kb.css` 的 `.card--x` 彩色分类卡片样式，每个卡片链接到对应页面：文献知识库(kb.html)、组学分析结果浏览器(analysis.html)、数据集定义编辑器(dataset.html)、Venn 图工具(jvenn.html)、文件查看器(viewer.html)、应用参数配置(settings.html)。
- 样式与 `agent/apps/styles/kb.css` 完全一致：复用其设计令牌（明暗双主题）、`.app` 网格布局、`.topbar`/`.sidebar`/`.content`、`.card`/`.card--x`、`.btn`、`.tag`、`.meta-grid` 等，不引入新的样式名或颜色。
- 支持与现有页面一致的明暗主题切换（基于 `data-theme` 属性 + `localStorage("kb-theme")`），页面打开时避免主题闪烁。

## 技术栈选型

- 前端：原生 HTML + CSS + 少量内联 JavaScript（与现有 `agent/apps/*.html` 保持一致，无框架）
- 样式：复用 `agent/apps/styles/kb.css` 的设计令牌与组件类（不新增样式文件或类名）
- 主题：内联最小脚本，读取 `localStorage("kb-theme")` 在首屏前设置 `data-theme`，并提供主题切换按钮，逻辑与 `js/kb.js` 对齐

## 实现方案

### 总体策略

将 `index.html` 作为应用启动页，使用与 kb.html 相同的 `.app` 网格骨架（topbar + sidebar + content）。sidebar 作为「模块导航」列表，content 内包含：

1. 顶部 hero 区（一个 `.card` 或 banner）用一段话总结软件能力；
2. 功能模块入口区（`.meta-grid` 或卡片网格），每个入口是带彩色 `card--x` 修饰的 `.card`，内含标题、简介与「进入」按钮/整卡链接，指向对应 html 页面；
3. 可选的能力标签 `.tags` 展示底层 R 模块关键词（差异/富集/多组学/可视化等）。

### 关键技术决策

- 复用 `kb.css` 而非新建样式：保证视觉一致性、降低维护成本，符合用户强约束。
- 纯静态链接（`href` 跳转）而非 SPA 路由：与现有各页面独立 html 的架构一致，WebView2 外壳按文件名加载，无需引入路由框架。
- 内联主题脚本放置于 `<head>`，在 CSS 生效前设置 `data-theme`，避免明暗闪烁；主题按钮复用 `.btn` 样式并调用与 `kb.js` 相同的 `localStorage` key（`kb-theme`）。
- 链接目标使用相对路径（如 `kb.html`），与现有页面同目录，确保 WebView2 可正确加载。

### 性能与可靠性

- 纯静态页面、无外部 CDN 依赖（与 `index.html` 当前为空、其它页面有的依赖 marked/pdfjs 不同，主页不需要），首屏快、离线可用。
- 主题脚本仅做 localStorage 读取与属性设置，无网络请求、无重排风险。

## 实现注意事项

- 必须引入 `<link href="styles/kb.css" rel="stylesheet">`；不要新建 css 文件。
- 颜色/阴影必须取自 `kb.css` 变量（如 `var(--accent)`、`var(--shadow)`、`var(--card-blue-soft)` 等），不得硬编码新色值。
- 卡片修饰类使用 `card--blue/green/purple/orange/teal/pink/gray` 其中之一，与现有彩色卡片体系一致。
- 主题初始化脚本需与 `js/kb.js` 一致：key 为 `kb-theme`，缺省回退逻辑一致；按钮图标/文案（🌙/暗色、☀️/亮色）对齐。
- 链接不要指向不存在的页面；仅链接到已确认的 6 个入口页面。

## 架构设计

沿用现有 `.app` 网格布局，主页自身不引入新架构：

```mermaid
graph TD
  A[index.html 启动页] --> B[topbar 品牌+主题切换]
  A --> C[sidebar 模块导航列表]
  A --> D[content: hero总结卡 + 模块入口卡片网格]
  D --> E1[kb.html 文献知识库]
  D --> E2[analysis.html 结果浏览器]
  D --> E3[dataset.html 数据集编辑]
  D --> E4[jvenn.html Venn图]
  D --> E5[viewer.html 文件查看]
  D --> E6[settings.html 参数配置]
```

## 目录结构

```
agent/apps/
└── index.html   # [MODIFY/NEW] 软件 startup 主页。包含：
                 #   - <head> 内联主题初始化脚本（读取 localStorage("kb-theme") 设置 data-theme，防闪烁）
                 #   - <link href="styles/kb.css"> 引用既有样式
                 #   - .app 网格骨架（topbar + sidebar + content）
                 #   - topbar：品牌 Logo(🧬) + 标题「科研数据分析智能工作站」+ 主题切换按钮
                 #   - sidebar：模块导航列表（链接到 6 个页面，复用 .doc-item 样式）
                 #   - content：hero 总结卡片（一段话总结软件能力）+ 模块入口卡片网格（复用 .card .card--x，每个入口链接到对应页面）+ R 能力 .tags 标签云
                 # 要求：样式完全复用 kb.css，不新增类名/颜色
```

## 关键代码结构（可选）

无需新增 JS 模块；仅需内联最小主题脚本，逻辑对齐 `js/kb.js`：

- 读取 `localStorage.getItem("kb-theme")`，缺省按 `prefers-color-scheme` 回退 `light/dark`
- 设置 `document.documentElement.dataset.theme`
- 主题按钮点击在 `light`/`dark` 间切换并写回 `localStorage("kb-theme")`

## 设计风格

沿用 `kb.css` 的 VS Code 风格明/暗双主题设计语言，保持与现有各页面（kb.html/analysis.html/dataset.html 等）完全一致的视觉体系。采用卡片化布局，无新增装饰样式。

## 页面规划（单页：启动主页）

1. 顶栏（topbar）：左侧品牌区（Logo + 软件名 + 副标题），右侧主题切换按钮，复用 `.btn` 样式。
2. 侧边栏（sidebar）：「功能导航」标题 + 六个模块入口链接（`.doc-item`），点击跳转对应页面。
3. 内容区（content）按从上到下分块：

- 欢迎/总结卡片（`.card`）：一句话标题 + 一段话总结软件能力（LLM agent 驱动 + 模块化 R 脚本 + 文献/数据集/结果/可视化等配套模块）。
- 功能模块入口网格（`.meta-grid` 或卡片行）：6 个彩色 `.card--x` 卡片，每张含图标/标题/简介/「进入」链接，分别对应 kb/analysis/dataset/jvenn/viewer/settings。
- 底层能力标签区（`.tags`）：差异分析、富集分析、多组学、机器学习、可视化、质控等 R 模块关键词。

## 交互与响应式

- 主题切换即时生效，与现有页面体验一致；明暗双主题下颜色取自 `kb.css` 变量。
- 卡片 hover 使用 `kb.css` 已有的 `transform`/`box-shadow` 过渡（无需新写）。
- 复用现有 `@media (max-width: 860px)` 响应式断点，移动端侧栏抽屉化。