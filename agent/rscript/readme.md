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
├── enrichment/                 # 富集分析：Fisher / GSVA
├── machine_learning/           # 机器学习：LASSO / 线性模型 / 随机森林
├── multivariate/               # 多变量：PCA / PLS-DA / OPLS-DA
├── network/                    # 网络：贝叶斯网络 / c-means / PLS-PM / WGCNA
├── preprocessing/              # 预处理：缺失值过滤 / 填补 / 归一化 / 标准化
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
| `get_npg_palette` | 返回 Nature Publishing Group 风格配色向量 | `n = 10`（颜色数）；`alpha = 1` | 命名字符向量。返回对象 |
| `theme_pub` | 发表级 ggplot 主题 | `base_size = 12`；`legend = "right"`；`grid = "y"` | ggplot 主题对象。返回对象 |
| `setup_base_font` | 设置基础字体（影响 pdf/png 输出） | `family = "sans"`；`font_dir = NULL` | 无（副作用设置图形设备字体） |
| `save_plot_unified` | 统一保存 ggplot 至 pdf+png | `plot`（必填）；`filename`（必填）；`output_dir = "."`；`width = 10`；`height = 8`；`dpi = 300`；`device = c("pdf","png")` | **直接落盘**：`<output_dir>/<filename>.pdf` + `.png` |

---

## `differential/`（差异分析）

### `differential/limma_de.R`

**`run_limma`** — 基于 limma 的线性模型差异表达分析（含经验贝叶斯平滑）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame，行名对应样本列 | 必填 |
| `group_col` | 字符，分组列名 | `"sample_info"` |
| `contrast` | 字符，对比公式（如 `"grp2-grp1"`） | `NULL` |
| `covariates` | 字符向量，需纳入的协变量列名 | `NULL` |
| `method` | 字符，归一化/估计方法 | `"ls"` |
| `trend` | 逻辑 | `TRUE` |
| `robust` | 逻辑 | `TRUE` |
| `adj_method` | 多重检验校正方法 | `"BH"` |
| `p_cutoff` | 数值，显著性阈值 | `0.05` |
| `logFC_cutoff` | 数值，logFC 阈值 | `1` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `results`（差异结果 data.frame：logFC、AveExpr、t、P.Value、adj.P.Val、B 等）、`fit`、`top_table`、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `results`。

### `differential/anova.R`

**`run_anova`** — 单因素方差分析（每组测序/测量重复）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符，分组列名 | `"sample_info"` |
| `adj_method` | 多重检验校正 | `"BH"` |
| `p_cutoff` | 数值 | `0.05` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `results`（data.frame：ANOVA F、P.Value、adj.P.Val、组均值等）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `results`。

### `differential/f_test.R`

**`run_f_test`** — F 检验（两组或多组均值差异检验）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `var_equal` | 逻辑，是否假定方差齐 | `TRUE` |
| `adj_method` | 多重检验校正 | `"BH"` |
| `p_cutoff` | 数值 | `0.05` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `results`（data.frame：statistic、P.Value、adj.P.Val 等）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `results`。

---

## `enrichment/`（富集分析）

### `enrichment/fisher_enrich.R`

**`run_fisher_enrich`** — 基于超几何分布（Fisher 精确检验）的富集分析。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `feature_list` | 字符向量，待富集的特征（如差异特征） | 必填 |
| `background` | 字符向量，背景特征全集 | 必填 |
| `annotation` | data.frame，特征→通路/类别映射 | 必填 |
| `feature_col` | 字符，annotation 中特征列名 | `"feature"` |
| `category_col` | 字符，annotation 中类别列名 | `"category"` |
| `min_size` | 数值，类别最小成员数 | `3` |
| `p_cutoff` | 数值 | `0.05` |
| `adj_method` | 多重检验校正 | `"BH"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `results`（data.frame：category、count、expected、odds_ratio、p_value、adj_p_value 等）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `results`。

### `enrichment/gsva.R`

**`run_gsva`** — 基因集变异分析（GSVA），将表达矩阵转为通路活性评分矩阵。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `gene_sets` | 列表，名称=基因集名，元素=特征向量 | 必填 |
| `method` | 字符，`"gsva"` / `"ssgsea"` / `"zscore"` / `"plage"` | `"gsva"` |
| `kcdf` | 字符，核密度类型 | `"Gaussian"` |
| `parallel` | 逻辑，是否并行 | `FALSE` |
| `parallel_sz` | 数值，并行线程数 | `1` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `scores`（通路×样本评分矩阵）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `scores`（矩阵需先转为 data.frame）。

---

## `machine_learning/`（机器学习）

### `machine_learning/lasso.R`

**`run_lasso`** — Lasso 回归（glmnet）特征选择与系数估计。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `x` | 数值矩阵，features × samples（或转置） | 必填 |
| `y` | 数值/因子向量，样本响应（长度=样本数） | 必填 |
| `alpha` | 数值，弹性网络混合参数（1=Lasso） | `1` |
| `family` | 字符，如 `"gaussian"` / `"binomial"` | `"gaussian"` |
| `n_fold` | 数值，交叉验证折数 | `10` |
| `lambda` | 数值，固定 lambda（NULL 则按 cv 选） | `NULL` |
| `transpose` | 逻辑，是否转置 x 使行为样本 | `TRUE` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `model`（glmnet 拟合）、`cvfit`、`coefficients`（非零系数 data.frame）、`lambda_min`/`lambda_1se`、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `coefficients`。

### `machine_learning/linear_model.R`

**`run_linear_model`** — 多元线性回归。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `x` | 数值矩阵，特征 × samples（或转置） | 必填 |
| `y` | 数值向量，响应 | 必填 |
| `transpose` | 逻辑 | `TRUE` |
| `standardize` | 逻辑，是否标准化 | `TRUE` |
| `intercept` | 逻辑，是否含截距 | `TRUE` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `model`（lm 拟合）、`coefficients`、`summary`（统计量 data.frame）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `coefficients` / `summary`。

### `machine_learning/rf_shap.R`

**`run_rf_shap`** — 随机森林训练 + SHAP 值解释。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `x` | 数值矩阵，特征 × samples（或转置） | 必填 |
| `y` | 向量，响应（分类或回归） | 必填 |
| `group_col` | 字符，样本分组列名（用于着色/分层） | `"sample_info"` |
| `exclude_groups` | 字符向量，需剔除的分组 | `NULL` |
| `transpose` | 逻辑 | `TRUE` |
| `n_trees` | 数值，树数量 | `500` |
| `cv_folds` | 数值，交叉验证折数 | `5` |
| `n_top_features` | 数值，展示/绘制的重要特征数 | `20` |
| `compute_shap` | 逻辑，是否计算 SHAP | `TRUE` |
| `seed` | 数值，随机种子 | `42` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `model`（randomForest 拟合）、`importance`（重要性 data.frame）、`shap`（SHAP 值矩阵）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `importance` / `shap`。

**`plot_rf_importance`** — 随机森林特征重要性条形图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `rf_result` | `run_rf_shap` 返回对象 | 必填 |
| `top_n` | 数值，展示前 N 重要特征 | `20` |
| `title` | 字符 | `"Random Forest Importance"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`plot_confusion_matrix`** — 随机森林预测混淆矩阵图（分类场景）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `rf_result` | `run_rf_shap` 返回对象（含预测与真实标签） | 必填 |
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
| `sample_info` | data.frame（可选，用于着色） | `NULL` |
| `group_col` | 字符，分组列名 | `NULL` |
| `n_comp` | 数值，保留主成分数 | `5` |
| `scale` | 逻辑，是否按特征标准化 | `TRUE` |
| `center` | 逻辑，是否中心化 | `TRUE` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `scores`（样本主成分坐标 data.frame）、`loadings`（特征载荷）、`variance`（各 PC 方差解释率）、`params`。
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
| `n_comp` | 数值，成分数 | `2` |
| `scale` | 逻辑 | `TRUE` |
| `validation` | 字符，`"none"` / `"CV"` / `"LOO"` | `"CV"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `scores`、`loadings`、`vip`（变量重要性投影值）、`perf`、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `vip` / `scores`。

**`plot_plsda_scores`** — PLS-DA 样本得分图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `plsda_result` | `run_plsda` 返回对象 | 必填 |
| `comp_x` / `comp_y` | 数值，使用第几成分 | `1` / `2` |
| `title` | 字符 | `"PLS-DA Scores"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

**`plot_vip`** — VIP 值排序条形图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `plsda_result` | `run_plsda` 返回对象（含 `vip`） | 必填 |
| `top_n` | 数值 | `20` |
| `threshold` | 数值，VIP 显著阈值线 | `1` |
| `title` | 字符 | `"VIP Scores"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `multivariate/oplsda.R`

**`run_oplsda`** — 正交偏最小二乘判别分析（OPLS-DA）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | `"sample_info"` |
| `ncomp_pred` | 数值，预测成分数 | `1` |
| `ncomp_ortho` | 数值，正交成分数 | `NULL`（自动） |
| `scale` | 逻辑 | `TRUE` |
| `validation` | 字符 | `"CV"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `scores`、`loadings`、`vip`、`ortho_scores`、`perf`、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存结果表格。

**`plot_oplsda_scores`** — OPLS-DA 样本得分图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `oplsda_result` | `run_oplsda` 返回对象 | 必填 |
| `comp_x` / `comp_y` | 数值 | `1` / `2` |
| `title` | 字符 | `"OPLS-DA Scores"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

---

## `network/`（网络分析）

### `network/bnlearn_net.R`

**`run_bn_learn`** — 基于 bnlearn 的贝叶斯网络结构学习。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `data` | data.frame，变量×观测（或转置） | 必填 |
| `transpose` | 逻辑 | `TRUE` |
| `method` | 字符，结构学习算法（如 `"hc"`、`"tabu"`） | `"hc"` |
| `whitelist` | 字符矩阵/数据框，强制边 | `NULL` |
| `blacklist` | 字符矩阵/数据框，禁止边 | `NULL` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `dag`（bn 对象）、`arcs`（边 data.frame）、`fitted`（参数拟合）、`params`。
- **输出文件**：返回 R 对象。

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

**`run_plspm`** — 偏最小二乘路径模型（PLS-PM）拟合。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `data` | data.frame，观测×变量 | 必填 |
| `inner_model` | 列表，内部路径（潜变量间关系） | 必填 |
| `outer_model` | 列表，测量模型（块指标） | 必填 |
| `scheme` | 字符，内模型权重方案 | `"centroid"` |
| `scaled` | 逻辑 | `TRUE` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `inner_paths`、`outer_loadings`、`r2`、`gof`、`params`。
- **输出文件**：返回 R 对象。

**`build_latent_def_from_annotation`** — 由注释表（特征→潜变量块）自动构建 PLS-PM 测量模型定义。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `annotation` | data.frame，含特征列与块/潜变量列 | 必填 |
| `feature_col` | 字符，特征列名 | `"feature"` |
| `block_col` | 字符，块/潜变量列名 | `"block"` |
| `inner_edges` | 字符矩阵，潜变量间边（可选） | `NULL` |

- **返回值**：列表，含 `outer_model`、`inner_model`（供 `run_plspm` 使用）。
- **输出文件**：返回 R 对象。

### `network/wgcna_module.R`

**`build_wgcna_modules`** — WGCNA 共表达模块识别。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `soft_power` | 数值，软阈值幂（NULL 则自动选） | `NULL` |
| `min_module_size` | 数值 | `30` |
| `merge_cut_height` | 数值，模块合并高度 | `0.25` |
| `network_type` | 字符，如 `"signed"` / `"unsigned"` | `"signed"` |
| `cor_fn` | 字符，相关函数 | `"cor"` |
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

**`run_wgcna_trait`** — WGCNA 模块与性状关联分析（单组学）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `modules` | `build_wgcna_modules` 返回对象 | 必填 |
| `trait` | data.frame，样本×性状 | 必填 |
| `cor_method` | 字符，`"pearson"` / `"spearman"` | `"pearson"` |
| `adj_method` | 多重检验校正 | `"BH"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `assoc`（模块-性状关联 data.frame：correlation、p_value、adj_p 等）、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `assoc`。

---

## `preprocessing/`（预处理）

### `preprocessing/filter_missing.R`

**`filter_missing`** — 按缺失值比例过滤特征。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `max_missing` | 数值，最大允许缺失比例（0–1） | 必填 |
| `by_group` | 逻辑，是否按分组计算缺失比例 | `FALSE` |
| `sample_info` | data.frame（当 by_group=TRUE） | `NULL` |
| `group_col` | 字符（当 by_group=TRUE） | `NULL` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `filtered`（过滤后矩阵）、`removed`（被移除特征向量）、`params`。
- **输出文件**：返回 R 对象。

### `preprocessing/impute_missing.R`

**`impute_missing`** — 缺失值填补。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵 | 必填 |
| `method` | 字符，`"knn"` / `"mean"` / `"median"` / `"min"` / `"zero"` | `"knn"` |
| `k` | 数值，knn 近邻数（method="knn"） | `10` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `imputed`（填补后矩阵）、`params`。
- **输出文件**：返回 R 对象。

### `preprocessing/normalize.R`

**`normalize`** — 表达矩阵归一化。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵 | 必填 |
| `method` | 字符，`"quantile"` / `"tmm"` / `"totals"` / `"median"` | `"quantile"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `normalized`（归一化矩阵）、`params`。
- **输出文件**：返回 R 对象。

### `preprocessing/scale.R`

**`scale_feature_median`** — 以特征中位数居中（特征级中心化）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵 | 必填 |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `scaled`（居中矩阵）、`center`（中位数向量）、`params`。
- **输出文件**：返回 R 对象。

**`scale_feature_zscore`** — 特征级 z-score 标准化（减中位数/除以 MAD）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵 | 必填 |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `scaled`、`center`、`scale`（MAD 向量）、`params`。
- **输出文件**：返回 R 对象。

**`scale_feature_minmax`** — 特征级 min-max 缩放至 [0,1]。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵 | 必填 |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `scaled`、`min`、`max`、`params`。
- **输出文件**：返回 R 对象。

**`scale_pareto`** — 特征级 Pareto 缩放（减均值/除以标准差平方根）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵 | 必填 |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `scaled`、`center`、`scale`、`params`。
- **输出文件**：返回 R 对象。

---

## `qcqa/`（质控与质控图）

### `qcqa/qcqa.R`

**`run_qcqa`** — 质控摘要：缺失率、变异系数、样本聚类一致性等。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵 | 必填 |
| `sample_info` | data.frame | `NULL` |
| `group_col` | 字符 | `NULL` |
| `cv_threshold` | 数值，CV 阈值 | `0.3` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `qc_table`（每特征 QC 指标 data.frame）、`sample_qc`、`params`。
- **输出文件**：返回 R 对象，需经 `export_table()` 保存 `qc_table`。

**`plot_qcqa`** — 质控图（缺失热图、CV 分布、样本 PCA 散点）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `qc_result` | `run_qcqa` 返回对象 | 必填 |
| `title` | 字符 | `"QC/QA"` |

- **返回值**：ggplot 对象（或多面板列表）。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

---

## `utils/`（工具函数）

### `utils/load_data.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `load_expression_matrix` | 读取表达矩阵 | `path`（必填）；`transpose = TRUE`（使行为特征） | 数值矩阵 |
| `load_sample_info` | 读取样本注释 | `path`（必填）；`sep = ","` | data.frame |
| `load_feature_info` | 读取特征注释 | `path`（必填）；`sep = ","` | data.frame |
| `create_omics_data` | 构造单组学 `OmicsData` 对象 | `expr_matrix`（必填）；`sample_info`（必填）；`feature_info = NULL` | `OmicsData` S3 对象 |
| `print.OmicsData` | 打印 `OmicsData` 摘要 | `x`（OmicsData）；`...` | 控制台输出（无返回值） |

### `utils/export.R`（导出约定，详见上方"快速开始"）

| 函数 | 功能 | 关键参数 | 产物 |
| --- | --- | --- | --- |
| `export_plot` | 保存 ggplot 为 pdf+png | `plot`、`output_dir`、`filename`、`width=8`、`height=6`、`dpi=300` | `.pdf` + `.png` |
| `export_heatmap` | 保存 pheatmap 为 pdf+png | 同上 | `.pdf` + `.png` |
| `export_table` | 保存 data.frame 为 csv | `data`、`output_dir`、`filename`、`use_rownames=TRUE`、`id_col_name="ID"` | `.csv` |

### `utils/plot_helpers.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `make_group_colors` | 生成分组成员配色（复用 npg 调色板） | `groups`（必填，字符向量） | 命名字符向量 |
| `save_plot` | 保存 ggplot 的轻量封装（等价于 `export_plot`） | `plot`（必填）；`output_dir`；`filename`；`width=8`；`height=6`；`dpi=300` | **直接落盘**：`.pdf` + `.png` |
| `extract_plot_meta` | 从结果对象提取用于绘图的元数据（样本/分组标签） | `result`（必填） | data.frame |

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
| `map_kegg_compound_to_pathway` | 将 KEGG compound ID 映射到通路 | `compound_ids`（必填）；`species = "hsa"` | data.frame（compound→pathway） |
| `run_kegg_pathway_enrich` | KEGG 通路富集（超几何/Fisher） | `features`（必填）；`background`（必填）；`species="hsa"`；`p_cutoff=0.05`；`adj_method="BH"` | 列表，含 `results` data.frame |
| `run_kegg_pathway_gsva` | KEGG 通路 GSVA 评分 | `expr_matrix`（必填）；`species="hsa"`；`method="gsva"` | 列表，含 `scores` 矩阵 |
| `run_kegg_pathway_wgcna` | KEGG 通路与 WGCNA 模块关联 | `modules`（必填，WGCNA 结果）；`species="hsa"`；`cor_method="pearson"` | 列表，含 `assoc` data.frame |

- **输出文件**：均返回 R 对象，需经 `export_table()` 保存 `results` / `scores` / `assoc`。

---

## `visualization/`（可视化）

### `visualization/volcano_plot.R`

**`plot_volcano`** — 差异分析结果火山图。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `results` | data.frame，含 `logFC`/`log2FoldChange` 与 `adj.P.Val`/`padj` 列 | 必填 |
| `logFC_threshold` | 数值 | `1` |
| `p_threshold` | 数值 | `0.05` |
| `label_top_n` | 数值，标注 top 差异特征数 | `10` |
| `title` | 字符 | `"Volcano plot"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `visualization/vip_manhattan.R`

**`plot_vip_manhattan`** — VIP 值曼哈顿图（PLS-DA/OPLS-DA 变量重要性）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `vip` | 数值向量或 data.frame（特征→VIP） | 必填 |
| `threshold` | 数值，VIP 显著阈值 | `1` |
| `top_n` | 数值，标注数 | `20` |
| `title` | 字符 | `"VIP Manhattan"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `visualization/heatmap_plot.R`

**`plot_heatmap`** — 通用表达热图（基于 pheatmap）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mat` | 数值矩阵（特征×样本） | 必填 |
| `annotation_col` | data.frame，列注释（可选） | `NULL` |
| `scale` | 字符，`"none"` / `"row"` / `"column"` | `"row"` |
| `cluster_rows` | 逻辑 | `TRUE` |
| `cluster_cols` | 逻辑 | `TRUE` |
| `show_rownames` | 逻辑 | `FALSE` |
| `top_n` | 数值，仅显示 top 变异特征 | `NULL` |
| `title` | 字符 | `""` |

- **返回值**：pheatmap 对象。
- **输出文件**：返回 R 对象，需经 `export_heatmap()` 保存。

### `visualization/venn_plot.R`

**`plot_venn`** — 韦恩图（2–5 组集合）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `sets` | 列表，命名集合（字符向量） | 必填 |
| `title` | 字符 | `"Venn"` |
| `fill` | 字符向量，各集合填充色 | `NULL`（自动） |

- **返回值**：ggplot 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

### `visualization/upset_plot.R`

**`plot_upset`** — Upset 图（高维集合交集）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `sets` | 列表，命名集合 | 必填 |
| `n_intersections` | 数值，展示交集数 | `10` |
| `order_by` | 字符，`"freq"` / `"degree"` | `"freq"` |
| `title` | 字符 | `"Upset"` |

- **返回值**：ggplot/ComplexUpset 对象。
- **输出文件**：返回 R 对象，需经 `export_plot()` 保存。

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
