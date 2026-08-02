---
name: omics-analysis-viewer
overview: 创建一个 HTML+JavaScript 单页 Web 应用，从 localhost 加载模块列表与各模块 conclusion.md，用 marked.js 渲染 Markdown，采用 kb.css 的 VS Code 风格 light/dark 双主题，侧栏支持 VS Dock 式折叠隐藏。
design:
  architecture:
    framework: html
  styleKeywords:
    - VS Code IDE Style
    - Minimalism
    - Dock Window
    - Card List
    - Smooth Transition
  fontSystem:
    fontFamily: Segoe UI
    heading:
      size: 17px
      weight: 700
    subheading:
      size: 13.5px
      weight: 600
    body:
      size: 15px
      weight: 400
  colorSystem:
    primary:
      - "#007acc"
      - "#0067b8"
    background:
      - "#ffffff"
      - "#f5f5f5"
      - "#1e1e1e"
      - "#252526"
    text:
      - "#1e1e1e"
      - "#d4d4d4"
      - "#6a6a6a"
    functional:
      - "#007acc"
      - "#e5f3ff"
      - "#f8f8f8"
todos:
  - id: create-html-css
    content: 创建 index.html 页面结构和 app.css 主题样式（复用 kb.css 设计令牌、grid 布局、折叠侧栏机制、markdown-body 样式）
    status: completed
  - id: implement-core-logic
    content: 实现 app.js 核心逻辑：加载 modules.txt、自然排序、渲染侧栏模块列表、搜索过滤、首次自动选中
    status: completed
    dependencies:
      - create-html-css
  - id: implement-rendering-interactions
    content: 实现 app.js 渲染与交互：marked.js 配置与 conclusion.md 渲染、图片路径重写、骨架屏、错误处理、主题切换、侧栏折叠/展开
    status: completed
    dependencies:
      - implement-core-logic
---

## 产品概述

一个组学分析结果浏览器 Web 应用，用于浏览 LLM 智能体生成的生物组学数据分析模块及其结论报告。应用通过 HTTP 请求加载模块列表和各模块的 Markdown 总结文件，以类 Visual Studio 的可折叠侧边栏 + 右侧内容区的布局进行展示。

## 核心功能

- 启动时从 `/tmp/modules.txt` 加载分析模块列表，按自然数字顺序排序（1, 2, ..., 9, 10, 11）
- 左侧边栏以模块列表形式展示，每项含数字序号徽章和模块名称标题；支持搜索过滤
- 侧边栏可像 VS Dock 工具窗口一样折叠隐藏/恢复展开，折叠后在左侧边缘显示恢复按钮
- 点击模块项后，右侧内容区请求 `/analysis/<模块名>/conclusion.md`，使用 marked.js 渲染为 HTML 展示
- 首次加载自动选中并展示第一个模块
- 加载中显示骨架屏动画，请求失败显示友好错误提示
- 支持 Light/Dark 双主题切换，默认跟随系统偏好，手动切换后持久化到 localStorage
- 主题配色与 `kb.css` 保持一致（VS Code 风格设计令牌）

## 技术栈

- 纯 HTML + CSS + JavaScript（无构建工具，无框架依赖）
- Markdown 渲染：marked.js（通过 jsDelivr CDN 引入）
- 主题系统：CSS 自定义属性（CSS Variables），复用 kb.css 的设计令牌体系
- 布局：CSS Grid（顶栏跨两列 + 侧栏/主区两列）

## 实现方案

### 整体策略

创建三个独立文件放置在工作区根目录（即 localhost Web 根），通过 `http://localhost/index.html` 直接访问。`index.html` 定义页面结构，`app.css` 复用 kb.css 的设计令牌并扩展折叠侧栏机制，`app.js` 处理数据加载、渲染和交互逻辑。

### 关键技术决策

1. **主题令牌复用**：完整复制 kb.css 的 `:root`（Light）和 `html[data-theme="dark"]`（Dark）CSS 变量定义，确保配色完全一致。包括 `--ui-foreground`、`--ui-background`、`--accent`、`--code-background`、卡片彩色变量等全部设计令牌。
2. **侧栏折叠机制**：通过在 `.app` 容器上切换 `.sidebar-collapsed` 类，将 `grid-template-columns` 从 `312px 1fr` 变为 `0px 1fr`，配合 `transition` 实现平滑收起动画。折叠后侧栏 `overflow: hidden` + `border: none` 完全隐藏，左侧边缘显示一个窄条恢复按钮 `.sidebar-restore`。
3. **自然排序**：`modules.txt` 内容为字典序（10, 11, 1, 2, ...），需按模块名开头的数字进行自然排序（1, 2, ..., 9, 10, 11），通过 `parseInt` 提取前缀数字比较实现。
4. **Markdown 渲染配置**：marked.js 配置 `gfm: true`（GitHub 风格表格）、`breaks: true`（换行转 `<br>`），适配中文 Markdown 中标题与正文无空格的写法。渲染后为代码块添加 `data-theme` 感知的样式。
5. **图片路径处理**：conclusion.md 中的相对图片路径（如 `figures/xxx.png`）需重写为绝对路径 `/analysis/<模块名>/figures/xxx.png`，通过 marked 的 `renderer.image` 自定义实现。
6. **主题初始化**：优先读取 `localStorage` 中的用户偏好，无记录时跟随 `window.matchMedia('(prefers-color-scheme: dark)')` 系统偏好。

### 性能与可靠性

- 模块列表仅请求一次，后续切换模块只请求对应 conclusion.md（单次 fetch，无 N+1 问题）
- 切换模块时若上一个请求仍在进行，通过 AbortController 取消旧请求，避免竞态
- 骨架屏加载状态防止用户在等待期间重复点击
- 请求失败时显示 banner 错误提示而非空白，保持可用性

### 实现备注

- `modules.txt` 为纯文本（每行一个模块名，无 JSON 包装），直接 `response.text()` 后 `split('\n')` 过滤空行
- conclusion.md 内容为中文 Markdown，标题格式如 `##一、分析概述`（标题标记后无空格），marked.js 默认兼容此格式
- 部分模块（如 `3_comparison_group_design`）的 conclusion.md 已确认存在；所有模块目录均含 conclusion.md，但仍需处理 404 的边界情况
- 不修改 kb.css 原文件，仅在新创建的 app.css 中复制其设计令牌

## 架构设计

### 系统结构

```mermaid
graph LR
    A[浏览器加载 index.html] --> B[app.js 初始化主题]
    B --> C[fetch /tmp/modules.txt]
    C --> D[解析+自然排序模块列表]
    D --> E[渲染侧栏模块项]
    E --> F[自动选中第一个模块]
    F --> G[fetch /analysis/模块名/conclusion.md]
    G --> H[marked.js 渲染 Markdown]
    H --> I[注入右侧内容区]
    E --> J[用户点击其他模块]
    J --> G
```

### 数据流

1. `modules.txt` → `text()` → `split('\n')` → 过滤空行 → 自然排序 → 模块数组
2. 用户点击模块 → 构造 URL `/analysis/<name>/conclusion.md` → `fetch` → `text()` → `marked.parse()` → DOM 注入

## 目录结构

```
g:\OmicsWorks\test\metabolism\demo\
├── index.html          # [NEW] 页面结构。定义 topbar（含侧栏折叠按钮、标题、主题切换按钮）、aside.sidebar（含搜索框和模块列表容器）、main.content（内容渲染区）。引入 app.css 和 marked.js CDN，底部引入 app.js。
├── app.css             # [NEW] 样式表。完整复制 kb.css 的 Light/Dark 设计令牌（CSS 变量），复用 .app grid 布局、.topbar、.sidebar、.content、.markdown-body、.doc-item、.search、.btn 等样式。新增：侧栏折叠动画（.sidebar-collapsed 状态下 grid 列宽变为 0）、.sidebar-restore 恢复按钮、.icon-btn 顶栏图标按钮、.badge 模块数字徽章、.skeleton 骨架屏。响应式适配移动端抽屉模式。
├── app.js              # [NEW] 应用逻辑。包含：主题初始化与切换（localStorage 持久化）、fetchModules() 加载模块列表并自然排序、renderModuleList() 渲染侧栏项、loadModule() 请求并渲染 conclusion.md（含 AbortController 竞态控制、骨架屏、错误处理）、marked.js 配置（gfm/breaks/图片路径重写）、侧栏折叠/展开 toggle、搜索过滤、首次自动选中。
```

## 设计风格

采用 VS Code 风格的 IDE 界面设计，与 kb.css 主题完全一致。整体布局为顶部工具栏 + 左侧可折叠模块导航栏 + 右侧 Markdown 内容渲染区。Light 模式为亮白背景配 Visual Studio 蓝色强调色；Dark 模式为深灰背景配同样蓝色强调。侧栏模块项采用卡片式列表，悬停时向右微移并显示阴影，选中项以蓝色软背景高亮。内容区 Markdown 文档居中展示，最大宽度 1080px，标题带下划线分隔，代码块带边框圆角，表格带边框条纹。切换内容时有淡入上升动画。侧栏折叠/展开有平滑过渡动画。

### 页面区块规划

**顶栏（topbar）**：左侧折叠按钮 + 品牌标识（logo 图标 + 应用标题 + 当前模块名），右侧主题切换按钮。跨两列全宽。

**侧边栏（sidebar）**：顶部"分析模块"标题 + 搜索输入框，下方为模块列表。每项含数字徽章和模块名称。可折叠隐藏。

**内容区（content）**：Markdown 渲染区域，居中布局，含加载骨架屏和空状态提示。

**侧栏恢复条（sidebar-restore）**：侧栏折叠后在左侧边缘显示的窄条按钮，点击恢复侧栏。