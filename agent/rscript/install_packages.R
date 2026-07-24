# =============================================================================
# install_packages.R
# -----------------------------------------------------------------------------
# 环境初始化脚本：在新 R 环境中安装 rscript 文件夹下全部分析脚本所依赖的程序包。
#
# 用法:
#   Rscript install_packages.R
#   或 在 R 会话中 source("install_packages.R")
#
# 逻辑:
#   1. 固化扫描全部 .R 脚本后收集到的包名列表（区分 CRAN / Bioconductor）。
#   2. 对每个包检查是否已安装；已安装则跳过，未安装则按来源安装。
#   3. Bioconductor 包依赖 BiocManager，缺失时先引导安装。
#   4. 运行结束输出安装汇总，并列出未能成功安装的包。
# =============================================================================

# ---------------------------------------------------------------------------
# 1. 已收集的包名列表（扫描 rscript 下全部 .R 脚本，合并 library()/require()
#    与 pkg::func() 两种用法后去重得到；stats / grDevices / grid / utils 等
#    基础包无需安装，已剔除）。
# ---------------------------------------------------------------------------

cran_packages <- c(
  "openxlsx", "jsonlite", "WGCNA", "ggplot2", "reshape2",
  "ggrepel", "ggVennDiagram", "VennDiagram", "RColorBrewer",
  "UpSetR", "pheatmap", "bnlearn", "igraph", "plspm",
  "randomForest", "dplyr", "glmnet", "e1071"
)

bioconductor_packages <- c(
  "mixOmics", "ropls", "impute", "limma", "GSVA"
)

# ---------------------------------------------------------------------------
# 2. 工具函数
# ---------------------------------------------------------------------------

# 判断某个包是否已安装（用 requireNamespace 检查，避免加载副作用）
is_installed <- function(pkg) {
  requireNamespace(pkg, quietly = TRUE)
}

# 检查并安装单个包：已安装则跳过，未安装按来源调用对应安装器
check_and_install <- function(pkg, source = c("cran", "bioconductor")) {
  source <- match.arg(source)

  if (is_installed(pkg)) {
    message(sprintf("[跳过] %-15s 已安装", pkg))
    return(TRUE)
  }

  message(sprintf("[安装] %-15s 来源: %s ...", pkg, source))
  ok <- tryCatch(
    {
      if (source == "bioconductor") {
        BiocManager::install(pkg, ask = FALSE, update = FALSE)
      } else {
        install.packages(pkg, repos = cran_repo)
      }
      # 安装后再确认一次
      is_installed(pkg)
    },
    error = function(e) {
      message(sprintf("  安装失败: %s", conditionMessage(e)))
      FALSE
    }
  )

  if (ok) {
    message(sprintf("[成功] %-15s 安装完成", pkg))
  } else {
    message(sprintf("[失败] %-15s 未能成功安装", pkg))
  }
  ok
}

# ---------------------------------------------------------------------------
# 3. 准备安装环境
# ---------------------------------------------------------------------------

# CRAN 镜像（避免交互式询问镜像导致脚本挂起）
cran_repo <- "https://cloud.r-project.org"

# 确保 Bioconductor 安装器 BiocManager 就绪
if (!is_installed("BiocManager")) {
  message("[引导] 未检测到 BiocManager，先从 CRAN 安装 ...")
  install.packages("BiocManager", repos = cran_repo)
}
if (!is_installed("BiocManager")) {
  stop("无法安装 BiocManager，Bioconductor 包将无法安装，请检查网络与 R 版本。")
}

# ---------------------------------------------------------------------------
# 4. 遍历安装缺失的包
# ---------------------------------------------------------------------------

failed_packages <- c()

message("\n================ 开始安装 CRAN 包 ================")
for (pkg in cran_packages) {
  if (!check_and_install(pkg, source = "cran")) {
    failed_packages <- c(failed_packages, pkg)
  }
}

message("\n============== 开始安装 Bioconductor 包 ==============")
for (pkg in bioconductor_packages) {
  if (!check_and_install(pkg, source = "bioconductor")) {
    failed_packages <- c(failed_packages, pkg)
  }
}

# ---------------------------------------------------------------------------
# 5. 安装结果汇总
# ---------------------------------------------------------------------------

message("\n==================== 安装汇总 ====================")
message(sprintf("CRAN 包总数:        %d", length(cran_packages)))
message(sprintf("Bioconductor 包总数: %d", length(bioconductor_packages)))
message(sprintf("需安装的包总数:     %d", length(cran_packages) + length(bioconductor_packages)))

if (length(failed_packages) == 0) {
  message("结果: 所有程序包均已就绪，环境初始化完成。")
} else {
  message("结果: 以下程序包未能成功安装，请手动排查（网络 / 镜像 / 系统依赖）:")
  for (pkg in failed_packages) {
    message(sprintf("  - %s", pkg))
  }
}
