# ==============================================================================
# 代谢组学 Demo 流程 - 公共配置
# ==============================================================================
# 职责：集中定义路径常量、分组列常量、性能参数常量，以及模块批量加载辅助函数。
# 所有分析脚本首行 source 本文件，保证路径与参数单点定义。
# ==============================================================================

# ------------------------------------------------------------------------------
# 路径常量（全部使用绝对路径 + 正斜杠，不依赖 setwd）
# ------------------------------------------------------------------------------
PROJECT_ROOT <- "g:/OmicsWorks"
RSCRIPT_ROOT <- file.path(PROJECT_ROOT, "agent/rscript")
DATA_DIR     <- file.path(PROJECT_ROOT, "extdata/Tobacco-fermentation")
DEMO_DIR     <- file.path(PROJECT_ROOT, "test/multiple_omics/metabolism_demo")

RESULT_DIR   <- file.path(DEMO_DIR, "results")
FIGURE_DIR   <- file.path(DEMO_DIR, "figures")
CACHE_DIR    <- file.path(DEMO_DIR, "cache")
KEGG_CACHE   <- file.path(CACHE_DIR, "kegg")

for (d in c(RESULT_DIR, FIGURE_DIR, CACHE_DIR, KEGG_CACHE)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

# ------------------------------------------------------------------------------
# 输入数据文件
# ------------------------------------------------------------------------------
FILE_EXPR    <- file.path(DATA_DIR, "expression/expression_metabolome.csv")
FILE_FEATURE <- file.path(DATA_DIR, "featureinfo_metabolome.csv")
FILE_SAMPLE  <- file.path(DATA_DIR, "sampleinfo.csv")

# ------------------------------------------------------------------------------
# 分组列常量
# ------------------------------------------------------------------------------
GROUP_VARIETY <- "variety"   # 2 组: Virginia / Burley
GROUP_PHASE   <- "phase"     # 4 组: 发酵阶段
GROUP_LOCATION <- "location" # 2 组: 产地

# ------------------------------------------------------------------------------
# 性能参数常量
# ------------------------------------------------------------------------------
WGCNA_TOP_N   <- 400    # WGCNA 输入特征数（按方差取 top N）
ASSOC_TOP_N   <- 300    # 关联网络输入特征数
MIC_MAX_PAIRS <- 2000   # 参与 MIC 计算的最大特征对数
MIC_N_PERM    <- 200    # MIC 置换检验次数
PLSPM_MIN_SIZE <- 3     # 潜变量最小成员数
PLSPM_MAX_LV   <- 15    # 潜变量最大个数
RANDOM_SEED   <- 42

# ------------------------------------------------------------------------------
# 模块批量加载辅助函数
# ------------------------------------------------------------------------------

#' 按相对路径列表批量 source agent/rscript 模块
#'
#' @param rel_paths 相对于 RSCRIPT_ROOT 的 .R 文件路径字符向量
#' @param verbose 是否打印加载进度
#' @return 不可见的已加载文件绝对路径向量
source_modules <- function(rel_paths, verbose = TRUE) {
  loaded <- character(0)
  for (rp in rel_paths) {
    fp <- file.path(RSCRIPT_ROOT, rp)
    if (!file.exists(fp)) {
      stop(sprintf("模块文件不存在: %s", fp))
    }
    source(fp, encoding = "UTF-8")
    loaded <- c(loaded, fp)
    if (verbose) cat(sprintf("  [source] %s\n", rp))
  }
  invisible(loaded)
}

#' 打印醒目的 section 分隔标题
#'
#' @param title section 标题
#' @param level 1 = 主标题(=), 2 = 子标题(-)
section <- function(title, level = 1) {
  ch <- if (level == 1) "=" else "-"
  bar <- paste(rep(ch, 78), collapse = "")
  cat("\n", bar, "\n", title, "\n", bar, "\n", sep = "")
}

#' 打印带时间戳的进度信息
step <- function(...) {
  cat(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), ..., "\n", sep = "")
}

#' 打印矩阵规模
mat_dim <- function(label, mat) {
  cat(sprintf("    %-28s : %d features x %d samples\n",
              label, nrow(mat), ncol(mat)))
}

#' 计时执行并打印耗时
timed <- function(label, expr) {
  t0 <- Sys.time()
  res <- force(expr)
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("    [耗时] %-40s %.2f s\n", label, el))
  invisible(res)
}
