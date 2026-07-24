---
name: setup_env_install_packages
overview: 扫描 rscript 文件夹下全部 R 脚本，收集其依赖的程序包名称列表，并新建一个用于在新环境中初始化安装这些依赖的 R 脚本（含"已安装则跳过、未安装则安装"的检查逻辑，且区分 CRAN 与 Bioconductor 来源）。
todos:
  - id: create-script
    content: 新建 install_packages.R 并固化已收集的 CRAN(18) 与 Bioconductor(5) 包名列表
    status: completed
  - id: implement-logic
    content: 实现 check_and_install 逻辑：引导安装 BiocManager，按来源安装缺失包
    status: completed
    dependencies:
      - create-script
  - id: add-report
    content: 添加安装结果汇总与失败包诊断输出，并验证脚本可运行
    status: completed
    dependencies:
      - implement-logic
---

## 用户需求

扫描 `g:/OmicsWorks/agent/rscript` 文件夹下的所有 R 脚本文件，收集这些脚本所依赖的全部第三方 R 程序包名称，并新建一个用于在新环境中初始化安装运行环境的 R 脚本。该脚本需实现：逐一检查包名列表中对应的程序包是否已安装在本地，若未安装则自动安装。

## 产品概述

交付一个可重复执行的 R 环境初始化脚本，运行后能使任意新 R 环境具备运行该目录下全部分析脚本所需的所有依赖。脚本同时兼容 CRAN 与 Bioconductor 两类来源的程序包。

## 核心功能

- 汇总并固化已扫描收集到的程序包清单（区分 CRAN 与 Bioconductor 来源）。
- 对每个包执行"已安装则跳过、未安装则安装"的检查逻辑。
- 自动引导安装 Bioconductor 安装器 `BiocManager`（缺失时先安装）。
- 安装前配置 CRAN 镜像仓库，安装失败给出可读提示。
- 运行结束输出安装结果汇总，并列出未能成功安装的包以便排查。

## 技术栈

- 语言：R（基础 R，无额外系统依赖）
- 包管理：CRAN 的 `install.packages()`、Bioconductor 的 `BiocManager::install()`
- 交付物：`g:/OmicsWorks/agent/rscript/install_packages.R`（单文件，独立于现有分析脚本，不侵入既有逻辑）

## 实现方案

### 总体策略

新建一个独立的自包含脚本，将扫描阶段已收集到的程序包名以硬编码向量形式固化（分为 `cran_packages` 与 `bioconductor_packages` 两组），并编写一个统一的"检查-安装"函数。运行时先确保 `BiocManager` 就绪，再遍历两组包：用 `requireNamespace(pkg, quietly = TRUE)` 判断是否已安装，已安装则跳过并打印提示，未安装则依据来源调用 `install.packages()` 或 `BiocManager::install()`。

### 关键技术决策

- **硬编码包名列表而非运行时动态扫描**：扫描阶段已人工核对去重（合并 `library()`/`require()` 与 `pkg::` 两种用法，剔除 `stats`/`grDevices`/`grid`/`utils` 等基础包），硬编码方式最稳定、可读、可审计，避免正则解析误判与重复 I/O；后续如需增减依赖，直接修改向量即可，符合 KISS 原则。
- **来源分离**：脚本中 `mixOmics`、`ropls`、`impute`、`limma`、`GSVA` 为 Bioconductor 包（原脚本已出现 `BiocManager::install` 调用），必须用 `BiocManager::install()` 安装，否则在 CRAN 上找不到会失败。这是本方案的关键正确性问题。
- **BiocManager 引导安装**：Bioconductor 包的安装依赖 `BiocManager`，脚本先检查并安装它（从 CRAN），再安装 Bioconductor 包，保证链路完整。
- **失败可观测**：安装调用包在 `tryCatch` 中，单个包失败不影响整体，最后汇总失败清单，降低排查成本。

### 性能与可靠性

- 包安装为一次性、非热路径操作，无性能瓶颈；时间复杂度与包数量线性相关（约 23 个包）。
- 使用 `requireNamespace(..., quietly = TRUE)` 做存在性检查，避免重复加载包造成的副作用；相比 `library()` 更安全。
- 安装前统一设置 `repos = "https://cloud.r-project.org"`，避免交互式询问镜像导致脚本挂起。

## 实现注意事项

- 复用原脚本既有的 `BiocManager::install('xxx')` 约定，保持与现有项目一致。
- 安装逻辑放在 `tryCatch` 中，记录 `failed_packages`，不抛未捕获异常中断整脚本。
- 仅在需要时打印信息（用 `message()`），不输出敏感信息；安装进度由 R 自身控制，避免日志刷屏。
- 不影响任何现有 `.R` 分析脚本，纯新增文件，零侵入、零兼容风险。

## 架构设计

本任务为单一独立脚本，无复杂组件关系。数据流为：包名列表（硬编码）→ 存在性检查 → 按来源安装 → 结果汇总输出。

## 目录结构

```
g:/OmicsWorks/agent/rscript/
└── install_packages.R   # [NEW] 环境初始化脚本。固化已收集的 CRAN(18) 与 Bioconductor(5) 包名列表；实现检查-安装函数 check_and_install(pkg, source)；引导安装 BiocManager；遍历安装缺失包；末尾打印安装汇总与失败清单。
```

## 关键代码结构

```r

# 已收集的包名列表（扫描全部 .R 脚本后去重得到）

cran_packages <- c("openxlsx", "jsonlite", "WGCNA", "ggplot2", "reshape2",
"ggrepel", "ggVennDiagram", "VennDiagram", "RColorBrewer",
"UpSetR", "pheatmap", "bnlearn", "igraph", "plspm",
"randomForest", "dplyr", "glmnet", "e1071")

bioconductor_packages <- c("mixOmics", "ropls", "impute", "limma", "GSVA")

# 检查并安装单个包：已安装则跳过，未安装按来源调用对应安装器

check_and_install <- function(pkg, source = c("cran", "bioconductor"))