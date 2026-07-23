---
name: result-tables-per-module-rewrite
overview: 将 Module10_ResultTables.vb 的 GenerateAndRunScriptAsync 逻辑重写为：用 For 循环遍历 _context.ModuleResults，针对每个模块扫描其 Workdir 下的 CSV，调用 LLM 生成英文注释（结合该模块 Goal/Conclusion 与 kb.json），再调用 LLM 编写并执行 openxlsx R 脚本，按现有 xlsx 样式生成单个 xlsx 文件并保存到该模块的 OutputDir。
todos:
  - id: rewrite-orchestration
    content: 重写 GenerateAndRunScriptAsync 为 per-module 循环，新增 CollectModuleCsvFiles / ReadKnowledgeBaseContent / GetModuleXlsxFileName 辅助方法，删除 CollectResultCsvFiles / GroupCsvByTheme / ThemeDisplayName
    status: completed
  - id: rewrite-annotation
    content: 重写注释生成为 GenerateAnnotationsForModuleAsync，提示词包含 Goal/Conclusion/kb.json/CSV表头，生成单模块注释JSON
    status: completed
    dependencies:
      - rewrite-orchestration
  - id: rewrite-rscript-prompt
    content: 重写 BuildRScriptPrompt 适配单模块单xlsx输出至 OutputDir，更新 GeneratePlanPromptText 与 GetConclusionItems
    status: completed
    dependencies:
      - rewrite-annotation
---

## 用户需求

将 `ResultTablesModule`（模块10）的逻辑从"全局扫描所有CSV按主题分组生成多个xlsx"改为"按模块逐一处理"。

## 产品概述

`ResultTablesModule` 是组学分析流程的倒数第二个模块，负责将各分析模块产生的中间结果CSV表格编译为格式化的xlsx文件。修改后，该模块将遍历 `_context.ModuleResults` 列表中每个已完成模块的分析结果，为每个模块独立生成一个xlsx文件。

## 核心功能

- 通过 For Each 循环遍历 `_context.ModuleResults` 中的每个 `ModuleResult`
- 对每个模块，递归列举 `ModuleResult.Workdir` 中的所有 CSV 文件，跳过无CSV的模块
- 调用 LLM 结合当前模块的 `Goal`、`Conclusion` 以及 `kb.json` 知识库内容，为每张sheet生成英文注释（讲解分析结果内容 + 每一列的具体含义）
- 调用 LLM 编写 R 脚本（openxlsx），按已有样式规范生成单个 xlsx 文件，保存到当前模块的 `ModuleResult.OutputDir`
- xlsx 样式保持不变：Cambria Math 11号字体、缩放90%、第一列浅灰斜体、第一行草绿注释、第二行深蓝白字加粗表头、freezePane B3
- 注释信息全英文，涵盖表内容讲解、每列含义说明、以及与模块分析目标和知识库生物学知识的关联

## 技术栈

- 语言: VB.NET（现有项目，.NET Framework）
- LLM 交互: Ollama LLMClient + Function Calling（write_file / run_rscript 等工具）
- xlsx 生成: R 语言 openxlsx 包（由 LLM 编写脚本，ShellTool 执行）
- 无新增依赖，完全基于现有项目架构

## 实现方案

### 整体策略

重写 `GenerateAndRunScriptAsync` 为 per-module 循环架构。每个模块独立走两阶段流程：先由独立 LLM 客户端生成注释 JSON，再由独立 LLM 客户端编写并执行 R 脚本。两个阶段均创建新的 LLMClient 实例以避免 token 累积（遵循基类 `GeneratePlanAsync` / `GenerateConclusionAsync` 各自创建独立 LLM 的模式）。

### 关键技术决策

1. **每模块独立 LLM 客户端**：注释生成和 R 脚本生成各创建独立 `LLMClient`，避免多模块间对话上下文累积导致 token 溢出或指令混淆。这与基类中 plan/conclusion 各用独立 LLM 的模式一致。

2. **CSV 递归收集**：使用 `Directory.GetFiles(mr.Workdir, "*.csv", SearchOption.AllDirectories)` 递归收集 Workdir 下所有 CSV，确保不遗漏子目录中的文件。

3. **注释 JSON 结构简化**：从原来的多 xlsx_files 数组结构简化为单模块结构（一个 xlsx + sheets 数组），降低 LLM 生成复杂度。

4. **错误隔离**：单个模块处理失败时记录日志并 Continue For，不影响其他模块处理。

5. **kb.json 读取复用**：在循环外一次性读取 kb.json 内容（带30000字符截断），传入每模块的注释提示词，避免重复 I/O。

### 性能与可靠性

- **I/O 优化**：kb.json 在循环外读取一次，复用于所有模块的注释提示词
- **LLM 调用量**：每模块 2 次 LLM 调用（注释 + R脚本），N 个模块共 2N 次，属于合理范围
- **错误恢复**：单模块失败不中断整体流程，日志记录错误信息供排查
- **输出路径**：xlsx 和注释 JSON 均保存到 `mr.OutputDir`，便于追溯

## 架构设计

### 数据流

```
_context.ModuleResults (List(Of ModuleResult))
    │
    For Each mr As ModuleResult
    │
    ├─ 1. CollectModuleCsvFiles(mr.Workdir) → CSV文件列表
    │     (跳过空列表模块)
    │
    ├─ 2. GenerateAnnotationsForModuleAsync(mr, csvFiles, kbContent)
    │     ├─ 构建骨架JSON (csv路径 + sheet名 + 空注释)
    │     ├─ LLM提示词: mr.Goal + mr.Conclusion + kb.json + CSV表头
    │     └─ 返回填充注释的JSON → 保存到 mr.OutputDir/table_descriptions.json
    │
    └─ 3. BuildRScriptPrompt + LLM.Chat (function calling)
          ├─ LLM编写R脚本 (write_file)
          ├─ LLM执行R脚本 (run_rscript)
          └─ xlsx保存到 mr.OutputDir/{ModuleIndex}_{ModuleName}.xlsx
```

### xlsx 样式规范（保持不变）

| 元素 | 样式 |
| --- | --- |
| 全局字体 | Cambria Math, 11号 |
| 缩放 | 90% |
| 第1行（注释） | 默认背景, 草绿色字体 #228B22 |
| 第2行（表头） | 深蓝背景 #1F4E79, 白色加粗字体 #FFFFFF |
| 第1列（ID列） | 浅灰背景 #D9D9D9, 斜体, 黑色字体 #000000 |
| 冻结窗格 | B3 (firstRow=3, firstCol=2) |


## 目录结构

```
g:\OmicsWorks\src\
└── Modules\
    └── Standard\
        └── Module10_ResultTables.vb   # [MODIFY] 重写核心逻辑
```

### 文件修改详情

**`Module10_ResultTables.vb`** [MODIFY] — 完整重写核心方法，保留样式规范

- **`GenerateAndRunScriptAsync`** (override 入口): 重写为 per-module For Each 循环。循环外读取 kb.json，循环内依次收集CSV → 生成注释 → 生成R脚本。每模块创建独立 LLMClient。单模块失败时 Continue For。
- **`CollectModuleCsvFiles(workdir)`** [NEW]: 替换原 `CollectResultCsvFiles`。使用 `Directory.GetFiles(workdir, "*.csv", SearchOption.AllDirectories)` 递归收集 Workdir 下所有 CSV。
- **`ReadKnowledgeBaseContent()`** [NEW]: 读取 `_context.KnowledgeBaseFile`（kb.json），截断至30000字符，返回字符串。循环外调用一次。
- **`GetModuleXlsxFileName(mr)`** [NEW]: 根据 `mr.ModuleIndex` 和 `mr.ModuleName` 生成 xlsx 文件名，格式 `{ModuleIndex}_{normalize(ModuleName)}.xlsx`，复用 `NormalizePathString` 扩展方法。
- **`GenerateAnnotationsForModuleAsync(mr, csvFiles, kbContent, ct)`** [NEW]: 替换原 `GenerateAnnotationsAsync`。构建单模块骨架JSON，LLM提示词包含 mr.Goal、mr.Conclusion、kb.json 内容、各CSV表头。要求 LLM 用英文为每张sheet生成注释（讲解内容 + 每列含义 + 生物学关联）。返回填充后的JSON。
- **`BuildRScriptPrompt(descPath, outputDir, xlsxFileName, mr, plan, step)`** [MODIFY]: 适配单模块单xlsx场景。输出目录改为 `mr.OutputDir`，xlsx 文件名使用 `GetModuleXlsxFileName` 结果。R脚本模板从遍历 `xlsx_files` 数组简化为处理单个模块的 sheets。
- **`GeneratePlanPromptText`** [MODIFY]: 更新计划描述，从"扫描全局目录"改为"遍历已完成的模块结果列表"。
- **`GetConclusionItems`** [MODIFY]: 更新总结条目，反映 per-module xlsx 生成方式。
- **`GetCsvHeader`** [KEEP]: 保持不变。
- **`SanitizeSheetName`** [KEEP]: 保持不变。
- **`CollectResultCsvFiles`** [DELETE]: 被 `CollectModuleCsvFiles` 替代。
- **`GroupCsvByTheme`** [DELETE]: 不再需要主题分组。
- **`ThemeDisplayName`** [DELETE]: 不再需要主题名映射。
- **`GenerateAnnotationsAsync`** [DELETE/REPLACE]: 被 `GenerateAnnotationsForModuleAsync` 替代。

## 关键代码结构

### 注释 JSON 结构（单模块）

```
{
  "module_name": "Expression Matrix Preprocessing",
  "module_index": 1,
  "goal": "<mr.Goal>",
  "conclusion": "<mr.Conclusion>",
  "xlsx_file": "1_expression_matrix_preprocessing.xlsx",
  "output_dir": "<mr.OutputDir absolute path>",
  "sheets": [
    {
      "csv": "<absolute csv path>",
      "sheet_name": "<sanitized english sheet name>",
      "annotation": "<english annotation: content + column meanings>"
    }
  ]
}
```

### R 脚本提示词关键差异

原模板遍历 `desc$xlsx_files[[i]]` 多文件，新模板改为读取单模块 JSON 后直接遍历 `desc$sheets[[j]]`，输出路径为 `file.path(desc$output_dir, desc$xlsx_file)`。