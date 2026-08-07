# 代谢组学 Demo 流程 —— 模块调试与修复报告

- **运行环境**：GNU R 4.5.0（`C:\Program Files\R\R-4.5.0\bin\Rscript.exe`），Windows / PowerShell
- **被测模块库**：`agent/rscript`（63 个 `.R` 脚本，加载器验证 63/63 成功、0 失败）
- **测试数据**：烟叶发酵项目代谢组，1000 代谢物 × 312 样本
- **产出**：60 个结果表格（CSV）+ 23 张插图（PDF/PNG 各 23）
- **调试原则**：所有缺陷在 `agent/rscript` 源码内修复，保持函数签名与返回结构不变，
  只增强健壮性；demo 脚本中**不使用 try/tryCatch 掩盖任何模块缺陷**。

---

## 一、总体结论

流程以 demo 作为集成测试用例，驱动模块库全链路运行，共定位并修复 **26 处缺陷**。
其中 **7 处属于"静默错误"**——不报错、不中断，但会输出在统计上错误的结果，
是本次调试中危害最大的一类。

全部脚本当前均可无错、无警告完整运行。

| 分析脚本 | 状态 | 关键产出 |
| --- | --- | --- |
| `verify_source_all.R` | 通过 | 63/63 模块加载成功 |
| `run_metabolome_demo.R` | 通过 | 预处理 / PCA / PLS-DA / limma / F 检验 / ANOVA / 热图 / 富集 |
| `run_wgcna_network.R` | 通过 | 3 个共表达模块、模块-性状关联 13/24 显著 |
| `run_association_network.R` | 通过 | 44850 对，37848 条显著边，1000 条非线性关联 |
| `run_regression_model.R` | 通过 | variety CV 准确率 1.000；phase CV 准确率 0.962 |
| `run_plspm_analysis.R` | 通过 | 三套潜变量体系，路径系数全部落在 [-1, 1] |

---

## 二、重点缺陷（静默错误类）

这类缺陷不会让脚本报错，只会让结果悄悄变错，因此必须逐个用数值证据确认。

### 2.1 `network/plspm_net.R` —— 路径系数未标准化，突破 [-1, 1]

**现象**：首次跑通后，`class` 体系的路径系数出现 `beta = -5.46`。
PLS-PM 的路径系数定义为标准化回归系数，理论上必须落在 [-1, 1]，超界即为错误。

**根因**：潜变量得分直接取 `prcomp(...)$x[, 1]`，这是**未标准化**的 PC1 得分，
其标准差等于 `sqrt(特征值)`，会随潜变量成员数增大而增大。内模型用
`lm(score_j ~ score_i)` 的原始斜率作路径系数，该斜率被 `sd(to)/sd(from)`
这一与成员数相关的比例污染。

**数值证据**：

```
各潜变量得分 SD：Ketone(11 个成员) = 2.27 … Unknown(369 个成员) = 13.99   （6.2 倍差距）
原始 beta 范围        : [-5.46, 5.11]，210 条中 54 条越界
按 sd 比例标准化后    : [-0.988, 0.998]，0 条越界
对称性 |b(A→B)-b(B→A)|: 3.9e-15（机器精度）
```

最后一行是关键佐证：标准化后 `A→B` 与 `B→A` 完全相等，恰好等于 Pearson 相关系数，
与 PLS-PM 理论对简单二元路径的要求一致，说明修复后的量纲正确。

**修复**：在 `run_plspm` 中把潜变量得分标准化为单位方差后再进入内模型。

**验证**：三套体系 426 条路径全部落在 [-1, 1]，最大不对称度 ~1e-15。

---

### 2.2 `multiomics/association_network.R` —— MIC 候选选取使非线性检测恒不可能

**现象**：`n_nonlinear = 0`。而 Spearman + MIC 网络的核心卖点就是发现
Spearman 捕捉不到的非线性关联，恒为 0 说明该能力完全失效。

**根因**：候选对按 `|rho|` **降序**取 Top-K 送入 MIC 计算，
而 `association` 判定 `nonlinear` 的条件是 `|rho| < rho_linear_min`（默认 0.3）。
两个条件在结构上互斥 —— 被算了 MIC 的边全是强线性边，永远不可能被判为非线性。
MIC 的计算量完全白费。

**数值证据**：

```
总边数                        : 44850
实际算了 MIC 的边             : 2000
MIC 候选边的 |rho| 范围       : [0.951, 0.973]   <- 全是极强线性
MIC 候选边中 |rho| < 0.3 的数 : 0                <- nonlinear 结构上不可能出现
全部边中 |rho| < 0.3 的数     : 15025            <- MIC 真正该覆盖的population，被全部跳过
```

**修复**：新增 `mic_candidate` 参数（`"balanced"` 默认 / `"low_rho"` / `"top_rho"`）。
`balanced` 策略下高 rho 与低 rho 各占一半，既验证强线性关联，
又让非线性关联真正可被检出；`top_rho` 保留原行为以向后兼容。

**验证**：修复后 MIC 候选中 1000 条 `|rho| < 0.3`，检出 **1000 条非线性关联**；
`n_significant` 保持 37848 不变，说明改动是增量的，未扰动原有线性结论。

---

### 2.3 `utils/kegg_pathway.R` —— 命中缓存后整表丢失

**现象**：第一次运行 KEGG 映射 889 条、107 个潜变量；
**第二次运行（缓存已存在）变成 0 条、0 个潜变量**，KEGG-PLSPM 直接失效。

**根因**：缓存只记录**有通路的化合物**。74 个查询化合物中 57 个有通路、
17 个本就没有通路。重跑时这 17 个被 `setdiff` 判定为"新 ID"再次联网查询，
KEGG 正确返回空 → `all_links` 为空 → 函数走到"无结果"早退分支，
**把已缓存的 889 条全部丢弃**。即每次带缓存的重跑都会静默清空结果。

**修复**：
1. 早退分支中若已有缓存则原样返回缓存，不再丢弃；
2. 新增负结果 sidecar 文件 `kegg_no_pathway_ids.txt` 记录"确认无通路"的 ID，
   避免每次重跑都重复联网查询；
3. 返回值按调用方请求的 ID 集合过滤，不再把缓存中的无关记录带出。

**验证**：重跑恢复 889 条 / 107 个潜变量；负结果文件正确记录 17 个 ID；
耗时由 **254.91 s 降至 1.78 s（143 倍）**。

---

### 2.4 `differential/anova.R` —— 预分配 0 值被当作真实 p = 0 参与校正

**根因**：结果表用 `character(n)` / `numeric(n)` 预分配后按下标填充。
若某特征的某因素在 `aov` 表中缺失（秩亏、常量列、拟合失败），
该行不会被写入，残留 `""` 与 `0`。随后 `p.adjust` 把这些 **0 当作真实 p 值**
参与 BH 校正 —— 既虚增显著数，又拉低所有其它特征的校正阈值，污染全表。

**修复**：改为预填 `NA_real_`，跳过常量特征，`aov` 包 `tryCatch`；
`significant` 显式排除 NA。`p.adjust` 默认忽略 NA，不会把缺失当显著。

---

### 2.5 `differential/f_test.R` —— 0 行输入破坏返回结构 + 同类 0 值污染

**根因**：`data.frame(feature_id = rownames(expr_matrix), ...)` 在 0 行时
`rownames()` 返回 `NULL`，该列被直接丢弃，随后
`rownames(results) <- results$feature_id` 对不存在的列赋值，破坏返回契约。
同时存在与 2.4 相同的 0 值污染问题。

**修复**：补 0 行/0 样本/分组水平不足的早退（返回列结构完整的空表）；
预填 NA；常量特征跳过；`aov` 包 `tryCatch`；行名 `make.unique` 去重。

---

### 2.6 `multivariate/pca.R` —— NA 方差与非正 ncomp

**根因**：`feature_var > 0` 中全 NA 列的 `var` 为 `NA`，逻辑下标里的 NA 会产生 NA 列；
且 `ncomp` 可能算出 0 或负数，`1:ncomp` 反向迭代取到错误的列。

**修复**：显式剔除 NA 方差列；补样本数/特征数充分性校验；
`ncomp` 夹取到 `[1, 可用组分数]`；全部 `1:ncomp` 改为 `seq_len(ncomp)`。

---

### 2.7 `visualization/heatmap_plot.R` —— 全 NA 行被选入热图

**根因**：`order(row_vars, decreasing = TRUE)` 把 NA 排在最后，
若有效行数不足 `n_features`，全 NA 行会被选入，缩放后又被统一置 0，
在热图上呈现为一整条无意义却视觉显著的"全零特征"。

**修复**：选取前先剔除 `NA` 与零方差行。

---

## 三、其余修复一览

| # | 文件 / 函数 | 问题 | 修复 |
| --- | --- | --- | --- |
| 1 | `source_all_scripts.R` | `sub(fixed=normalizePath(...))` 用法错误，相对路径退化为绝对路径，排序规则失效 | 正确剥离根目录前缀；`source(f, encoding="UTF-8")` |
| 2 | `source_all_scripts.R` | `install_packages.R` 被 source 时触发联网安装 | 加入 `exclude_names` |
| 3 | `utils/load_data.R` | `print.OmicsData` 引用不存在的 `$metadata$matched`，恒打印 NULL | 改为 `matched_features` / `unmatched_features` 并做 NULL 保护 |
| 4 | `utils/export.R` | PDF 设备无法输出 Unicode（`γ-Hexalactone` 报 mbcsToSbcs）；设备未配对 | 改用 `cairo_pdf` 并新增 `.with_device()` 以 `on.exit` 保证 `dev.off()` |
| 5 | `utils/plot_helpers.R` | `save_plot` 中 `pdf()`→`print()`→`dev.off()` 裸序列，`print` 抛错则设备泄漏，后续绘图被静默写入残留 PDF；`ggsave` 不支持非 ggplot 对象 | 复用 `.with_device()`；统一 draw 逻辑，支持 base 绘图函数 |
| 6 | `network/wgcna_module.R` | `plot_wgcna_dendrogram` 用 `pdf(NULL)` 且未配对 `dev.off()`，实际不产出文件并泄漏设备 | 改为返回绘图闭包，交由 `export_heatmap` 落盘 |
| 7 | `network/wgcna_module.R` | `plot_soft_threshold` 纵轴符号取反错误（`-sign(SFT.R.sq)`） | 改为 `-sign(fi$slope) * SFT.R.sq`，并过滤零方差 |
| 8 | `network/wgcna_trait.R` | `traits` 用 `mode<-numeric` 强转产生 NA；样本未对齐；秩亏 `lm` 取 `coef[2,]` 越界 | 逐列数值化、样本对齐校验、零方差列剔除、秩亏保护 |
| 9 | `multiomics/association_network.R` | `.build_node_table` 中 `deg[s]` 按名索引含重复名的向量，只命中首个元素，degree 统计错误 | 改用 `tabulate` 在唯一节点上统计，且只计显著边 |
| 10 | `multiomics/association_network.R` | Fisher 合并 p 值对所有边统一按 df=4 处理，非 MIC 候选边被强制 padj=1 | 按边使用各自 df（有 MIC 为 4，否则为 2） |
| 11 | `multiomics/association_network.R` | 经验 p 可能为 0，导致 Fisher 合并后 p 值为 0 | 采用 `(b+1)/(R+1)` 伪计数 |
| 12 | `multiomics/plot_association_network.R` | 阈值筛选用 `pvalue` 而非校正后的 `padj`；`padj` 仅存于 attr 无法参与筛选 | `padj` 提升为正式列，绘图与建图统一使用 |
| 13 | `multiomics/plot_association_network.R` | `plot_association_summary` 依赖未声明的 `reshape2`；`shape=21` 下颜色映射错误 | 改用 base R 变形；修正 fill/color 映射 |
| 14 | `machine_learning/linear_model.R` | `cv_folds` 参数声明了却从未使用，交叉验证实际未执行 | 实现真正的 K 折交叉验证，返回 `cv_accuracy` 与 `cv_confusion_matrix` |
| 15 | `machine_learning/linear_model.R` | `p >= n` 时模型饱和，训练准确率恒为 1 无参考价值 | 增加特征数预筛与显式警告 |
| 16 | `differential/limma_de.R` | `safe_case` 顺序错位；`all_results` 在回退路径未定义；`pvalue_topN` 行名索引错位 | 修正取值顺序、补定义、改用位置索引 |
| 17 | `differential/limma_de.R` | `.t_test_de` 回退路径：`t.test` 未保护；`log2(mean/mean)` 在均值为负/0 时产生 NaN/Inf | 包 `tryCatch`；log 尺度数据改用均值之差；补空结果保护 |
| 18 | `enrichment/fisher_enrich.R` | 无类别通过 `min_size` 时对 0 行 data.frame 赋 `p_adj`、设 `rownames` 异常 | 补空结果保护 |
| 19 | `enrichment/fisher_enrich.R` | 显著性全 TRUE 或全 FALSE 时 `scale_fill_manual(labels=)` 数量不匹配报错 | 改用具名 values/labels，并补空输入占位图 |
| 20 | `visualization/volcano_plot.R` | `p_value` 为 0 时 `-log10` 得 `Inf`；`direction` 水平不全时配色标签不匹配 | Inf 截断至有限上限；固定 3 水平 factor + 具名标签 |
| 21 | `differential/anova.R` | `summary.aov` 行名带对齐尾部空格，`fac %in% rownames()` 永不匹配，结果恒空 | `trimws()` 行名；补空结果保护 |
| 22 | `network/plspm_net.R` | **KEGG 分支命名空间错配**：成员取自 `compound_id`（如 `C00025`）而 `rownames(info)` 为 feature ID，`intersect` 恒为空，KEGG 潜变量恒为 0 | 建立 `compound_id → feature_id` 反查后再取成员 |
| 23 | `network/plspm_net.R` | `plot_plspm_network` 硬编码列位置 `[5:6]` / `[7:8]`，列数变化即错位 | 改为按列名合并；补空输入保护 |
| 24 | `network/plspm_net.R` | 内模型对每个有序对重复拟合两次 `lm`（共 2k(k-1) 次） | 合并为单趟，同时产出系数矩阵与汇总表 |
| 25 | `multivariate/plsda.R` | `.plsda_base` 中 `1:ncomp` 在 `ncomp=0` 时反向迭代，且 `paste0("comp", 1:ncomp)` 产生错误列名 | 改用 `seq_len(ncomp)` |
| 26 | `theme_palette.R` | 顶层 `theme_set()` 未加命名空间限定；`extrafont` 缺失时触发自动安装 | 显式 `library(ggplot2)`；`extrafont` 改为可选；补 serif 回退 |

---

## 四、`1:n` 反向迭代的系统性排查

`for (i in 1:n)` 在 `n = 0` 时会反向迭代 `c(1, 0)`，导致下标越界或静默取错数据，
是本仓库中分布最广的一类模式。已修复本流程调用到的全部位置：

- `differential/f_test.R`、`differential/anova.R`、`differential/limma_de.R`
- `multivariate/pca.R`、`multivariate/plsda.R`
- `network/wgcna_trait.R`、`network/plspm_net.R`

**未修改**（不在本流程调用链上，避免无关重构，留待后续）：
`preprocessing/impute_missing.R`、`network/bnlearn_net.R`、`multivariate/oplsda.R`、
`machine_learning/lasso.R`、`microbiome/sparcc_network.R`、`microbiome/beta_diversity.R`
（其中 `beta_diversity.R` 的 `1:(n-1)` 在 `n <= 1` 时风险等级与已修复项相同）。

---

## 五、关键分析结论

- **PCA / PLS-DA**：样本按发酵阶段（phase）呈清晰梯度分布，品种（variety）次之。
- **差异分析**：limma 三种策略（`pvalue_logFC` / `pvalue_topN` / `pvalue_vip`）
  均正常工作，VIP 策略得到 372 个显著特征。
- **F 检验 / ANOVA**：phase 因素 1000/1000 特征显著，variety 因素 500/1000 显著，
  说明发酵阶段是主导变异来源。
- **WGCNA**：识别 3 个共表达模块（剔除 grey），模块-性状关联 13/24 对达 p < 0.05。
- **关联网络**：44850 对中 37848 条显著，含 1000 条非线性关联（修复后新增能力）。
- **回归预测**：variety 交叉验证准确率 1.000，phase 为 0.962。
- **PLSPM**：三套潜变量体系（WGCNA 模块 3 个 / KEGG 通路 107→Top15 / class 分类 47→Top15）
  路径系数全部落在 [-1, 1]。

> 说明：富集分析中各化学分类 `p_adj` 均未达 0.05。这与数据本身一致 ——
> 差异代谢物（429/1000）在各化学类别中近似均匀分布，不存在某一类别的特异性富集，
> 属于合理的阴性结果，非模块缺陷。

---

## 六、产出文件清单

```
test/multiple_omics/metabolism_demo/
├── config.R                     公共配置：路径、分组列、性能参数、模块加载辅助
├── check_data_structure.R       数据核对（确定 id_col / 分类列 / KEGG 可行性）
├── verify_source_all.R          加载器连通性验证（63/63 通过）
├── run_metabolome_demo.R        基础流程 SECTION 1-9
├── run_wgcna_network.R          WGCNA 共表达模块 + 模块-性状关联
├── run_association_network.R    Spearman + MIC 关联网络
├── run_regression_model.R       线性回归表型预测
├── run_plspm_analysis.R         三套潜变量 PLSPM 路径分析
├── cache/                       中间态缓存（rds + KEGG 映射与负结果缓存）
├── results/                     60 个 CSV 结果表
├── figures/                     23 张插图（PDF + PNG 各 23）
└── DEBUG_REPORT.md              本报告
```

**结果表分组**：`00_` 数据核对与加载状态；`01_` 预处理；`02_` PCA；`03_` PLS-DA；
`04_` limma；`05_` F 检验与 ANOVA；`07_` 富集；`10_`–`13_` WGCNA 与模块-性状；
`20_`–`21_` 关联网络；`30_` 回归；`40_` PLSPM 与 KEGG 映射。

---

## 七、运行方式

按依赖顺序执行（进阶脚本依赖基础流程产生的 `cache/*.rds`）：

```powershell
$R = "C:\Program Files\R\R-4.5.0\bin\Rscript.exe"
$D = "g:/OmicsWorks/test/multiple_omics/metabolism_demo"

& $R "$D/check_data_structure.R"
& $R "$D/verify_source_all.R"
& $R "$D/run_metabolome_demo.R"        # 必须先跑，生成 cache
& $R "$D/run_wgcna_network.R"
& $R "$D/run_association_network.R"
& $R "$D/run_regression_model.R"
& $R "$D/run_plspm_analysis.R"         # 依赖 WGCNA 缓存
```
