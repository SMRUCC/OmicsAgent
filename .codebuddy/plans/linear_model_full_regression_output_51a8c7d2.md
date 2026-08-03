---
name: linear_model_full_regression_output
overview: 修改 agent/rscript/machine_learning/linear_model.R，为 run_linear_model 增加逐特征一元线性回归（y=0/1 分组编码，x=分子丰度），导出的 linear_model_coefficients.csv 将包含斜率、截距、R2、调整R2、p值、y=ax+b 方程字符串及 avsb 组别比较标签（对照组a=0/处理组b=1）。
todos:
  - id: refactor-linear-model
    content: 重构 run_linear_model：新增逐特征一元线性回归（对照组a=0 vs 各处理组b=1），导出含 slope/intercept/r2/adj_r2/p_value/p_adj/equation/comparison 的完整结果表并替换 coefficients，保留分类模型与 accuracy，原系数迁移至 classification_coefficients，恢复原始特征名，更新 roxygen 文档
    status: completed
  - id: verify-output
    content: 运行 Rscript test/omics_flow/demo_metabolomics.R 重新生成 CSV，核对 linear_model_coefficients.csv 的列内容、比较标签与行数是否符合要求
    status: completed
    dependencies:
      - refactor-linear-model
---

## 用户需求

- 修改 `agent/rscript` 中"通过分子预测分组"的线性回归脚本（`machine_learning/linear_model.R` 的 `run_linear_model`）
- 当前 `test/omics_flow/tables/linear_model_coefficients.csv` 输出不令人满意：导出的是多项 logistic 系数，且列名混乱（feature_id 实际是组名、group 实际是特征名），缺少统计量
- 要求导出**所有结果**，每条结果必须包含：斜率、截距、R2、调整R2、p 值、`y = ax + b` 线性方程字符串、avsb 组别比较标签（默认对照组 a=0，处理组 b=1）

## 产品概述

- 代谢组学分析流程（demo_metabolomics.R Step 20）中的线性回归模型步骤：用分子表达量预测样本分组
- 期望输出逐特征一元线性回归（OLS）的完整统计结果表：`y = 数值化分组(0/1)` 对 `x = 单个分子特征` 逐特征拟合

## 核心功能

- 逐特征拟合 `y ~ x`（y 为 0/1 分组编码：对照组 a=0，处理组 b=1）
- 每条结果导出：feature_id、comparison 比较标签、slope（斜率）、intercept（截距）、r2、adj_r2、p_value、方程字符串（如 `y = 0.4275*x + 0.5388`）
- 比较标签格式：如 `Standard (control)(a=0) vs Clostridium difficile infection(b=1)`
- 保留原有分类模型（accuracy 等）输出，保持向后兼容

## 技术栈

- R 基础统计：`stats::lm`、`stats::glm`、`stats::coef`、`stats::summary.lm`、`stats::p.adjust`
- 遵循现有 `agent/rscript` 项目约定：函数式 R 脚本、`@export` roxygen 文档、英文列名、配合 `utils/export.R` 的 `export_table` 导出 CSV

## 实现方案

修改 `g:/OmicsWorks/agent/rscript/machine_learning/linear_model.R` 中的 `run_linear_model`：

1. **保留前置逻辑**：样本对齐、`exclude_groups` 过滤、`control_group` relevel、`top_features` 筛选、`make.names`（并在 make.names 前记录原始特征名映射，导出时恢复原始名称，避免 `.1/.2` 后缀）。
2. **新增逐特征一元线性回归**：

- 构建比较对：以 `control_group`（未指定时用因子首水平）为 a=0，其余每个组别依次为 b=1，即"对照组 vs 各处理组"；每组比较仅保留两组样本。
- 数值编码 y：a 组=0，b 组=1；对每个特征 x 拟合 `lm(y ~ x)`。
- 通过 `tryCatch` 提取：slope（coef[2]）、intercept（coef[1]）、r2（`summary$r.squared`）、adj_r2（`summary$adj.r.squared`）、p_value（斜率系数 p 值）；构造方程字符串 `sprintf("y = %.4g*x + %.4g", slope, intercept)`。
- 每个比较内对 p 值做 BH 校正得到 p_adj；附带样本量 n。

3. **重构输出表** `coefficients`：列依次为 `feature_id, comparison, slope, intercept, r2, adj_r2, p_value, p_adj, n, equation`；表使用默认 rownames（1..n），feature_id 作为真实列，避免 `export_table` 重复添加前缀列。
4. **向后兼容**：保留原分类模型（二元 glm binomial / 多元 nnet::multinom / MASS::lda）及其 `accuracy`、`predictions`、`confusion_matrix` 返回项；原分类系数迁移至新返回元素 `classification_coefficients`。
5. **更新 roxygen 文档**：说明新的返回结构与输出列含义。
6. **demo 无需修改**：`demo_metabolomics.R` 已直接调用 `export_table(lm_result$coefficients, ...)`，新表替换后自动生成符合要求的 CSV。

## 稳健性与性能

- 零方差/秩亏特征：`tryCatch` 捕获后返回 NA 行并告警，不中断流程
- 某组样本量 < 2：跳过该比较并告警
- 性能：逐特征 OLS 为 O(特征数 × 样本数) 单次拟合，demo 中仅 15 个特征、最多 2 组比较，开销可忽略

## 目录结构

```
g:/OmicsWorks/
├── agent/
│   └── rscript/
│       └── machine_learning/
│           └── linear_model.R   # [MODIFY] 重构 run_linear_model：新增逐特征 OLS 完整结果表，保留分类模型，更新 roxygen
└── test/
    └── omics_flow/
        ├── demo_metabolomics.R  # 不改动（自动导出新 coefficients 表）
        └── tables/
            └── linear_model_coefficients.csv  # [验证] 运行 demo 后重新生成并核对
```