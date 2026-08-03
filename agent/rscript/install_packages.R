# =============================================================================
# install_packages.R
# -----------------------------------------------------------------------------
# OmicsFlow 分析环境一键安装与加载引导脚本
#
# 本脚本对 rscript/ 目录下全部 30 个 R 脚本中所直接引用的第三方包进行
# 统一安装与加载。包的来源（CRAN / Bioconductor）已根据引用方式区分：
#   - requireNamespace("pkg", quietly = TRUE)
#   - pkg::func() / pkg:::func()
#
# 已排除 R 自带基础包：stats / grDevices / utils / grid / graphics
# （这些包随 R 一起发布，无需安装）
#
# 用法：在 R 中执行 source("rscript/install_packages.R") 或修改工作目录后
#       直接 Rscript rscript/install_packages.R
# =============================================================================

# -----------------------------------------------------------------------------
# 1. 包清单（从 rscript 全部脚本提取，已去重）
# -----------------------------------------------------------------------------
# CRAN 包（含 R 推荐的 nnet/MASS/cluster，均可用 install.packages 安装）
cran_packages <- c(
  "ggplot2", "ggrepel", "RColorBrewer", "VennDiagram", "UpSetR",
  "pheatmap", "WGCNA", "dynamicTreeCut", "plsdepot", "cluster",
  "bnlearn", "randomForest", "fastshap", "nnet", "MASS",
  "mixOmics", "glmnet", "metaboanalyst"
)

# Bioconductor 包（必须用 BiocManager::install 安装）
bioc_packages <- c("limma", "GSVA", "impute", "ComplexHeatmap")

# -----------------------------------------------------------------------------
# 2. 确保 BiocManager 可用（用于安装 Bioconductor 包）
# -----------------------------------------------------------------------------
if (!requireNamespace("BiocManager", quietly = TRUE)) {
  message("[setup] 正在安装 BiocManager ...")
  install.packages("BiocManager", repos = "https://cloud.r-project.org")
}

# -----------------------------------------------------------------------------
# 3. 仅安装缺失的包（避免重复下载）
# -----------------------------------------------------------------------------
installed <- rownames(installed.packages())

missing_cran <- setdiff(cran_packages, installed)
missing_bioc <- setdiff(bioc_packages, installed)

if (length(missing_cran) > 0) {
  message(sprintf("[cran] 需要安装 %d 个 CRAN 包: %s",
                  length(missing_cran), paste(missing_cran, collapse = ", ")))
  install.packages(missing_cran, repos = "https://cloud.r-project.org")
} else {
  message("[cran] 所有 CRAN 包均已安装，跳过。")
}

if (length(missing_bioc) > 0) {
  message(sprintf("[bioc] 需要安装 %d 个 Bioconductor 包: %s",
                  length(missing_bioc), paste(missing_bioc, collapse = ", ")))
  BiocManager::install(missing_bioc, ask = FALSE)
} else {
  message("[bioc] 所有 Bioconductor 包均已安装，跳过。")
}

# -----------------------------------------------------------------------------
# 4. 统一加载全部包（逐包容错，单包失败不中断）
# -----------------------------------------------------------------------------
all_packages <- c(cran_packages, bioc_packages)
loaded_ok <- c()
loaded_fail <- c()

for (pkg in all_packages) {
  ok <- tryCatch({
    library(pkg, character.only = TRUE)
    TRUE
  }, error = function(e) {
    message(sprintf("[load] 警告: 包 '%s' 加载失败 -> %s", pkg, conditionMessage(e)))
    FALSE
  })
  if (isTRUE(ok)) loaded_ok <- c(loaded_ok, pkg) else loaded_fail <- c(loaded_fail, pkg)
}

# -----------------------------------------------------------------------------
# 5. 汇总输出
# -----------------------------------------------------------------------------
cat("\n==================== 安装/加载汇总 ====================\n")
cat(sprintf("CRAN 包      : %d 个（清单）\n", length(cran_packages)))
cat(sprintf("Bioconductor : %d 个（清单）\n", length(bioc_packages)))
cat(sprintf("已成功加载   : %d 个\n", length(loaded_ok)))
if (length(loaded_ok) > 0) cat("  - ", paste(loaded_ok, collapse = ", "), "\n")
cat(sprintf("加载失败     : %d 个\n", length(loaded_fail)))
if (length(loaded_fail) > 0) cat("  - ", paste(loaded_fail, collapse = ", "), "\n")
cat("======================================================\n")

if (length(loaded_fail) > 0) {
  warning(sprintf("有 %d 个包未能加载，请检查安装日志。", length(loaded_fail)))
}
