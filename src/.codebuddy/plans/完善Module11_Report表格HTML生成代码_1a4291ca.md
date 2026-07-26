---
name: 完善Module11_Report表格HTML生成代码
overview: 在 `Module11_Report.vb` 的 `BuildHtmlReport` 函数中，完善 `For Each data_rep As TableFigureCaption In section.figure_tables` 循环内对 CSV 表格类型的 HTML 渲染逻辑：使用 `DataFrameResolver.Load` 读取 CSV，提取前 9 行数据，按 `TableFigureCaption.fields` 指定的列（空则取全部列）构建 HTML 表格插入到报告中。
todos:
  - id: implement-csv-table-html
    content: 在 Module11_Report.vb 的 BuildHtmlReport 表格分支中实现 CSV 读取、前9行提取、fields列过滤及 HTML table 生成
    status: completed
---

## 用户需求

在 `Modules\Standard\Module11_Report.vb` 的 `BuildHtmlReport` 函数中，完善 `For Each data_rep As TableFigureCaption In section.figure_tables` 循环内对 CSV 表格类型的 HTML 渲染逻辑。

## 产品概述

当前报告模块已能处理图片类型（通过 DataURI 嵌入），但对于 CSV 表格类型仅输出了表注文字，未生成实际表格内容。需要补充表格内容生成逻辑：使用 `DataFrameResolver.Load` 读取 CSV 文件，提取前 9 行数据，按 `TableFigureCaption.fields` 指定的列字段（为空则取全部列）构建 HTML `<table>` 表格并插入到报告中。

## 核心功能

- 读取 CSV 文件并解析为 DataFrameResolver 对象
- 根据 `fields` 属性过滤显示列（空数组/Nothing 时显示全部列，自动跳过 CSV 中不存在的字段）
- 提取前 9 行数据行构建 HTML 表格（含表头行 + 数据行）
- 所有单元格内容经 `EscapeHtml` 转义，防止 HTML 注入
- 保留双语表注（中文 + 英文）

## 技术栈

- 语言：VB.NET（.NET 10.0，`OptionStrict Off`，`OptionInfer On`）
- CSV 解析库：`dataframework-netcore5.vbproj`（已通过 ProjectReference 引用）
- 命名空间：`Microsoft.VisualBasic.Data.Framework.StorageProvider`（已在文件头部导入）

## 实现方案

在现有 `ElseIf figPath IsNot Nothing Then` 分支（行 317-323）中，保留 `DataFrameResolver.Load` 调用和双语表注，增加 HTML 表格构建逻辑：

1. **确定显示列**：检查 `data_rep.fields` 是否为空/Nothing。若为空则使用 `csvDf.HeadTitles` 全部列；若非空则遍历 fields，通过 `csvDf.GetOrdinal(name)` 过滤掉 CSV 中不存在的字段，仅保留有效列名及其索引。
2. **提取数据行**：使用 `csvDf.Rows.Take(9)` 取前 9 行数据。
3. **构建 HTML 表格**：生成 `<table>` 结构，`<thead>` 中输出列标题行，`<tbody>` 中逐行输出数据单元格。每个单元格值通过 `row(ordinal)` 安全获取（越界返回空字符串），并经 `EscapeHtml` 转义。
4. **边界处理**：若 CSV 无数据行或有效列为空，仍输出表注但跳过表格生成；若文件加载失败则捕获异常并记录日志。

### 关键技术决策

- **列过滤策略**：不使用 `DataFrameResolver.[Select]()` 子集化方法（它会重置内部游标并创建新对象），而是直接用 `GetOrdinal` 获取索引后在遍历行时按索引取值。这样只需一次遍历，避免额外对象分配，性能更优。
- **行数限制**：使用 LINQ `Take(9)` 而非手动计数，代码简洁且不会对大文件产生内存压力（DataFrameResolver 已将全部数据加载到内存，Take 只是限制迭代次数）。

## 实现备注

- **性能**：DataFrameResolver.Load 已将整个 CSV 加载到内存，`Take(9)` 仅限制输出行数，不减少内存占用。对于极大 CSV 文件可考虑未来使用 `fast:=True` 参数优化加载速度，但当前场景下表格数据通常不大，无需额外优化。
- **安全性**：所有单元格内容必须经过 `EscapeHtml` 转义，防止 CSV 中的 HTML 特殊字符（如 `<`, `>`, `&`）破坏报告结构或造成 XSS。
- **向后兼容**：不修改现有的图片处理分支和 CSS 样式（表格样式已在行 264-267 定义），仅扩展表格分支的输出内容。

## 目录结构

仅修改一个文件：

```
g:\OmicsWorks\src\
├── Modules\
│   └── Standard\
│       └── Module11_Report.vb  # [MODIFY] 完善 BuildHtmlReport 中表格分支的 HTML 表格生成逻辑（行 317-323 区域）
```

### 文件修改详情

**`Module11_Report.vb`** — 修改 `BuildHtmlReport` 函数中 `ElseIf figPath IsNot Nothing Then` 分支：

- 保留 `Dim csvDf As DataFrameResolver = DataFrameResolver.Load(figPath.Item2)` 
- 保留双语表注 `<p>` 输出
- 新增：根据 `data_rep.fields` 确定有效列名和列索引数组
- 新增：构建 `<table><thead>...</thead><tbody>...</tbody></table>` HTML 结构
- 新增：遍历前 9 行数据，按列索引取值并 `EscapeHtml` 转义后输出 `<td>`
- 新增：CSV 加载异常 try-catch 保护，失败时输出错误提示文本