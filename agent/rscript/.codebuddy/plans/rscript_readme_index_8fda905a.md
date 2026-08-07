---
name: rscript_readme_index
overview: 扫描 rscript/ 下全部 52 个 R 脚本，提取其中所有 @export 公开函数的 roxygen 文档（功能、参数、返回值、是否直接落盘），按分类目录组织，生成一份中文的 R 函数索引 readme.md。
todos:
  - id: extract-functions
    content: 使用 [subagent:code-explorer] 提取全部 52 脚本中 @export 函数文档并按目录归类
    status: completed
  - id: write-overview
    content: 撰写 readme 总览与快速开始：source_all_scripts 加载、OmicsData、export 落盘约定
    status: completed
    dependencies:
      - extract-functions
  - id: write-index
    content: 按目录分章节编写函数索引：功能、参数表、返回值、输出文件说明
    status: completed
    dependencies:
      - extract-functions
      - write-overview
  - id: review-consistency
    content: 复核 readme 与脚本一致性，修正 @export 范围、参数默认值与落盘描述
    status: completed
    dependencies:
      - write-index
---

## 用户需求

扫描 `rscript/` 目录下全部 52 个 R 脚本，阅读其 roxygen2 风格的注释与代码，生成一份中文的 R 函数索引文件 `readme.md`（当前为空文件，直接覆盖）。

## 产品概述

`readme.md` 作为整个 OmicsFlow R 工具集的函数参考手册：按功能目录分类，逐函数说明功能、所在脚本相对路径、输入参数（名称/类型/默认值/格式）、返回值，以及脚本“输出的结果文件”。

## 核心特性

- 覆盖全部 52 个脚本中所有 `@export` 的公开函数（含 utils、preprocessing、visualization 等工具函数），跳过 `@keywords internal`/`@noRd` 内部辅助函数。
- 每个函数条目包含：函数名、所在脚本、功能简述（中文）、参数表（名称/类型/默认值/格式）、返回值（中文）、输出文件说明。
- 输出文件区分两类：直接写盘的函数（如生成 `.xlsx`/`.csv`）；仅返回 R 对象、需经 `export_table`/`export_plot`/`export_heatmap` 保存的惯例。
- 开头提供总览、加载方式（`source_all_scripts.R`）、公共数据结构（OmicsData）与导出约定，便于按索引上手调用。
- 全文中文撰写，函数名与参数名保留英文原文。

## 技术方法

此为纯文档生成任务，无新运行时代码，复用脚本既有的 roxygen2 注释规范（`#' @description`、`#' @param <name> <说明>`、`#' @return`、`#' @examples`、`#' @export`）。

### 提取与判定策略

1. **函数定位**：逐文件定位 `name <- function(...)` 定义，捕获其上方 roxygen 块；以是否存在 `#' @export` 作为公开函数收录依据，以 `@keywords internal`/`@noRd` 作为剔除依据。
2. **参数与返回值**：直接解析 `@param`/`@return` 文本，保留类型、默认值与格式说明（如 `expr_matrix` 为 features×samples 数值矩阵、`sample_info` 为含 `ID/sample_name/sample_info` 列的 data.frame）；无默认值的必填参数标注“必填”。
3. **输出文件判定**：

- 直接写盘：扫描函数体是否调用 `write.csv`/`saveWorkbook`/`openxlsx`/`pdf()`/`png()`/`ComplexHeatmap::draw`+`dev.off` 等，标注生成的具体扩展名与路径来源（如 `compile_csv_to_xlsx()` 依据 `output_xlsx` 生成 `.xlsx`；`extract_sheets.R` 直接读写）。
- 对象返回：对返回 ggplot/数据框/列表的分析函数，统一说明“返回 R 对象，需用 `utils/export.R` 中的 `export_plot`/`export_table`/`export_heatmap` 落盘（生成 `<filename>.pdf`+`.png` 或 `<filename>.csv`）”。

4. **分类组织**：沿用现有目录（根目录/differential/enrichment/multivariate/machine_learning/network/multiomics/visualization/utils/qcqa/preprocessing），每章聚合该目录脚本的函数，保持与代码目录一致，便于扩展时按章追加。

### 公共上下文（务必在总览章呈现）

- 入口 `source_all_scripts.R`：递归 source 全部脚本（跳过自身），utils/、qcqa/ 优先。
- 公共数据对象 `OmicsData`（`utils/load_data.R` 的 `create_omics_data`/`load_expression_matrix`/`load_sample_info`/`load_feature_info`/`print.OmicsData`），多数分析函数的统一输入。
- 导出约定（`utils/export.R`）：`export_plot`、`export_heatmap`、`export_table` 的签名与产物。

### 性能与可靠性

- 一次性批量读取/抽取 52 个文件，避免重复磁盘扫描；对大文件（如 `multiomics/association_network.R` 28KB、`plot_dbn_plspm.R` 36KB）仅抽取注释与签名，不逐行解释实现。
- 落盘判定基于只读扫描，不执行任何脚本，避免副作用。
- 复核阶段以 `@export` 集合为基准对账，确保无遗漏、无内部函数误入。

## 目录结构

```
rscript/
└── readme.md   # [MODIFY/覆盖] R 函数索引。结构：总览 → 快速开始（加载/OmicsData/导出约定）→ 按目录分章函数索引（参数表+返回值+输出文件）→ 附录。全文中文，函数名参数名保留英文。
```

## 关键说明（无需代码）

- 不新增任何 R 代码或目录，仅产出 `readme.md`。
- 文件规模较大（预计 52 脚本、100+ 公开函数），按章分节、参数用表格呈现以保证可读性与可维护性。

## Agent Extensions

### SubAgent

- **code-explorer**
- Purpose: 高效扫描 rscript/ 下全部 52 个 R 脚本，逐文件提取每个 `@export` 公开函数的 roxygen 文档（函数名、所在路径、参数名/类型/默认值/格式、`@return`、函数体内是否直接写盘），并跳过 `@keywords internal`/`@noRd` 函数，按目录归类输出结构化清单。
- Expected outcome: 提供一份分目录、逐函数的结构化抽取结果，作为编写 readme.md 的事实依据，避免主代理逐个大文件全文读取导致的上下文膨胀与遗漏。