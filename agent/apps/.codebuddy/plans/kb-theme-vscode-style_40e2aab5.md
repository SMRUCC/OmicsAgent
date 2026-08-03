---
name: kb-theme-vscode-style
overview: 将 kb.html 页面从「翡翠绿玻璃拟态 + 生物感光斑」主题重构为 VS Code 扁平亮/暗双主题，落地用户提供的配色 token，并将知识点分类卡片接入 7 种强调色。
design:
  architecture:
    framework: html
  styleKeywords:
    - VS Code Flat
    - 扁平化
    - 纯色表面
    - 细边框
    - 轻量阴影
    - 彩色分类卡片
    - 专业编辑器质感
  fontSystem:
    fontFamily: Segoe UI
    heading:
      size: 17px
      weight: 700
    subheading:
      size: 16px
      weight: 700
    body:
      size: 14px
      weight: 400
  colorSystem:
    primary:
      - "#007acc"
      - "#0067b8"
      - "#e5f3ff"
    background:
      - "#ffffff"
      - "#f5f5f5"
      - "#1e1e1e"
      - "#252526"
    text:
      - "#1e1e1e"
      - "#6a6a6a"
      - "#d4d4d4"
      - "#9d9d9d"
    functional:
      - "#107c10"
      - "#6b5bcf"
      - "#ca5010"
      - "#038387"
      - "#b3007a"
      - "#5a5a5a"
      - "#ef4444"
todos:
  - id: rewrite-css-tokens
    content: 重写 kb.css 令牌层：删绿色/玻璃/blob 变量，写入 light token 与派生 dark token
    status: completed
  - id: flat-ui-components
    content: 将 topbar/sidebar/card/doc-item/markdown/tag 等组件改为扁平纯色风格并套用阴影
    status: completed
    dependencies:
      - rewrite-css-tokens
  - id: color-card-modifiers
    content: 新增 .card--blue/green/purple/orange/teal/pink/gray 彩色分类修饰类
    status: completed
    dependencies:
      - rewrite-css-tokens
  - id: inject-card-classes
    content: 在 kb.js 渲染函数按 block 类型注入 card--x 修饰类，不改数据逻辑
    status: completed
    dependencies:
      - color-card-modifiers
  - id: verify-themes
    content: 本地核对亮/暗双主题与彩色卡片渲染，确保无遗留绿色/玻璃变量
    status: completed
    dependencies:
      - flat-ui-components
      - inject-card-classes
---

## 用户需求

将 kb.html 页面的主题样式从「翡翠绿玻璃拟态 + 生物感光斑」重构为 VS Code 扁平亮/暗双主题，并落地用户提供的完整配色 token。

## 产品概述

文献知识库浏览器（kb.html）是一套前端单页应用，左侧文献列表、右侧知识点/全文渲染。本次仅调整视觉主题体系，不改变数据加载与交互逻辑。重构后页面呈现 VS Code 风格的干净扁平界面：纯色 UI 表面、细致边框、轻量阴影、Segoe UI / Cascadia Code 字体；支持亮色（light）与暗色（dark）双主题切换。

## 核心功能

- 落地用户提供的 light 主题设计令牌（UI 表面、VS Code 蓝强调色、状态栏、代码块、7 组 action card 强调色、字体、三档阴影），并删除原有光斑背景与玻璃模糊效果。
- 派生并实现 VS Code Dark+ 风格的 dark 主题令牌，与 light 字段一一对应。
- 将知识点分类卡片接入 7 种强调色：不同知识 block（关键基因、关键通路、关键代谢物、关键发现、生物机制、与研究主题相关性、对比设计建议、预期发现、核心参考文献）分别使用对应 soft 背景 + 强调色标题/左边框。
- 主题切换按钮交互保持不变（基于 data-theme 属性，localStorage 持久化）。

## 技术栈

- 纯静态前端：HTML + 原生 CSS 变量 + 原生 JS（与现有 kb.html / js/kb.js 技术栈完全一致，不引入任何框架或构建工具）。
- 样式文件：styles/kb.css（全量重写设计与令牌体系）。
- 脚本文件：js/kb.js（仅注入卡片强调色修饰类，逻辑层不变）。

## 实现方案

### 总体策略

采用「设计令牌 + 语义化修饰类」的分层方案：将用户提供的 token 原样写入 `:root` 与 `html[data-theme="dark"]`，移除旧 green/glass/blob 变量；所有组件改用新令牌（如 `--ui-background`、`--ui-border`、`--accent`、`--shadow-md`）；知识点卡片用 `.card--blue/.card--green/...` 修饰类映射 7 组强调色。JS 仅在渲染各 block 时按类型追加一个修饰类，数据/网络逻辑零改动。

### 关键技术决策

1. **令牌命名对齐用户原 token**：直接采用 `--ui-foreground`、`--ui-background`、`--accent`、`--shadow-sm/md/lg`、`--card-blue` 等，避免引入中间层，便于后续用户单独微调任意 token。
2. **扁平化落地**：删除 `body::before` 的 blob 径向渐变背景；移除 `header/aside/.card` 上的 `backdrop-filter: blur` 与 `rgba` 半透明玻璃；背景改用 `--ui-background` 纯色，表面层（卡片/侧栏）用 `--ui-background-alt`。
3. **暗色派生（VS Code Dark+）**：`--ui-background:#1e1e1e`、`--ui-background-alt:#252526`、`--ui-background-hover:#2a2d2e`、`--ui-foreground:#d4d4d4`、`--ui-foreground-muted:#9d9d9d`、`--ui-border:#3c3c3c`、`--ui-border-strong:#555`、`--accent` 保持 `#007acc`、`--code-background:#1e1e1e`；强调色 soft 变体在暗色下降低明度（如 `--card-blue-soft:#06283d` 等）。
4. **彩色卡片分类映射**（与渲染函数一一对应）：

- 关键基因/蛋白 → blue；关键通路 → purple；关键代谢物 → teal；关键发现 → green；生物机制 → orange；与研究主题相关性 → blue（复用）；对比设计建议 → pink；预期发现 → purple（复用）；核心参考文献 → gray。
- 每个 `.card--x` 设置 `background:var(--card-x-soft)`、`border-left:3px solid var(--card-x)`、`.card h3` 用强调色。

5. **性能**：仅 CSS 变量替换与类名增删，无重排热点；主题切换沿用原 `data-theme` 属性 + `transition`，无 JS 开销。

### 执行要点（防回归）

- 保留原 `--radius`（16px）、`--radius-sm`（10px）或改为更贴 VS Code 的 6px/4px 圆角（建议 8px/6px，保持柔和但不圆润）；颜色/阴影严格套用 token 三档。
- `themeBtn` 图标文案逻辑（kb.js 的 applyTheme/toggleTheme）完全不动，仅确保 CSS 变量名存在即可。
- 标记/标签（`.tag`、`.tag.active`）改用 `--accent` 蓝系替代原绿色渐变。
- 代码块 `.markdown-body pre/code` 改用 `--code-background` / `--code-border` / `--code-foreground`。
- 滚动条、骨架屏、banner、空状态、移动端抽屉均改用新令牌，避免遗留绿色/玻璃变量。
- 不改动 `getJson/getText/parseDocTxt` 等数据逻辑及 `BASE_URL` 等配置。

## 架构设计

### 系统结构（组件 → 令牌）

```mermaid
graph TD
  A[kb.html data-theme] --> B[styles/kb.css 令牌层]
  B -->|light| C1[:root 用户提供 token]
  B -->|dark| C2[html[data-theme=dark] VS Code Dark+ 派生]
  C1 --> D[组件层: topbar/sidebar/card/doc-item/markdown/tag]
  C2 --> D
  D --> E[.card--blue... 彩色分类修饰类]
  F[js/kb.js 渲染] -->|注入 card--x 类| D
```

主题切换链路：点击 themeBtn → `toggleTheme()` 改 `data-theme` 属性 → CSS 变量整体切换，JS 逻辑与渲染函数签名不变。

## 目录结构

```
g:/OmicsWorks/agent/apps/
├── styles/
│   └── kb.css      # [MODIFY] 全量重写。移除绿色/玻璃/blob 变量；写入用户 light token 到 :root、派生 dark token 到 html[data-theme=dark]；所有组件改用新令牌；新增 .card--blue/green/purple/orange/teal/pink/gray 修饰类（soft 背景 + 强调色左边框/标题）；字体改 Segoe UI / Cascadia Code；阴影套用 --shadow-sm/md/lg。
├── js/
│   └── kb.js       # [MODIFY] 仅改渲染层：tagSection/mechanismsSection/comparisonSection/expectedFindingsSection/kbReferencesSection/renderKnowledge 在生成 .card 时按 block 类型追加对应 card--x 修饰类；不改动网络/解析/主题切换逻辑。
└── kb.html         # [不变] 已引用 styles/kb.css 且默认 data-theme=light，无需改动。
```

## 关键代码结构（可选）

仅展示彩色卡片修饰类的核心契约（写入 kb.css）：

```css
/* 彩色分类卡片：由 kb.js 按 block 类型追加 card--x */
.card--blue    { background: var(--card-blue-soft);    border-left: 3px solid var(--card-blue); }
.card--green   { background: var(--card-green-soft);   border-left: 3px solid var(--card-green); }
.card--purple  { background: var(--card-purple-soft);  border-left: 3px solid var(--card-purple); }
.card--orange  { background: var(--card-orange-soft);  border-left: 3px solid var(--card-orange); }
.card--teal    { background: var(--card-teal-soft);    border-left: 3px solid var(--card-teal); }
.card--pink    { background: var(--card-pink-soft);    border-left: 3px solid var(--card-pink); }
.card--gray    { background: var(--card-gray-soft);    border-left: 3px solid var(--card-gray); }
.card--blue h3, .card--green h3, .card--purple h3,
.card--orange h3, .card--teal h3, .card--pink h3,
.card--gray h3 { color: var(--ui-foreground); }
.card--blue h3 .dot { background: var(--card-blue); }
/* ...其余 dot 同理映射对应强调色 */
```

## 设计风格

采用 VS Code 扁平化（Flat / Fluent-lite）设计语言，呈现干净、专业的代码编辑器质感。移除数码感光斑与玻璃模糊，使用纯色 UI 表面、1px 细边框、轻量分层阴影（sm/md/lg）建立层次。配色以 VS Code 蓝（#007acc）为主强调，知识点分类卡片使用 7 种柔和强调色（soft 背景 + 实色左边框/圆点）区分内容类型，提升信息可扫读性。字体统一为 Segoe UI（界面）与 Cascadia Code（代码），字号沿用现有层级（标题 16-17px、正文 14-15px、辅助 11-13px）。暗色主题基于 VS Code Dark+，背景 #1e1e1e、表面 #252526、前景 #d4d4d4，保持与亮色一致的结构与间距。整体交互保留轻微 hover 位移与边框高亮，过渡平滑（0.2-0.35s）。