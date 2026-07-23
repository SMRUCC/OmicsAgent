---
name: 优化Modules文件夹LLM提示词（英译中+专业化）
overview: 将 Modules 文件夹下 12 个 VB 文件中所有英文 LLM 提示词翻译为中文，并优化为结构化、专业化、上下游衔接清晰的中文提示词。保留 JSON 键名、R/Python 包名、函数名、文件路径等代码标识符为英文。
---

## 用户需求

将 OmicsWorks LLM Agent 项目 Modules 文件夹中所有发给 LLM 的英文提示词翻译为中文，并进行专业化优化。

## 产品概述

本项目是一个生物信息学组学数据分析 LLM Agent，通过 11 个标准分析模块（预处理→PCA→比对设计→差异分析→KEGG→WGCNA→CMeans→贝叶斯网络→PLSPM→结果表格→报告）依次调用 LLM 完成自动化分析流程。当前所有模块中发给 LLM 的提示词均为英文，需要统一翻译为中文并优化指令质量。

## 核心功能

- 将 12 个 VB 文件中所有英文 LLM 提示词（包括 prompt 字符串、CDATA 块、上下文信息标题、错误重试消息）翻译为专业中文
- 优化提示词结构：统一采用"角色定位→上下游衔接→任务目标→输入要求→实现要求→输出要求→注意事项"的结构化格式
- 强化上下游模块数据流衔接：每个模块明确说明读取上游模块的输出文件前缀和目录、为下游模块提供什么输入
- 消除歧义：阈值、文件命名规则、路径、图片规格（DPI/格式/标签语言）等均明确无歧义
- 保留英文的内容：JSON 键名（module_name/goal/execution_steps 等）、R/Python 包名与函数名、文件路径、字符串插值占位符、代码模板

## 技术栈

- 项目语言：VB.NET（.NET），提示词为嵌入在 VB 字符串中的自然语言文本
- 修改类型：纯文本内容翻译与优化，不涉及代码逻辑变更
- JSON 反序列化约束：`LenientJsonParser.ParseJSON(json).CreateObject(Of ModulePlan)` 依赖 JSON 键名与 VB.NET 类属性名映射，JSON 键名必须保留英文

## 实现方案

### 策略概述

逐文件将所有英文 LLM 提示词翻译为中文，翻译过程中同步进行结构化优化。以 `AnalysisModuleBase.vb` 基类为模板确立统一术语和结构规范，再依次应用到各子模块。

### 关键技术决策

1. **JSON 模板中键名保留英文、描述文本翻译中文**：`GetPlantJSONTemplate()` 返回的 JSON 中，`"module_name"`、`"goal"`、`"execution_steps"` 等键名保留英文（因为 `ModulePlan` 类属性名是英文），但键值中的占位描述如 `<brief description of the analysis goal>` 翻译为中文
2. **R 代码模板保留英文**：Module 10/11 的 CDATA 块中包含 R 代码示例（`library(openxlsx)`、`createWorkbook()` 等），代码部分保留英文，仅翻译指令性文本
3. **输出语言约束保留**：部分提示词要求输出为英文（如图片标签 "All text labels in English"、XLSX 文本 "All text MUST be in English"），翻译后仍需保留此约束
4. **BuildContextInfo 段落标题翻译**：`# Workspace Information`→`# 工作区信息` 等自然语言标题翻译为中文，但其中的路径、文件名等数据保持原样

### 上下游数据流映射（优化依据）

| 模块 | 输出CSV前缀 | 下游消费者 |
| --- | --- | --- |
| Module 1 预处理 | `preprocess_` | Module 2, 4, 6, 7 |
| Module 3 比对设计 | `comparison_` + `design.json` | Module 4, 5 |
| Module 4 差异分析 | `limma_` | Module 5, 10 |
| Module 5 KEGG | `kegg_` | Module 6(GSVA as traits), 10 |
| Module 6 WGCNA | `wgcna_` | Module 7, 10 |
| Module 7 CMeans | `cmeans_` | Module 10 |
| Module 8 贝叶斯 | `bayesian_` | Module 10 |
| Module 9 PLSPM | `plspm_` | Module 10 |
| Module 10 表格 | XLSX文件 | Module 11 |
| Module 11 报告 | HTML/PDF | 最终输出 |


### 统一术语表

- expression matrix → 表达矩阵
- sample info / sample metadata → 样本信息表
- comparison design → 比对组别设计
- differential molecules → 差异分子
- enrichment analysis → 富集分析
- soft threshold power → 软阈值幂次
- module eigengene → 模块特征基因
- confidence ellipse → 置信椭圆
- permutation test → 置换检验

## 实现注意事项

- **性能**：提示词长度变化不影响运行性能；但需注意翻译后不要过度膨胀提示词长度，保持简洁专业
- **向后兼容**：不修改任何 VB.NET 代码逻辑、方法签名、类属性；仅修改字符串内容
- **字符串插值保留**：所有 `{...}` 占位符（如 `{Workspace}`、`{CsvFileNamePrefix}`、`{_config.Analysis.MetaboliteVipCutoff}`）必须原样保留
- **CDATA 块处理**：Module 10/11 使用 `<root><![CDATA[...