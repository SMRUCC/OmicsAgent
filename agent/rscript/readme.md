# OmicsFlow R 脚本函数索引

本索引汇总 `rscript/` 目录下全部 R 脚本中的所有**公开导出函数**（即以 `#' @export` 标注的函数）。每个函数条目包含：功能简述、所在脚本相对路径、输入参数（名称/类型/默认值/格式）、返回值，以及**输出的结果文件**说明。

> 约定：所有脚本仅**定义函数**，不主动执行分析。除明确标注"直接落盘"的函数外，其余分析/可视化函数均**返回 R 对象**（data.frame / 列表 / ggplot / pheatmap 等），需借助 `utils/export.R` 中的导出辅助函数落盘（见下方"导出约定"）。

---

## 总览

### 目录结构

```
rscript/
├── source_all_scripts.R        # 入口：递归 source 全部脚本（无 @export 函数）
├── compile_csv_to_xlsx.R       # 将多个 CSV 合并为单个 .xlsx（直接落盘）
├── extract_sheets.R            # 从 .xlsx 抽取指定工作表写回 CSV（命令行脚本，无 @export）
├── install_packages.R          # 安装全部依赖包（环境准备脚本，无 @export）
├── theme_palette.R             # 配色与主题辅助
├── differential/               # 差异分析：limma / ANOVA / F 检验
├── enrichment/                 # 富集分析：Fisher / GSVA / KEGG
├── machine_learning/           # 机器学习：LASSO / 线性模型 / 随机森林
├── microbiome/                 # 微生物组：α/β多样性 / 分类组成 / LEfSe / 核心 / ANCOM-BC / SparCC
├── multivariate/               # 多变量：PCA / PLS-DA / OPLS-DA
├── network/                    # 网络：贝叶斯网络 / c-means / PLS-PM / WGCNA
├── preprocessing/              # 预处理：缺失值过滤 / 填补 / 归一化 / 标准化
├── proteome/                   # 蛋白质组：GO富集 / 聚类 / PPI / 质控 / 功能谱
├── multiomics/                 # 多组学整合：关联网络 / 轨迹 / DBN / PLS-PM / 通路桥接等
├── qcqa/                       # 质控与质控图（QC/QA）
├── utils/                      # 工具：数据加载 / 导出 / 绘图辅助 / 预定义模块 / KEGG
└── visualization/              # 可视化：火山图 / 曼哈顿 / 热图 / 韦恩 / upset
```

### 快速开始

**1. 加载全部函数**（入口脚本，递归 source 全部脚本，跳过自身，utils/ 与 qcqa/ 优先）：

```r
source("source_all_scripts.R")
```

**2. 公共数据结构 `OmicsData` / `MultiOmicsData`**：

多数分析（尤其 `multiomics/`）的统一输入。

- `utils/load_data.R`：
  - `create_omics_data(expr_matrix, sample_info, feature_info = NULL, ...)`：构造单组学对象。`expr_matrix` 为 features × samples 数值矩阵；`sample_info` 为 data.frame，行名需匹配 `expr_matrix` 列名。
  - `load_expression_matrix(path, ...)` / `load_sample_info(path, ...)` / `load_feature_info(path, ...)`：从 CSV/TSV 读取对应组成部分。
- `multiomics/multiomics_data.R`：
  - `create_multiomics_data(expr_list, sample_info, feature_info_list = NULL, match_cols = NULL)`：构造 `MultiOmicsData`。`expr_list` 为命名列表，每个元素为一个组学层的表达矩阵（features × samples）；`sample_info` 为样本注释；`feature_info_list` 可选（与各层对应的特征注释列表）；`match_cols` 可选（匹配键列）。
  - 取数辅助：`get_omics_matrix(mo, name)`、`get_omics_list(mo, layers = NULL)`、`get_feature_info(mo, name)`。

**3. 导出约定**（`utils/export.R`）：返回对象需经以下函数落盘。

| 函数 | 签名要点 | 产物 |
| --- | --- | --- |
| `export_plot` | `(plot, output_dir, filename, width = 8, height = 6, dpi = 300)` | `<output_dir>/<filename>.pdf` + `.png` |
| `export_heatmap` | `(plot, output_dir, filename, width = 8, height = 6, dpi = 300)` | `<output_dir>/<filename>.pdf` + `.png` |
| `export_table` | `(data, output_dir, filename, use_rownames = TRUE, id_col_name = "ID")` | `<output_dir>/<filename>.csv` |

> 所有返回 ggplot/pheatmap 对象的绘图函数，在文档示例中以 `export_plot` / `export_heatmap` 保存；所有返回 data.frame/列表的分析函数，以 `export_table` 保存其表格成分。本索引统一注明"返回 R 对象，需经 `export_*` 保存"。

---

## 根目录脚本

### `source_all_scripts.R`

递归 source 全部 `.R` 脚本（跳过自身），`utils/` 与 `qcqa/` 优先加载。无参数、无返回值，仅在控制台打印加载汇总。**不落盘**。

### `compile_csv_to_xlsx.R`

**`compile_csv_to_xlsx`** — 将多个 CSV 文件合并写入单个 Excel 工作簿。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `csv_paths` | 字符向量，CSV 文件路径（可含 glob 通配符） | 必填 |
| `output_xlsx` | 字符，输出 .xlsx 路径 | 必填 |
| `json_path` | 字符，可选 JSON，描述每个 CSV 对应的工作表名与内容 | `NULL` |

- **返回值**：无（返回不可见 `NULL`）。
- **输出文件（直接落盘）**：生成 `output_xlsx` 指定的单个 `.xlsx`，每个 CSV 对应一个工作表（工作表名取自文件名或 JSON 描述）。

### `extract_sheets.R`

命令行脚本：从给定 `.xlsx` 抽取指定工作表写回独立 CSV。配合 `Rscript extract_sheets.R <input.xlsx> <sheet1,sheet2,...> [outdir]` 运行。**不含 `@export` 函数**，通常不通过 `source()` 调用，输出由命令行参数决定。

### `install_packages.R`

环境准备脚本：检测并安装本项目依赖的全部 R 包（CRAN + Bioconductor）。**无 `@export` 函数**，通常在初始化环境时直接 `source()` 或 `Rscript` 运行。

### `theme_palette.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `get_npg_palette` | 返回 Nature Publishing Group 风格配色向量 | `n`（必填，颜色数） | 命名字符向量。返回对象 |
| `theme_pub` | 发表级 ggplot 主题 | `base_size = 13` | ggplot 主题对象。返回对象 |
| `setup_base_font` | 设置基础字体（影响 pdf/png 输出） | 无参数 | 无（副作用设置图形设备字体） |
| `save_plot_unified` | 统一保存 ggplot 至 pdf+png | `plot`（必填）；`filename`（必填）；`width = 8`；`height = 6`；`dpi = 300`；`device = c("pdf","png")` | **直接落盘**：`<output_dir>/<filename>.pdf` + `.png` |

---

## `differential/`（差异分析）

### `differential/limma_de.R`

**`run_limma`** — 基于 limma 的线性模型差异表达分析（含经验贝叶斯平滑）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame，行名对应样本列 | 必填 |
| `group_col` | 字符，分组列名 | `"sample_info"` |
| `control_group` | 字符，对照/参考组名（NULL 则取字母序第一组） | `NULL` |
| `case_groups` | 字符向量，与对照比较的组（NULL 则所有非对照组） | `NULL` |
| `exclude_groups` | 字符向量，建模前剔除的分组（如 `"QC"`） | `"QC"` |
| `strategy` | 字符，筛选策略：`"pvalue_logFC"` / `"pvalue_vip"` / `"pvalue_topN"` | `"pvalue_logFC"` |
| `p_threshold` | 数值，p 值阈值 | `0.05` |
| `logfc_threshold` | 数值，logFC 绝对值阈值 | `1` |
| `vip_threshold` | 数值，VIP 阈值（strategy="pvalue_vip" 用） | `1.0` |
| `top_n` | 数值，"pvalue_topN" 策略下按 logFC 取前 N | `20` |
| `p_adj_method` | 多重检验校正方法 | `"BH"` |
| `vip_result` | PLS-DA 的 VIP 结果（strategy="pvalue_vip" 时必填） | `NULL` |

- **返回值**：列表，含 `results`（合并结果 data.frame：feature_id、logFC、AveExpr、t、P.Value、adj.P.Val、B、significant、regulation 等）、`significant`（显著特征子集）、`comparisons`（每对比 data.frame 列表）、`strategy`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `results`（注意行名即 feature_id，建议 `use_rownames=TRUE`）。

### `differential/anova.R`

**`run_anova`** — 多因素方差分析（可同时检验多个因子，如处理×时间×批次）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame，样本注释 | 必填 |
| `factors` | 字符向量，用作因子的列名（如 `c("sample_info")` 或 `c("sample_info","condition")`） | `"sample_info"` |
| `exclude_groups` | 命名列表，按因子指定需剔除的分组（如 `list(sample_info="QC")`） | `NULL` |
| `p_adj_method` | 多重检验校正方法 | `"BH"` |

- **返回值**：列表，含 `results`（data.frame：feature_id、各因子的 F_stat/p_value/p_adj）、`factor_results`（每因子单独的 data.frame 列表）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `results`（注意行名即 feature_id，建议 `use_rownames=TRUE`）。

### `differential/f_test.R`

**`run_f_test`** — F 检验（单因素方差分析，检验组间整体差异）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame，样本注释 | 必填 |
| `group_col` | 字符，分组列名 | `"sample_info"` |
| `exclude_groups` | 字符向量，建模前剔除的分组（如 QC） | `"QC"` |
| `p_adj_method` | 多重检验校正方法 | `"BH"` |

- **返回值**：data.frame，含 `feature_id`（行名）、`F_stat`、`p_value`、`p_adj`、`significant`（p_adj<0.05）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存（注意默认行名即 feature_id，建议 `use_rownames=TRUE`）。

---

## `enrichment/`（富集分析）

### `enrichment/fisher_enrich.R`

**`run_fisher_enrich`** — 基于超几何分布（Fisher 精确检验）的富集分析（按单列注释类别，如 KEGG 通路）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `significant_features` | 字符向量，待富集的特征（如差异特征） | 必填 |
| `all_features` | 字符向量，背景特征全集 | 必填 |
| `feature_info` | data.frame，特征→类别映射（行名或某列为特征 ID） | 必填 |
| `category_col` | 字符，feature_info 中类别列名 | `"kegg"` |
| `min_size` | 数值，类别最小成员数 | `5` |
| `max_size` | 数值，类别最大成员数 | `500` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `results`（data.frame：category、count、size、expected、fold_enrichment、p_value、p_adj 等）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `results`。

**`plot_enrichment`** — 富集结果条形图（展示 fold enrichment 与显著性）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `enrich_result` | `run_fisher_enrich` 返回对象 | 必填 |
| `top_n` | 数值，展示前 N 类别 | `20` |
| `p_threshold` | 数值，显著性阈值 | `0.05` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `enrichment/gsva.R`

**`run_gsva`** — 基因集变异分析（GSVA），将表达矩阵转为通路活性评分矩阵（按注释列划分基因集）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `feature_info` | data.frame，特征注释（含用于分组的类别列） | 必填 |
| `pathway_col` | 字符，feature_info 中通路/基因集列名 | `"kegg"` |
| `min_size` | 数值，通路最小特征数 | `5` |
| `max_size` | 数值，通路最大特征数 | `500` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `gsva_matrix`（通路×样本评分矩阵）、`pathways`（通路特征集列表）、`n_pathways`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `gsva_matrix`（矩阵需先转为 data.frame）。

**`plot_gsva_heatmap`** — GSVA 通路评分热图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `gsva_result` | `run_gsva` 返回对象 | 必填 |
| `sample_info` | data.frame，样本注释 | 必填 |
| `group_col` | 字符，分组列名 | `"sample_info"` |

- **返回值**：pheatmap/ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_heatmap()` 保存。

### `enrichment/kegg.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `run_kegg_pathway_enrich` | KEGG 通路 Fisher 富集（先映射化合物到通路再逐条检验） | `significant_compounds`（必填）；`all_compounds`（必填，背景）；`kegg_mapping`（必填）；`p_adj_method="BH"`；`min_size=2` | data.frame（行名=pathway_name） |
| `run_kegg_pathway_gsva` | KEGG 通路活性评分（GSVA/ssgsea/zscore/mean） | `expr_matrix`（必填）；`kegg_mapping`（必填）；`feature_info=NULL`；`feature_id_col="name"`；`kegg_col="kegg"`；`method="mean"`；`min_size=2`；`max_size=500` | 列表，含 `gsva_matrix`（通路×样本矩阵）、`pathways`、`n_pathways` |
| `run_kegg_pathway_wgcna` | 由 KEGG 通路构建预定义特征模块（供 `wgcna_module_trait` 使用） | `expr_matrix`（必填）；`kegg_mapping`（必填）；`feature_info`（必填）；`feature_id_col="name"`；`kegg_col="kegg"`；`min_size=2`；`max_size=500` | 列表，含 `MEs`、`colors`、`module_sizes`、`modules`、`n_modules`、`category_col="kegg_pathway"` |
| `plot_kegg_enrichment` | KEGG 通路富集结果水平条形图（按 -log10(p) 排序，显著通路高亮） | `enrich_res`（必填，`run_kegg_pathway_enrich` 返回）；`top_n=20` | ggplot 对象。若输入为空则返回 NULL |
| `plot_kegg_pathway_activity` | KEGG 通路活性热图（方差最大的前 N 条通路） | `gsva_res`（必填，`run_kegg_pathway_gsva` 返回）；`top_n=30`；`sample_info=NULL`；`group_col=NULL` | ggplot 对象。若输入为空则返回 NULL |

- **输出文件**：均返回 R 对象，需经 `export_table()` 保存（GSVA 的 `gsva_matrix` 需先转 data.frame；enrich 的 data.frame 直接保存）。绘图函数需经 `export_plot()` 保存。

---

## `machine_learning/`（机器学习）

### `machine_learning/lasso.R`

**`run_lasso`** — Lasso 回归（cv.glmnet）分类/回归与特征选择（含交叉验证与混淆矩阵）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame，样本注释 | 必填 |
| `group_col` | 字符，分组列名（作为响应变量） | `"sample_info"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `model`（cv.glmnet 拟合）、`selected_features`（选中特征向量）、`coefficients`（非零系数 data.frame）、`lambda`、`accuracy`、`confusion_matrix`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `coefficients`。

**`plot_lasso_path`** — Lasso 系数路径图（系数 vs L1 norm）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `lasso_result` | `run_lasso` 返回对象 | 必填 |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `machine_learning/linear_model.R`

**`run_linear_model`** — 多元线性/逻辑回归（含分类准确率与混淆矩阵）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame，样本注释 | 必填 |
| `group_col` | 字符，分组列名（响应变量） | `"sample_info"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `coefficients`（回归系数 data.frame）、`classification_coefficients`（各分组特征系数）、`accuracy`、`predictions`、`confusion_matrix`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `coefficients` / `classification_coefficients`。

### `machine_learning/rf_shap.R`

**`run_rf_shap`** — 随机森林训练 + SHAP 值解释（含准确率与混淆矩阵）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame，样本注释 | 必填 |
| `group_col` | 字符，分组列名（响应变量） | `"sample_info"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `model`（随机森林模型）、`accuracy`、`confusion_matrix`、`importance`（MeanDecreaseGini）、`shap_values`（SHAP 值矩阵）、`shap_summary`（绘图用汇总 data.frame）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `importance` / `shap_values`。

**`plot_rf_importance`** — 随机森林特征重要性（SHAP）条形图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `rf_result` | `run_rf_shap` 返回对象 | 必填 |
| `top_n` | 数值，展示前 N 重要特征 | `20` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`plot_confusion_matrix`** — 随机森林预测混淆矩阵热图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `rf_result` | `run_rf_shap` 返回对象（含 `confusion_matrix`） | 必填 |
| `title` | 字符 | `"Confusion Matrix"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

---

## `multivariate/`（多变量分析）

### `multivariate/pca.R`

**`run_pca`** — 主成分分析。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `scale` | 逻辑，是否按特征标准化 | `TRUE` |
| `center` | 逻辑，是否中心化 | `TRUE` |
| `ncomp` | 数值，保留主成分数（NULL 则取 min(样本数-1, 特征数, 10)） | `NULL` |

- **返回值**：列表，含 `pca_result`（prcomp 对象）、`scores`（样本×PC 得分 data.frame）、`loadings`（特征×PC 载荷 data.frame）、`var_explained`（各 PC 方差解释率 % 向量）、`ncomp`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `scores` / `loadings`。

**`plot_pca_scores`** — PCA 样本得分散点图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `pca_result` | `run_pca` 返回对象 | 必填 |
| `group_col` | 字符，分组着色列名 | `NULL` |
| `pc_x` / `pc_y` | 数值，使用第几主成分 | `1` / `2` |
| `title` | 字符 | `"PCA Scores"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`plot_pca_loadings`** — PCA 特征载荷图（双标图）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `pca_result` | `run_pca` 返回对象 | 必填 |
| `top_n` | 数值，展示前 N 载荷特征 | `20` |
| `pc` | 数值，使用第几主成分 | `1` |
| `title` | 字符 | `"PCA Loadings"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `multivariate/plsda.R`

**`run_plsda`** — 偏最小二乘判别分析。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符，分组列名 | `"sample_info"` |
| `ncomp` | 数值，成分数 | `2` |
| `exclude_groups` | 字符向量，建模前剔除的分组（如 `"QC"`） | `NULL` |

- **返回值**：列表，含 `scores`（样本得分 data.frame）、`loadings`（特征载荷 data.frame）、`vip`（VIP 值 data.frame）、`model`（PLS-DA 模型对象）、`groups`（分组水平）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `vip` / `scores`。

**`plot_plsda_scores`** — PLS-DA 样本得分图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `plsda_result` | `run_plsda` 返回对象 | 必填 |
| `sample_info` | data.frame，样本注释（用于着色，可选） | `NULL` |
| `comp_x` / `comp_y` | 数值，使用第几成分 | `1` / `2` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`plot_vip`** — VIP 值排序条形图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `plsda_result` | `run_plsda` 返回对象（含 `vip`） | 必填 |
| `top_n` | 数值 | `20` |
| `threshold` | 数值，VIP 显著阈值线 | `1.0` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `multivariate/oplsda.R`

**`run_oplsda`** — 正交偏最小二乘判别分析（OPLS-DA）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame |  |
| `group_col` | 字符 | `"sample_info"` |
| `ncomp_pred` | 数值，预测成分数 | `1` |
| `ncomp_orth` | 数值，正交成分数 | `1` |
| `exclude_groups` | 字符向量，建模前剔除的分组 | `NULL` |

- **返回值**：列表，含 `scores`（含预测与正交得分的 data.frame）、`loadings`（特征载荷 data.frame，首列为 feature_id）、`vip`（VIP 值 data.frame）、`model`（OPLS-DA 模型对象）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `scores` / `loadings` / `vip`。

**`plot_oplsda_scores`** — OPLS-DA 样本得分图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `oplsda_result` | `run_oplsda` 返回对象 | 必填 |
| `color_col` | 字符，着色列名（NULL 则使用分组） | `NULL` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

---

## `network/`（网络分析）

### `network/bnlearn_net.R`

**`run_bnlearn`** — 基于 bnlearn 的贝叶斯网络结构学习（时间序列/多条件组学数据推断特征间调控关系）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，特征×样本（时序数据列需按时间排序） | 必填 |
| `time_points` | 数值向量，时间点（NULL 则按样本顺序） | `NULL` |
| `feature_info` | data.frame，特征注释（用于节点标签，可选） | `NULL` |
| `name_col` | 字符，feature_info 中节点名列 | `"name"` |
| `algorithm` | 字符，学习算法 `"hc"`/`"tabu"`/`"gs"` | `"hc"` |
| `score` | 字符，评分函数 | `"bic"` |
| `max_nodes` | 数值，最大节点数（超则按方差取 top） | `50` |
| `seed` | 数值，随机种子 | `42` |

- **返回值**：列表，含 `network`（bn 对象）、`arcs`（有向边 data.frame）、`nodes`（节点名向量）、`adjacency`（邻接矩阵）。
- **输出文件**：返回 R 对象。

**`plot_bnlearn_network`** — 贝叶斯网络结构可视化。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `bn_result` | `run_bnlearn` 返回对象 | 必填 |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `network/cmeans.R`

**`run_cmeans`** — 模糊 c-means 聚类。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `data` | 数值矩阵，样本×特征或特征×样本 | 必填 |
| `n_clusters` | 数值，聚类数 | `6` |
| `m` | 数值，模糊指数 | `2` |
| `seed` | 数值，随机种子 | `42` |
| `transpose` | 逻辑 | `TRUE` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `cluster`（成员向量）、`membership`（隶属度矩阵）、`centers`、`params`。
- **输出文件**：返回 R 对象。

**`plot_cmeans_profiles`** — c-means 聚类成员轮廓图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `cmeans_result` | `run_cmeans` 返回对象 | 必填 |
| `top_n` | 数值，每类展示的特征数 | `10` |
| `title` | 字符 | `"c-means cluster profiles"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`export_cmeans_membership`** — 将 c-means 隶属度写盘。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `result` | `run_cmeans` 返回对象 | 必填 |
| `output_dir` | 字符，输出目录 | 必填 |
| `filename` | 字符，文件名（不含扩展名） | `"cmeans_membership"` |
| `top_n` | 数值，每类展示 top 隶属度特征数 | `NULL` |

- **输出文件（直接落盘）**：`<output_dir>/<filename>.csv`（隶属度/聚类成员）。

### `network/plspm_net.R`

**`run_plspm`** — 偏最小二乘路径模型（PLS-PM）拟合（由观测特征组构造潜变量网络，适合多组学整合）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，特征×样本 | 必填 |
| `feature_info` | data.frame，特征注释 | 必填 |
| `latent_def` | 命名列表，每个元素为特征 ID 向量，或 feature_info 中的列名（定义潜变量） | 必填 |
| `inner_model` | 矩阵，潜变量间关系（NULL 则全连接） | `NULL` |
| `feature_id_col` | 字符，feature_info 中特征 ID 列名 | `"ID"` |
| `ncomp` | 数值，PLS 成分数 | `2` |

- **返回值**：列表，含 `scores`（潜变量得分，样本×潜变量）、`outer_model`（特征载荷）、`inner_model`（潜变量路径系数）、`path_coefficients`。
- **输出文件**：返回 R 对象。

**`build_latent_def_from_annotation`** — 由注释表（特征→潜变量块）自动构建 PLS-PM 测量模型定义。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，特征×样本 | 必填 |
| `feature_info` | data.frame，特征注释 | 必填 |
| `annotation_col` | 字符，块/潜变量列名 | 必填 |
| `feature_id_col` | 字符，特征 ID 列名 | `"ID"` |
| `min_size` | 数值，潜变量最小特征数 | `2` |

- **返回值**：命名列表（潜变量→特征向量），供 `run_plspm` 使用。
- **输出文件**：返回 R 对象。

**`plot_plspm_network`** — PLS-PM 网络图（潜变量及路径系数可视化）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `plspm_result` | `run_plspm` 返回对象 | 必填 |
| `p_threshold` | 数值，路径显著性阈值 | `0.05` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `network/wgcna_module.R`

**`build_wgcna_modules`** — WGCNA 共表达模块识别。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `soft_power` | 数值，软阈值幂（NULL 则自动选，失败时回退 6） | `NULL` |
| `min_module_size` | 数值，最小模块大小 | `10` |
| `merge_cut_height` | 数值，模块合并高度 | `0.25` |
| `network_type` | 字符，`"signed"` / `"unsigned"` / `"signed hybrid"` | `"signed"` |
| `cor_fn` | 字符，相关函数（如 `"cor"` / `"bicor"`） | `"cor"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `module_colors`（特征→模块命名向量）、`module_labels`、`MEs`（模块特征基因矩阵）、`soft_power`、`gene_tree`、`diss_TOM`、`params`。
- **输出文件**：返回 R 对象。

**`plot_wgcna_dendrogram`** — WGCNA 聚类树与模块着色图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `wgcna_result` | `build_wgcna_modules` 返回对象 | 必填 |
| `title` | 字符 | `"WGCNA Dendrogram"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`plot_soft_threshold`** — WGCNA 软阈值筛选图（尺度无关性 vs 平均连接度）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `wgcna_result` | `build_wgcna_modules` 返回对象（含软阈值诊断） | 必填 |
| `title` | 字符 | `"Soft Threshold"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `network/wgcna_trait.R`

**`wgcna_module_trait`** — WGCNA 模块特征基因与性状关联（含线性相关）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `wgcna_result` | `build_wgcna_modules` 返回对象 | 必填 |
| `traits` | 数值矩阵/data.frame（samples × traits），行名需匹配 `MEs` 样本 | 必填 |
| `sample_info` | data.frame，样本注释（可选） | `NULL` |
| `cor_method` | 字符 | `"pearson"` |

- **返回值**：列表，含 `module_trait_cor`（相关矩阵）、`module_trait_p`（p 矩阵）、`module_trait_lm`（每模块-性状线性回归 data.frame，含 estimate/std_error/t_stat/p_value/r_squared）、`feature_trait_cor`/`feature_trait_lm`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `module_trait_lm`。

**`plot_module_trait`** — 模块-性状相关性热图（标注显著性）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `assoc_result` | `wgcna_module_trait` 返回对象 | 必填 |
| `p_threshold` | 数值，显著性阈值 | `0.05` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

---

## `preprocessing/`（预处理）

### `preprocessing/filter_missing.R`

**`filter_missing_values`** — 按缺失值比例过滤特征（支持分组/整体两种策略）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples，缺失用 NA 表示 | 必填 |
| `sample_info` | data.frame，样本注释（含分组列，method="group" 时必填） | `NULL` |
| `threshold` | 数值，缺失比例阈值（0–1），超过则移除 | `0.8` |
| `method` | 字符，`"group"`（所有组均超阈值才移除）/ `"overall"`（整体超阈值） | `"group"` |
| `group_col` | 字符，sample_info 中分组列名 | `"sample_info"` |
| `exclude_groups` | 字符向量，建模前剔除的分组（如 QC） | `NULL` |

- **返回值**：列表，含 `filtered_matrix`（过滤后矩阵）、`removed_features`、`kept_features`、`missing_report`（每特征缺失比例 data.frame）。
- **输出文件**：返回 R 对象。

### `preprocessing/impute_missing.R`

**`impute_min_half`** — 以每特征最小正值的一半填补缺失（代谢组学常用）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `treat_zero_as_missing` | 逻辑，是否将 0 视为缺失 | `TRUE` |
| `factor` | 数值，最小正值的乘子（0.5=一半） | `0.5` |

- **返回值**：填补后的数值矩阵。
- **输出文件**：返回 R 对象。

**`impute_knn`** — K 近邻（KNN）缺失值填补（基于 `impute` 包）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `k` | 数值，近邻数 | `10` |
| `treat_zero_as_missing` | 逻辑，是否将 0 视为缺失 | `TRUE` |
| `max_na_prop` | 数值，单特征最大允许 NA 比例（超出则移除该特征） | `0.5` |

- **返回值**：填补后的数值矩阵。
- **输出文件**：返回 R 对象。

### `preprocessing/normalize.R`

**`normalize_sample_total`** — 按样本总量归一化（转为相对丰度/ppm）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `scale_factor` | 数值，缩放因子 | `1` |
| `multiply_by` | 数值，归一化后乘子（1=比例，1e6=ppm） | `1e6` |

- **返回值**：按样本总和归一化后的数值矩阵。
- **输出文件**：返回 R 对象。

**`normalize_median`** — 按样本中位数归一化。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |

- **返回值**：按样本中位数归一化后的数值矩阵。
- **输出文件**：返回 R 对象。

### `preprocessing/scale.R`

**`scale_feature_median`** — 以特征中位数居中（可选按 MAD 缩放）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `scale` | 逻辑，是否同时按 MAD（中位数绝对偏差）缩放 | `FALSE` |

- **返回值**：中位数居中（或 MAD 缩放后）的数值矩阵。
- **输出文件**：返回 R 对象。

**`scale_feature_zscore`** — 特征级 z-score 标准化（减均值/除以标准差）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |

- **返回值**：z-score 标准化后的数值矩阵。
- **输出文件**：返回 R 对象。

**`scale_feature_minmax`** — 特征级 min-max 缩放至 [0,1]。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |

- **返回值**：min-max 缩放后的数值矩阵。
- **输出文件**：返回 R 对象。

**`scale_pareto`** — 特征级 Pareto 缩放（均值居中/除以标准差平方根）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |

- **返回值**：Pareto 缩放后的数值矩阵。
- **输出文件**：返回 R 对象。

---

## `qcqa/`（质控与质控图）

### `qcqa/qcqa.R`

**`qc_variation`** — 质控变异评估：计算每特征的 CV(%)、均值、标准差及汇总统计。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame，样本注释 | 必填 |
| `qc_group` | 字符，QC 样本分组列名（用于子集评估） | `"QC"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `qc_cv`（每特征 CV 向量）、`qc_mean`、`qc_sd`、`summary`（QC 统计 data.frame）、`plot`（CV 分布 ggplot）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `summary`。

**`qc_pca_assessment`** — 质控 PCA 评估：QC 样本在研究样本云中的离散程度。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame，样本注释 | 必填 |
| `qc_group` | 字符，QC 样本分组列名 | `"QC"` |
| `scale` | 逻辑，是否按特征标准化 | `TRUE` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `pca_result`（PCA 结果）、`scores`（PC 得分）、`qc_dispersion`（QC 样本到 QC 质心的平均距离）、`plot`（QC 高亮的 PCA 得分 ggplot）。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存 `plot`。

---

## `utils/`（工具函数）

### `utils/load_data.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `load_expression_matrix` | 读取表达矩阵 | `file`（必填）；`feature_id_col = NULL`（特征 ID 列） | 数值矩阵 |
| `load_sample_info` | 读取样本注释 | `file`（必填） | data.frame |
| `load_feature_info` | 读取特征注释 | `file`（必填）；`id_col = "ID"` | data.frame |
| `create_omics_data` | 构造单组学 `OmicsData` 对象 | `expr_matrix`（必填）；`sample_info`（必填）；`feature_info = NULL`（可选） | `OmicsData` S3 对象 |

### `utils/export.R`（导出约定，详见上方"快速开始"）

| 函数 | 功能 | 关键参数 | 产物 |
| --- | --- | --- | --- |
| `export_plot` | 保存 ggplot 为 pdf+png | `plot`、`output_dir`、`filename`、`width=8`、`height=6`、`dpi=300` | `.pdf` + `.png` |
| `export_heatmap` | 保存 pheatmap 为 pdf+png | 同上 | `.pdf` + `.png` |
| `export_table` | 保存 data.frame 为 csv | `data`、`output_dir`、`filename`、`use_rownames=TRUE`、`id_col_name="ID"` | `.csv` |

### `utils/plot_helpers.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `make_group_colors` | 生成分组成员配色（基于 RColorBrewer 调色板） | `groups`（必填，字符向量）；`palette_name = "Set2"`；`custom_colors = NULL` | 命名字符向量 |
| `save_plot` | 保存 ggplot 的轻量封装（等价于 `export_plot`） | `plot`（必填）；`filename`（必填）；`output_dir = "."`；`width=8`；`height=6`；`dpi=300` | **直接落盘**：`.pdf` + `.png` |
| `extract_plot_meta` | 从样本注释提取用于绘图的元数据（样本/分组标签） | `sample_info`（必填）；`color_col = "sample_info"` | data.frame |

### `utils/external_modules`（预定义模块）

**`predefined_module_eigengenes`** — 由特征注释表计算预定义功能模块的特征基因（eigengene）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `feature_info` | data.frame，特征注释（含特征 ID 列与类别列） | 必填 |
| `feature_id_col` | 字符，特征 ID 列名（需匹配 `expr_matrix` 行名） | `"feature"` |
| `category_col` | 字符，模块/类别列名 | `"category"` |
| `min_size` | 数值，模块最小特征数 | `3` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `MEs`（样本×模块矩阵）、`module_sizes`、`n_modules`。
- **输出文件**：返回 R 对象。

### `utils/kegg_pathway.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `map_kegg_compound_to_pathway` | 查询 KEGG REST API，将 KEGG compound ID（如 `C02845`）映射到通路 | `kegg_ids`（必填）；`cache_dir=NULL`；`batch_size=10`；`delay=0.3` | data.frame（compound_id、pathway_id、pathway_name） |
| `run_kegg_pathway_enrich` | KEGG 通路富集（Fisher 精确检验，先映射化合物到通路再检验每条通路） | `significant_compounds`（必填）；`all_compounds`（必填，背景）；`kegg_mapping`（必填，来自上一步）；`p_adj_method="BH"`；`min_size=2` | data.frame（pathway 富集结果，行名=pathway_name） |
| `run_kegg_pathway_gsva` | KEGG 通路活性评分（GSVA/ssgsea/zscore/mean） | `expr_matrix`（必填）；`kegg_mapping`（必填）；`feature_info=NULL`；`feature_id_col="name"`；`kegg_col="kegg"`；`method="mean"`；`min_size=2`；`max_size=500` | 列表，含 `gsva_matrix`（通路×样本矩阵）、`pathways`、`n_pathways` |
| `run_kegg_pathway_wgcna` | 由 KEGG 通路释义构建特征模块（供 `wgcna_module_trait` 使用） | `expr_matrix`（必填）；`kegg_mapping`（必填）；`feature_info`（必填）；`feature_id_col="name"`；`kegg_col="kegg"`；`min_size=2`；`max_size=500` | 列表，含 `MEs`、`colors`、`module_sizes`、`modules`、`n_modules`、`category_col="kegg_pathway"` |

- **输出文件**：均返回 R 对象，需经 `export_table()` 保存（GSVA 的 `gsva_matrix` 需先转 data.frame；enrich 的 data.frame 直接保存）。

---

## `visualization/`（可视化）

### `visualization/volcano_plot.R`

**`plot_volcano`** — 差异分析结果火山图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `de_results` | data.frame，含 p 值与 logFC 列（列名由下列参数指定） | 必填 |
| `p_threshold` | 数值，p 值显著性阈值 | `0.05` |
| `logfc_threshold` | 数值，logFC 绝对值阈值 | `1` |
| `top_n` | 数值，标注 top 差异特征数 | `5` |
| `p_col` | 字符，`de_results` 中 p 值列名 | `"p_adj"` |
| `logfc_col` | 字符，`de_results` 中 logFC 列名 | `"logFC"` |
| `color_up` / `color_down` / `color_ns` | 字符，上/下调/不显著配色 | `"#e74c3c"` / `"#2ecc71"` / `"grey70"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `visualization/vip_manhattan.R`

**`plot_vip_manhattan`** — VIP 值曼哈顿图（PLS-DA/OPLS-DA 变量重要性）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `vip` | 数值向量或 data.frame（特征→VIP） | 必填 |
| `feature_info` | data.frame，特征注释（用于标签，可选） | 必填 |
| `threshold` | 数值，VIP 显著阈值 | `1` |
| `top_n` | 数值，标注数 | `20` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `visualization/heatmap_plot.R`

**`plot_heatmap`** — 通用表达热图（基于 pheatmap）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，特征×样本 | 必填 |
| `sample_info` | data.frame，样本注释（用于列注释） | 必填 |
| `feature_info` | data.frame，特征注释（可选） | `NULL` |
| `scale` | 字符，`"none"` / `"row"` / `"column"` | `"row"` |
| `cluster_rows` | 逻辑 | `TRUE` |
| `cluster_cols` | 逻辑 | `TRUE` |
| `show_rownames` | 逻辑 | `FALSE` |
| `top_n` | 数值，仅显示 top 变异特征 | `NULL` |

- **返回值**：pheatmap 对象。
- **输出文件**：返回 R 对象，需经 `export_heatmap()` 保存。

### `visualization/venn_plot.R`

**`plot_venn`** — 韦恩图（2–5 组集合）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `sets` | 列表，命名集合（字符向量） | 必填 |
| `fill_colors` | 字符向量，各集合填充色 | `NULL`（自动） |
| `font_size` | 数值，字体缩放 | `0.8` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`export_venn`** — 将韦恩图直接写盘。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `venn` | `plot_venn` 返回的 ggplot 对象 | 必填 |
| `output_dir` | 字符，输出目录 | `"."` |
| `filename` | 字符，文件名（不含扩展名） | `"venn"` |

- **输出文件（直接落盘）**：`<output_dir>/<filename>.pdf` + `.png`。

### `visualization/upset_plot.R`

**`plot_upset`** — Upset 图（高维集合交集）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `sets` | 列表，命名集合 | 必填 |
| `n_intersections` | 数值，展示交集数 | `30` |
| `order_by` | 字符，`"size"` / `"degree"` | `"size"` |

- **返回值**：ggplot/ComplexUpset 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

---

## `microbiome/`（微生物组分析）

### `microbiome/microbiome_utils.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `calc_relative_abundance` | 将计数矩阵转为相对丰度（列归一化） | `expr_matrix`（必填）；`multiply_by=1` | 数值矩阵 |
| `rarefy_matrix` | 稀疏化（rarefaction），使所有样本等深度 | `expr_matrix`（必填）；`depth=NULL`（最小深度）；`n_iter=10`；`seed=42` | 数值矩阵 |
| `calc_goods_coverage` | 计算 Good's coverage 指数 | `expr_matrix`（必填） | 数值向量 |

### `microbiome/alpha_diversity.R`

**`calc_alpha_diversity`** — 计算α多样性指数（Shannon / Simpson / inv_Simpson / Chao1 / ACE / Pielou / Goods_coverage / observed_species）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples（行=taxa，列=样本） | 必填 |
| `method` | 字符，`"count"`（计数）/ `"abundance"`（相对丰度） | `"count"` |
| `digits` | 数值，保留小数位 | `4` |

- **返回值**：data.frame（样本 × 指数），含 sample、observed_species、shannon、simpson、inv_simpson、chao1、ace、pielou、goods_coverage 列。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

**`test_alpha_diversity`** — α多样性指数组间差异统计检验（Kruskal-Wallis / ANOVA，2 组自动切 Wilcoxon）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `alpha_df` | `calc_alpha_diversity` 返回的 data.frame | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `test` | 字符，`"kruskal"` / `"anova"` / `"wilcox"` | `"kruskal"` |
| `p_adjust` | 字符 | `"BH"` |

- **返回值**：data.frame（index、p_value、p_adj、test_method、comparison）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

**`plot_alpha_diversity`** — 分组箱线图（每个指数一个子图，可选叠加 p 值标注）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `alpha_df` | `calc_alpha_diversity` 返回对象 | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `test_result` | `test_alpha_diversity` 返回对象（可选，用于标注 p 值） | `NULL` |
| `show_pvalue` | 逻辑 | `TRUE` |

- **返回值**：ggplot 对象列表（每个指数一个）。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `microbiome/beta_diversity.R`

**`calc_beta_diversity`** — 计算样本间β多样性距离。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `method` | 字符，`"bray"` / `"jaccard"` / `"sorensen"` / `"euclidean"` | `"bray"` |
| `method_type` | 字符，`"count"` / `"abundance"` | `"count"` |

- **返回值**：dist 对象。
- **输出文件**：返回 R 对象。

**`run_permanova`** — PERMANOVA (vegan::adonis2) 组间差异检验。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `dist_mat` | dist 对象 | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `permutations` | 数值 | `999` |

- **返回值**：列表，含 `result`（adonis2 对象）、`r2`、`p_value`、`df`。
- **输出文件**：返回 R 对象。

**`run_pcoa`** — 主坐标分析（PCoA）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `dist_mat` | dist 对象 | 必填 |
| `ncomp` | 数值 | `min(n_samples - 1, 10)` |

- **返回值**：列表，含 `points`（样本坐标 data.frame）、`var_explained`、`eigenvalues`、`ncomp`。
- **输出文件**：返回 R 对象。

**`run_nmds`** — 非度量多维尺度分析（NMDS）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `dist_mat` | dist 对象 | 必填 |
| `ncomp` | 数值 | `2` |
| `trymax` | 数值，最大迭代 | `50` |
| `seed` | 数值 | `42` |

- **返回值**：列表，含 `points`、`stress`、`ncomp`。
- **输出文件**：返回 R 对象。

**`plot_ordination`** — 排序散点图（PCoA / NMDS），支持分组着色、置信椭圆、质心标注。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `ord_result` | `run_pcoa` 或 `run_nmds` 返回对象 | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `title` | 字符 | `"PCoA"` |
| `show_ellipses` | 逻辑 | `TRUE` |
| `show_centroids` | 逻辑 | `TRUE` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `microbiome/taxa_composition.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `aggregate_by_taxonomy` | 按 phylum/class/order/family/genus 聚合丰度 | `expr_matrix`（必填）；`feature_info`（必填）；`level`（必填） | 列表，含 `matrix`、`level` |
| `calc_relative_abundance_pseudo` | 计算相对丰度（加伪计数） | `expr_matrix`（必填）；`pseudo_count=1e-6` | 数值矩阵 |
| `plot_taxa_barplot` | 分类组成堆叠柱状图（Top N + Other） | `expr_matrix`（必填）；`sample_info`（必填）；`feature_info`（必填）；`level="phylum"`；`top_n=10`；`group_col="sample_info"`；`title=NULL` | ggplot 对象 |
| `plot_taxa_pie` | 分类组成饼图 | `expr_matrix`（必填）；`sample_info`（必填）；`feature_info`（必填）；`level="phylum"`；`top_n=8`；`group_col=NULL`；`title=NULL` | ggplot 对象 |

- **输出文件**：绘图函数返回 R 对象，需经 `export_plot()` 保存。

### `microbiome/biomarker_lefse.R`

**`run_lefse_analysis`** — LEfSe 风格生物标志物发现（Kruskal-Wallis + LDA effect size）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `kw_p_threshold` | 数值，KW p 值阈值 | `0.05` |
| `lda_threshold` | 数值，LDA score 阈值 | `2.0` |
| `p_adjust` | 字符 | `"BH"` |

- **返回值**：列表，含 `full_results`（所有 taxa 的 KW + LDA 结果）、`significant`（显著 biomarker）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

**`plot_lefse_lda`** — LDA score 条形图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `lefse_result` | `run_lefse_analysis` 返回对象 | 必填 |
| `top_n` | 数值 | `20` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`plot_lefse_cladogram`** — 简化版 cladogram（同心圆表示分类层级）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `lefse_result` | `run_lefse_analysis` 返回对象 | 必填 |
| `feature_info` | data.frame，含分类层级列 | 必填 |
| `levels` | 字符向量，分类层级列名 | `c("phylum","class","order","family","genus")` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `microbiome/core_microbiome.R`

**`identify_core_microbiome`** — 按频率和丰度阈值识别核心 taxa。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | `NULL` |
| `group_col` | 字符 | `"sample_info"` |
| `prevalence_threshold` | 数值，出现频率阈值（0–1） | `0.8` |
| `abundance_threshold` | 数值，平均相对丰度阈值 | `1e-4` |
| `detection_limit` | 数值，检出限 | `0` |

- **返回值**：列表，含 `core_features`（核心 taxa 名）、`prevalence`（频率 data.frame）、`core_by_group`（分组核心列表）、`shared_core`（各组共有）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

**`plot_prevalence`** — 频率-丰度散点图（高亮核心 taxa）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `core_result` | `identify_core_microbiome` 返回对象 | 必填 |
| `title` | 字符 | `"Prevalence vs Abundance"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`plot_core_heatmap`** — 核心 taxa 相对丰度热图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵 | 必填 |
| `core_result` | `identify_core_microbiome` 返回对象 | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `scale` | 逻辑 | `TRUE` |

- **返回值**：pheatmap 对象。
- **输出文件**：返回 R 对象，需经 `export_heatmap()` 保存。

### `microbiome/diff_abundance_ancom.R`

**`run_ancom_bc`** — ANCOM-BC 风格差异丰度分析（组成性数据校正）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `pseudo_count` | 数值，伪计数 | `1` |
| `p_adjust` | 字符 | `"BH"` |
| `p_threshold` | 数值 | `0.05` |
| `w_threshold` | 数值，ANCOM W 统计量阈值 | `0.7` |

- **返回值**：列表，含 `results`（data.frame：feature、logFC、p_value、p_adj、W、significant）、`significant`、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `results`。

**`plot_ancom_volcano`** — 差异丰度火山图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `ancom_result` | `run_ancom_bc` 返回对象 | 必填 |
| `feature_info` | data.frame（可选，用于标签） | `NULL` |
| `name_col` | 字符 | `"name"` |
| `top_n` | 数值，标注数 | `15` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `microbiome/sparcc_network.R`

**`run_sparcc`** — SparCC 组成性数据关联分析（迭代估计校正伪关联）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `n_iterations` | 数值 | `20` |
| `n_permutations` | 数值（0 则不做） | `100` |
| `filter_threshold` | 数值，|correlation| 阈值 | `0.3` |
| `p_adjust` | 字符 | `"BH"` |
| `p_threshold` | 数值 | `0.05` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `cor_matrix`（相关系数矩阵）、`p_matrix`（p 值矩阵）、`edges`（显著边表 data.frame：source、target、correlation、p_value、p_adj）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `edges`。

**`plot_sparcc_network`** — SparCC 关联网络可视化。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `sparcc_result` | `run_sparcc` 返回对象 | 必填 |
| `cor_threshold` | 数值 | `0.3` |
| `p_threshold` | 数值 | `0.05` |
| `layout` | 字符，`"fr"` / `"circle"` / `"kk"` | `"fr"` |
| `node_size_by_degree` | 逻辑 | `TRUE` |

- **返回值**：ggraph / igraph 图对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

---

## `proteome/`（蛋白质组分析）

### `proteome/protein_qc.R`

**`run_protein_qc`** — 蛋白质组全面质控（鉴定数 / 缺失率 / CV / 动态范围 / 样本相关性 / PCA 异常值）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples（行=蛋白） | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `cv_threshold` | 数值，CV 阈值（%） | `20` |
| `missing_rate_threshold` | 数值，缺失率阈值（%） | `30` |
| `log_transform` | 逻辑，是否做 log2 变换 | `FALSE` |

- **返回值**：列表，含 `sample_summary`（样本级 QC）、`feature_summary`（蛋白级 QC）、`cv_distribution`、`correlation_matrix`、`pca_result`（含 outlier 标记的 PCA 得分 data.frame）、`flagged_samples`、`flagged_features`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `sample_summary` / `feature_summary`。

**`plot_protein_qc`** — 5 面板质控图（鉴定数 / 缺失率 / CV / 相关性 / PCA）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `qc_result` | `run_protein_qc` 返回对象 | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |

- **返回值**：ggplot 对象列表（5 个面板）。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `proteome/go_enrichment.R`

**`run_go_enrichment`** — GO 术语富集分析（BP / MF / CC 三本体，Fisher 精确检验）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `significant_proteins` | 字符向量，显著蛋白 ID | 必填 |
| `all_proteins` | 字符向量，背景蛋白 ID | 必填 |
| `feature_info` | data.frame，含 GO 术语注释 | 必填 |
| `id_col` | 字符，ID 列名 | `"ID"` |
| `go_col` | 字符，GO 术语列名 | `"go_terms"` |
| `ontologies` | 字符向量，`c("BP","MF","CC")` | `c("BP","MF","CC")` |
| `p_adjust` | 字符 | `"BH"` |
| `p_threshold` | 数值 | `0.05` |
| `min_genes` | 数值，GO 术语中最少显著基因数 | `2` |

- **返回值**：列表，含 `results`（合并 data.frame：ontology、go_id、go_term、count、expected、fold_enrichment、p_value、p_adj）、`by_ontology`（按本体分组的列表）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `results`。

**`plot_go_enrichment`** — GO 富集条形图（按 ontology 分面着色）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `go_result` | `run_go_enrichment` 返回对象 | 必填 |
| `top_n` | 数值 | `15` |
| `ontologies` | 字符向量 | `c("BP","MF","CC")` |
| `plot_type` | 字符，`"bar"` / `"bubble"` | `"bar"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `proteome/protein_clustering.R`

**`cluster_protein_profiles`** — 蛋白表达模式聚类（K-means / 层次 / 模糊 c-means）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符，用于定义时间/条件顺序 | `"sample_info"` |
| `method` | 字符，`"kmeans"` / `"hierarchical"` / `"fcm"` | `"kmeans"` |
| `n_clusters` | 数值 | `6` |
| `scale` | 逻辑 | `TRUE` |
| `nstart` | 数值，K-means 随机起始 | `25` |

- **返回值**：列表，含 `clusters`（聚类分配向量）、`centers`（聚类中心）、`profiles`（长表：protein、cluster、group、value）、`silhouette`（轮廓系数）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `profiles`。

**`plot_profile_clusters`** — 聚类表达谱面板图（每个聚类一个子图，含中心线和个体曲线）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `cluster_result` | `cluster_protein_profiles` 返回对象 | 必填 |
| `n_features` | 数值，每聚类展示的最大蛋白数 | `50` |
| `show_center` | 逻辑 | `TRUE` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`plot_cluster_centers`** — 聚类中心比较图（所有中心在同一图）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `cluster_result` | `cluster_protein_profiles` 返回对象 | 必填 |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `proteome/protein_ppi.R`

**`query_string_ppi`** — 通过 STRING API 查询 PPI 网络。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `protein_ids` | 字符向量，蛋白 ID（UniProt / 基因符号） | 必填 |
| `species` | 数值，物种 NCBI taxon ID | `9606` |
| `score_threshold` | 数值，STRING score 阈值（0–1000） | `400` |
| `network_type` | 字符，`"functional"` / `"physical"` | `"functional"` |

- **返回值**：列表，含 `edges`（source、target、score）、`nodes`（id、degree）、`string_ids`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `edges`。

**`build_local_ppi`** — 基于本地数据的 PPI 网络构建（STRING 不可用时的降级方案）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵 | 必填 |
| `cor_method` | 字符 | `"spearman"` |
| `cor_threshold` | 数值 | `0.7` |
| `p_adjust` | 字符 | `"BH"` |
| `p_threshold` | 数值 | `0.01` |

- **返回值**：同 `query_string_ppi`。
- **输出文件**：返回 R 对象。

**`plot_ppi_network`** — PPI 网络可视化（ggraph / igraph）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `ppi_result` | `query_string_ppi` 或 `build_local_ppi` 返回对象 | 必填 |
| `layout` | 字符 | `"fr"` |
| `node_size_by_degree` | 逻辑 | `TRUE` |

- **返回值**：ggraph / igraph 图对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`calc_ppi_topology`** — PPI 网络拓扑分析（度 / 介度 / 紧密度 / 特征向量 / hub 蛋白）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `ppi_result` | `query_string_ppi` 或 `build_local_ppi` 返回对象 | 必填 |

- **返回值**：列表，含 `global_metrics`（n_nodes、n_edges、density、n_components、avg_path_length、avg_clustering）、`node_metrics`（protein、degree、betweenness、closeness、eigenvector）、`hub_proteins`（前 10% hub）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `node_metrics`。

### `proteome/functional_profile.R`

**`calc_protein_functional_profile`** — 按功能类别聚合蛋白丰度（mean / median / sum / PC1）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `feature_info` | data.frame，含功能类别列 | 必填 |
| `category_col` | 字符（如 `"kegg_pathway"`、`"cog_category"`、`"super_class"`） | 必填 |
| `agg_method` | 字符，`"mean"` / `"median"` / `"sum"` / `"pc1"` | `"mean"` |
| `min_size` | 数值 | `3` |
| `max_size` | 数值 | `100` |

- **返回值**：列表，含 `profile_matrix`（功能类别 × 样本矩阵）、`category_info`（各类别蛋白数等）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `profile_matrix`。

**`plot_functional_heatmap`** — 功能类别丰度热图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `func_result` | `calc_protein_functional_profile` 返回对象 | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `top_n` | 数值 | `30` |

- **返回值**：pheatmap 对象。
- **输出文件**：返回 R 对象，需经 `export_heatmap()` 保存。

**`plot_functional_comparison`** — 分组间功能类别活性比较图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `func_result` | `calc_protein_functional_profile` 返回对象 | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `control_group` | 字符 | `NULL` |
| `top_n` | 数值 | `20` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`diff_functional_category`** — 功能类别差异分析（limma）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `func_result` | `calc_protein_functional_profile` 返回对象 | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `control_group` | 字符 | `NULL` |
| `p_adjust` | 字符 | `"BH"` |
| `p_threshold` | 数值 | `0.05` |
| `fc_threshold` | 数值 | `0.5` |

- **返回值**：data.frame（feature_id、logFC、P.Value、adj.P.Val、significant 等，调用 `run_limma` 的返回）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

---

## `multiomics/`（多组学整合）

### `multiomics/multiomics_data.R`

**`create_multiomics_data`** — 构造 `MultiOmicsData` 对象。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_list` | 命名列表，每个元素为一个组学层表达矩阵（features × samples） | 必填 |
| `sample_info` | data.frame，样本注释 | 必填 |
| `feature_info_list` | 列表，与各层对应的特征注释（可选） | `NULL` |
| `match_cols` | 字符向量，匹配键列（可选） | `NULL` |

- **返回值**：`MultiOmicsData` S3 对象（含 `omics`、`sample_info`、`common_samples`、`metadata`）。
- **输出文件**：返回 R 对象。

同文件其他导出函数：

| 函数 | 功能 | 关键参数（默认值） | 返回值 |
| --- | --- | --- | --- |
| `print.MultiOmicsData` | 打印 MultiOmicsData 摘要 | `x`（必填）；`...` | 控制台输出 |
| `get_omics_matrix` | 取某层表达矩阵 | `mo`（必填）；`name`（必填） | 数值矩阵 |
| `get_omics_list` | 取层列表 | `mo`（必填）；`layers = NULL`（全部） | 命名矩阵列表 |
| `get_feature_info` | 取某层特征注释 | `mo`（必填）；`name`（必填） | data.frame |
| `preprocess_multiomics` | 批量预处理（过滤/填补/归一化/标准化） | `mo`、`filter_threshold=0.5`、`filter_method="group"`、`group_col="sample_info"`、`impute=TRUE`、`normalize=TRUE`、`scale=TRUE`、`log_transform=FALSE`、`skip_normalize=NULL` | `MultiOmicsData`（含 `preprocessing` 记录） |
| `subset_multiomics` | 按样本子集 | `mo`、`samples=NULL`、`subset_col=NULL`、`subset_values=NULL` | `MultiOmicsData` |
| `drop_zero_variance` | 去除零方差特征 | `mat`（必填）；`label="matrix"`；`verbose=TRUE` | 数值矩阵 |

### `multiomics/cross_correlation.R`

**`run_cross_correlation`** — 两层间相关分析（spearman/pearson + 显著性）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mat_x` | 数值矩阵，特征×样本（层 X） | 必填 |
| `mat_y` | 数值矩阵，特征×样本（层 Y） | 必填 |
| `method` | 字符，`"spearman"` / `"pearson"` | `"spearman"` |
| `r_threshold` | 数值，最小绝对相关 | `0.6` |
| `p_threshold` | 数值，最大校正 p | `0.05` |
| `max_pairs` | 数值，稀疏表保留对数上限 | `100000` |
| `name_x` / `name_y` | 字符，层标签 | `"x"` / `"y"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `cor_matrix`、`p_matrix`、`padj_matrix`、`pairs`（data.frame：feature_x、feature_y、omics_x、omics_y、r、p、padj）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `pairs`。

**`run_all_pairwise_correlation`** — 对所有层两两组合运行相关分析。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `layer_pairs` | 列表，长 2 的字符向量（如 `list(c("microbiome","metabolome"))`） | 必填 |
| `method` | 字符 | `"spearman"` |
| `r_threshold` | 数值 | `0.6` |
| `p_threshold` | 数值 | `0.05` |
| `max_pairs` | 数值 | `100000` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：命名列表（`combo`→相关结果），含 `all_pairs` 合并稀疏表。
- **输出文件**：返回 R 对象。

**`summarise_correlation_partners`** — 汇总每个特征的显著相关伙伴数。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `pairs` | `run_cross_correlation` 的 `pairs` data.frame | 必填 |
| `side` | 字符，`"x"` / `"y"` / `"both"` | `"both"` |
| `top_n` | 数值，返回 top 特征数 | `50` |

- **返回值**：data.frame（feature、omics、n_partners、n_positive、n_negative、mean_abs_r、max_abs_r）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

### `multiomics/cross_omics_regression.R`

**`run_cross_omics_regression`** — 跨组学线性回归（线性关联筛选，互补于秩相关）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `x_matrix` | 数值矩阵，预测层特征×样本 | 必填 |
| `y_matrix` | 数值矩阵，响应层特征×样本 | 必填 |
| `x_name` / `y_name` | 字符，层标签 | `"x"` / `"y"` |
| `p_adjust` | 多重检验校正 | `"BH"` |
| `min_samples` | 数值，所需最小共享样本数 | `6` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `pairs`（data.frame：x_feature、y_feature、x_name、y_name、slope、intercept、se、t_stat、p_value、padj、r_squared、n_samples）、`x_summary`、`y_summary`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `pairs`。

**`plot_regression_pair`** — 单个特征对回归散点图（含拟合线与 95% 置信带）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `x_values` | 数值向量，解释变量（跨样本） | 必填 |
| `y_values` | 数值向量，响应变量 | 必填 |
| `x_label` / `y_label` | 字符，轴标签 | 必填 |
| `title` | 字符 | `NULL` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`top_regression_pairs`** — 提取最显著（或最高 R²）的回归特征对。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `reg` | `run_cross_omics_regression` 返回对象 | 必填 |
| `top_n` | 数值 | `12` |
| `by` | 字符，排序依据 `"padj"` / `"r2"` | `"padj"` |

- **返回值**：data.frame（`reg$pairs` 的 top_n 行）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

### `multiomics/association_network.R`

**`run_cross_omics_association`** — 跨组学显著关联网络（spearman-rho + MIC + 合并 p 分类）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mat_x` | 数值矩阵，特征×样本（层 X），含行名 | 必填 |
| `mat_y` | 数值矩阵，特征×样本（层 Y） | 必填 |
| `name_x` / `name_y` | 字符，层标签 | 必填 |
| `top_n` | 数值，按方差预筛选每层 top 特征 | `NULL` |
| `max_pairs_for_mic` | 数值，送入 MIC 的最大特征对数 | `2000` |
| `mic_pvalue_method` | 字符，`"permutation"` / `"none"` | `"permutation"` |
| `n_perm` | 数值，共享 MIC 零分布置换次数 | `1000` |
| `score_method` | 字符，`"combined"`（`w*|rho|+(1-w)*MIC`）/ `"nonlinear"`（`MIC-rho²`） | `"combined"` |
| `score_weight` | 数值，[0,1]，combined 中 |rho| 权重 | `0.5` |
| `p_adjust` | 多重检验校正 | `"BH"` |
| `p_threshold` | 数值，校正合并 p 显著性阈值 | `0.05` |
| `rho_linear_min` | 数值，|rho| 高于此判为线性（vs 非线性） | `0.6` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `edges`（9 列边表：source、target、spearman-rho、spearman-pval、MIC、MIC-pvalue、score、pvalue、association）、`nodes`（name、omics、degree）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `edges`。

**`run_intra_omics_association`** — 单组学内部关联网络（仅评估严格上三角）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mat` | 数值矩阵，特征×样本（单组学层） | 必填 |
| `name` | 字符，层标签 | 必填 |
| `top_n` | 数值 | `NULL` |
| `max_pairs_for_mic` | 数值 | `2000` |
| `mic_pvalue_method` | 字符 | `"permutation"` |
| `n_perm` | 数值 | `1000` |
| `score_method` | 字符 | `"combined"` |
| `score_weight` | 数值 | `0.5` |
| `p_adjust` | 字符 | `"BH"` |
| `p_threshold` | 数值 | `0.05` |
| `rho_linear_min` | 数值 | `0.6` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：同 `run_cross_omics_association`（`edges` 边表）。
- **输出文件**：返回 R 对象。

**`run_all_omics_associations`** — 遍历 MultiOmicsData 全部跨层+层内组合批量运行。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `layers` | 字符向量，参与层（NULL=全部） | `NULL` |
| `top_n` | 数值 | `NULL` |
| `max_pairs_for_mic` | 数值 | `2000` |
| `mic_pvalue_method` | 字符 | `"permutation"` |
| `n_perm` | 数值 | `1000` |
| `score_method` | 字符 | `"combined"` |
| `score_weight` | 数值 | `0.5` |
| `p_adjust` | 字符 | `"BH"` |
| `p_threshold` | 数值 | `0.05` |
| `rho_linear_min` | 数值 | `0.6` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `cross`（命名列表，run_cross_omics_association 结果）、`intra`、`summary`（各组合 pair 计数/显著计数 data.frame）。
- **输出文件**：返回 R 对象。

### `multiomics/cross_omics_network.R`

**`build_cross_omics_network`** — 由相关稀疏表列表构建 igraph 网络对象。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `pairs_list` | 命名列表，元素为含 feature_x、feature_y、r、padj 列的 data.frame（名遵循 "layerX_vs_layerY" 约定） | 必填 |
| `r_threshold` | 数值，保留最小 |r| | `0.7` |
| `padj_threshold` | 数值，保留最大校正 p | `0.05` |
| `max_edges` | 数值，边数上限（超限保留最强） | `2000` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表（无保留边时为 NULL），含 `graph`（igraph，节点带 omics 属性）、`edges`、`nodes`（omics、degree）。
- **输出文件**：返回 R 对象。

**`get_network_hubs`** — 提取枢纽节点（按 degree / betweenness）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `network` | `build_cross_omics_network` 结果或 igraph 对象 | 必填 |
| `top_n` | 数值 | `20` |
| `by` | 字符，`"degree"` / `"betweenness"` | `"degree"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：data.frame（name、omics、degree、betweenness、closeness、mean_abs_r）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

### `multiomics/diablo_integration.R`

**`run_diablo`** — DIABLO 多组学整合与判别分析（基于 mixOmics）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `group_col` | 字符，判别分组列 | 必填 |
| `ncomp` | 数值，成分数 | `2` |
| `keep` | 数值向量/列表，各层保留比例 | `NULL`（自动） |
| `design` | 矩阵，层间权重设计 | `NULL`（全连接） |
| `validation` | 字符，`"none"` / `"Mfold"` | `"Mfold"` |
| `nfold` | 数值，交叉验证折数 | `10` |
| `tau` | 数值，判别/跨层相关权衡 | `0.1` |
| `exclude_groups` | 字符向量，建模前剔除的分组 | `NULL` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `model`（block.splsda 拟合）、`scores`（各层得分 data.frame，含 group 标签）、`loadings`、`selected_features`、`groups`、`design`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `loadings`/`scores`。

**`diablo_block_correlation`** — DIABLO 各块成分交叉相关（circle plot 的数值版）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `diablo_result` | `run_diablo` 返回对象 | 必填 |
| `comp` | 数值，成分索引 | `1` |

- **返回值**：data.frame（layer_x、layer_y、component、correlation）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

**`run_layerwise_plsda`** — 逐层独立 PLS-DA（DIABLO 不可用时的降级/概览）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `layers` | 字符向量（NULL=全部） | `NULL` |
| `ncomp` | 数值 | `2` |
| `exclude_groups` | 字符向量 | `NULL` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：命名列表（各层 `run_plsda` 结果，空项已剔除）。
- **输出文件**：返回 R 对象。

### `multiomics/dynamic_bayesian_network.R`

**`aggregate_time_series`** — 按时间聚合为时序面板（用于 DBN）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mat` | 数值矩阵，特征×样本 | 必填 |
| `sample_info` | data.frame，含时间列与分组列 | 必填 |
| `time_col` | 字符，时间列名 | `"day"` |
| `group_cols` | 字符向量，分组列（如 `c("location","variety")`） | `c("location","variety")` |

- **返回值**：聚合矩阵与时间元信息列表。
- **输出文件**：返回 R 对象。

**`build_transition_pairs`** — 由聚合数据构造滞后转移对（t → t+lag）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `agg_mat` | `aggregate_time_series` 结果 | 必填 |
| `time_meta` | 时间元信息 | 必填 |
| `max_lag` | 数值，最大滞后步长 | `1` |

- **返回值**：转移对数据框。
- **输出文件**：返回 R 对象。

**`discretize_transition_data`** — 转移数据离散化（供 DBN 学习）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `df` | 转移对数据框 | 必填 |
| `features` | 字符向量，需离散化的特征 | 必填 |
| `n_bins` | 数值，箱数 | `3` |

- **返回值**：离散化数据框。
- **输出文件**：返回 R 对象。

**`run_dbn_layer`** — 单组学动态贝叶斯网络（时序滞后弧 + bootstrap 强度）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，特征×样本 | 必填 |
| `sample_info` | data.frame，含时间列与分组列 | 必填 |
| `feature_info` | data.frame（可选，含 name 列） | `NULL` |
| `time_col` | 字符 | `"day"` |
| `group_cols` | 字符向量，分组列 | `c("location","variety")` |
| `max_nodes` | 数值，保留 top 节点数 | `25` |
| `algorithm` | 字符，bn 学习算法 | `"hc"` |
| `score` | 字符，评分函数 | `"bic"` |
| `boot_R` | 数值，bootstrap 重复数 | `100` |
| `strength_threshold` | 数值，弧强度阈值 | `0.5` |
| `n_bins` | 数值，离散化箱数 | `3` |
| `name_col` | 字符，特征名列 | `"name"` |
| `seed` | 数值 | `42` |

- **返回值**：列表，含 `arcs`（带 strength 边表）、`nodes_df`（time_slice、degree、omics）、`fitted`（bn.fit）、`data`、`params`。
- **输出文件**：返回 R 对象。

**`run_dbn_multiomics`** — 全组学动态贝叶斯网络（合并多层时序弧）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `layers` | 字符向量（NULL=全部） | `NULL` |
| `per_layer_nodes` | 数值，每层保留节点数 | `8` |
| `time_col` | 字符 | `"day"` |
| `group_cols` | 字符向量 | `c("location","variety")` |
| `enforce_layer_order` | 逻辑，是否强制层序为父→子 | `FALSE` |
| `layer_order` | 字符向量，层顺序（NULL 取 mo） | `NULL` |
| `algorithm` | 字符 | `"hc"` |
| `score` | 字符 | `"bic"` |
| `boot_R` | 数值 | `100` |
| `strength_threshold` | 数值 | `0.5` |
| `n_bins` | 数值 | `3` |
| `name_col` | 字符 | `"name"` |
| `seed` | 数值 | `42` |

- **返回值**：列表，含 `arcs`（含 edge_type：inter/intra_omics）、`nodes_df`、`layer_order`、`params`。
- **输出文件**：返回 R 对象。

**`summarise_dbn_network`** — 汇总 DBN 网络（按层/边类型计数）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `dbn_result` | `run_dbn_layer` / `run_dbn_multiomics` 返回对象 | 必填 |
| `label` | 字符，标签 | `NULL` |

- **返回值**：data.frame（网络摘要）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

### `multiomics/network_perturbation.R`

> 本文件函数与上方 DBN（dynamic_bayesian_network.R）结果配套，用于网络级虚拟扰动与调控重要性评估（输入均为 `run_dbn_layer()` / `run_dbn_multiomics()` 的结果对象）。

**`get_downstream_nodes`** — 查找某节点在 DBN 中的所有下游可达节点及其最短路径距离（结构证据层，始终可用）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `dbn_result` | DBN 结果对象（`run_dbn_*()` 输出） | 必填 |
| `node` | 字符，起始节点名 | 必填 |
| `max_distance` | 数值，最大路径长度 | `Inf` |

- **返回值**：data.frame（node、distance），无下游时为空。
- **输出文件**：返回 R 对象。

**`run_node_knockout`** — 模拟节点敲除以衡量结构破坏程度。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `dbn_result` | DBN 结果对象 | 必填 |
| `nodes` | 字符向量，待敲除节点（默认所有有出弧的节点） | `NULL` |
| `top_n` | 数值，仅保留出度最高的 top_n 节点 | `NULL`（全部） |

- **返回值**：data.frame（每节点：n_descendants、n_arcs_lost、n_components_after、n_orphaned）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

**`run_virtual_perturbation`** — 虚拟扰动分析（knockout / overexpress / inhibit + 下游传播推断）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `dbn_result` | DBN 结果对象（含 bn.fit 与数据） | 必填 |
| `mode` | 字符，`"knockout"` / `"overexpress"` / `"inhibit"` | 必填 |
| `nodes` | 候选节点（默认所有有出弧节点） | `NULL` |
| `n_sim` | 数值，Monte-Carlo 采样数 | `2000` |
| `top_n` | 数值，送入推断层的候选数 | `15` |
| `seed` | 数值 | `42` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `node_summary`（每节点效应摘要）、`pair_details`（每对下游效应）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `pair_details`。

**`score_regulatory_importance`** — 综合调控重要性评分（归一化至 [0,1]）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `perturb_result` | `run_virtual_perturbation()` 输出 | 必填 |
| `weights` | 命名数值向量，各成分权重 | `c(descendants=0.4, tvd=0.4, betweenness=0.2)` |

- **返回值**：data.frame（按 impact_score 排序，含 rank 列）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

**`run_perturbation_panel`** — 运行全部扰动模式并合并排序。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `dbn_result` | DBN 结果对象 | 必填 |
| `modes` | 字符向量，扰动模式（默认全部三种） | `NULL` |
| `n_sim` | 数值，每干预 Monte-Carlo 采样数 | `3000` |
| `top_n` | 数值，每模式候选数 | `15` |
| `seed` | 数值 | `42` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `importance`（堆叠评分）、`pair_details`（堆叠下游效应）、`by_mode`（原始每模式结果）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `pair_details`。

### `multiomics/mantel_procrustes.R`

**`compute_omics_distances`** — 为各层构建样本距离矩阵（供 Mantel/Procrustes 复用）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mat_list` | 命名列表，各层数值矩阵（特征×样本） | 必填 |
| `method` | 字符，距离方法（如 `"euclidean"`、`"bray"`） | `"euclidean"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：命名列表（各层 `dist` 对象）。
- **输出文件**：返回 R 对象。

**`run_mantel_test`** — Mantel 检验（层间/层-环境距离矩阵相关性）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mat_list` | 命名列表，各层数值矩阵 | 必填 |
| `env_data` | data.frame，环境变量（样本×变量，可选） | `NULL` |
| `dist_method` | 字符，组学距离方法 | `"euclidean"` |
| `env_dist_method` | 字符，环境距离方法 | `"euclidean"` |
| `method` | 字符，Mantel 相关方法 | `"pearson"` |
| `permutations` | 数值，置换次数 | `999` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `omics_omics`（data.frame：layer_x、layer_y、mantel_r、p_value、significance）、`omics_env`（层-环境，env_data 为 NULL 时为空）、`distances`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

**`run_procrustes`** — Procrustes 分析（两种排序配置样本对齐）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mat_x` | 数值矩阵，第一配置（特征×样本） | 必填 |
| `mat_y` | 数值矩阵，第二配置 | 必填 |
| `dist_method` | 字符 | `"euclidean"` |
| `permutations` | 数值 | `999` |
| `name_x` / `name_y` | 字符，层标签 | `"x"` / `"y"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `procrustes`、`protest`、`ss`、`correlation`、`p_value`、`coordinates`（data.frame：sample、x1、y1、x2、y2、residual）。
- **输出文件**：返回 R 对象。

**`run_all_procrustes`** — 对多个层对批量运行 Procrustes。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `layer_pairs` | 列表，长 2 的字符向量 | 必填 |
| `dist_method` | 字符 | `"euclidean"` |
| `permutations` | 数值 | `999` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `results`（各层对 run_procrustes 输出）、`summary`（data.frame：layer_x、layer_y、ss、correlation、p_value、significance）。
- **输出文件**：返回 R 对象。

### `multiomics/multiomics_plspm.R`

**`clean_ec_number`** — 清洗并截断 EC 编号到指定层级。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `x` | 字符向量，原始 EC 注释（如 `"EC 1.13.11.71"`） | 必填 |
| `level` | 数值，保留的 EC 组件数 | `2` |

- **返回值**：截断后的 EC 类字符向量（无可用编号处为 NA）。
- **输出文件**：返回 R 对象。

**`build_multiomics_latent_def`** — 由多组学注释自动构建 PLS-PM 测量模型定义。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `source_map` | 命名列表，层→注释来源列（如 `list(transcriptome="ec_number", metabolome="super_class")`） | 必填 |
| `top_n` | 数值，按方差保留的潜变量特征数 | `15` |
| `ec_level` | 数值，EC 截断层级 | `2` |
| `fallback_sources` | 字符向量，覆盖不足时的备用列 | `NULL` |
| `min_coverage` | 数值，接受某来源的最小注释覆盖比例 | `0.2` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `latent_def`（潜变量→特征 ID 命名列表）、`definitions`（data.frame：latent、layer、source、group、n_features）、`layer_sources_used`。
- **输出文件**：返回 R 对象。

**`build_hierarchical_inner_model`** — 按生物学层级构建 PLS-PM 内部路径（下三角）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `definitions` | `build_multiomics_latent_def` 的 `definitions` data.frame | 必填 |
| `layer_order` | 字符向量，最上游层在前 | 必填 |
| `allow_within_layer` | 逻辑，同层潜变量是否相连 | `FALSE` |
| `adjacent_only` | 逻辑，是否仅连相邻层（非全部下游） | `FALSE` |

- **返回值**：列表，含 `path_matrix`（下三角 0/1 矩阵）、`definitions`（按路径矩阵行序重排）。
- **输出文件**：返回 R 对象。

**`run_multiomics_plspm`** — 分层多组学 PLS 路径模型（整合各层为潜变量网络）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `latent_def` | 命名列表，潜变量→特征 ID | 必填 |
| `definitions` | `build_hierarchical_inner_model` 的 `definitions` data.frame | 必填 |
| `path_matrix` | 下三角 0/1 内部模型矩阵 | 必填 |
| `scale` | 逻辑，标准化显变量 | `TRUE` |
| `boot_val` | 逻辑，是否 bootstrap 验证 | `FALSE` |
| `br` | 数值，bootstrap 重复数 | `100` |
| `min_block_size` | 数值，清洗后每块最小显变量数 | `2` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `model`、`inner_paths`（路径系数表：from_layer、to_layer、path_coeff、p_value）、`outer_loadings`、`scores`、`fit_summary`（R² 等）、`effects`、`gof`、`definitions`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `inner_paths`/`fit_summary`。

**`summarise_plspm_paths`** — 汇总 PLS-PM 路径系数表（按 (from_layer,to_layer) 过渡）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `plspm_result` | `run_multiomics_plspm` 返回对象 | 必填 |
| `p_threshold` | 数值，显著性阈值 | `0.05` |

- **返回值**：data.frame（每 (from_layer,to_layer) 一行）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

### `multiomics/pathway_bridge.R`

**`split_by_organism`** — 按来源生物（宿主/微生物）拆分特征注释。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `feature_info` | data.frame，特征注释 | 必填 |
| `organism_col` | 字符，生物列名 | `"organism"` |
| `host_pattern` | 字符，宿主正则 | `"Nicotiana"` |

- **返回值**：列表（host、microbe 两个 data.frame）。
- **输出文件**：返回 R 对象。

**`build_cross_omics_modules`** — 由共享注释列构建跨组学模块（模块特征基因）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `category_col` | 字符，分组注释列（如 `"super_class"`） | `"super_class"` |
| `layers` | 字符向量（NULL=全部） | `NULL` |
| `min_size` | 数值，模块最小特征数 | `3` |
| `organism_col` | 字符（可选） | `NULL` |
| `organism_keep` | 字符，`"all"` / `"host"` / `"microbe"` | `"all"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `eigengenes`（各层 模块×样本 矩阵命名列表）、`definitions`（data.frame：layer、module、n_features）、`category_col`。
- **输出文件**：返回 R 对象。

**`run_pathway_bridge`** — 相邻组学层间共享模块关联（通路桥接链）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `modules` | `build_cross_omics_modules` 结果 | 必填 |
| `layer_order` | 字符向量，生物学层序 | `c("transcriptome","proteome","metabolome","volatilome")` |
| `method` | 字符，`"pearson"` / `"spearman"` | `"pearson"` |
| `p_adjust` | 多重检验校正 | `"BH"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `links`（data.frame：module、from_layer、to_layer、r、p、padj、模块大小）、`chains`（data.frame：每模块连续显著链接数）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `links`。

### `multiomics/wgcna_trait_association.R`

**`build_wgcna_modules_layer`** — 在某一组学层构建 WGCNA 模块（封装 `build_wgcna_modules`）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `layer` | 字符，组学层名 | 必填 |
| `soft_power` | 数值（NULL 自动） | `NULL` |
| `min_module_size` | 数值 | `10` |
| `merge_cut_height` | 数值 | `0.25` |
| `network_type` | 字符 | `"signed"` |
| `cor_fn` | 字符 | `"cor"` |

- **返回值**：列表（module_colors、MEs、membership、layer 等）。
- **输出文件**：返回 R 对象。

**`wgcna_traits_from_layer`** — 将下游组学层表达矩阵转为性状矩阵。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `layer` | 字符，下游层名 | 必填 |
| `reference_samples` | 字符向量，参考样本顺序 | 必填 |
| `features` | 字符向量，限制性状（NULL=全部） | `NULL` |
| `log_transform` | 逻辑，是否 log2(x+1) | `FALSE` |

- **返回值**：数值矩阵（samples × traits）。
- **输出文件**：返回 R 对象。

**`run_wgcna_trait_association`** — WGCNA 模块特征基因 vs 下游性状关联。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `wgcna` | `build_wgcna_modules_layer` 结果 | 必填 |
| `traits` | 数值矩阵（samples × traits） | 必填 |
| `trait_layer` | 字符，下游层名（用于标签） | 必填 |
| `cor_method` | 字符 | `"pearson"` |
| `p_adjust` | 字符 | `"BH"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `module_trait`（data.frame：module、trait、r、p、padj、lm_*）、`module_summary`、`trait_summary`、`used_traits`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `module_trait`。

**`annotate_wgcna_trait_result`** — 为模块-性状结果附加可读特征名。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `assoc` | `run_wgcna_trait_association` 结果 | 必填 |
| `module_feature_info` | data.frame，模块层特征注释 | `NULL` |
| `module_layer` | 字符 | `"module"` |
| `trait_feature_info` | data.frame，性状层特征注释 | `NULL` |
| `trait_layer` | 字符 | `"trait"` |

- **返回值**：data.frame（在 `assoc$module_trait` 基础上增列）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存。

**`plot_wgcna_trait_heatmap`** — 模块-性状相关性热图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `assoc` | `run_wgcna_trait_association` 结果 | 必填 |
| `top_n_traits` | 数值，展示性状数 | `40` |
| `title` | 字符 | `NULL` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `multiomics/temporal_trajectory.R`

**`run_temporal_trajectory`** — 重构单一组学层的时间轨迹。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame，行名匹配样本列 | 必填 |
| `time_col` | 字符，时间列名 | `"day"` |
| `group_col` | 字符，分组列（可选） | `NULL` |
| `phase_col` | 字符，阶段标注列（可选） | `NULL` |
| `n_comp` | 数值，保留主成分数 | `2` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `trajectory`（data.frame：group、time、phase、n_samples、均值 PC 坐标）、`scores`、`variance`、`path_length`（各 group 累计轨迹长度）。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `trajectory`。

**`run_all_temporal_trajectories`** — 对 `MultiOmicsData` 每层运行轨迹。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `time_col` | 字符 | `"day"` |
| `group_col` | 字符 | `NULL` |
| `phase_col` | 字符 | `NULL` |
| `layers` | 字符向量（NULL=全部） | `NULL` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `per_layer`（各层轨迹）、`path_summary`（跨层路径长度 data.frame）。
- **输出文件**：返回 R 对象。

**`run_temporal_clustering`** — 按时间表达模式聚类特征（模糊 c-means）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | 必填 |
| `time_col` | 字符 | `"day"` |
| `n_clusters` | 数值 | `6` |
| `top_n` | 数值，仅取最变异特征（NULL=全部） | `NULL` |
| `seed` | 数值 | `42` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `cmeans`（run_cmeans 结果）、`profiles`（长表：cluster、time、均值，供绘图）、`membership`、`time_matrix`。
- **输出文件**：返回 R 对象。

### 多组学可视化（`multiomics/plot_*.R`）

以下绘图函数均**返回 ggplot / pheatmap 对象**，需经 `export_plot()` / `export_heatmap()` 保存。

| 函数（脚本） | 功能 | 关键参数（默认值） | 输入 |
| --- | --- | --- | --- |
| `plot_cross_correlation_heatmap` (`plot_multiomics.R`) | 跨组学相关热图 | `cor_result`（必填）；`top_n=30`；`title="Cross-omics correlation"`；`cluster=TRUE` | pheatmap 对象 |
| `plot_mantel_network` (`plot_multiomics.R`) | Mantel 统计条形图 | `mantel_result`（必填）；`title="Mantel test"`；`alpha=0.05` | ggplot |
| `plot_procrustes` (`plot_multiomics.R`) | Procrustes 位移图 | `proc_result`（必填）；`sample_info=NULL`；`color_col=NULL`；`title="Procrustes analysis"` | ggplot |
| `plot_diablo_scores` (`plot_multiomics.R`) | DIABLO 各块得分图 | `diablo_result`（必填）；`title="DIABLO sample scores"` | ggplot（分面） |
| `plot_temporal_trajectory` (`plot_multiomics.R`) | 发酵轨迹图 | `traj_result`（必填）；`title="Fermentation trajectory"`；`show_samples=TRUE` | ggplot |
| `plot_temporal_clusters` (`plot_multiomics.R`) | 时序聚类剖面图 | `cluster_result`（必填）；`title="Temporal expression clusters"` | ggplot |
| `plot_cross_omics_network` (`plot_multiomics.R`) | 跨组学关联网络图 | `network`（必填）；`label_top=15`；`title="Cross-omics association network"`；`seed=42` | ggplot |
| `plot_pathway_bridge_heatmap` (`plot_multiomics.R`) | 通路桥接热图 | `bridge_result`（必填）；`top_n=30`；`title="Pathway bridging across omics layers"` | ggplot |
| `plot_correlation_partners` (`plot_multiomics.R`) | 相关伙伴数条形图 | `summary_df`（必填）；`top_n=20`；`title="Top correlation partners"` | ggplot |
| `build_association_network` (`plot_association_network.R`) | 由边表构建 igraph 网络 | `edges`（必填）；`p_threshold=0.05`；`max_edges`（按 |score| 截断，默认由调用方定）；`node_omics=NULL`；`default_omics`（推断失败时的层标签）；`verbose=TRUE` | igraph 对象 |
| `plot_association_network` (`plot_association_network.R`) | 显著关联网络图 | `g`（igraph 或边表）；`p_threshold=0.05`（仅当 g 为边表时）；`label_top_n=12`；`title`（必填时给出） | ggplot |
| `plot_association_summary` (`plot_association_network.R`) | 关联计数堆叠条形图 | `results`（命名列表，每个含 `edges`/`params`）；`title` | ggplot |
| `get_association_hubs` (`plot_association_network.R`) | 提取枢纽节点 | `g`（igraph）；`top_n=20` | data.frame |
| `plot_dbn_layer` (`plot_dbn_plspm.R`) | 单组学 DBN 图（双时间片列） | `dbn_result`（必填）；`title=NULL`；`label_top=30`；`layout="fr"`（或 "force"/"kk"/"tree"/"hier"/坐标矩阵） | ggplot |
| `plot_dbn_multiomics` (`plot_dbn_plspm.R`) | 全组学 DBN 图（每层一列） | `dbn_result`（必填）；`title=NULL`；`label_top=30`；`layout="fr"`（或 "force"/"kk"/"hier"/坐标矩阵） | ggplot |
| `plot_perturbation_ranking` (`plot_dbn_plspm.R`) | 调控重要性排序条形图 | `importance_df`（必填）；`top_n=20`；`title=NULL` | ggplot |
| `plot_perturbation_heatmap` (`plot_dbn_plspm.R`) | 扰动下游效应热图 | `pair_details`（必填）；`mode=NULL`（取首个可用模式）；`top_n=15`；`title=NULL` | ggplot |
| `plot_perturbation_subnetwork` (`plot_dbn_plspm.R`) | 单节点扰动子网络图 | `dbn_result`（必填）；`node`（必填）；`title=NULL`；`max_distance=Inf`；`layout="fr"`（或 "force"/"kk"/"ring"/坐标矩阵） | ggplot |
| `plot_plspm_hierarchy` (`plot_dbn_plspm.R`) | 分层 PLS-PM 路径图 | `plspm_result`（必填）；`layer_order`（需提供）；`title=NULL`；`layout="hier"`（或 "fr"/"force"/"kk"/坐标矩阵） | ggplot |
| `plot_plspm_r2` (`plot_dbn_plspm.R`) | PLS-PM 解释方差条形图 | `plspm_result`（必填）；`title=NULL` | ggplot |

> `network_perturbation.R` 的扰动分析函数（`get_downstream_nodes`、`run_node_knockout`、`run_virtual_perturbation`、`score_regulatory_importance`、`run_perturbation_panel`，详见子代理/直接阅读该脚本）与上方 DBN 绘图函数配套使用；其输入为 DBN 结果对象，返回 data.frame/列表，需经 `export_table()` 保存。

---

## 附录：输出文件类型速查

| 落盘方式 | 触发条件 | 典型产物 |
| --- | --- | --- |
| **直接落盘函数** | 函数体内调用 `openxlsx`/`write.csv`/`saveWorkbook` 等 | `.xlsx`（compile_csv_to_xlsx）、`.csv`（extract_sheets、export_cmeans_membership、save_plot 系列） |
| **导出辅助函数** | 返回对象 + 调用 `utils/export.R` | `.pdf` + `.png`（export_plot/export_heatmap）、`.csv`（export_table） |
| **仅控制台输出** | `print.OmicsData`/`print.MultiOmicsData`、`source_all_scripts.R`、`extract_sheets.R`（命令行） | 无文件，仅打印 |

> 提示：参数默认值均以脚本内 `#' @param` 标注为准。标记为"必填"的参数在函数调用时必须提供。涉及 `MultiOmicsData` 的函数需先通过 `create_multiomics_data()`（multiomics/multiomics_data.R）构造输入对象。内部辅助函数（以 `#' @keywords internal` 或 `#' @noRd` 标注，如 `aggregate_time_series` 之外的 `.dbn_*`、`%||%`、`.row_standardise`、`.perturb_*`、`.dbn_*`、`.norm01` 等）未在本索引收录。
