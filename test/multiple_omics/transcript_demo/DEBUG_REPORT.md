# 转录组学分析 Demo 调试报告（DEBUG_REPORT）

> 测试对象：`agent/rscript` 模块化 R 函数库
> 运行环境：GNU R 4.5.0（Windows ucrt），`C:\Program Files\R\R-4.5.0\bin\Rscript.exe`
> 数据集：`extdata/Tobacco-fermentation/`（烟草发酵 2000 基因 × 312 样本）
> 目录：`test/multiple_omics/transcript_demo/`
> 生成日期：2026-08-08

---

## 一、被测模块统计表

| 模块文件 | 被调用的函数 | 调用脚本 | 状态 |
|---|---|---|---|
| `utils/load_data.R` | `load_expression` / `load_feature_info` / `load_sample_info` / `create_omics_data` | `run_transcriptome_demo.R` | ✅ 正常 |
| `utils/export.R` | `export_table` / `export_plot` / `export_heatmap` | 全部脚本 | ✅ 正常 |
| `utils/plot_helpers.R` | `make_group_colors` / `export_heatmap` 支持闭包 | 时序/WGCNA | ✅ 正常 |
| `theme_palette.R` | 调色板 | 全部脚本 | ✅ 正常 |
| `preprocessing/*.R` | `filter_missing_values` / `normalize_median` / `log2_transform` / `scale_pareto` | 主流程 | ✅ 正常 |
| `qcqa/qcqa.R` | `run_qcqa` | 主流程 | ✅ 正常 |
| `multivariate/pca.R` | `run_pca` / `plot_pca_scores` / `plot_pca_loadings` | 主流程 | ✅ 正常 |
| `differential/limma_de.R` | `run_limma` | 主流程 | ✅ 正常 |
| `enrichment/fisher_enrich.R` | `run_fisher_enrich` | 主流程 | ✅ 正常 |
| `visualization/*.R` | `plot_volcano` / `plot_heatmap` | 主流程 | ✅ 正常 |
| `proteome/protein_clustering.R` | `cluster_protein_profiles` / `plot_profile_clusters` / `plot_cluster_centers` | `run_temporal_clustering.R` | ✅ 正常 |
| `network/wgcna_module.R` | `build_wgcna_modules` / `plot_soft_threshold` / `plot_wgcna_dendrogram` | `run_wgcna_analysis.R` | ✅ 正常 |
| `network/wgcna_trait.R` | `wgcna_module_trait` / `plot_module_trait` | `run_wgcna_analysis.R` | ✅ 正常 |
| `utils/kegg_pathway.R` | `map_kegg_compound_to_pathway` / `run_kegg_pathway_enrich` / `run_kegg_pathway_gsva` / `plot_kegg_enrichment`★ / `plot_kegg_pathway_activity`★ | `run_kegg_pathway.R` | ⚠️ 修复 |

★ = 本次缺陷修复中**新增**的通用函数（原本缺失）。

---

## 二、缺陷逐条记录

### 缺陷 1（源码·功能缺陷）：`map_kegg_compound_to_pathway` 仅支持化合物 `cpd:` 前缀，不支持 KO 号

- **现象**：`run_kegg_pathway.R` 需要基于注释表中的 KO 号（`K01610` 格式）做 KEGG 通路映射，但原实现一律对输入 ID 加 `cpd:` 前缀并请求 `link/pathway/cpd:K01610`，KEGG 返回空，导致 KO→pathway 映射全部失败，富集/活性分析无通路可用。
- **根因**：函数设计面向代谢组（化合物 C 号），联网端点硬编码为 `cpd:`；转录组的 KO 号（`K\d+` 或 `ko:`）被错误加上化合物前缀。
- **修复方案**：在 `agent/rscript/utils/kegg_pathway.R` 的 `map_kegg_compound_to_pathway` 中，按 ID 类型归一化前缀——`ko:`/`K\d+` → `ko:` 端点，`cpd:`/`C\d+` → `cpd:` 端点——两者均使用通用接口 `rest.kegg.jp/link/pathway/<id>`；并在清洗结果时用 `sub("^(ko|cpd):", "", ...)` 剥离前缀，使 `compound_id` 与 `feature_info$kegg` 的 `K01610` 格式对齐。**化合物路径逻辑完全不变，向后兼容。**
- **验证证据**：`run_kegg_pathway.R` SECTION 2 输出
  ```
  非空 KO 号: 647 个。
  Found 519 pathways for 550 unique pathways
  kegg_mapping (compound_id x pathway_id) dim: 5386 x 3
  唯一 KO 号映射到通路: 519 / 647
  ```
  519/647 KO 成功映射到 KEGG 通路，且 mapping 缓存到 `cache/kegg/kegg_pathway_mapping.csv`；代谢组既有调用（`metabolism_demo`）参数/返回结构未变，源码可正常 `source` 且 5 个导出函数全部可见。

### 缺陷 2（源码·缺失函数）：`run_kegg_pathway_enrich` / `run_kegg_pathway_gsva` 没有配套可视化函数

- **现象**：`run_kegg_pathway.R` 调用 `plot_kegg_enrichment(res)` 与 `plot_kegg_pathway_activity(res)` 时，R 报「找不到对象」。子代理前期误报这两个函数存在，实际 `kegg_pathway.R` 中**从未定义**它们。
- **根因**：`kegg_pathway.R` 提供了富集/GSVA 的计算函数，却遗漏了对应的绘图输出函数，模块能力不完整。
- **修复方案**：在 `agent/rscript/utils/kegg_pathway.R` 末尾**新增两个通用 ggplot2 绘图函数**（仅读取既有返回结构，不引入新分析语义）：
  - `plot_kegg_enrichment(enrich_res, top_n=20)`：横向条形图，x = `-log10(p_value)`，色标标注 `p_adj<0.05` 显著通路。
  - `plot_kegg_pathway_activity(gsva_res, top_n=30, sample_info=NULL, group_col=NULL)`：按通路行方差取 top_n 可变通路，geom_tile 热图。
  两个函数均以 `ggplot2` 对象返回，与现有 `export_plot()` 兼容；新增函数不影响任何既有调用。
- **验证证据**：源码 `source` 后 `exists("plot_kegg_enrichment")` / `exists("plot_kegg_pathway_activity")` 均为 `TRUE`；`run_kegg_pathway.R` 成功导出 `figures/07_kegg_enrich.pdf|png` 与 `figures/07_kegg_activity.pdf|png`。

### 缺陷 3（源码·健壮性缺陷）：`plot_kegg_enrichment` 未处理重复 `pathway_name` 导致 factor 崩溃

- **现象**：富集表含多条不同 `pathway_id` 但同名（如不同物种/版本同名通路）的记录，构造 `factor(label, levels=rev(label))` 因重复水平报错：`factor level [3] is duplicated`。
- **根因**：绘图函数直接以 `pathway_name` 作为分类标签，未去重。
- **修复方案**：在 `plot_kegg_enrichment` 中用 `make.unique(as.character(label), sep="·")` 对重复标签追加后缀，保证 factor 水平唯一。
- **验证证据**：修复后 `run_kegg_pathway.R` 完整跑通 SECTION 3 富集条形图，无报错。

### Demo 层调用修正（非源码缺陷，记录备查）

| # | 脚本 | 修正内容 | 性质 |
|---|---|---|---|
| D1 | `run_temporal_clustering.R` | 补充 `source_modules("utils/plot_helpers.R")`（`plot_profile_clusters` 内部依赖 `make_group_colors`） | 缺失依赖加载 |
| D2 | `run_wgcna_analysis.R` | 从 cache 补充读取 `feature_info`（SECTION 5 成员表注释需要） | 缺失变量 |
| D3 | `run_kegg_pathway.R` | 改用真实签名：`run_kegg_pathway_enrich(significant_compounds, all_compounds, kegg_mapping)` 与 `run_kegg_pathway_gsva(expr_matrix, ...)`（参数名 `expr_matrix` 非 `expr_mat`，且 enrich 直接接受 KO 号向量而非 feature_info 表） | 调用约定不符 |

> 说明：D1–D3 均为 demo 脚本未正确对齐真实函数签名/依赖所致，已在 demo 层修正，未掩盖任何模块缺陷。

---

## 三、关键分析结论

### 3.1 数据尺度与质量

| 指标 | 值 |
|---|---|
| 表达矩阵 | 2000 基因 × 312 样本（首列 `name` 为主键） |
| 丰度范围 | 0.103 – 111.427，中位数 5.175（已归一化 TPM/FPKM 类，非 counts） |
| 缺失 / 零值 | 0 / 0（连续型，适合作 limma + log2，而非 DESeq2/edgeR） |
| 保留基因 | 全部 2000（2 个未匹配注释置 NA，符合需求） |
| 基因 CV > 20% | 2000 / 2000（发酵过程表达高度动态，符合预期） |

### 3.2 PCA 主成分

`PC1=55.06%  PC2=23.68%  PC3=7.47%  PC4=6.08%`。前两主成分累计解释 **78.7%** 方差，样本按发酵阶段（phase）明显分簇，第一主成分对应发酵进程时间轴。

### 3.3 差异表达（limma）

| 对比 | 显著差异基因（p_adj<0.05 & |logFC|≥1） |
|---|---|
| **Fresh vs Late_maturation**（主对比） | **1047 / 2000（52.4%）** |
| Burley vs Virginia（品种次级对比） | **0** |

**生物学解释**：发酵阶段效应极强且弥漫（过半基因在阶段间差异表达），而品种间无显著差异。阶段对比 0 品种差异与蛋白组 demo 结论一致，反映该发酵体系的品种遗传背景效应弱于工艺阶段效应，**非计算缺陷**。

### 3.4 Fisher 过表达富集（super_class / category / family）

| 维度 | 通路/类别数 | 显著（p_adj<0.05） |
|---|---|---|
| super_class | 32 | **0** |
| category | 53 | **0** |
| family | 32 | **0** |

### 3.5 KEGG 通路富集

- KO→pathway 映射：519/647 个 KO 成功映射，覆盖 550 条通路（5386 条映射记录）。
- 差异基因中有 KO 注释 515 个，背景有 KO 注释 647 个。
- 富集结果：366 条候选通路，**p_adj<0.05 显著数 = 0**（raw p 范围 0.36–1.0，fold enrichment ≤ 1.125）。

### 3.6 为什么富集"0 显著"不是缺陷

差异基因（1047/2000）在功能注释与 KEGG 通路中**近乎均匀地铺开**：

- Alcohol 类：背景 42，差异 30（占 71%），整体差异率 52% → fold = 1.21，不显著；
- 超几何检验要求"前景中某类别比例显著高于背景"，而此处前景与背景高度重叠（差异基因即背景的主体），fold enrichment ≈ 1，自然无法检出偏向性。

这是**全局性转录重编程**的统计学体现：烟草发酵并非激活少数特异通路，而是系统性地重塑绝大多数代谢/调控通路。WGCNA 结果进一步印证这一点——**32/48 个模块-性状关联显著**，且 turquoise 模块与发酵天数 `day` 强正相关（r=0.97, p≈1e-193），black 模块与 Late_maturation 负相关（r=-0.82）。

> 因此"0 显著富集"是真实生物学信号（差异基因弥漫、无功能偏向），而非代码 bug。报告特别澄清，避免误判。

### 3.7 时序聚类（按 day）

kmeans（scale=TRUE，n=6 簇）轮廓系数 **0.651**，6 个表达模式簇大小均衡，已导出成员表（`05_cluster_members.csv`）、轮廓图与中心图。

### 3.8 WGCNA 模块-性状关联

- 软阈值 `power=6`（`network_type="signed"`，`min_module_size=30`）；识别 6 个模块：black / blue / brown / green / turquoise / yellow。
- 模块-性状关联 **32/48 显著**（p<0.05），最显著者为 turquoise×day（r=0.97）、turquoise×Late_maturation（r=0.95）、black×Late_maturation（r=-0.82）。
- 导出模块成员表、模块特征基因矩阵、关联长表与相关性热图。

---

## 四、产出清单

### 4.1 结果表格（`results/`）

| 文件 | 内容 |
|---|---|
| `00_data_structure_summary.csv` | 数据核对摘要 |
| `01_qc_gene_cv.csv` | 基因层面 QC（CV / 表达分布） |
| `02_limma_phase.csv` / `02_limma_variety.csv` | limma 阶段 / 品种差异结果 |
| `03_fisher_super_class.csv` / `03_fisher_category.csv` / `03_fisher_family.csv` | 三维度 Fisher 富集 |
| `05_cluster_members.csv` | 时序聚类成员表 |
| `06_wgcna_members.csv` / `06_wgcna_module_eigengenes.csv` / `06_wgcna_module_trait.csv` | WGCNA 成员 / MEs / 模块-性状关联 |
| `07_kegg_mapping.csv` / `07_kegg_enrich.csv` / `07_kegg_activity.csv` | KEGG 映射 / 富集 / 通路活性评分 |

### 4.2 插图（`figures/`，每图 PDF + PNG 双格式）

- `01_expression_distribution` · `02_pca_scores_{phase,variety,location}` · `02_pca_loadings_PC1_PC2` · `02_volcano_phase`
- `03_fisher_{super_class,category,family}` · `04_heatmap_top50`
- `05_cluster_profiles` · `05_cluster_centers`
- `06_wgcna_soft_threshold` · `06_wgcna_dendrogram` · `06_wgcna_module_trait`
- `07_kegg_enrich` · `07_kegg_activity`

### 4.3 缓存（`cache/`）

- `transcript_pipeline_cache.rds`（主流程中间态：expr_log2 / expr_mat / sample_info / feature_info / de_phase）
- `wgcna_result.rds`（WGCNA 模块结果，独立缓存避免重算）
- `kegg/kegg_pathway_mapping.csv`（KEGG API 响应缓存）

---

## 五、运行方式（PowerShell，按依赖顺序）

```powershell
$R = "C:\Program Files\R\R-4.5.0\bin\Rscript.exe"
cd g:\OmicsWorks\test\multiple_omics\transcript_demo

# 1. 数据核对与模块健康检查（可选，验证用）
& $R check_data_structure.R
& $R verify_source_all.R

# 2. 主流程（必须先跑，生成 cache）
& $R run_transcriptome_demo.R

# 3. 三个进阶脚本（任意顺序，独立读取 cache）
& $R run_temporal_clustering.R
& $R run_wgcna_analysis.R
& $R run_kegg_pathway.R      # 首次会联网构建 KO→pathway 映射（已缓存）
```

> 所有脚本均使用 `source("config.R")` 提供的绝对路径与 `source_modules()` 加载器，`source()` 统一 `encoding="UTF-8"`；demo 层不使用 tryCatch 包裹分析调用，模块缺陷会真实抛出。

---

## 六、修复原则落实情况

| 原则 | 落实 |
|---|---|
| 缺陷在 `agent/rscript` 源码内修复 | ✅ 缺陷 1/2/3 均在 `utils/kegg_pathway.R` 修复 |
| 不在 demo 层用 try/tryCatch 掩盖 | ✅ demo 全程未用 tryCatch，真实抛出并定位 |
| 保持函数签名与返回结构向后兼容 | ✅ 化合物路径（`cpd:`）逻辑未变；`metabolism_demo` 既有 `run_kegg_pathway_enrich(sig, bg, mapping)` 调用不受影响；源码可正常 `source` |
| 通用正确实现，不针对本数据集 hack | ✅ KO 支持基于 ID 前缀自动判别（通用）；新增绘图函数为通用 ggplot2 输出 |
| 每次修复有运行证据 | ✅ 见各缺陷「验证证据」 |
| 兼容性守护 | ✅ 修改后单独 `source` `kegg_pathway.R` 验证 5 个导出函数齐全、无 lint 错误；确认仅 `transcript_demo` / `metabolism_demo` 依赖该文件且调用契约不变 |
