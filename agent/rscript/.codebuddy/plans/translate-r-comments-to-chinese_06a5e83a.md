---
name: translate-r-comments-to-chinese
overview: "将 rscript/ 目录下全部 65 个 R 脚本中的注释与文档（含 # 注释、#' roxygen 文档、被注释掉的示例代码块中的说明文字）翻译为中文并原地替换；已是中文的段落跳过，实际 R 代码、变量名、路径、字符串字面量一律保持原样。"
todos:
  - id: translate-root
    content: 翻译根目录 R 脚本（compile_csv_to_xlsx/extract_sheets/source_all_scripts/theme_palette，跳过已中文的 install_packages）
    status: completed
  - id: translate-util-pre
    content: 翻译 preprocessing(4) 与 utils(5) 共 9 个 R 脚本注释
    status: completed
  - id: translate-stat
    content: 翻译 differential/enrichment/multivariate/machine_learning 共 11 个 R 脚本注释
    status: completed
  - id: translate-micro-net
    content: 翻译 microbiome(8) 与 network(5) 共 13 个 R 脚本注释
    status: completed
  - id: translate-multiomics
    content: 翻译 multiomics 目录下 16 个 R 脚本注释
    status: completed
  - id: translate-proteome-viz
    content: 翻译 proteome(5)/qcqa(1)/visualization(5) 共 11 个 R 脚本注释
    status: completed
  - id: verify-residual
    content: 扫描残留英文注释并抽查，补译遗漏，确认零代码改动
    status: completed
    dependencies:
      - translate-root
      - translate-util-pre
      - translate-stat
      - translate-micro-net
      - translate-multiomics
      - translate-proteome-viz
---

## 用户需求

扫描 `g:/OmicsWorks/agent/rscript/` 目录及其所有子目录中的全部 R 脚本代码文件（共 65 个 `.R` 文件），将其中所有注释文档翻译为简体中文。

## 产品概述

这是一项针对现有 R 脚本代码库的大规模注释翻译任务，目标是让整个 `rscript/` 代码库的注释统一为中文，提升中文团队的可读性与维护性。不涉及任何代码逻辑改动、功能新增或架构调整。

## 核心特征与处理规则

- **范围**：仅处理 `.R` 脚本文件（65 个），排除 `readme.md` 等非 R 脚本文件。
- **翻译策略**：仅中文替换原文，不保留英文原文。
- **已中文段落**：已是中文（中文占主导）的注释块/段落直接跳过，不重复翻译。
- **注释类型全覆盖**：
- 文件头分隔注释块（`# ===`、`# ----` 等）
- `#'` roxygen 文档（`@param`/`@return`/`@export`/`@examples` 等标签名保留英文，仅翻译其后说明文字）
- 行内尾注（`code  # 注释`，仅翻译 `#` 之后部分，代码保持原样）
- 被注释掉的示例代码块（仅翻译其中的人类可读说明文字；R 标识符、变量名、函数调用、文件路径、字符串字面量一律保持原样）
- **零代码改动**：严格保留所有 R 代码、字符串内容、空行、缩进与格式；禁止改写函数名、参数名、变量名、包名。
- **校验**：全部翻译完成后扫描残留英文注释，抽查关键文件。

## 技术栈与方法论

本任务为纯文本注释翻译，无新增技术栈或架构。核心在于“安全改写注释、零代码改动”的可靠方法论。

## 实现方法

逐文件执行：先用 `read_file` 读取完整文件，再按行识别并翻译注释，最后整文件写回。

### 注释行识别规则

- 仅处理以 `#`（可含前导空格）或 `#'`（roxygen）开头的行。
- 行内尾注：代码与 `#` 之间保留原样，仅取 `#` 之后文本翻译。
- 被注释掉的代码示例块：逐行判断——纯说明文字（如 `# Example usage (uncomment to run)`）翻译；`# var <- "path"`、`# func(...)` 等代码行保持原样（仅当该行后仍有尾注说明时仅翻译尾注）。

### roxygen 标签处理

保留 `@param`、`@return`、`@export`、`@examples`、`@import` 等标签关键字原文，仅翻译紧随其后的描述性文字。

### 已中文判定

若某注释块中中文占比明显占主导（如 `install_packages.R` 全中文），整体跳过，避免无意义重写。

## 实现注意事项

- **性能/规模**：65 个文件、合计数千行注释，属批量操作。按目录分批次推进，每批次完成后即写回，避免单文件过长导致上下文溢出。
- **防回归**：写回前必须已 `read_file` 该文件原内容；翻译只替换注释文本，严禁触碰任何 R 表达式、字符串字面量、路径与函数调用。
- **校验**：完成后使用 `search_content` 以正则 `^\s*#.*[A-Za-z]{4,}` 扫描疑似残留英文注释行，人工确认是否为不可翻译的代码标识符或合法的英文专有名词（如包名、API 名），其余需补译。

## 目录结构（受影响文件清单）

以下为全部 65 个 R 脚本（分组列出待翻译文件，`install_packages.R` 已全中文故跳过）：

```
rscript/
├── compile_csv_to_xlsx.R      # [MODIFY] 翻译全部英文注释（含末尾示例块说明）
├── extract_sheets.R           # [MODIFY] 翻译英文注释
├── source_all_scripts.R       # [MODIFY] 翻译英文注释
├── theme_palette.R            # [MODIFY] 翻译英文注释
├── (install_packages.R 已全中文，跳过)
├── differential/
│   ├── anova.R                # [MODIFY]
│   ├── f_test.R               # [MODIFY]
│   └── limma_de.R             # [MODIFY]
├── enrichment/
│   ├── fisher_enrich.R        # [MODIFY]
│   └── gsva.R                 # [MODIFY]
├── machine_learning/
│   ├── lasso.R                # [MODIFY]
│   ├── linear_model.R         # [MODIFY]
│   └── rf_shap.R              # [MODIFY]
├── microbiome/
│   ├── alpha_diversity.R      # [MODIFY]
│   ├── beta_diversity.R       # [MODIFY]
│   ├── biomarker_lefse.R      # [MODIFY]
│   ├── core_microbiome.R      # [MODIFY]
│   ├── diff_abundance_ancom.R # [MODIFY]
│   ├── microbiome_utils.R     # [MODIFY]
│   ├── sparcc_network.R       # [MODIFY]
│   └── taxa_composition.R     # [MODIFY]
├── network/
│   ├── bnlearn_net.R          # [MODIFY]
│   ├── cmeans.R               # [MODIFY]
│   ├── plspm_net.R            # [MODIFY]
│   ├── wgcna_module.R         # [MODIFY]
│   └── wgcna_trait.R          # [MODIFY]
├── multiomics/
│   ├── association_network.R          # [MODIFY]
│   ├── cross_correlation.R            # [MODIFY]
│   ├── cross_omics_network.R          # [MODIFY]
│   ├── cross_omics_regression.R       # [MODIFY]
│   ├── diablo_integration.R           # [MODIFY]
│   ├── dynamic_bayesian_network.R     # [MODIFY]
│   ├── mantel_procrustes.R            # [MODIFY]
│   ├── multiomics_data.R              # [MODIFY]
│   ├── multiomics_plspm.R             # [MODIFY]
│   ├── network_perturbation.R         # [MODIFY]
│   ├── pathway_bridge.R               # [MODIFY]
│   ├── plot_association_network.R     # [MODIFY]
│   ├── plot_dbn_plspm.R               # [MODIFY]
│   ├── plot_multiomics.R              # [MODIFY]
│   ├── temporal_trajectory.R          # [MODIFY]
│   └── wgcna_trait_association.R      # [MODIFY]
├── multivariate/
│   ├── oplsda.R               # [MODIFY]
│   ├── pca.R                  # [MODIFY]
│   └── plsda.R                # [MODIFY]
├── preprocessing/
│   ├── filter_missing.R       # [MODIFY]
│   ├── impute_missing.R       # [MODIFY]
│   ├── normalize.R            # [MODIFY]
│   └── scale.R                # [MODIFY]
├── proteome/
│   ├── functional_profile.R   # [MODIFY]
│   ├── go_enrichment.R        # [MODIFY]
│   ├── protein_clustering.R   # [MODIFY]
│   ├── protein_ppi.R          # [MODIFY]
│   └── protein_qc.R           # [MODIFY]
├── qcqa/
│   └── qcqa.R                 # [MODIFY]
├── utils/
│   ├── export.R               # [MODIFY]
│   ├── kegg_pathway.R         # [MODIFY]
│   ├── load_data.R            # [MODIFY]
│   ├── plot_helpers.R         # [MODIFY]
│   └── predefined_modules.R   # [MODIFY]
└── visualization/
    ├── heatmap_plot.R         # [MODIFY]
    ├── upset_plot.R           # [MODIFY]
    ├── venn_plot.R            # [MODIFY]
    ├── vip_manhattan.R        # [MODIFY]
    └── volcano_plot.R         # [MODIFY]
```