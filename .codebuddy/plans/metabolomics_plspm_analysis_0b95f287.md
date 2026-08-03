---
name: metabolomics_plspm_analysis
overview: 在 demo_metabolomics.R 中新增一个 PLS-PM 分析步骤：基于 kegg 通路（经 kegg_mapping 展开）和 super_class 分类分别构建潜变量、合并后做全连接 PLS-PM 路径分析，并导出路径系数表与路径网络图。必要时修改 agent/rscript/network/plspm_net.R 以支持分组潜变量的正确构建。
todos:
  - id: add-build-latent-def
    content: 在 plspm_net.R 新增 build_latent_def_from_annotation 函数，按 super_class 与 kegg_mapping 展开潜变量
    status: completed
  - id: fix-run-plspm-guard
    content: 加固 run_plspm 对向量形式 latent_def 的处理并保留既有接口
    status: completed
    dependencies:
      - add-build-latent-def
  - id: add-demo-step25
    content: 在 demo_metabolomics.R 新增 Step 25 调用 PLS-PM 并导出路径表与网络图
    status: completed
    dependencies:
      - add-build-latent-def
  - id: update-summary
    content: 在 demo_metabolomics.R 末尾 Summary 追加 PLS-PM 潜变量数与显著路径数
    status: completed
    dependencies:
      - add-demo-step25
---

## 用户需求

在代谢组学分析流程 `test/omics_flow/demo_metabolomics.R` 中新增一个 PLS-PM（偏最小二乘路径模型）分析项目。

## 产品概述

基于代谢物注释信息，分别利用 KEGG ID 对应的 KEGG 通路（经 `kegg_mapping` 多对多展开）以及 `super_class` 分类构建潜变量，将两类潜变量合并后执行全连接 PLS-PM 路径分析，导出路径系数/显著性结果表与路径网络图。

## 核心功能

- 按 `super_class` 分类构建潜变量（每组 feature 名称向量，组内样本数 ≥2）。
- 按 KEGG 通路构建潜变量（feature_info$kegg 关联 kegg_mapping 的 compound→pathway，每个通路一组 feature，组内样本数 ≥2；一个化合物属多个通路时自然进入多个潜变量组）。
- 合并上述两类潜变量定义，调用 `run_plspm` 做全连接（两两线性回归）路径拟合。
- 导出路径分析结果表（from/to/path_coeff/p_value）至 `tables/`。
- 导出路径网络图（圆形布局、显著路径实线/非显著虚线）至 `figures/`。
- 在流程末尾 Summary 中打印 PLS-PM 潜变量数量与显著路径数量。
- 必要时修正 `agent/rscript/network/plspm_net.R` 中潜变量构建相关逻辑，并新增分组展开辅助函数。

## 技术栈

- 语言/环境：R（Rscript），沿用现有管线约定。
- 已有依赖：`plspm_net.R`（`run_plspm`、`plot_plspm_network`）、`kegg_pathway.R`（提供 `kegg_mapping` 接口与数据）、`utils/load_data.R`（`load_feature_info`）、通用导出函数 `export_table`/`export_plot`。
- 可视化：ggplot2 + ggrepel（已在脚本中加载）。

## 实现方案

### 总体策略

保持现有 24 个 Step 不变，在 Step 24 之后作为 Step 25 追加 PLS-PM 分析；在管线函数层新增一个分组展开辅助函数，将 `feat_info` 的 `super_class` 列与 `kegg_mapping` 通路展开为符合 `run_plspm` 的 `latent_def`（命名 list，元素为 feature 名称向量），再调用现有 `run_plspm`（inner_model=NULL，全连接）与 `plot_plspm_network` 完成分析与绘图。

### 关键技术决策

1. **新增 `build_latent_def_from_annotation()`**：核心新增函数。直接产出"feature 名称向量"形式的 `latent_def`，避开现有 `run_plspm` 对"列名分组"的缺陷（第 62-66 行 `feature_info[common_features, lv_def] == lv_def[1]` 逻辑错误，只会匹配等于列名本身的行）。由于辅助函数已给出正确向量，主体 `run_plspm` 无需改动即可正常工作，降低回归风险。
2. **KEGG 通路展开**：用 `feature_info$kegg` 与 `kegg_mapping$compound_id` 建立映射（compound→pathway 多对多），按 `pathway_name` 聚合 feature 名称。一个 feature 属于多个通路时，会分别进入对应潜变量组，各自 `prcomp` 第一主成分作为得分，无需复制矩阵行。
3. **super_class 展开**：按 `super_class` 列拆分非空类别，聚合 feature 名称。
4. **全连接拟合**：沿用 `run_plspm` 默认 `inner_model=NULL`，对所有潜变量两两 `lm` 得到 `path_mat` 与 `inner_summary`（含 p 值），满足用户确认的"全连接自动拟合"。
5. **稳健性**：Step 25 用 `tryCatch` 包裹（与 Step 19/21-24 一致），`kegg_mapping` 不存在时跳过 KEGG 部分仅用 super_class；导出沿用 `export_table`/`export_plot`。

### 性能与可靠性

- 潜变量数量取决于通路/类别数（可能数十个），全连接需 O(n²) 次 `lm`，n 为潜变量数；本数据集规模下开销可忽略。
- `prcomp` 在每组 feature（通常 2~数十个）× 样本数上计算，开销极小。
- 风险点：部分通路样本数 <2 时 `run_plspm` 内部 `length(lv_features) < 2` 会 `next` 跳过，需在辅助函数层用 `min_size=2` 过滤，避免出现单一 feature 无法 PCA 的情况。
- 路径网络图节点较多时布局拥挤，但现有 `plot_plspm_network` 已通过实/虚线区分显著路径，满足可读性；如需可后续增加仅显示显著路径的开关（不在本次范围）。

## 实现说明（防止回归）

- 仅在 `demo_metabolomics.R` 末尾追加 Step 25 与 Summary 打印项，不影响既有 Step。
- 辅助函数新增于 `agent/rscript/network/plspm_net.R`，命名与现有风格一致（`build_latent_def_from_annotation`），不影响 `run_plspm`/`plot_plspm_network` 既有签名。
- 复用已加载的全局变量 `feat_info`、`kegg_mapping`、`scaled_mat`、`norm_mat`（建议使用 `scaled_mat` 以保持与其他分析一致）。
- 导出文件名遵循现有约定：`plspm_path_coefficients.csv`、`plspm_pathway_network.png/pdf`。
- 日志复用 `cat()`，不输出大对象；出错时打印 `conditionMessage(e)` 并置成功标志为 FALSE。

## 架构设计

- 数据流：feat_info + kegg_mapping → build_latent_def_from_annotation → latent_def(list) → run_plspm(scaled_mat, feat_info, latent_def) → plspm_result → export_table(inner_model) + plot_plspm_network → 导出。
- 复用现有函数层与导出层，无新架构模式引入。

## 目录结构

```
agent/rscript/network/
└── plspm_net.R                  # [MODIFY] 新增 build_latent_def_from_annotation() 函数：基于 super_class 列与 kegg_mapping 展开潜变量定义；可选加固 run_plspm 列名分支（不影响既有向量接口）。
test/omics_flow/
└── demo_metabolomics.R          # [MODIFY] 在 Step 24 后新增 Step 25（构建 latent_def → run_plspm → 导出路径表与网络图，tryCatch 包裹）；在 Summary 区块追加 PLS-PM 潜变量数与显著路径数打印。
```

## 关键代码结构（新增辅助函数签名）

```
#' Build latent variable definitions from feature annotation
#' @param expr_matrix  numeric matrix (features x samples)
#' @param feature_info data.frame with feature annotations (rownames=feature id, cols: kegg, super_class)
#' @param kegg_mapping data.frame with compound_id, pathway_id, pathway_name (NULL allowed)
#' @param feature_id_col column name for feature id in feature_info (default "name")
#' @param kegg_col column name for KEGG id (default "kegg")
#' @param category_col column name for super class (default "super_class")
#' @param min_size minimum features per latent variable (default 2)
#' @param use_kegg logical, build KEGG pathway LVs (default TRUE)
#' @param use_super_class logical, build super_class LVs (default TRUE)
#' @return named list of character vectors (feature ids) for run_plspm
build_latent_def_from_annotation <- function(expr_matrix, feature_info,
    kegg_mapping = NULL, feature_id_col = "name", kegg_col = "kegg",
    category_col = "super_class", min_size = 2,
    use_kegg = TRUE, use_super_class = TRUE)
```