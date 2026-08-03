---
name: rscript_packages_install_loader
overview: 扫描 rscript 文件夹全部 R 脚本，提取所有被直接引用的 CRAN/Bioconductor 第三方包，并编写一个统一安装与加载脚本（install_packages.R）放在 rscript 目录下。
todos:
  - id: create-install-script
    content: 在 rscript 下创建 install_packages.R，定义 cran/bioc 包清单并按来源安装缺失包
    status: completed
  - id: add-loader-summary
    content: 为脚本补充逐包 library 加载、tryCatch 容错与安装加载汇总输出
    status: completed
    dependencies:
      - create-install-script
---

## 用户需求

扫描 `rscript` 文件夹中的所有 30 个 R 脚本，提取其中直接引用的 CRAN 与 Bioconductor 第三方程序包名称，并在 `rscript` 文件夹中编写一个 R 脚本，对提取到的所有程序包执行统一的安装与加载操作。

## 产品概述

生成一个独立的 R 安装/加载引导脚本 `install_packages.R`，放在 `rscript` 目录下。该脚本自动识别并安装项目依赖的全部第三方 R 包（区分 CRAN 与 Bioconductor 来源），随后统一加载，便于一次性搭建 OmicsFlow 分析运行环境。

## 核心特性

- 自动提取并固化 21 个被脚本直接引用的第三方包，排除 R 自带基础包（stats/grDevices/utils/grid/graphics）。
- 区分来源：CRAN 包使用 `install.packages()`，Bioconductor 包（limma、GSVA、impute、ComplexHeatmap）使用 `BiocManager::install()`。
- 仅安装缺失包，避免重复安装，提升执行效率。
- 加载阶段使用 `library(pkg, character.only=TRUE)` 并做容错，打印每个包安装/加载的成功或失败状态汇总。

## 技术栈

- 语言：R（与各 rscript 脚本一致）
- 包管理：CRAN（`install.packages`）+ Bioconductor（`BiocManager`）
- 运行环境：基础 R 解释器，无额外框架依赖

## 实现方案

采用单一引导脚本方案：在 `rscript/install_packages.R` 中定义 `cran_packages` 与 `bioc_packages` 两个字符向量（来自已扫描提取的清单），通过 `installed.packages()` 比对仅安装缺失项，CRAN 走 `cloud.r-project.org` 镜像，Bioconductor 走 `BiocManager::install()`，最后循环 `library(character.only=TRUE)` 加载全部包并输出汇总。

关键技术决策：

- **分离 CRAN/Bioconductor 来源**：4 个 Bioconductor 包无法通过 `install.packages` 安装，必须由 `BiocManager` 处理；脚本先确保 `BiocManager` 自身已安装。
- **仅安装缺失包**：用 `setdiff(包列表, rownames(installed.packages()))` 过滤，避免重复下载、节省时间与网络开销。
- **容错加载**：用 `tryCatch` 包裹 `library`，单个包加载失败不影响其余，并打印明确提示（如 pheatmap 与 ComplexHeatmap 均提供绘图函数，仅提示潜在命名冲突，不阻断）。
- **复用现有模式**：保持与项目一致的 `requireNamespace` 惰性风格与中文注释约定，不改动任何现有 30 个脚本。

## 实现说明

- 性能：包安装为一次性网络 IO，缺失过滤将耗时从 O(全部包) 降至仅缺失项；加载阶段 21 个包开销可忽略。
- 日志：使用 `message()`/`cat()` 打印分组（CRAN/Bioc）安装数与最终加载结果，不输出大体积 payload。
- 影响面控制：纯新增文件，不修改任何现有脚本，blast radius 为零；若某些包在受限网络下安装失败，仅告警并继续，不中断脚本。

## 架构设计

本任务为单文件引导脚本，无复杂架构。数据流：
`定义包清单` → `检测缺失` → `按来源安装` → `循环加载` → `输出汇总`

## 目录结构

```
g:/OmicsWorks/agent/rscript/
└── install_packages.R   # [NEW] 统一安装与加载脚本。定义 cran_packages/bioc_packages 两个向量（共 21 个第三方包），
                          # 先确保 BiocManager 已安装，按来源仅安装缺失包，再逐包 library 加载并容错，
                          # 末尾打印安装/加载汇总。文件头注释说明已排除 R 基础包。
```

## 关键代码结构（包清单定义示意）

```
# 已从 rscript 全部 30 个脚本提取的直接引用第三方包（基础包已排除）
cran_packages <- c(
  "ggplot2", "ggrepel", "RColorBrewer", "VennDiagram", "UpSetR",
  "pheatmap", "WGCNA", "dynamicTreeCut", "plsdepot", "cluster",
  "bnlearn", "randomForest", "fastshap", "nnet", "MASS",
  "mixOmics", "glmnet", "metaboanalyst"
)
bioc_packages <- c("limma", "GSVA", "impute", "ComplexHeatmap")
```