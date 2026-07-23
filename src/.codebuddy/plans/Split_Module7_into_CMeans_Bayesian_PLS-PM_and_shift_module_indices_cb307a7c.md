---
name: Split Module7 into CMeans/Bayesian/PLS-PM and shift module indices
overview: 将 Module7_Advanced.vb 拆分为 Module7_CMeans、Module8_Bayesian、Module9_PLSPM 三个独立分析模块，将原 Module8_ResultTables 和 Module9_Report 的索引顺延为 10 和 11（同时重命名文件），并更新所有引用 ModuleIndex 的代码。
todos:
  - id: create-split-modules
    content: 创建 Module7_CMeans.vb、Module8_Bayesian.vb、Module9_PLSPM.vb 三个新文件，从 Module7_Advanced.vb 拆分内容，然后删除原 Module7_Advanced.vb
    status: completed
  - id: rename-shift-modules
    content: 重命名 Module8_ResultTables.vb 为 Module10_ResultTables.vb（索引8→10），重命名 Module9_Report.vb 为 Module11_Report.vb（索引9→11），更新各自的 ModuleIndex、注释、CSV分组逻辑和计划提示词
    status: completed
    dependencies:
      - create-split-modules
  - id: update-workflow-references
    content: 更新 Workflow.vb 的 CreateModule 分发逻辑、报告模块检测(8/9→10/11)、自定义模块偏移(10→12)、强制报告检查(9→11)
    status: completed
    dependencies:
      - create-split-modules
      - rename-shift-modules
  - id: update-config-and-docs
    content: 更新 Opts.vb 默认模块列表(1-9→1-11)、Program.vb 帮助文本、JsonDefinedModule.vb 注释、README.md 文档
    status: completed
    dependencies:
      - create-split-modules
      - rename-shift-modules
---

## 产品概述

将现有的 Module7_Advanced.vb（包含 CMeans + Bayesian + PLS-PM 三种进阶分析）拆分为三个独立的分析模块，使每个模块专注于单一分析方法。同时将原 Module8（结果表格整理）和 Module9（论文报告）的索引顺延为 10 和 11，并同步更新项目中所有引用 ModuleIndex 的代码。

## 核心功能

- 将 Module7 拆分为 Module7_CMeans（模糊聚类）、Module8_Bayesian（动态贝叶斯网络）、Module9_PLSPM（因果路径分析）三个独立模块
- 将原 Module8_ResultTables 重命名为 Module10_ResultTables（索引 8→10）
- 将原 Module9_Report 重命名为 Module11_Report（索引 9→11）
- 更新 Workflow.vb 的 CreateModule 分发逻辑、报告模块检测逻辑、自定义模块起始索引
- 更新 Opts.vb 默认模块列表、Program.vb 帮助文本、JsonDefinedModule.vb 注释
- 更新 ResultTables 模块的 CSV 分组逻辑（将 Advanced 分组拆分为 3 组）
- 更新 Report 模块的计划提示词章节结构
- 更新 README.md 文档

## 技术栈

- 语言：VB.NET (.NET 10, SDK-style 项目)
- 项目文件：OmicsAgent.vbproj（使用 globbing 自动包含 .vb 文件，无需手动修改项目文件）
- 架构模式：每个分析模块继承 AnalysisModuleBase，通过 ModuleIndex 属性标识序号，Workflow.vb 中 CreateModule 函数按索引分发实例

## 实现方案

### 拆分策略

将 Module7_Advanced.vb 的 `GeneratePlanPromptText()` 和 `GetConclusionItems()` 内容按原始三个分析主题拆分：

- **CMeans (Module 7)**：原始 items 1-3（模糊聚类、KEGG 富集、WGCNA 关联分析），CsvFileNamePrefix = "cmeans_"
- **Bayesian (Module 8)**：原始 item 4（bnlearn 动态贝叶斯网络，时间序列数据），CsvFileNamePrefix = "bayesian_"
- **PLS-PM (Module 9)**：原始 item 5（PLS-PM 因果路径分析，多组学数据），CsvFileNamePrefix = "plspm_"

每个新模块遵循现有模式：继承 AnalysisModuleBase，实现 ModuleName、ModuleIndex、CsvFileNamePrefix、GeneratePlanPromptText、GetConclusionItems 五个成员。

### 索引顺延策略

- Module8_ResultTables.vb → Module10_ResultTables.vb，ModuleIndex 8→10
- Module9_Report.vb → Module11_Report.vb，ModuleIndex 9→11
- 自定义模块起始索引 10→12

### 关键技术决策

- **文件重命名**：保持 ModuleN_Name.vb 命名规范一致性，重命名文件而非仅改索引值
- **CSV 分组拆分**：ResultTables 模块的 GroupCsvByTheme 中将 "Advanced_Analysis_Results" 拆分为 "CMeans_Clustering_Results"、"Bayesian_Network_Results"、"PLSPM_Causal_Results" 三组，匹配新的模块结构
- **动态索引解析不受影响**：Module9_Report.vb 使用 regex `analysis_modules_(\d+)` 动态解析模块目录，Module8_ResultTables.vb 使用 glob `analysis_modules_*` 扫描目录，两者均已支持任意索引值

## 实现注意事项

- **.vbproj 无需修改**：SDK-style 项目自动 globbing 包含 .vb 文件
- **向后兼容性**：已有工作区中 analysis_modules_8/ 和 analysis_modules_9/ 目录不会自动迁移，但新运行将使用新索引
- **性能无影响**：仅改变模块分发逻辑，不涉及算法或数据流变更
- **日志一致性**：AnalysisModuleBase.RunAsync 中使用 ModuleIndex 输出日志，索引变更后日志自动反映新值

## 目录结构

```
Modules/Standard/
├── Module1_Preprocessing.vb        # [不变] 预处理模块
├── Module2_PCA.vb                  # [不变] PCA分析模块
├── Module3_ComparisonDesign.vb     # [不变] 比对组设计模块
├── Module4_Limma.vb                # [不变] LIMMA差异分析模块
├── Module5_KEGG.vb                 # [不变] KEGG功能分析模块
├── Module6_WGCNA.vb                # [不变] WGCNA模块
├── Module7_CMeans.vb               # [NEW] CMeans模糊聚类分析模块。从Module7_Advanced.vb拆分，包含模糊聚类、KEGG富集、WGCNA关联分析。ModuleIndex=7, CsvFileNamePrefix="cmeans_"
├── Module8_Bayesian.vb             # [NEW] 动态贝叶斯网络分析模块。从Module7_Advanced.vb拆分，包含bnlearn网络构建和调控关系识别。ModuleIndex=8, CsvFileNamePrefix="bayesian_"
├── Module9_PLSPM.vb                # [NEW] PLS-PM因果路径分析模块。从Module7_Advanced.vb拆分，包含潜变量构建和路径系数估计。ModuleIndex=9, CsvFileNamePrefix="plspm_"
├── Module10_ResultTables.vb        # [MODIFY+重命名] 原Module8_ResultTables.vb。ModuleIndex 8→10。更新GroupCsvByTheme拆分为3组，更新ThemeDisplayName，更新计划提示词和注释
└── Module11_Report.vb              # [MODIFY+重命名] 原Module9_Report.vb。ModuleIndex 9→11。更新GeneratePlanPromptText中Results章节结构

Modules/
├── JsonDefinedModule.vb            # [MODIFY] 更新注释：自定义模块起始索引 10→12

Workflow.vb                         # [MODIFY] 更新CreateModule分发(7-11+自定义12+)、报告模块检测(8/9→10/11)、自定义模块偏移(10→12)、强制报告检查(9→11)

AppRuntime/
├── Opts.vb                         # [MODIFY] 默认模块列表 {1..9} → {1..11}

Program.vb                          # [MODIFY] 帮助文本 1-9 → 1-11

README.md                           # [MODIFY] 更新模块列表、项目结构、命令行参数说明、分析模块说明章节

[DELETE] Modules/Standard/Module7_Advanced.vb  # 拆分完成后删除原文件
```

## 关键代码结构

### 新模块基类继承模式（以 CMeans 为例）

```
Public Class CMeansAnalysisModule : Inherits AnalysisModuleBase
    Public Overrides ReadOnly Property ModuleName As String = "CMeans Fuzzy Clustering Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 7
    Public Overrides ReadOnly Property CsvFileNamePrefix As String = "cmeans_"
    ' GeneratePlanPromptText() - CMeans聚类+KEGG富集+WGCNA关联
    ' GetConclusionItems() - 聚类结果总结条目
End Class
```

### Workflow.vb CreateModule 更新后的分发逻辑

```
Case 7 : Return New CMeansAnalysisModule(_config, _context, _logger)
Case 8 : Return New BayesianNetworkModule(_config, _context, _logger)
Case 9 : Return New PLSPMAnalysisModule(_config, _context, _logger)
Case 10 : Return New ResultTablesModule(_config, _context, _logger)
Case 11 : Return New ReportModule(_config, _context, _logger)
Case Is >= 12
    Dim customIdx = index - 12  ' 偏移量从10改为12
```