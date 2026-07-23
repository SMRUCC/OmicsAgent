---
name: 为R脚本补充程序包加载代码
overview: 分析 rscript 文件夹下每个 R 脚本中通过 `package::function()` 命名空间前缀和 `requireNamespace()` 引用的所有程序包，并在每个脚本最开头（roxygen 注释之前）添加对应的 `library()` 加载代码。共涉及 12 个需要修改的脚本，1 个无需修改的测试脚本，1 个仅使用 base R 函数的脚本。
todos:
  - id: add-lib-data-basic
    content: 为 data_io.R、missing_value.R、differential.R 添加 library() 加载代码
    status: completed
  - id: add-lib-analysis
    content: 为 enrichment.R、clustering.R、qcqa.R 添加 library() 加载代码
    status: completed
  - id: add-lib-multivariate-ml
    content: 为 multivariate.R、machine_learning.R 添加 library() 加载代码
    status: completed
  - id: add-lib-network-wgcna
    content: 为 network.R、wgcna.R 添加 library() 加载代码
    status: completed
  - id: add-lib-visualization
    content: 为 visualization.R 添加 library() 加载代码
    status: completed
---

## 需求概述

用户要求分析 `g:/OmicsWorks/agent/rscript/` 文件夹中每一个 R 脚本，识别出每个脚本通过 `package::function()` 命名空间前缀或 `requireNamespace("package")` 调用所引用的所有 R 程序包，然后在每个脚本文件的最开头位置（第一行之前）补充对应的 `library()` 包加载代码。

## 产品概述

这是一组组学数据分析 R 脚本（OmicsAnalyzer 包的各功能模块），共 13 个文件，涵盖数据输入输出、归一化、缺失值处理、差异分析、富集分析、聚类分析、多元统计、机器学习、网络分析、WGCNA、质量控制和可视化等功能。需要为其中 11 个有外部包引用的脚本添加加载代码，2 个无需修改。

## 核心功能

- 逐脚本扫描所有 `package::function()` 命名空间前缀引用和 `requireNamespace("package")` 检查
- 汇总每个脚本引用的去重程序包列表
- 在每个脚本最开头插入统一格式的注释块和 `library()` 加载代码
- 保留脚本内部原有的 `requireNamespace()` 软依赖检查和 `::` 命名空间调用不变
- `normalization.R`（仅用 base R 函数无命名空间引用）和 `__agent_check.R`（测试文件）无需修改

## 技术栈

- 语言：R
- 操作：在每个 `.R` 文件最开头（第一行 roxygen `#'` 注释之前）插入包加载代码块

## 实现方案

### 分析方法

通过完整阅读每个 R 脚本源码，识别以下两种包引用模式：

1. `package::function()` — 命名空间前缀调用（如 `ggplot2::ggplot()`、`stats::aov()`）
2. `requireNamespace("package")` — 软依赖检查（如 `requireNamespace("limma")`）

将两种模式引用的包名去重合并，作为该脚本的依赖包列表。

### 代码块格式

每个脚本最开头插入统一格式的注释块 + `library()` 调用 + 空行：

```
# ============================================================
# Required packages
# ============================================================
library(pkg1)
library(pkg2)

```

空行之后接脚本原有内容，不修改任何已有代码。

### 设计决策

1. **包含 base R 包**：`stats`、`utils`、`grDevices`、`grid` 等 base 包虽默认已加载，但脚本中使用了 `::` 前缀显式引用，因此在 library() 列表中一并列出，使依赖关系清晰完整。`library()` 对已加载包无害。
2. **不修改函数内部逻辑**：保留原有 `requireNamespace()` 检查和 `::` 命名空间调用不变，仅在文件顶部追加 `library()` 加载代码。这是最小侵入式修改，不影响现有软依赖设计。
3. **`%>%` 管道操作符**：`machine_learning.R` 中使用了 `%>%`（来自 magrittr，由 dplyr 重新导出），`library(dplyr)` 即可使 `%>%` 可用，无需单独加载 magrittr。
4. **无需修改的文件**：`normalization.R` 仅使用 base R 函数（colSums、sweep、apply、median 等），无任何 `::` 前缀引用；`__agent_check.R` 仅一行 `cat()` 调用，无包引用。

### 各脚本待添加的包列表

| 脚本 | 包列表 |
| --- | --- |
| clustering.R | e1071, reshape2, ggplot2, grDevices |
| data_io.R | utils |
| differential.R | stats, limma |
| enrichment.R | stats, ggplot2, grDevices, GSVA |
| machine_learning.R | randomForest, dplyr, ggplot2, grDevices, stats, glmnet, reshape2 |
| missing_value.R | impute |
| multivariate.R | stats, ggplot2, grDevices, ggrepel, mixOmics, ropls |
| network.R | bnlearn, igraph, ggplot2, grDevices, grid, ggrepel, plspm |
| qcqa.R | stats, ggplot2, grDevices |
| visualization.R | ggplot2, grDevices, ggrepel, ggVennDiagram, VennDiagram, RColorBrewer, grid, UpSetR, pheatmap |
| wgcna.R | WGCNA, stats, ggplot2, grDevices, reshape2 |
| normalization.R | 无需修改 |
| __agent_check.R | 无需修改 |


## 实现注意事项

- 插入位置必须在文件第一行之前，确保 `library()` 在任何函数定义和 roxygen 注释之前执行
- 包名顺序按 base 包在前、第三方包在后的逻辑排列，同类型包聚集
- `library()` 调用顺序应与脚本中首次出现的引用顺序大致对应
- 插入后确保新代码块末尾有空行分隔，不破坏原有 roxygen 文档块格式