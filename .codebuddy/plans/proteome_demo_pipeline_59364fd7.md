---
name: proteome_demo_pipeline
overview: 在 test/multiple_omics/proteome_demo 中基于 agent/rscript 模块化函数编写烟草发酵蛋白质组学分析 demo 流程（QC→预处理→PCA→limma差异→富集→功能谱→聚类→热图/火山图导出），并根据 Rscript 实际运行输出修复 agent/rscript 中暴露出的代码缺陷。
todos:
  - id: setup-config
    content: 创建 proteome_demo 目录骨架与 config.R，定义路径常量、分组列、source_modules 与日志辅助函数
    status: completed
  - id: check-data
    content: 编写并运行 check_data_structure.R 与 verify_source_all.R，核实 ID 主键、注释覆盖度、分组分布与模块加载状态
    status: completed
    dependencies:
      - setup-config
  - id: fix-known-bugs
    content: 修复已确认缺陷：load_data.R 重复 ID 崩溃、functional_profile.R 的 run_limma_de 调用错误、go_enrichment.R 的 Fisher 列联表与空结果保护
    status: completed
    dependencies:
      - check-data
  - id: main-pipeline
    content: 编写 run_proteome_demo.R，实现加载对齐、质控、预处理、PCA、limma 差异、Fisher 富集、热图与缓存导出
    status: completed
    dependencies:
      - fix-known-bugs
  - id: advanced-scripts
    content: 编写 run_functional_profile.R 与 run_protein_clustering.R，完成功能谱分析与蛋白表达模式聚类及其插图导出
    status: completed
    dependencies:
      - main-pipeline
  - id: debug-iterate
    content: 用 Rscript 逐脚本运行全流程，按 R 报错与告警在 agent/rscript 源码内修复缺陷并重跑至无错无警告，必要时用 [subagent:code-explorer] 追溯调用链与同类缺陷
    status: completed
    dependencies:
      - main-pipeline
      - advanced-scripts
  - id: debug-report
    content: 撰写 DEBUG_REPORT.md，逐条记录缺陷现象、根因、数值证据、修复方式与验证结果，并汇总产出清单与运行方式
    status: completed
    dependencies:
      - debug-iterate
---

## 用户需求

基于本地 GNU R 4.5.0（`C:\Program Files\R\R-4.5.0\bin\Rscript.exe`），在 `test/multiple_omics/proteome_demo` 目录下编写一套 demo 蛋白质组学分析流程。流程必须通过 `source()` 加载 `agent/rscript` 中的模块化 R 脚本，再调用其中的具体函数完成分析，导出结果数据表格与结果插图。同时，以该 demo 作为集成测试用例驱动模块库运行，根据 GNU R 的实际输出定位并修复 `agent/rscript` 中被调用到的脚本缺陷。

## 输入数据

- 表达矩阵：`extdata/Tobacco-fermentation/expression/expression_proteome.csv`（1000 蛋白 × 312 样本，线性尺度，无缺失值）
- 蛋白注释：`extdata/Tobacco-fermentation/featureinfo_proteome.csv`（含 gene_id、name、kegg、pfam、ec_number、category、super_class、family 等注释列）
- 样本信息：`extdata/Tobacco-fermentation/sampleinfo.csv`（312 样本，含 variety、timepoint、phase、location 等分组列）

## 核心功能

### 分析流程内容

- **数据加载与对齐**：加载三张表并构建统一的组学数据对象，打印匹配情况与分组分布
- **蛋白质组质控**：蛋白鉴定数、缺失率、组内 CV 分布、样本相关性、PCA 异常值检测
- **预处理链路**：缺失值过滤、中位数归一化、log2 变换、Pareto 标度
- **PCA 主成分分析**：按发酵阶段、品种着色的得分图与载荷图
- **limma 差异表达分析**：以发酵阶段（Fresh vs 后续阶段）为主对比、品种为次级对比，输出全量与显著蛋白结果表及火山图
- **功能富集分析**：基于蛋白注释类别（super_class / category / family）的 Fisher 过表达富集与富集条形图
- **功能谱分析**：按功能类别聚合蛋白丰度，生成功能活性矩阵、功能谱热图与分组比较图
- **蛋白表达模式聚类**：按时间/阶段聚类蛋白表达轮廓，输出聚类成员表、轮廓图与聚类中心对比图
- **差异蛋白聚类热图**：Top 差异蛋白的分组热图

### 调试修复内容

- 已确认必须修复的缺陷：注释加载函数在重复 ID 下崩溃、功能类别差异分析调用不存在的函数、GO 富集列联表构造错误
- 运行过程中新暴露的错误一律在 `agent/rscript` 源码内修复，保持函数签名与返回结构稳定，不在 demo 中用 try/tryCatch 掩盖缺陷
- 输出调试报告，逐条记录缺陷现象、根因、修复方式与验证证据

## 产出形式

- `results/` 目录：编号有序的 CSV 结果表格
- `figures/` 目录：每张插图同时输出 PDF 与 PNG
- `cache/` 目录：中间矩阵缓存，供后续脚本复用
- `DEBUG_REPORT.md`：模块调试与修复报告

## 技术栈

- **语言/运行时**：GNU R 4.5.0（ucrt，Windows），通过 `Rscript.exe` 命令行执行
- **模块库**：`agent/rscript`（现有模块化函数库，本次仅调用 + 修复，不重造分析逻辑）
- **核心依赖**（均已实测安装）：limma、ggplot2、pheatmap、ComplexHeatmap、RColorBrewer、ggrepel、e1071、cluster、matrixStats
- **组织范式**：完全对齐既有 `test/multiple_omics/metabolism_demo/`（config.R 配置分离 + 主流程脚本 + DEBUG_REPORT.md）

## 实现方案

### 总体策略

以 demo 作为 `agent/rscript` 的集成测试驱动器：编写分节（SECTION）式主流程脚本，每节调用一组模块函数并打印可诊断的中间状态（矩阵维度、显著数、分组分布），运行后按 R 报错/告警定位缺陷，在模块源码内修复后重跑，直至全链路无错无警告完成。

### 关键技术决策

**1. 复用 metabolism_demo 的配置分离范式**

新建 `config.R` 集中定义绝对路径常量、分组列常量、阈值参数，并提供 `source_modules()`（按相对路径批量 source，文件不存在即 stop）、`section()`/`step()`/`mat_dim()` 日志辅助。这样路径单点定义、不依赖 `setwd`，与既有 demo 风格完全一致，降低维护成本。

**2. 特征 ID 主键选择（关键，基于实测）**

实测表明 `featureinfo_proteome.csv` 的 `name`/`id` 列有 343 个重复值且含 2 个 Excel 损坏值 `#NAME?`，而 `gene_id` 唯一。但表达矩阵首列用的是 `name` 语义的值（998/1000 命中 `name`，0/1000 命中 `gene_id`）。因此：

- `load_feature_info()` 必须以 `id_col = "name"` 调用（走正常分支，避免 fallback 把全部列名小写化的副作用）
- 重复 ID 的处理必须在模块内用 `make.unique()` 兜底（与 `load_expression_matrix()` 的既有行为对齐），而非在 demo 里预清洗数据

**3. 分组列选择（关键，基于实测）**

`sample_info` 列有 26 个水平（variety_timepoint 组合），粒度过细，直接用于两组 limma 对比无意义。故：

- 主分组用 `phase`（4 水平：Fresh / Early_fermentation / Active_fermentation / Late_maturation），对照组设为 `Fresh`
- 次级分组用 `variety`（2 水平，完全平衡）
- 所有涉及 `group_col` 的调用显式传参，不依赖默认值 `"sample_info"`
- 所有 `run_limma` / `run_f_test` 调用必须显式传 `exclude_groups = NULL`（本数据集无 QC 样本，默认值 `"QC"` 虽不误伤但显式关闭更清晰）

**4. 数值尺度处理**

实测数据为线性尺度（0.45~414，中位数 21.6，无 NA/无 0）。差异分析必须在 log2 空间进行以保证 logFC 语义正确；PCA 使用 Pareto 标度矩阵并设 `scale = FALSE`（避免二次标准化）。由于无缺失值，`filter_missing_values` 会全量保留，但仍纳入流程以覆盖该模块的代码路径。

**5. 富集分析的基因集来源**

实测 `kegg` 列仅 56% 覆盖且为 KO 号（K01610 形式），每个 KO 对应蛋白数少、检验易退化；而 `super_class`（45 水平）、`category`（113 水平）、`family`（45 水平）100% 覆盖。故富集以这三列为类别来源，调用 `run_fisher_enrich(feature_id_col = "name", category_col = ...)`。不引入 KEGG 联网映射（proteome 的 KO 号与 metabolism_demo 的化合物 ID 语义不同，复用 `map_kegg_compound_to_pathway` 不成立）。

**6. GO 富集不纳入流程**

实测 featureinfo 无任何 GO 注释列，`run_go_enrichment()` 在本数据集上不可调用。但其 Fisher 列联表构造存在确定性错误（第 4 格恒为 0），属于"读代码即可确认"的科学性缺陷，仍在修复范围内并在报告中记录，避免遗留隐患。

### 已确认缺陷与修复方向

| 文件 | 缺陷 | 修复方向 |
| --- | --- | --- |
| `utils/load_data.R:137` | `rownames(df) <- df[[id_col]]` 在重复 ID 下直接 `stop`，与同文件 `load_expression_matrix` 的 `make.unique` 行为不一致 | 重复时 warning + `make.unique()`，保持返回结构不变 |
| `proteome/functional_profile.R:275` | 调用不存在的 `run_limma_de()`，参数名 `p_adjust` 也不匹配 | 改调 `run_limma()`，参数映射为 `p_adj_method`，并适配其返回的 list 结构（取 `$results`） |
| `proteome/go_enrichment.R:131` | Fisher 列联表第 4 格写成 `n_bg_total - n_bg_total`（恒 0），p 值全部失真 | 修正为 `(n_bg_total - n_sig_total) - (n_bg_in_term - n_sig_in_term)` |
| `proteome/go_enrichment.R:166` | 各本体结果全空时 `do.call(rbind, ...)` 返回 NULL，后续 `rownames(combined) <- NULL` 报错 | 补空结果保护，返回列结构完整的空 data.frame |


### 性能与可读性要点

- 312 样本的样本相关性热图与样本级柱状图坐标轴标签极度拥挤：绘图时关闭 x 轴文本或对样本抽样展示，保证插图可读
- `run_protein_qc` 的组内 CV 采用 `sapply` 逐特征循环（1000 特征 × 26 组），实测规模可接受，不做重构
- 热图特征数控制在 Top 50~60，避免行标签不可读
- 中间矩阵（log2、Pareto、sample_info、feature_info、差异结果）缓存为 `cache/*.rds`，避免后续脚本重复计算

### 修复原则（对齐既有 DEBUG_REPORT 的调试纪律）

- 所有缺陷在 `agent/rscript` 源码内修复，不在 demo 中用 try/tryCatch 掩盖
- 保持函数签名与返回结构不变，只增强健壮性，确保 `metabolism_demo` 等既有调用方不被破坏
- 修复必须是通用正确的实现，禁止为跑通本 demo 做数据特判 hack
- 每处修复需有数值证据（修复前后对比）支撑，写入报告

## 目录结构

```
g:/OmicsWorks/
├── agent/rscript/                          # [MODIFY] 被测模块库，按运行输出修复
│   ├── utils/load_data.R                   # [MODIFY] load_feature_info 重复 ID 崩溃 → make.unique 兜底
│   ├── proteome/functional_profile.R       # [MODIFY] diff_functional_category 调用不存在的 run_limma_de → 改调 run_limma 并适配返回结构
│   ├── proteome/go_enrichment.R            # [MODIFY] Fisher 列联表第 4 格错误 + 空结果 rbind 保护
│   └── <其余被调用脚本>                     # [MODIFY] 运行中新暴露的缺陷按需修复（预处理/PCA/limma/富集/热图/聚类/QC）
└── test/multiple_omics/proteome_demo/      # [NEW] 本次产出目录
    ├── config.R                            # [NEW] 公共配置：PROJECT_ROOT/RSCRIPT_ROOT/DATA_DIR 等绝对路径常量、
    │                                       #       输入文件路径、分组列常量（GROUP_PHASE/GROUP_VARIETY/GROUP_LOCATION）、
    │                                       #       阈值与随机种子；提供 source_modules() 批量加载与
    │                                       #       section()/step()/mat_dim() 日志辅助；自动创建 results/figures/cache 目录
    ├── check_data_structure.R              # [NEW] 数据核对脚本：确认 feature id 主键列、ID 匹配率、注释列覆盖度、
    │                                       #       分组水平分布、数值尺度（是否已 log），把结论落成 00_ 前缀 CSV，
    │                                       #       为主流程的参数选择提供实测依据
    ├── verify_source_all.R                 # [NEW] 加载器连通性验证：source agent/rscript/source_all_scripts.R，
    │                                       #       打印成功/失败脚本数并对失败项报错，作为模块库健康检查
    ├── run_proteome_demo.R                 # [NEW] 主流程脚本，分 SECTION 组织：
    │                                       #       1 数据加载对齐(load_*/create_omics_data)
    │                                       #       2 蛋白质组质控(run_protein_qc/plot_protein_qc)
    │                                       #       3 预处理(filter_missing_values/normalize_median/log2/scale_pareto)
    │                                       #       4 PCA(run_pca/plot_pca_scores/plot_pca_loadings)
    │                                       #       5 limma 差异(run_limma + plot_volcano，phase 与 variety 两套对比)
    │                                       #       6 Fisher 富集(run_fisher_enrich/plot_enrichment，三种类别列)
    │                                       #       7 差异蛋白热图(plot_heatmap)
    │                                       #       8 缓存中间态到 cache/*.rds
    ├── run_functional_profile.R            # [NEW] 功能谱进阶脚本：读取 cache，调用
    │                                       #       calc_protein_functional_profile / plot_functional_heatmap /
    │                                       #       plot_functional_comparison / diff_functional_category，
    │                                       #       导出功能活性矩阵、类别信息表、功能差异表与对应插图
    ├── run_protein_clustering.R            # [NEW] 表达模式聚类脚本：读取 cache，调用
    │                                       #       cluster_protein_profiles / plot_profile_clusters /
    │                                       #       plot_cluster_centers，导出聚类成员表与轮廓/中心图
    ├── results/                            # [NEW] CSV 结果表输出目录（按 00_/01_/02_... 前缀编号分组）
    ├── figures/                            # [NEW] 插图输出目录（每图 PDF + PNG 各一份）
    ├── cache/                              # [NEW] 中间态 rds 缓存目录
    └── DEBUG_REPORT.md                     # [NEW] 调试与修复报告：环境信息、被测模块统计、缺陷逐条记录
                                            #       （现象/根因/数值证据/修复/验证）、关键分析结论、产出清单、运行方式
```

## 运行方式

按依赖顺序执行（进阶脚本依赖主流程生成的 `cache/*.rds`）：

```
$R = "C:\Program Files\R\R-4.5.0\bin\Rscript.exe"
$D = "g:/OmicsWorks/test/multiple_omics/proteome_demo"

& $R "$D/check_data_structure.R"
& $R "$D/verify_source_all.R"
& $R "$D/run_proteome_demo.R"          # 必须先跑，生成 cache
& $R "$D/run_functional_profile.R"
& $R "$D/run_protein_clustering.R"
```

## Agent Extensions

### SubAgent

- **code-explorer**
- Purpose: 在调试阶段，当某个模块函数报错需要跨文件追溯调用链（如 `functional_profile.R` → `limma_de.R` → `plot_helpers.R` 的依赖关系），或需要排查同类缺陷模式（如 `1:n` 反向迭代、重复 ID 处理不一致）在模块库中的其他分布位置时，用于批量检索定位
- Expected outcome: 输出准确的文件路径与行号清单，确保缺陷修复覆盖完整、不遗漏同类问题，同时避免对未被调用的无关脚本做不必要的改动