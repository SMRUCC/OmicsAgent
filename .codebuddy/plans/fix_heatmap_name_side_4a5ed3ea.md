---
name: fix_heatmap_name_side
overview: 修正 agent/rscript/visualization/heatmap_plot.R 中 plot_heatmap() 列注释的 annotation_name_side 参数取值错误，解决 Step 14 Heatmap 报错。
todos:
  - id: fix-heatmap-nameside
    content: 修正 heatmap_plot.R 列注释 annotation_name_side 为 left，行为注释补充 top
    status: completed
---

## 用户需求

执行代谢组学分析流程脚本 `test/omics_flow/demo_metabolomics.R` 时，在 Step 14: Heatmap 阶段报错：

`错误: Group: 'name_side' should be 'left' or 'right' when it is a column annotation.`

用户要求分析报错原因，并修正 `agent/rscript` 文件夹中对应的 R 脚本（`heatmap_plot.R`）的错误，不修改 demo 脚本本身。

## 产品概述

这是一个 R 语言代谢组学分析流程中的热图绘制函数 bug 修复任务。问题出在 `plot_heatmap()` 函数使用 ComplexHeatmap 绘制热图时，对列注释（column annotation）错误地设置了行注释专属的参数取值，导致渲染失败。

## 核心功能

- 修正 `agent/rscript/visualization/heatmap_plot.R` 中 `plot_heatmap()` 的列注释参数 `annotation_name_side` 取值，使其符合 ComplexHeatmap 对列注释的约束（只能为 `left` 或 `right`）。
- 顺带为行注释补充 `annotation_name_side = "top"`，提升注释名称可读性。
- 确保修复后不影响 pheatmap 回退分支及 demo 脚本的其他逻辑。

## 技术栈

- 语言：R（脚本位于 `agent/rscript/visualization/`）
- 可视化依赖：ComplexHeatmap（优先）、pheatmap（回退）
- 复用项目现有约定：颜色映射 `make_group_colors()`、导出函数 `export_heatmap()`

## 实现方案

### 问题根因

在 `agent/rscript/visualization/heatmap_plot.R` 第 89-96 行的 ComplexHeatmap 分支中，`col_anno` 是按列分组（`Group = groups`）的列注释，并作为 `top_annotation` 附加到热图顶部。但代码设置了 `annotation_name_side = "top"`。根据 ComplexHeatmap 的校验规则：

- 列注释（column annotation）的注释名称方向只能为 `'left'` 或 `'right'`。
- 行注释（row annotation）的注释名称方向才能为 `'top'` 或 `'bottom'`。

将列注释误设为 `'top'` 触发了报错。

### 关键修改决策

1. 将 `col_anno` 的 `annotation_name_side = "top"` 改为 `annotation_name_side = "left"`，恢复为合法的列注释取值，直接消除报错。
2. 为 `row_anno`（Family 行注释，第 107-111 行）补充 `annotation_name_side = "top"`，使行注释名称居于顶部，与列注释语义对齐，提升可读性（非触发错误的必需项，但属合理增强）。

### 性能与可靠性

- 该修改仅涉及注释方向的元数据参数，不改变矩阵运算、聚类或绘图画布，无性能开销。
- 保留 pheatmap 回退分支（第 131-167 行）原样不变，确保未安装 ComplexHeatmap 时的兼容性不退化。
- 不改动 demo 脚本及 `gsva.R` 中的 `plot_gsva_heatmap`（其未直接使用该参数）。

## 实现说明

- 仅修改 `heatmap_plot.R` 一个文件，范围小、风险低、向后兼容。
- 修改后建议本地重新 source 该文件并调用 `plot_heatmap(...)` 验证 ComplexHeatmap 分支可正常生成对象。

## 架构设计

本次为单函数单文件的小范围 bug 修复，不涉及架构调整，沿用现有 `visualization/` 模块结构。

## 目录结构

```
agent/rscript/visualization/
└── heatmap_plot.R  # [MODIFY] 修正 plot_heatmap() 中列注释 col_anno 的 annotation_name_side（"top" -> "left"）；为行注释 row_anno 补充 annotation_name_side = "top"。不改变函数签名、返回值及 pheatmap 回退逻辑。
```