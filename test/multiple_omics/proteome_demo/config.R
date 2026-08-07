# =============================================================================
# config.R  --  烟草发酵蛋白质组学分析 demo 的集中配置
# -----------------------------------------------------------------------------
# 约定：
#   - 所有路径使用绝对路径，不依赖 setwd()
#   - 主流程与各进阶脚本统一 source 本文件，保证路径与参数单一来源
#   - section()/step()/mat_dim() 为轻量日志辅助，便于运行输出可诊断
# =============================================================================

# ---- 根目录与模块库路径 -----------------------------------------------------
PROJECT_ROOT <- "g:/OmicsWorks"
RSCRIPT_ROOT <- file.path(PROJECT_ROOT, "agent", "rscript")
DATA_DIR     <- file.path(PROJECT_ROOT, "extdata", "Tobacco-fermentation")

# ---- 输入数据文件路径 -------------------------------------------------------
EXPR_FILE    <- file.path(DATA_DIR, "expression", "expression_proteome.csv")
FEATURE_FILE <- file.path(DATA_DIR, "featureinfo_proteome.csv")
SAMPLE_FILE  <- file.path(DATA_DIR, "sampleinfo.csv")

# ---- 输出目录（自动创建） ---------------------------------------------------
DEMO_DIR    <- "g:/OmicsWorks/test/multiple_omics/proteome_demo"
RESULTS_DIR <- file.path(DEMO_DIR, "results")
FIGURES_DIR <- file.path(DEMO_DIR, "figures")
CACHE_DIR   <- file.path(DEMO_DIR, "cache")

# ---- 分组列常量（基于实测：sample_info 26 水平粒度过细，phase 4 水平为主分组）
GROUP_PHASE    <- "phase"
GROUP_VARIETY  <- "variety"
GROUP_LOCATION <- "location"
# 主对比：Fresh（对照） vs Late_maturation（后续成熟阶段）
CONTRAST_PHASE_CONTROL <- "Fresh"
CONTRAST_PHASE_CASE    <- "Late_maturation"
CONTRAST_VAR_CONTROL   <- "Burley"
CONTRAST_VAR_CASE      <- "Virginia"

# ---- 阈值与随机种子 ---------------------------------------------------------
SEED            <- 20250808
P_THRESHOLD     <- 0.05
LOGFC_THRESHOLD <- 1          # log2 fold change 阈值（用于差异判定/火山图）
CV_THRESHOLD    <- 20         # 质控 CV 阈值（%）
MISSING_THRESH  <- 30         # 质控缺失率阈值（%）
N_TOP_CLUSTER   <- 50         # 热图 Top 差异蛋白数量
N_CLUSTERS      <- 6          # 表达模式聚类数

# ---- 日志辅助 ---------------------------------------------------------------
section <- function(title) {
  bar <- paste(rep("=", 72), collapse = "")
  cat(sprintf("\n%s\n### %s\n%s\n", bar, title, bar))
}
step <- function(msg) {
  cat(sprintf("  [step] %s\n", msg))
}
mat_dim <- function(x, label = "matrix") {
  if (is.null(x)) { cat(sprintf("  %s: NULL\n", label)); return(invisible(NULL)) }
  d <- dim(x)
  if (is.null(d)) d <- length(x)
  cat(sprintf("  %s dim: %s\n", label, paste(d, collapse = " x ")))
  invisible(NULL)
}

# ---- 模块加载 ---------------------------------------------------------------
# source_modules(): 按相对 RSCRIPT_ROOT 的相对路径批量 source 指定脚本。
# 任一文件不存在即 stop()，保证加载失败可立即暴露，而非运行时才崩溃。
source_modules <- function(rel_paths) {
  for (p in rel_paths) {
    full <- file.path(RSCRIPT_ROOT, p)
    if (!file.exists(full)) {
      stop(sprintf("模块脚本不存在: %s (解析为 %s)", p, full))
    }
    step(sprintf("source: %s", p))
    source(full, local = FALSE, encoding = "UTF-8")
  }
  invisible(NULL)
}

# ---- 输出目录创建（在 source 本文件时即保证存在）---------------------------
for (d in c(RESULTS_DIR, FIGURES_DIR, CACHE_DIR)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}
