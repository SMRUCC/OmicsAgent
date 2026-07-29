---
name: html-report-optimization
overview: 重构 Knowledge\HtmlReport.vb 的 BuildHtmlReport 大函数，将其按功能拆分为多个小函数；在生成的 HTML 中新增封面页、目录(TOC)与图/表自动编号；修复布局错位问题（图片内联间隙、表格跨页、markdown 列表/代码块未样式化、重复的 <br> 处理等）；并直接优化外部 CSS 文件 G:\OmicsWorks\agent\docs\report.css，美化最终报告样式。
design:
  architecture:
    framework: html
  styleKeywords:
    - 学术报告风格
    - 严谨简洁
    - A4 打印排版
    - 深蓝主色调
    - 封面页
    - 目录导引
    - 图表居中
    - 条纹表格
  fontSystem:
    fontFamily: Lora
    heading:
      size: 22pt
      weight: 700
    subheading:
      size: 16pt
      weight: 600
    body:
      size: 12pt
      weight: 400
  colorSystem:
    primary:
      - "#1f4e79"
      - "#2e5c8a"
    background:
      - "#FFFFFF"
      - "#F5F5F5"
    text:
      - "#333333"
      - "#555555"
    functional:
      - "#1f4e79"
      - "#CCCCCC"
      - "#F9F9F9"
todos:
  - id: refactor-builders
    content: 拆分 BuildHtmlReport 为子函数并修正 EscapeHtml，新增封面/目录/编号逻辑
    status: completed
  - id: fix-figures-tables
    content: 修复结果区图表匹配与排序，新增图/表自动编号计数器并按声明顺序渲染
    status: completed
    dependencies:
      - refactor-builders
  - id: remove-br-hack
    content: 移除 Module11_Report.vb 调用处的 .Replace("<br><br>","") hack
    status: completed
    dependencies:
      - refactor-builders
  - id: beautify-css
    content: 优化外部 report.css：封面/目录/图片居中/表格跨页与固定布局/markdown 元素样式
    status: completed
    dependencies:
      - refactor-builders
      - fix-figures-tables
  - id: verify-report
    content: 编译项目并生成样例 HTML 检查布局与结构完整性
    status: completed
    dependencies:
      - refactor-builders
      - fix-figures-tables
      - remove-br-hack
      - beautify-css
---

## 用户需求

优化 VB.NET 科研 agent 项目中 `Knowledge\HtmlReport.vb` 的 `BuildHtmlReport` 函数：将庞杂的单一函数按功能拆分为多个小函数，并美化最终生成的 HTML 研究报告（再经 wkhtmltopdf 转为 A4 PDF）。

## 产品概述

重构报告 HTML 生成逻辑并美化排版。在保留现有“标题→摘要→关键词→引言→材料与方法→结果→讨论→结论”主干的基础上，新增封面页、章节目录(TOC)与图/表自动编号（图1/表1…及中英文图注），修复当前存在的布局错位、图片底部空隙、表格跨页切断、markdown 元素未样式化等问题。

## 核心功能

- 将 `BuildHtmlReport` 拆分为文档头、封面、目录、摘要、标准章节、结果子章节、图、表等子函数，主函数仅做编排。
- 新增封面页（标题/研究主题/日期/关键词）与目录页（锚点跳转、引导点）。
- 结果章节内图与表按类型分别在资源中精确匹配、按声明顺序渲染，并维护图/表自动编号计数器。
- 修正 `EscapeHtml`：仅做 markdown 转换，去除 blanket 换行→`<br>` 替换；移除 `Module11_Report.vb` 调用处的 `.Replace("<br><br>","")` 临时 hack。
- 直接编辑外部 CSS 文件 `G:\OmicsWorks\agent\docs\report.css`：修复图片 `display:block` 居中、表格 `break-inside:avoid` 与 `table-layout:fixed`、补充 `ul/ol/li/blockquote/code/pre/h4` 等样式，优化封面/目录/图注排版。

## 技术栈

- 语言/框架：VB.NET（.NET，现有项目），扩展方法 + `StringBuilder` 拼接 HTML。
- 报告管线：`BuildHtmlReport` 生成 HTML → `wkhtmltopdf` 转 A4 PDF（流程不变）。
- 样式：外部 CSS `G:\OmicsWorks\agent\docs\report.css`，由代码 `{App.HOME}/../docs/report.css` 读取并内联，路径保持不变。
- 数据模型：`ReportContent` / `ResultSection` / `TableFigureCaption`（已读取，结构不变）。

## 实现方案

### 总体策略

将单体 `BuildHtmlReport` 重构为“编排函数 + 一组职责单一的私有构建函数”，每个函数负责一个语义块（文档头/封面/目录/摘要/标准章节/结果子章节/图/表），由主函数按顺序拼接。引入轻量 `ReportCounters` 类（figureNo/tableNo）在章节间传递以实现图/表连续自动编号；章节标题写入 `id` anchor，目录据此生成跳转链接。

### 关键技术决策

1. **拆分而非重写**：保留现有数据模型与 DataURI 内联图片方式，仅重构拼接逻辑，降低回归风险。
2. **EscapeHtml 修正**：原函数先 `markdown.Transform` 再对全部 `\n` 做 `<br>` 替换，把块级元素间换行变成多余 `<br>`，调用处再用 `.Replace("<br><br>","")` 掩盖。改为仅返回 `markdown.Transform(text)`，由 markdown 自行处理块/内联；调用处 hack 同步删除。
3. **图表匹配与排序修复**：原逻辑 `figures.JoinIterates(tables).OrderBy(BaseName)` 把图与表混合按文件名排序，且表格仅在 `figures` 中查找、回退 `data_rep.file.FileExists`，脆弱且顺序不可预期。改为：图在 `res.figures` 中按文件名匹配（回退 FileExists）、表在 `res.tables` 中匹配；按 JSON 声明顺序（先 figures 后 tables，或保持数组顺序）渲染，避免文件名排序导致的错位。
4. **自动编号**：`ReportCounters` 实例在 `BuildResultsSection` 内调用 `BuildFigure`/`BuildTable` 时自增，图注输出「图 n：…/Figure n: …」「表 n：…/Table n: …」，支持后续交叉引用。

### 性能与可靠性

- CSV 表格读取沿用 `DataFrameResolver.Load` + `Rows.Take(9)`，无性能问题；保持 try/catch 并记录 `loginfo`（复用现有 logger，不输出大 payload）。
- HTML 拼接使用 `StringBuilder`，O(N) 线性，N 为章节/图表数，开销可忽略。
- 保持对外签名 `BuildHtmlReport(content, res, loginfo)` 不变，保证 `Module11_Report.vb` 调用兼容。

## 实现要点（防回归）

- 仅修改 `HtmlReport.vb`、`Module11_Report.vb` 与外部 `report.css`，不触碰数据模型与其他模块。
- 图片仍用 `New DataURI(figPath.filename).ToString` 内联，保证 wkhtmltopdf 离线可用。
- 删除 `.Replace("<br><br>","")` 前确认 `EscapeHtml` 已不再产生双 `<br>`，避免回归。
- CSS 保留 `@page A4`、`#1f4e79` 主色与衬线字体基调，仅新增/修正规则，不影响既有章节样式。

## 架构设计

模块内函数组合（无新架构模式，符合现有 `HtmlReport` Module 组织）：
`BuildHtmlReport`（编排）→ `BuildDocumentHead` → `BuildCoverPage` → `BuildTableOfContents` → `BuildAbstractSection` → `BuildStandardSection`×N → `BuildResultsSection`×M →（`BuildFigure`/`BuildTable`）→ `EscapeHtml`（工具）。
数据流：`ReportContent` + `ReportResource` + `ReportCounters` → 各构建函数产出 HTML 片段 → `StringBuilder` 汇总为完整文档。

## 目录结构

```
g:\OmicsWorks\src\Knowledge\HtmlReport.vb        # [MODIFY] 重构核心。拆分 BuildHtmlReport 为编排函数；新增 BuildDocumentHead/BuildCoverPage/BuildTableOfContents/BuildAbstractSection/BuildStandardSection/BuildResultsSection/BuildFigure/BuildTable；新增 ReportCounters 计数类；修正 EscapeHtml（仅 markdown 转换，去 blanket <br>）；为 h1-h3 写入 id anchor。保持对外签名不变、DataURI 内联图片不变。
g:\OmicsWorks\src\Modules\Standard\Module11_Report.vb  # [MODIFY] 删除第 110 行 BuildHtmlReport 结果后的 .Replace("<br><br>","") 临时 hack；其余调用逻辑与 PDF 转换流程保持不变。
g:\OmicsWorks\agent\docs\report.css              # [MODIFY] 外部 CSS 美化与布局修复：新增 .cover/.toc 样式（含 break-after:page）；img 改为 display:block;margin:0 auto;height:auto;max-width:100%;max-height:500px；figure/table 增加 break-inside:avoid/page-break-inside:avoid；table 增加 table-layout:fixed 与 th/td 的 word-wrap/overflow-wrap；补充 ul/ol/li/blockquote/code/pre/h4 样式防止溢出；优化 .abstract/.keywords/figcaption 观感，保留 A4 与 #1f4e79 主色。
```

## 关键代码结构

```
' 图/表自动编号计数器（在结果章节间传递，引用类型天然可变）
Friend Class ReportCounters
    Public figureNo As Integer = 0
    Public tableNo As Integer = 0
End Class

' 重构后的主函数签名（保持不变，保证调用兼容）
<Extension>
Friend Function BuildHtmlReport(content As ReportContent, res As ReportResource, loginfo As Action(Of String)) As String

' 各子构建函数（私有，返回 HTML 片段）
Private Function BuildDocumentHead(title As String) As String
Private Function BuildCoverPage(content As ReportContent) As String
Private Function BuildTableOfContents(content As ReportContent) As String
Private Function BuildAbstractSection(content As ReportContent) As String
Private Function BuildStandardSection(sectionNumber As String, anchorId As String, heading As String, body As String) As String
Private Function BuildResultsSection(section As ResultSection, subsectionNo As Integer, res As ReportResource, counters As ReportCounters, loginfo As Action(Of String)) As String
Private Function BuildFigure(dataRep As TableFigureCaption, figPath As ResourceFile, counters As ReportCounters) As String
Private Function BuildTable(dataRep As TableFigureCaption, tblPath As ResourceFile, counters As ReportCounters, loginfo As Action(Of String)) As String
Private Function EscapeHtml(text As String) As String   ' 仅 markdown.Transform，不再替换换行
```

## 设计风格

采用严谨学术报告（Scientific Paper）风格，A4 打印排版，深蓝 `#1f4e79` 主色调，衬线字体（Cambria/Times 衬线 + 中文 PingFang SC/微软雅黑回退）。整体简洁、专业、留白合理，适合科研论文初稿 PDF 输出。

## 页面规划（单文档多页，A4 PDF）

报告为连续文档，含封面页、目录页、正文。各页通过 `break-after:page` 控制分页。

### 封面页（.cover）

- 顶部大留白，居中大号报告标题；下方研究主题/副标题；分隔细线；生成日期；底部关键词斜体。
- `break-after:page` 使目录另起一页，视觉庄重。

### 目录页（.toc）

- 居中“目录”标题，编号章节列表（1 引言、2 材料与方法、3 结果含 3.1…3.n、4 讨论、5 结论），带引导点。
- 锚点 `<a href="#id">` 跳转；`break-after:page`。

### 标准章节块

- h2 章节标题带下边框与主色；正文 `text-align:justify`、首行缩进 `2em`；列表/引用/代码块均有样式，避免溢出。

### 结果子章节块（3.n）

- h3 自动编号子标题（3.1/3.2…）；叙述文本；按声明顺序嵌入图与表，图文错落。

### 图块（figure）

- 图片 `display:block` 水平居中，`max-height` 限制；figcaption 显示「图 n：中文 / Figure n: English」，`break-inside:avoid` 防跨页切断。

### 表块（table）

- 表注 + 边框条纹表格，`table-layout:fixed` 防溢出，单元格换行；`break-inside:avoid` 避免长表被分页切断。

## 交互与响应式

报告为静态打印文档（无交互）；“响应式”体现为打印分页：封面/目录强制分页，图与表避免跨页，窄列内容换行，保证 A4 输出无错位。