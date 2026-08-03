---
name: fix-cmeans-degeneration
overview: 修复 run_cmeans() 使用 cluster::fanny 导致所有特征 membership 退化为 1/k 的问题，改用 e1071::cmeans（与已验证成功案例一致），保持返回接口兼容。
todos:
  - id: fix-run-cmeans
    content: 修改 agent/rscript/network/cmeans.R 的 run_cmeans()：将 cluster::fanny 替换为 e1071::cmeans，更新包检查与 roxygen 文档，保持 cluster/membership/centers/model 返回接口不变，并添加非空聚类数提示
    status: completed
  - id: verify-with-r
    content: 用标准 R（C:\Program Files\R\R-4.5.0\bin\Rscript.exe）重新运行 test/omics_flow/demo_metabolomics.R，验证 Step 18 输出 cmeans_membership.csv 出现多 cluster 且 membership 有区分度
    status: completed
    dependencies:
      - fix-run-cmeans
---

## 需求概述

用户运行代谢组学分析流程 test/omics_flow/demo_metabolomics.R（Step 18: CMeans 模糊聚类）时，发现输出表 test/omics_flow/tables/cmeans_membership.csv 中 2059 个 feature 全部被硬分配到 cluster1，未分散到其他 cluster。用户要求审查 agent/rscript 中的脚本代码，定位根因并提出修复计划。

## 根因结论（已通过标准 R 4.5.0 实际复现验证）

- 问题代码：agent/rscript/network/cmeans.R 的 run_cmeans()，第 47 行使用 cluster::fanny(scaled_mat, k=6, memb.exp=2, maxit=100, stand=FALSE) 执行模糊聚类。
- 已验证现象：FANNY 算法在该数据集（2059 特征 × 18 样本，z-score 标准化后）收敛到"所有 membership 均等于 1/k"的退化不动点，fanny 自身发出警告 "the memberships are all very close to 1/k. Maybe decrease 'memb.exp' ?"，最终所有 feature 的硬分配（which.max）均为 cluster1。
- 对照验证：同一数据上 e1071::cmeans（经典 FCM）正常产生聚类结构（cluster 大小 561/513/505/480，membership 最大值 0.175-0.961）；且仓库内已验证成功的案例（test/metabolism/demo/.../run_cmeans.R）同样使用 e1071::cmeans。

## 修复范围

仅修改 agent/rscript/network/cmeans.R 中的 run_cmeans()：将聚类引擎由 cluster::fanny 替换为 e1071::cmeans，保持返回对象（cluster / membership / centers / model）与下游函数 plot_cmeans_profiles()、export_cmeans_membership() 的接口完全兼容，demo 脚本与其余函数无需改动。

## 技术栈

- R 语言，沿用项目现有脚本体系（agent/rscript，由 source_all_scripts.R 递归加载）
- 聚类引擎：e1071::cmeans（经典模糊 C 均值，项目成功案例同款），替代 cluster::fanny
- 依赖：e1071 包（已确认安装于标准 R 4.5.0）

## 实现方案

### 核心决策

1. 替换聚类引擎：run_cmeans() 中 cluster::fanny(scaled_mat, k=n_clusters, memb.exp=m, maxit=max_iter, stand=FALSE) → e1071::cmeans(scaled_mat, centers=n_clusters, m=m, iter.max=max_iter)。理由：FCM 有显式聚类中心迭代，不会陷入 fanny 的均匀 membership 退化不动点；与仓库已验证成功的实现一致，风险最低。
2. 保持返回接口兼容（下游 plot_cmeans_profiles / export_cmeans_membership / demo 均依赖）：

- $cluster：apply(cm$membership, 1, which.max)，命名向量（rownames 为 feature 名）
- $membership：cm$membership，列名覆盖为 Cluster1..K，行名为 feature 名
- $centers：cm$centers（聚类 × 样本），行名 Cluster1..K，列名为样本名
- $model：原始 cmeans 对象

3. 保留现有预处理逻辑：t(scale(t(as.matrix(expr_matrix)))) z-score 与 is.na→0 填充，保证输入与修复前一致（诊断已确认该输入下 cmeans 正常）。
4. 包检查与文档：requireNamespace("cluster") → requireNamespace("e1071")；同步更新 run_cmeans 的 roxygen 注释（依赖说明、返回值描述）。
5. 退化防御（增强）：返回结果前统计实际非空 cluster 数，若小于 n_clusters 时输出提示（FCM 空中心属正常现象，demo 第 428 行会打印实际聚类数）。

### 性能与可靠性

- cmeans 计算复杂度与 fanny 同阶（O(iter × n × k × d)），2059×18 规模毫秒级完成，无性能顾虑。
- set.seed(seed) 在调用前设置，保证结果可复现。
- 修改面仅一个函数，不触碰数据加载、预处理、绘图、导出链路，回归风险最小。

### 验证方式

- 使用标准 R 全路径（C:\Program Files\R\R-4.5.0\bin\Rscript.exe；注意系统 PATH 中的 Rscript 指向 SMRUCC R#，不可直接使用）重新运行 test/omics_flow/demo_metabolomics.R。
- 检查 cmeans_membership.csv：cluster 列应出现多个取值，membership 各列不再全为 1/6。
- 检查 cmeans_profiles 图与 Step 18 控制台输出（Clusters: ≥2）。