---
name: metabolomics-demo-pipeline
overview: 在 test/multiple_omics/metabolism_demo 中基于 Tobacco-fermentation 代谢组测试数据，用 agent/rscript 的模块化函数编写完整代谢组学分析 demo 流程，并根据 Rscript 实际运行输出对 agent/rscript 中被调用到的脚本进行调试与错误修复。
todos:
  - id: verify-data-and-loader
    content: 编写并运行数据核对与模块加载验证脚本，确定特征ID关联方式、富集类别列与分组列
    status: pending
  - id: build-load-preprocess
    content: 编写主脚本数据加载与预处理段（过滤/填补/归一化/标度），运行并修复相关模块缺陷
    status: pending
    dependencies:
      - verify-data-and-loader
  - id: build-multivariate
    content: 实现PCA与PLS-DA分析段并导出得分图、载荷图、VIP图，修复 pca.R 与 plsda.R 缺陷
    status: pending
    dependencies:
      - build-load-preprocess
  - id: build-differential
    content: 实现limma两组差异与ANOVA多组差异分析段，导出结果表与火山图，修复 limma_de.R、anova.R、volcano_plot.R
    status: pending
    dependencies:
      - build-load-preprocess
  - id: build-heatmap-enrichment
    content: 实现聚类热图与化学分类富集分析段，修复 heatmap_plot.R 与 fisher_enrich.R 缺陷
    status: pending
    dependencies:
      - build-differential
  - id: full-run-and-report
    content: 端到端完整重跑流程验证全部产物，撰写 DEBUG_REPORT.md 汇总修复项与结果清单
    status: pending
    dependencies:
      - build-multivariate
      - build-heatmap-enrichment
---

## 用户需求

基于烟叶发酵代谢组测试数据，在 `test/multiple_omics/metabolism_demo` 目录下编写一个完整的 demo 代谢组学分析流程，通过 `source()` 加载 `agent/rscript` 中的模块化 R 脚本并调用其中函数完成分析，导出结果表格与插图；同时以此为手段实测 `agent/rscript` 中的脚本代码，根据 GNU R 的真实运行输出定位并修复模块源码中的错误。

## 产品概述

一套可一键运行的代谢组学分析 demo 流程，输入为烟叶发酵项目的三份测试数据：

- 代谢组表达矩阵（1000 个代谢物 × 312 个样本）
- 代谢物注释表（含化学分类、KEGG、分子式等）
- 样本信息表（含品种、发酵时间点、发酵阶段、产地、海拔等分组信息）

流程按标准代谢组学分析范式串联多个功能模块，每一步都调用 `agent/rscript` 中已有的模块化函数，运行结束后在独立的结果目录中产出全部数据表格与图片。流程本身即为模块库的集成测试用例，运行过程中暴露的模块缺陷需回到模块源码中修复。

## 核心功能

### 分析流程内容

- **数据加载与对齐**：读取表达矩阵、样本信息、代谢物注释三张表，完成样本与特征的对齐校验，输出数据概况摘要
- **数据预处理**：缺失值过滤、缺失值填补、样本间归一化、特征标度变换，并记录每一步前后的矩阵规模变化
- **无监督分析**：主成分分析，按发酵阶段/品种着色展示样本分布与聚集趋势
- **有监督判别分析**：偏最小二乘判别分析，输出样本得分分布与变量重要性排序
- **差异代谢物分析**：两组对比的差异分析，以及按发酵阶段的多组差异检验
- **聚类热图**：选取差异显著的代谢物绘制带样本分组注释与化合物类别注释的聚类热图
- **富集分析**：以代谢物化学分类为类别体系，对差异代谢物做过表达富集检验
- **结果导出**：所有分析结果表格导出为 CSV，所有插图导出为图片文件

### 视觉效果

- 图表为发表级质量：主成分得分图与判别分析得分图带分组配色和置信椭圆；变量重要性图与富集结果图为横向条形图；差异分析结果为火山图并标注 Top 差异代谢物；热图带行列双向注释色块与层次聚类树
- 分组配色统一，图例清晰，中文注释与英文图形标签并存

### 模块调试与修复

- 使用本机 R 解释器实际执行流程，逐段验证
- 依据 R 的真实报错与警告定位到模块源码的具体文件与位置
- 在 `agent/rscript` 源码中修复缺陷（而非在 demo 中绕过），修复后重跑直至流程完整无错通过
- 最终汇总说明修复了哪些模块的哪些问题，以及产出了哪些结果文件

## 技术栈

- **运行环境**：GNU R 4.5.0（`C:\Program Files\R\R-4.5.0\bin\Rscript.exe`），Windows / PowerShell
- **模块库**：项目自有 `agent/rscript` 模块化脚本集（约 66 个 `.R` 文件）
- **依赖包**（已实测全部安装）：ggplot2、ggrepel、RColorBrewer、limma、mixOmics、ComplexHeatmap、pheatmap、ropls、dplyr、tidyr、circlize
- **调用方式**：demo 脚本通过 `source()` 逐个加载所需模块脚本，再调用其导出函数；不在 demo 中重写任何分析逻辑

## 实现方案

### 总体策略

采用**分步骤单文件主脚本 + 显式模块加载**的方式：demo 主脚本按分析流程顺序划分为若干 section，每个 section 前先 `source()` 该步骤依赖的模块脚本，再调用函数并立即落盘结果。这样做的原因：

1. **精准定位缺陷**：显式 `source()` 具体文件（而非一次性 `source_all_scripts.R`）能让报错直接对应到模块文件，便于定位修复；同时避免加载 microbiome/proteome/multiomics 等与本流程无关的脚本引入干扰
2. **失败可续跑**：每个 section 独立产出结果，前面 section 成功的产物不会因后面报错而丢失
3. **契合测试目的**：流程即测试用例，覆盖 utils / preprocessing / multivariate / differential / visualization / enrichment 六个目录的核心函数

为兼顾"验证 `source_all_scripts.R` 本身是否可用"这一测试目标，额外提供一个薄封装：主脚本优先按显式清单加载，同时单独跑一次 `source_all_scripts.R` 做加载连通性验证并记录其加载汇总。

### 关键技术决策

**决策 1：分组列的选择**

样本信息中 `sample_info` 列有 26 个唯一值（粒度过细，等同于 `condition`），直接用作分组会导致：配色板耗尽（`make_group_colors` 在 n>9 时退化为 `rainbow`）、图例拥挤、limma 对比矩阵爆炸（25 个对比）、热图列注释不可读。

因此在 demo 中显式传入更合适的分组列：

- PCA 着色：`phase`（4 组）为主，`variety`（2 组）作 shape 维度
- PLS-DA：`variety`（2 组，判别任务清晰）与 `phase`（4 组）各跑一次
- limma 两组差异：`variety`（Virginia vs Burley），control_group 显式指定
- 多组差异：`run_anova` 以 `phase` 为因子，或 `run_f_test` 按 `phase`
- 热图列注释：`phase`

这不修改模块默认值，只是在调用时传参，保持模块通用性。

**决策 2：`exclude_groups` 默认值的处理**

`run_limma` 默认 `exclude_groups = "QC"`、`run_f_test` 默认 `exclude_groups = "QC"`，但本数据集**无 QC 样本**。需实测确认：当 `exclude_groups` 指定的组不存在时，`rownames(sample_info)[!(sample_info[[group_col]] %in% exclude_groups)]` 会返回全部样本，逻辑上应安全。若实测发现异常（如 group_col 为 factor 导致比较异常），需在模块中加健壮性保护。

**决策 3：富集分析的类别列选择**

`run_fisher_enrich` 默认 `category_col = "kegg"`，而注释表 `kegg` 列在前若干行为空字符串。实现时先统计 `kegg` 非空比例：

- 若非空比例过低（不足以产生有效富集），改用 `super_class` / `class` / `family` 作为 `category_col`
- 同时保留一次 `kegg` 列的调用，以测试模块在"类别大量为空"边界下的行为，暴露潜在缺陷

**决策 4：预处理链路的设计**

数据为 peak area 量纲，取值分布跨度大（实测有 0.15 ~ 15 的范围）。预处理链路设计为：
`filter_missing_values`（去除高缺失特征）→ `impute_min_half`（代谢组学常用最小值一半填补）→ `normalize_median`（样本间中位数归一化）→ log2 变换 → `scale_pareto`（代谢组学标准 Pareto 标度）

其中 log2 变换模块库中未提供独立函数，且 limma 要求近似正态的输入。为避免在 demo 中写分析逻辑，将 log2 变换作为一个**极薄的内联步骤**（单行 `log2(x + 1)`）并明确注释其为数据变换而非分析逻辑；差异分析在 log 空间进行以保证 logFC 语义正确。PCA/PLS-DA 使用 Pareto 标度后的矩阵。

**决策 5：调试修复的边界控制**

修复原则：

- **只修被本流程调用到的模块**，不做无关重构
- 修复以**最小改动 + 向后兼容**为准：不改变函数签名与返回结构，只补齐健壮性（空结果保护、长度校验、列名兼容、factor/character 处理）
- 若某处需改变行为，优先加防御分支而非替换原逻辑
- 每次修复后立即重跑对应 section 验证

### 已预判的高风险缺陷点（需重点验证）

| 位置 | 风险描述 |
| --- | --- |
| `multivariate/plsda.R` `run_plsda` | `vip_df` 用 `rownames(expr_matrix)` 与 `vip_scores` 拼装，若 mixOmics 因零方差特征丢弃变量，两者长度不一致会报错 |
| `multivariate/plsda.R` `plot_plsda_scores` | scores 列名依赖 `comp1`/`Comp1` 前缀猜测，mixOmics 实际列名可能为 `comp 1`（含空格）导致取列为 NULL |
| `enrichment/fisher_enrich.R` `run_fisher_enrich` | 无任何类别通过 `min_size` 时 `results` 为 0 行，`results$p_adj <- p.adjust(...)` 与 `rownames(results) <- make.unique(...)` 可能异常 |
| `enrichment/fisher_enrich.R` `plot_enrichment` | `scale_fill_manual(labels = c("Not Sig", ...))` 在 `p_adj < p_threshold` 全 TRUE 或全 FALSE 时 labels 数与 factor 水平数不匹配，ggplot 报错 |
| `utils/plot_helpers.R` `save_plot` | 内部用 `ggplot2::ggsave` 输出 PNG，对 pheatmap/ComplexHeatmap 对象不兼容；热图应改用 `utils/export.R` 的 `export_heatmap` |
| `visualization/heatmap_plot.R` `plot_heatmap` | 依赖 `feature_info` 的 rownames 与 `expr_matrix` rownames 匹配；若表达矩阵行名是化合物名而注释表 rownames 是 METAB 编号，`match()` 全 NA 导致注释失效 |
| `utils/load_data.R` `create_omics_data` | `print.OmicsData` 引用 `x$metadata$matched`，但构造时写入的是 `matched_features`，打印会出现 NULL |
| `differential/limma_de.R` `run_limma` | `pvalue_topN` 分支用 `rownames(comp_data)` 索引赋值，而前面已 `rownames(combined) <- NULL`，索引会错位 |
| `preprocessing/filter_missing.R` | `group_missing` 用 `dimnames` 直接以组名作列名，组名含特殊字符时 data.frame 构造会 mangle 列名 |


### 特征 ID 关联策略

表达矩阵首列列名为 `name`，注释表主键为 `ID`（METAB_xxxxx）且另有 `name` 列。实现第一步必须核对表达矩阵行名的实际取值：

- 若行名为化合物名 → `load_feature_info(file, id_col = "name")`，使注释表 rownames 与表达矩阵行名一致
- 若行名为 METAB 编号 → `load_feature_info(file, id_col = "ID")`

该判定结果同时决定 `run_fisher_enrich` 的 `feature_id_col` 取值与 `plot_heatmap` 的注释匹配是否生效。

## 目录结构

```
g:/OmicsWorks/
├── agent/rscript/                          # [MODIFY] 依据实测报错修复被调用到的模块
│   ├── utils/
│   │   ├── load_data.R                     # [MODIFY?] print.OmicsData 的 metadata 字段名不一致；
│   │   │                                   #   load_feature_info 大小写回退分支会把 id_col 一并转小写，
│   │   │                                   #   需确认不破坏 rownames 设置
│   │   ├── export.R                        # [MODIFY?] export_table 在 0 行 data.frame 时 cbind 行为；
│   │   │                                   #   export_heatmap 对 pheatmap/ComplexHeatmap 分支实测
│   │   └── plot_helpers.R                  # [MODIFY?] save_plot 用 ggsave 保存非 ggplot 对象会失败，
│   │                                       #   需加类型判断或改由 export_heatmap 承担
│   ├── preprocessing/
│   │   ├── filter_missing.R                # [MODIFY?] group_missing 组名做列名的 mangle 问题；
│   │   │                                   #   全部特征被移除时的空矩阵保护
│   │   ├── impute_missing.R                # [MODIFY?] impute_min_half 逐行 for 循环在 1000×312 上的性能；
│   │   │                                   #   全 NA 行填 0 的边界
│   │   ├── normalize.R                     # [MODIFY?] 归一化后 NA 传播
│   │   └── scale.R                         # [MODIFY?] scale_pareto 对零方差行的处理
│   ├── multivariate/
│   │   ├── pca.R                           # [MODIFY?] ncomp 上限与样本数关系；
│   │   │                                   #   plot_pca_scores 中 shape 水平超过 25 时的处理；
│   │   │                                   #   sample_info 按 scores$sample_id 重排的正确性
│   │   └── plsda.R                         # [MODIFY?] 高风险：vip_scores 与 rownames 长度不一致；
│   │                                       #   scores 列名 comp/Comp 兼容；exclude_groups 后 vip 对齐
│   ├── differential/
│   │   ├── limma_de.R                      # [MODIFY?] pvalue_topN 分支 rownames 索引错位；
│   │   │                                   #   exclude_groups="QC" 在无 QC 数据集上的行为；
│   │   │                                   #   all_results 在 limma 缺失回退路径下未定义
│   │   ├── anova.R                         # [MODIFY?] 多因子建模与 exclude_groups 命名列表处理
│   │   └── f_test.R                        # [MODIFY?] 单组或组内样本不足时 aov 报错保护
│   ├── visualization/
│   │   ├── volcano_plot.R                  # [MODIFY?] p_value 为 0 时 -log10 产生 Inf；
│   │   │                                   #   direction 全为单一水平时 scale_color_manual labels 不匹配
│   │   └── heatmap_plot.R                  # [MODIFY?] feature_info rownames 匹配失效；
│   │                                       #   col_order 与 ComplexHeatmap column_order 的一致性
│   └── enrichment/
│       └── fisher_enrich.R                 # [MODIFY?] 高风险：空结果时 p_adj 赋值与 rownames 设置；
│                                           #   plot_enrichment 的 fill labels 数量不匹配
│
└── test/multiple_omics/metabolism_demo/    # [NEW] demo 流程与产物目录
    ├── run_metabolome_demo.R               # [NEW] 主流程脚本。职责：按 section 顺序 source 所需模块并调用函数完成
    │                                       #   完整代谢组学分析。要求：脚本顶部集中定义 RSCRIPT_ROOT / DATA_DIR /
    │                                       #   OUT_DIR 等路径常量（用绝对路径或基于脚本位置推导，避免依赖工作目录）；
    │                                       #   每个 section 用醒目注释分隔并 cat 进度日志；每步产出立即落盘；
    │                                       #   关键中间量（矩阵维度、分组计数、显著特征数）打印到控制台便于比对；
    │                                       #   全程不实现分析逻辑，只做数据流转与函数调用
    ├── check_data_structure.R              # [NEW] 前置数据核对脚本。职责：核实表达矩阵首列取值形态（化合物名 vs
    │                                       #   METAB 编号）、表达矩阵行名与注释表 ID/name 列的匹配率、kegg 列非空
    │                                       #   比例、各候选分组列的取值分布、缺失值与零值比例。输出一份核对摘要，
    │                                       #   用于确定主脚本中 id_col / category_col / 分组列的正确取值
    ├── verify_source_all.R                 # [NEW] 模块加载连通性验证脚本。职责：单独执行
    │                                       #   agent/rscript/source_all_scripts.R，捕获其加载汇总（成功/失败清单），
    │                                       #   记录哪些模块脚本无法被 source。用于测试加载器本身及暴露语法级错误
    ├── results/                            # [NEW] 结果表格输出目录（CSV），由脚本自动创建
    │                                       #   预期产物：数据概况摘要、缺失值报告、预处理后矩阵、PCA 得分与载荷、
    │                                       #   PLS-DA 得分与 VIP、limma 差异结果与显著子集、ANOVA/F 检验结果、
    │                                       #   富集分析结果
    ├── figures/                            # [NEW] 结果插图输出目录（PDF + PNG），由脚本自动创建
    │                                       #   预期产物：PCA 得分图、PCA 载荷图、PLS-DA 得分图、VIP 条形图、
    │                                       #   火山图、聚类热图、富集条形图
    └── DEBUG_REPORT.md                     # [NEW] 调试修复报告。职责：逐条记录实测发现的模块缺陷——所在文件与函数、
                                            #   R 的原始报错信息、根因分析、修复方案与改动点、修复后验证结果；
                                            #   末尾附产出文件清单与流程运行结论
```

## 执行要点

- **运行命令**：PowerShell 中必须用 `& "C:\Program Files\R\R-4.5.0\bin\Rscript.exe" "<脚本绝对路径>"` 形式（路径含空格）
- **编码处理**：R 控制台为中文本地化，报错信息为中文；读取 stderr 时注意编码，必要时在脚本中 `Sys.setlocale` 或以 UTF-8 写出日志文件再读取
- **路径处理**：demo 脚本中所有路径用正斜杠或 `file.path()` 构造，避免反斜杠转义问题；`source()` 模块时使用绝对路径，不依赖 `setwd`
- **增量验证**：先跑 `check_data_structure.R` 确定关键参数，再跑 `verify_source_all.R` 排查语法级问题，最后分段跑主脚本；每修复一处立即重跑验证
- **性能注意**：1000×312 矩阵规模不大，但 `impute_min_half` 的逐行 for 循环、`run_fisher_enrich` 的逐类别 `rbind` 增长、`plot_heatmap` 的全矩阵距离计算需留意；若实测明显偏慢再考虑向量化，不做过早优化
- **绘图设备**：`export_plot`/`export_heatmap` 使用 `png(type = "cairo")`，Windows 下需确认 cairo 可用；若不可用需在模块中加设备回退
- **热图导出**：`plot_heatmap` 返回 ComplexHeatmap/pheatmap 对象，必须用 `export_heatmap()` 而非 `save_plot()`
- **修复纪律**：所有修复落在 `agent/rscript` 源码，保持函数签名与返回结构不变，只增强健壮性；不在 demo 脚本中用 try/tryCatch 掩盖模块缺陷

## Agent Extensions

### SubAgent

- **code-explorer**
- Purpose: 在调试阶段遇到跨模块的错误链路（如某函数报错根因位于其依赖的 utils 辅助函数）时，快速定位相关函数定义、调用点与依赖关系
- Expected outcome: 准确给出缺陷所在的文件路径、函数名与相关代码位置，避免遗漏同类问题的其他调用点