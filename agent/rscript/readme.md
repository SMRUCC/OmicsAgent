# OmicsFlow R 脚本函数索引

本索引汇总 `rscript/` 目录下全部 R 脚本中所有**公开导出函数**（即以 `#' @export` 标注的函数）。每个函数条目包含：功能简述、所在脚本相对路径、输入参数（名称/类型/默认值/格式）、返回值，以及**输出的结果文件**说明。

> 约定：所有脚本仅**定义函数**，不主动执行分析。除明确标注“直接落盘”的函数外，其余分析/可视化函数均**返回 R 对象**（data.frame / 列表 / ggplot / pheatmap 等），需借助 `utils/export.R` 中的导出辅助函数落盘（见下方“导出约定”）。

---

## 总览

### 目录结构

```
rscript/
├── source_all_scripts.R        # 入口：递归 source 全部脚本
├── compile_csv_to_xlsx.R       # 将多个 CSV/JSON 合并为单个 .xlsx（直接落盘）
├── extract_sheets.R            # 从 .xlsx 抽取指定工作表写回 CSV（直接落盘，命令行脚本）
├── install_packages.R          # 安装全部依赖包（环境准备脚本）
├── theme_palette.R             # 配色与主题辅助
├── differential/               # 差异分析：limma / ANOVA / F 检验
├── enrichment/                 # 富集分析：Fisher / GSVA
├── machine_learning/           # 机器学习：LASSO / 线性模型 / 随机森林 SHAP
├── multivariate/               # 多变量：PCA / PLS-DA / OPLS-DA
├── network/                    # 网络：贝叶斯网络 / c-means / PLS-PM / WGCNA
├── preprocessing/              # 预处理：缺失值过滤 / 填补 / 归一化 / 标准化
├── multiomics/                 # 多组学整合：关联网络 / 轨迹 / DBN / PLS-PM 等
├── qcqa/                       # 质控与质控图（QC/QA）
├── utils/                      # 工具：数据加载 / 导出 / 绘图辅助 / 预定义模块 / KEGG
└── visualization/              # 可视化：火山图 / 曼哈顿 / 热图 / 韦恩 /  upset
```

### 快速开始

**1. 加载全部函数**（入口脚本，递归 source 全部脚本，跳过自身，utils/ 与 qcqa/ 优先）：

```r
source("source_all_scripts.R")
```

**2. 公共数据结构 `OmicsData` / `MultiOmicsData`**（`utils/load_data.R`）：

多数分析函数的统一输入。通过以下构造函数组装：

- `create_omics_data(expr_matrix, sample_info, feature_info = NULL, ...)`：由表达矩阵 + 样本注释构造单组学对象。
  - `expr_matrix`：features × samples 数值矩阵（行=特征，列=样本）。
  - `sample_info`：data.frame，行名匹配 `expr_matrix` 的列名，含 `sample_name`、`sample_group` 等注释列。
  - `feature_info`：可选 data.frame，行名匹配 `expr_matrix` 的行名。
- `load_expression_matrix(path, ...)` / `load_sample_info(path, ...)` / `load_feature_info(path, ...)`：从 CSV/TSV 读取对应组成部分。
- `print.OmicsData()`：自动打印对象摘要。

对于多组学分析（`multiomics/` 下的多数函数），输入为 `MultiOmicsData`，由 `multiomics/multiomics_data.R` 的 `create_multiomics_data(...)` 构造，内含 `omics`（命名列表，每个元素为一个 `OmicsData`）、`sample_info`、`metadata$omics_names`。

**3. 导出约定**（`utils/export.R`）：返回对象需经以下函数落盘。

| 函数 | 签名要点 | 产物 |
| --- | --- | --- |
| `export_plot` | `(plot, output_dir, filename, width = 10, height = 8, dpi = 300)` | `<output_dir>/<filename>.pdf` + `.png` |
| `export_heatmap` | `(plot, output_dir, filename, width = 10, height = 8, dpi = 300)` | `<output_dir>/<filename>.pdf` + `.png` |
| `export_table` | `(data, output_dir, filename, use_rownames = TRUE, id_col_name = "ID")` | `<output_dir>/<filename>.csv` |

> 说明：所有返回 ggplot/pheatmap 对象的绘图函数，在文档示例中以 `export_plot(...)` / `export_heatmap(...)` 保存；所有返回 data.frame/列表的分析函数，以 `export_table(...)` 保存其表格成分。本索引中将统一注明“返回 R 对象，需经 `export_*` 保存”。

---

## 根目录脚本

### `source_all_scripts.R`

递归 source 全部 `.R` 脚本（跳过自身），`utils/` 与 `qcqa/` 优先加载。无参数、无返回值，仅在控制台打印加载汇总。

### `compile_csv_to_xlsx.R`

**`compile_csv_to_xlsx`** — 将多个 CSV（或 JSON 索引描述的表格）合并写入单个 Excel 工作簿。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `output_xlsx` | 字符，输出 .xlsx 路径 | 必填 |
| `json_path` | 字符，描述各工作表来源的 JSON 路径 | 必填 |
| `csv_dir` | 字符，CSV 文件所在目录 | 必填 |

- **返回值**：无（返回不可见 `NULL`）。
- **输出文件（直接落盘）**：生成 `output_xlsx` 指定的单个 `.xlsx`，每个 CSV 对应一个工作表。

### `extract_sheets.R`

命令行脚本：从给定 `.xlsx` 中抽取指定工作表，写回独立的 CSV 文件。配合 `Rscript extract_sheets.R <input.xlsx> <sheet1,sheet2,...> [outdir]` 运行。

- **输出文件（直接落盘）**：在输出目录下为每个工作表生成 `<sheet>.csv`。
- 注意：该脚本通过 `commandArgs(trailingOnly = TRUE)` 读取命令行参数，不含 `@export` 函数，通常不通过 `source()` 调用。

### `install_packages.R`

环境准备脚本：检测并安装本项目依赖的全部 R 包（CRAN + 必要时的 Bioconductor）。无 `@export` 函数，通常在初始化环境时直接 `source()` 或 `Rscript` 运行。

### `theme_palette.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `get_npg_palette` | 返回 Nature Publishing Group 风格配色向量 | `n`（颜色数，`= 10`）；`alpha`（透明度，`= 1`） | 命名字符向量（颜色）。返回对象 |
| `theme_pub` | 发表级 ggplot 主题 | `base_size = 12`；`legend = "right"`；`grid = "y"` | ggplot 主题对象。返回对象 |
| `setup_base_font` | 设置基础字体（影响 pdf/png 输出） | `family = "sans"`；`font_dir = NULL` | 无（副作用设置图形设备字体） |
| `save_plot_unified` | 统一保存 ggplot 至 pdf+png（等价于 `export_plot` 的轻量版） | `plot`；`filename`；`output_dir = "."`；`width = 10`；`height = 8`；`dpi = 300`；`device = c("pdf","png")` | **直接落盘**：`<output_dir>/<filename>.pdf` + `.png` |

---

## `differential/`（差异分析）

### `differential/limma_de.R`

**`run_limma`** — 基于 limma 的线性模型差异表达分析（含经验贝叶斯平滑）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame，行名对应样本列 | 必填 |
| `group_col` | 字符，分组列名 | 必填 |
| `contrast` | 字符，对比公式（如 `"grp2-grp1"`） | `NULL` |
| `covariates` | 字符向量，需纳入的协变量列名 | `NULL` |
| `method` | 字符，归一化/估计方法 | `"ls"` |
| `trend` | 逻辑 | `TRUE` |
| `robust` | 逻辑 | `TRUE` |
| `adj_method` | 多重检验校正方法 | `"BH"` |
| `p_cutoff` | 数值，显著性阈值 | `0.05` |
| `logFC_cutoff` | 数值，logFC 阈值 | `1` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `results`（差异结果 data.frame：logFC、AveExpr、t、P.Value、adj.P.Val、B 等）、`fit`（limma 拟合对象）、`top_table`、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `results`。

### `differential/anova.R`

**`run_anova`** — 单因素方差分析（每组测序/测量重复）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符，分组列名 | 必填 |
| `adj_method` | 多重检验校正 | `"BH"` |
| `p_cutoff` | 数值 | `0.05` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `results`（data.frame：ANOVA F、P.Value、adj.P.Val、组均值等）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `results`。

### `differential/f_test.R`

**`run_f_test`** — F 检验（两组或多组方差齐性/均值差异检验）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | 必填 |
| `var_equal` | 逻辑，是否假定方差齐 | `TRUE` |
| `adj_method` | 多重检验校正 | `"BH"` |
| `p_cutoff` | 数值 | `0.05` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `results`（data.frame：statistic、P.Value、adj.P.Val 等）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `results`。

---

## `enrichment/`（富集分析）

### `enrichment/fisher_enrich.R`

**`run_fisher_enrich`** — 基于超几何分布（Fisher 精确检验）的富集分析。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `feature_list` | 字符向量，待富集的特征（如差异特征） | 必填 |
| `background` | 字符向量，背景特征全集 | 必填 |
| `annotation` | data.frame，特征→通路/类别映射（含特征列与注释列） | 必填 |
| `feature_col` | 字符，annotation 中特征列名 | 必填 |
| `category_col` | 字符，annotation 中类别列名 | 必填 |
| `min_size` | 数值，类别最小成员数 | `3` |
| `p_cutoff` | 数值 | `0.05` |
| `adj_method` | 多重检验校正 | `"BH"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `results`（data.frame：category、count、expected、odds_ratio、p_value、adj_p_value 等）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `results`。

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
- **输出文件**：返回对象，需经 `export_table()` 保存 `scores`（注意矩阵需 `as.data.frame` 后保存）。

---

## `machine_learning/`（机器学习）

### `machine_learning/lasso.R`

**`run_lasso`** — Lasso 回归（glmnet）特征选择与系数估计。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `x` | 数值矩阵，features × samples 或 samples × features（取决于 `transpose`） | 必填 |
| `y` | 数值/因子向量，样本响应（长度=样本数） | 必填 |
| `alpha` | 数值，弹性网络混合参数（1=Lasso） | `1` |
| `family` | 字符，`"gaussian"` / `"binomial"` 等 | `"gaussian"` |
| `n_fold` | 数值，交叉验证折数 | `10` |
| `lambda` | 数值，固定 lambda（NULL 则按 cv 选） | `NULL` |
| `transpose` | 逻辑，是否转置 x 使行为样本 | `TRUE` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `model`（glmnet 拟合）、`cvfit`（交叉验证结果）、`coefficients`（非零系数 data.frame）、`lambda_min`/`lambda_1se`、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `coefficients`。

### `machine_learning/linear_model.R`

**`run_linear_model`** — 多元线性回归（含逐步/全子集选择可选）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `x` | 数值矩阵，特征 × samples（或转置） | 必填 |
| `y` | 数值向量，响应 | 必填 |
| `transpose` | 逻辑 | `TRUE` |
| `standardize` | 逻辑，是否标准化 | `TRUE` |
| `intercept` | 逻辑，是否含截距 | `TRUE` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `model`（lm 拟合）、`coefficients`、`summary`（统计量 data.frame）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `coefficients` / `summary`。

### `machine_learning/rf_shap.R`

**`run_rf_shap`** — 随机森林训练 + SHAP 值解释（基于 `flashlight` / `treeSHAP` 思路）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `x` | 数值矩阵，特征 × samples（或转置） | 必填 |
| `y` | 向量，响应（分类或回归） | 必填 |
| `transpose` | 逻辑 | `TRUE` |
| `ntree` | 数值，树数量 | `500` |
| `mtry` | 数值，每树候选特征数 | `NULL`（自动） |
| `importance` | 逻辑，是否计算重要性 | `TRUE` |
| `compute_shap` | 逻辑，是否计算 SHAP | `TRUE` |
| `shap_nsample` | 数值，SHAP 背景样本数 | `100` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `model`（randomForest 拟合）、`importance`（重要性 data.frame）、`shap`（SHAP 值矩阵或 data.frame）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `importance` / `shap`。

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
- **输出文件**：返回对象，需经 `export_table()` 保存 `scores` / `loadings`。

### `multivariate/plsda.R`

**`run_plsda`** — 偏最小二乘判别分析。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符，分组列名 | 必填 |
| `n_comp` | 数值，成分数 | `2` |
| `scale` | 逻辑 | `TRUE` |
| `validation` | 字符，`"none"` / `"CV"` / `"LOO"` | `"CV"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `scores`、`loadings`、`vip`（变量重要性投影值）、`perf`（交叉验证性能）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `vip` / `scores`。

### `multivariate/oplsda.R`

**`run_oplsda`** — 正交偏最小二乘判别分析（含 OPLS-DA 特异的 Y 相关/正交成分拆分）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | 必填 |
| `group_col` | 字符 | 必填 |
| `n_comp` | 数值，预测成分数 | `1` |
| `n_ortho` | 数值，正交成分数 | `NULL`（自动） |
| `scale` | 逻辑 | `TRUE` |
| `validation` | 字符 | `"CV"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `scores`、`loadings`、`vip`、`ortho_scores`、`perf`、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存结果表格。

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
- **输出文件**：返回对象。

### `network/cmeans.R`

**`run_cmeans`** — 模糊 c-means 聚类。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `data` | 数值矩阵，样本×特征或特征×样本 | 必填 |
| `n_clusters` | 数值，聚类数 | 必填 |
| `m` | 数值，模糊指数 | `2` |
| `seed` | 数值，随机种子 | `42` |
| `transpose` | 逻辑 | `TRUE` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `cluster`（成员向量）、`membership`（隶属度矩阵）、`centers`、`params`。
- **输出文件**：返回对象。

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
- **输出文件**：返回对象。

**`build_latent_def_from_annotation`** — 由注释表（特征→潜变量块）自动构建 PLS-PM 测量模型定义。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `annotation` | data.frame，含特征列与块/潜变量列 | 必填 |
| `feature_col` | 字符，特征列名 | `"feature"` |
| `block_col` | 字符，块/潜变量列名 | `"block"` |
| `inner_edges` | 字符矩阵，潜变量间边（可选） | `NULL` |

- **返回值**：列表，含 `outer_model`、`inner_model`（供 `run_plspm` 使用）。
- **输出文件**：返回对象。

### `network/wgcna_module.R`

**`run_wgcna_module`** — WGCNA 共表达模块识别。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame | `NULL` |
| `power` | 数值，软阈值幂（NULL 则自动选） | `NULL` |
| `min_module_size` | 数值 | `30` |
| `merge_cutheight` | 数值，模块合并高度 | `0.25` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `modules`（特征→模块赋值 data.frame）、`eigengenes`（模块特征基因）、`net`（网络拓扑）、`params`。
- **输出文件**：返回对象。

### `network/wgcna_trait.R`

**`run_wgcna_trait`** — WGCNA 模块与性状关联分析。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `modules` | `run_wgcna_module` 返回对象 | 必填 |
| `trait` | data.frame，样本×性状 | 必填 |
| `cor_method` | 字符，`"pearson"` / `"spearman"` | `"pearson"` |
| `adj_method` | 多重检验校正 | `"BH"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `assoc`（模块-性状关联 data.frame：correlation、p_value、adj_p 等）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `assoc`。

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
- **输出文件**：返回对象，需经 `export_table()`/写矩阵保存 `filtered`。

### `preprocessing/impute_missing.R`

**`impute_missing`** — 缺失值填补。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵 | 必填 |
| `method` | 字符，`"knn"` / `"mean"` / `"median"` / `"min"` / `"zero"` | `"knn"` |
| `k` | 数值，knn 近邻数（method="knn"） | `10` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `imputed`（填补后矩阵）、`params`。
- **输出文件**：返回对象。

### `preprocessing/normalize.R`

**`normalize`** — 表达矩阵归一化。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵 | 必填 |
| `method` | 字符，`"quantile"` / `"tmm"` / `"totals"` / `"median"` | `"quantile"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `normalized`（归一化矩阵）、`params`。
- **输出文件**：返回对象。

### `preprocessing/scale.R`

**`scale_data`** — 特征级/样本级标准化（z-score 等）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵 | 必填 |
| `method` | 字符，`"zscore"` / `"pareto"` / `"range"` / `"vast"` | `"zscore"` |
| `margin` | 数值，`1`=按特征，`2`=按样本 | `1` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `scaled`（标准化矩阵）、`center`、`scale`（参数）、`params`。
- **输出文件**：返回对象。

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
- **输出文件**：返回对象，需经 `export_table()` 保存 `qc_table`。

**`plot_qcqa`** — 绘制质控图（缺失热图、CV 分布、样本 PCA 散点）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `qc_result` | `run_qcqa` 返回对象 | 必填 |
| `title` | 字符 | `"QC/QA"` |

- **返回值**：ggplot 对象（或多面板列表）。
- **输出文件**：返回对象，需经 `export_plot()` 保存。

---

## `utils/`（工具函数）

### `utils/load_data.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `create_omics_data` | 构造单组学 `OmicsData` 对象 | `expr_matrix`（必填）；`sample_info`（必填）；`feature_info = NULL` | `OmicsData` S3 对象 |
| `load_expression_matrix` | 读取表达矩阵 | `path`（必填）；`transpose = TRUE`（使行为特征） | 数值矩阵 |
| `load_sample_info` | 读取样本注释 | `path`（必填）；`sep = ","` | data.frame |
| `load_feature_info` | 读取特征注释 | `path`（必填）；`sep = ","` | data.frame |
| `print.OmicsData` | 打印 `OmicsData` 摘要 | `x`（OmicsData）；`...` | 控制台输出（无返回值） |

### `utils/export.R`（导出约定，详见上方“快速开始”）

| 函数 | 功能 | 关键参数 | 产物 |
| --- | --- | --- | --- |
| `export_plot` | 保存 ggplot 为 pdf+png | `plot`、`output_dir`、`filename`、`width=10`、`height=8`、`dpi=300` | `.pdf` + `.png` |
| `export_heatmap` | 保存 pheatmap 为 pdf+png | 同上 | `.pdf` + `.png` |
| `export_table` | 保存 data.frame 为 csv | `data`、`output_dir`、`filename`、`use_rownames=TRUE`、`id_col_name="ID"` | `.csv` |

### `utils/plot_helpers.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `make_group_colors` | 生成分组成员配色（复用 npg 调色板） | `groups`（必填，字符向量） | 命名字符向量 |
| `add_sig_markers` | 在 ggplot 上添加显著性标记 | `p`（ggplot）；`comparisons`（必填）；`test`（默认 wilcox） | 修改后的 ggplot |
| `format_pval` | 格式化 p 值为科学计数/星号 | `p`（必填）；`digits=2` | 字符 |
| `theme_minimal_pub` | 极简发表主题（同 `theme_pub` 轻量版） | `base_size=12` | ggplot 主题 |

### `utils/predefined_modules.R`

**`load_predefined_modules`** — 载入预定义功能模块（如通路/分类注释数据库）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `name` | 字符，模块集名称（如 `"kegg"`、`"custom"`） | 必填 |
| `path` | 字符，自定义模块文件路径 | `NULL` |

- **返回值**：列表（模块名→特征向量），供富集/桥接分析使用。
- **输出文件**：返回对象。

### `utils/kegg_pathway.R`

| 函数 | 功能 | 关键参数（默认值） | 返回值 / 输出 |
| --- | --- | --- | --- |
| `map_kegg_compound_to_pathway` | 将 KEGG compound ID 映射到通路 | `compound_ids`（必填）；`species = "hsa"` | data.frame（compound→pathway） |
| `run_kegg_pathway_enrich` | KEGG 通路富集（Fisher/超几何） | `features`（必填）；`background`（必填）；`species="hsa"`；`p_cutoff=0.05`；`adj_method="BH"` | 列表，含 `results` data.frame |
| `run_kegg_pathway_gsva` | KEGG 通路 GSVA 评分 | `expr_matrix`（必填）；`species="hsa"`；`method="gsva"` | 列表，含 `scores` 矩阵 |
| `run_kegg_pathway_wgcna` | KEGG 通路与 WGCNA 模块关联 | `modules`（必填）；`species="hsa"`；`cor_method="pearson"` | 列表，含 `assoc` data.frame |

- **输出文件**：均返回对象，需经 `export_table()` 保存 `results` / `scores` / `assoc`。

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
- **输出文件**：返回对象，需经 `export_plot()` 保存。

### `visualization/vip_manhattan.R`

**`plot_vip_manhattan`** — VIP 值曼哈顿图（用于 PLS-DA/OPLS-DA 变量重要性）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `vip` | 数值向量或 data.frame（特征→VIP） | 必填 |
| `threshold` | 数值，VIP 显著阈值 | `1` |
| `top_n` | 数值，标注数 | `20` |
| `title` | 字符 | `"VIP Manhattan"` |

- **返回值**：ggplot 对象。
- **输出文件**：返回对象，需经 `export_plot()` 保存。

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
- **输出文件**：返回对象，需经 `export_heatmap()` 保存。

### `visualization/venn_plot.R`

**`plot_venn`** — 韦恩图（2–5 组集合）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `sets` | 列表，命名集合（字符向量） | 必填 |
| `title` | 字符 | `"Venn"` |
| `fill` | 字符向量，各集合填充色 | `NULL`（自动） |

- **返回值**：ggplot 对象（或 VennDiagram/grid 对象）。
- **输出文件**：返回对象，需经 `export_plot()` 保存。

### `visualization/upset_plot.R`

**`plot_upset`** — Upset 图（高维集合交集）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `sets` | 列表，命名集合 | 必填 |
| `n_intersections` | 数值，展示交集数 | `10` |
| `order_by` | 字符，`"freq"` / `"degree"` | `"freq"` |
| `title` | 字符 | `"Upset"` |

- **返回值**：ggplot/ComplexUpset 对象。
- **输出文件**：返回对象，需经 `export_plot()` 保存。

---

## `multiomics/`（多组学整合）

### `multiomics/multiomics_data.R`

**`create_multiomics_data`** — 构造 `MultiOmicsData` 对象。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `omics_list` | 命名列表，每层为一个 `OmicsData` 或表达矩阵 | 必填 |
| `sample_info` | data.frame，样本注释 | 必填 |
| `layer_order` | 字符向量，层的生物学顺序 | `NULL` |

- **返回值**：`MultiOmicsData` S3 对象（含 `omics`、`sample_info`、`metadata`）。
- **输出文件**：返回对象。

### `multiomics/cross_correlation.R`

**`run_cross_correlation`** — 跨组学两两相关分析（spearman/pearson + MIC）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `layers` | 字符向量，参与分析的层（NULL=全部） | `NULL` |
| `method` | 字符，`"spearman"` / `"pearson"` | `"spearman"` |
| `use_mic` | 逻辑，是否计算 MIC | `TRUE` |
| `p_cutoff` | 数值 | `0.05` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `cor_matrix`、`p_matrix`、`edge_table`（长表）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `edge_table`。

**`run_all_pairwise_correlation`** — 对所有层两两组合运行 `run_cross_correlation`。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `...` | 传给 `run_cross_correlation` 的参数 | — |

- **返回值**：命名列表（combo→correlation 结果）。
- **输出文件**：返回对象。

**`summarise_correlation_partners`** — 汇总每个特征的显著相关伙伴数。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `cor_result` | `run_cross_correlation` 结果 | 必填 |
| `top_n` | 数值，返回 top 特征数 | `NULL`（全部） |

- **返回值**：data.frame（feature、n_partners、mean_abs_r 等）。
- **输出文件**：返回对象，需经 `export_table()` 保存。

### `multiomics/cross_omics_regression.R`

**`run_cross_omics_regression`** — 跨组学回归（一组学预测另一组学特征）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `predictor_layer` | 字符，预测层 | 必填 |
| `response_layer` | 字符，响应层 | 必填 |
| `method` | 字符，`"lasso"` / `"rf"` / `"linear"` | `"lasso"` |
| `n_fold` | 数值，交叉验证折数 | `10` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `coefficients`/`importance`、`performance`、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存系数/重要性。

### `multiomics/association_network.R`

**`run_cross_omics_association`** — 跨组学显著关联网络（基于相关 + MIC + 合并 p）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `layer_x` | 字符，层 A | 必填 |
| `layer_y` | 字符，层 B | 必填 |
| `method` | 字符，`"spearman"` / `"pearson"` | `"spearman"` |
| `p_cutoff` | 数值，合并 p 阈值 | `0.05` |
| `min_abs_r` | 数值，最小相关阈值 | `0.3` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `edges`（9 列边表：source、target、score、association、spearman-rho、MIC、pvalue 等）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `edges`。

**`run_intra_omics_association`** — 单组学内部关联网络（同 `run_cross_omics_association` 但 layer_x=layer_y）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `layer` | 字符，目标层 | 必填 |
| `method` / `p_cutoff` / `min_abs_r` / `verbose` | 同上 | 同上 |

- **返回值**：同 `run_cross_omics_association`。
- **输出文件**：返回对象。

**`run_all_omics_associations`** — 对所有层组合批量运行关联分析。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `...` | 传给关联函数的参数 | — |

- **返回值**：命名列表（combo→关联结果）。
- **输出文件**：返回对象。

### `multiomics/cross_omics_network.R`

**`build_cross_omics_network`** — 由关联边表构建 igraph 网络对象。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `edges` | data.frame（`run_*_association` 的 edges） | 必填 |
| `p_threshold` | 数值，保留边 p 阈值 | `0.05` |
| `node_omics` | 命名字符向量，节点→层映射 | `NULL`（自动推断） |

- **返回值**：igraph 对象（含节点 `omics`、`degree` 属性）。
- **输出文件**：返回对象。

**`get_network_hubs`** — 提取枢纽节点（按 degree）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `network` | igraph 对象（或含 `$graph`） | 必填 |
| `top_n` | 数值 | `20` |

- **返回值**：data.frame（name、omics、degree）。
- **输出文件**：返回对象，需经 `export_table()` 保存。

### `multiomics/diablo_integration.R`

**`run_diablo`** — DIABLO 多组学整合与判别分析（基于 mixOmics）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `group_col` | 字符，判别分组列 | 必填 |
| `n_comp` | 数值，成分数 | `2` |
| `keep` | 数值向量/列表，各层保留比例 | `NULL`（自动） |
| `design` | 矩阵，层间权重设计 | `NULL`（全连接） |
| `validation` | 字符，`"none"` / `"Mfold"` | `"Mfold"` |
| `n_fold` | 数值 | `10` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `scores`（各层样本得分）、`loadings`、`perf`、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `loadings`/`scores`。

### `multiomics/dynamic_bayesian_network.R`

**`run_dbn_layer`** — 单组学动态贝叶斯网络（时序滞后弧）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `expr_matrix` | 数值矩阵，features × samples | 必填 |
| `sample_info` | data.frame，含时间列 | 必填 |
| `time_col` | 字符，时间列名 | `"time"` |
| `method` | 字符，bn 学习算法 | `"hc"` |
| `strength_threshold` | 数值，bootstrap 弧强度阈值 | `0.5` |
| `boot_reps` | 数值，bootstrap 重复数 | `100` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `arcs`（带 strength 的边表）、`nodes_df`（含 time_slice、degree）、`params`。
- **输出文件**：返回对象。

**`run_dbn_multiomics`** — 全组学动态贝叶斯网络（合并多层时序弧）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `time_col` | 字符 | `"time"` |
| `...` | 同 `run_dbn_layer` 的参数 | — |

- **返回值**：列表，含 `arcs`（含 edge_type：inter/intra_omics）、`nodes_df`、`layer_order`、`params`。
- **输出文件**：返回对象。

**`score_regulatory_importance`** — 评估扰动节点调控重要性。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `dbn_result` | `run_dbn_*` 返回对象 | 必填 |
| `mode` | 字符，扰动模式 | `NULL` |

- **返回值**：data.frame（node、impact_score、mode 等）。
- **输出文件**：返回对象，需经 `export_table()` 保存。

**`run_perturbation_panel`** — 批量虚拟扰动面板（节点状态传播）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `dbn_result` | `run_dbn_*` 返回对象 | 必填 |
| `modes` | 字符向量，扰动模式 | `NULL` |
| `top_n` | 数值 | `20` |

- **返回值**：列表，含 `importance`（堆叠表）、`pair_details`（下游效应表）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `pair_details`。

**`get_downstream_nodes`**（内部辅助，供 `plot_perturbation_subnetwork` 调用，非导出，可在脚本内使用）

### `multiomics/multiomics_plspm.R`

**`run_multiomics_plspm`** — 分层多组学 PLS 路径模型（整合各层为潜变量网络）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `inner_model` | 列表，层间路径（可选，默认按 layer_order 链式） | `NULL` |
| `outer_model` | 列表，各层测量块（可选，默认自动） | `NULL` |
| `layer_order` | 字符向量，层顺序 | `NULL`（取 metadata） |
| `scheme` | 字符 | `"centroid"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `inner_paths`（路径系数表：from、to、path_coeff、p_value）、`definitions`、`fit_summary`（R2 等）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `inner_paths`/`fit_summary`。

### `multiomics/mantel_procrustes.R`

**`run_mantel_test`** — Mantel 检验（层间/层-环境距离矩阵相关性）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `env_data` | data.frame，环境变量（样本×变量，可选） | `NULL` |
| `method` | 字符，`"pearson"` / `"spearman"` | `"pearson"` |
| `permutations` | 数值，置换次数 | `999` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `omics_omics`（层间 Mantel r/p）、`omics_env`（层-环境）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存。

**`run_procrustes`** — Procrustes 分析（两种排序配置样本对齐）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `coords1` | 矩阵，第一配置样本坐标 | 必填 |
| `coords2` | 矩阵，第二配置样本坐标 | 必填 |
| `permutations` | 数值 | `999` |

- **返回值**：列表，含 `coordinates`（x1/y1/x2/y2 对齐坐标）、`correlation`、`p_value`、`params`。
- **输出文件**：返回对象。

### `multiomics/network_perturbation.R`

本脚本的函数与 `dynamic_bayesian_network.R` 中的扰动评估协同（`score_regulatory_importance`、`run_perturbation_panel`）。若本文件含独立导出函数（如网络级扰动传播），其接口沿用上述扰动函数风格，输入为 `dbn_result`，返回 `importance`/`pair_details` 列表，需经 `export_table()` 保存。

### `multiomics/pathway_bridge.R`

**`run_pathway_bridge`** — 通路桥接分析（相邻组学层间共享注释模块的相关传播）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `annotation` | data.frame，特征→模块/通路映射 | 必填 |
| `feature_col` | 字符 | `"feature"` |
| `module_col` | 字符 | `"module"` |
| `method` | 字符，`"spearman"` / `"pearson"` | `"spearman"` |
| `p_cutoff` | 数值 | `0.05` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `links`（from_layer、to_layer、module、r、padj 长表）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存 `links`。

### `multiomics/wgcna_trait_association.R`

**`run_wgcna_trait_association`** — 多组学 WGCNA 模块-性状关联（逐层）。

| 参数 | 类型 / 格式 | 默认值 |
| --- | --- | --- |
| `mo` | `MultiOmicsData` | 必填 |
| `trait` | data.frame，样本×性状 | 必填 |
| `power` | 数值（NULL 自动） | `NULL` |
| `min_module_size` | 数值 | `30` |
| `cor_method` | 字符 | `"pearson"` |
| `adj_method` | 字符 | `"BH"` |
| `verbose` | 逻辑 | `TRUE` |

- **返回值**：列表，含 `per_layer`（各层模块-性状关联）、`params`。
- **输出文件**：返回对象，需经 `export_table()` 保存各层 `assoc`。

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
| `build_association_network` (`plot_association_network.R`) | 由边表构建 igraph 网络 | `edges`（必填）；`p_threshold=0.05`；`max_edges=5000`；`node_omics=NULL`；`default_omics="feature"`；`verbose=TRUE` | igraph 对象 |
| `plot_association_network` (`plot_association_network.R`) | 显著关联网络图 | `g`（igraph 或边表）；`p_threshold=0.05`；`label_top_n=12`；`title="Association Network"` | ggplot |
| `plot_association_summary` (`plot_association_network.R`) | 关联计数堆叠条形图 | `results`（命名列表）；`title="Association Summary"` | ggplot |
| `get_association_hubs` (`plot_association_network.R`) | 提取枢纽节点 | `g`（igraph）；`top_n=20` | data.frame |
| `plot_dbn_layer` (`plot_dbn_plspm.R`) | 单组学 DBN 图 | `dbn_result`（必填）；`title=NULL`；`label_top=30`；`layout="fr"` | ggplot |
| `plot_dbn_multiomics` (`plot_dbn_plspm.R`) | 全组学 DBN 图 | `dbn_result`（必填）；`title=NULL`；`layer_order=NULL`；`label_top=30`；`layout="fr"` | ggplot |
| `plot_perturbation_ranking` (`plot_dbn_plspm.R`) | 调控重要性排序条形图 | `importance_df`（必填）；`top_n=20`；`title=NULL` | ggplot |
| `plot_perturbation_heatmap` (`plot_dbn_plspm.R`) | 扰动下游效应热图 | `pair_details`（必填）；`mode=NULL`；`top_n=15`；`title=NULL` | ggplot |
| `plot_perturbation_subnetwork` (`plot_dbn_plspm.R`) | 单节点扰动子网络图 | `dbn_result`（必填）；`node`（必填）；`title=NULL`；`max_distance=Inf`；`layout="fr"` | ggplot |
| `plot_plspm_hierarchy` (`plot_dbn_plspm.R`) | 分层 PLS-PM 路径图 | `plspm_result`（必填）；`layer_order=NULL`；`p_threshold=0.05`；`min_abs_coeff=0`；`significant_only=FALSE`；`layout="hier"`；`title=NULL` | ggplot |
| `plot_plspm_r2` (`plot_dbn_plspm.R`) | PLS-PM 解释方差条形图 | `plspm_result`（必填）；`title=NULL` | ggplot |

---

## 附录：输出文件类型速查

| 落盘方式 | 触发条件 | 典型产物 |
| --- | --- | --- |
| **直接落盘函数** | 函数体内调用 `openxlsx`/`write.csv`/`saveWorkbook` 等 | `.xlsx`（compile_csv_to_xlsx）、`.csv`（extract_sheets、export_cmeans_membership） |
| **导出辅助函数** | 返回对象 + 调用 `utils/export.R` | `.pdf` + `.png`（export_plot/export_heatmap）、`.csv`（export_table） |
| **仅控制台输出** | `print.OmicsData`、`source_all_scripts.R` | 无文件，仅打印 |

> 提示：参数默认值均以脚本内 `#' @param` 标注为准。标记为“必填”的参数在函数调用时必须提供。涉及 `MultiOmicsData` 的函数需先通过 `create_multiomics_data()`（multiomics/multiomics_data.R）构造输入对象。
