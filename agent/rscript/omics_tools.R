# ============================================================================
# OmicsAgent R 工具函数库
# 通用辅助函数，供 LLM 生成的 R 脚本 source() 使用
# ============================================================================

#' 安全加载 R 包，未安装则自动安装
#' @param pkg 包名（字符）
safe_load <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message(sprintf("Installing package: %s", pkg))
    tryCatch({
      install.packages(pkg, repos = "https://cloud.r-project.org", quiet = TRUE)
    }, error = function(e) {
      message(sprintf("Failed to install %s: %s", pkg, e$message))
    })
  }
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf("Required R package '%s' is not available.", pkg))
  }
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}

#' 读取表达矩阵 CSV
#' 第一列为分子 ID，其余列为样本
#' @param csv_path CSV 文件路径
#' @return list(data = matrix, ids = character, samples = character)
read_expression_matrix <- function(csv_path) {
  df <- read.csv(csv_path, check.names = FALSE, row.names = 1, stringsAsFactors = FALSE)
  # 转换为数值矩阵
  mat <- as.matrix(df)
  mode(mat) <- "numeric"
  list(
    data = mat,
    ids = rownames(mat),
    samples = colnames(mat)
  )
}

#' 读取样本信息 CSV
#' @param csv_path CSV 文件路径
#' @return data.frame
read_sample_info <- function(csv_path) {
  df <- read.csv(csv_path, check.names = FALSE, stringsAsFactors = FALSE)
  df
}

#' 读取注释 CSV
#' @param csv_path CSV 文件路径
#' @return data.frame
read_annotation <- function(csv_path) {
  df <- read.csv(csv_path, check.names = FALSE, stringsAsFactors = FALSE)
  # 标准化列名
  colnames(df) <- tolower(colnames(df))
  df
}

#' 缺失值处理
#' @param mat 表达矩阵
#' @param method "knn" | "min" | "median" | "zero"
impute_missing <- function(mat, method = "min") {
  if (!any(is.na(mat))) return(mat)
  if (method == "min") {
    min_val <- min(mat, na.rm = TRUE)
    mat[is.na(mat)] <- min_val
  } else if (method == "median") {
    mat[is.na(mat)] <- median(mat, na.rm = TRUE)
  } else if (method == "zero") {
    mat[is.na(mat)] <- 0
  } else if (method == "knn") {
    safe_load("impute")
    mat <- impute::impute.knn(mat)$data
  }
  mat
}

#' 过滤低方差特征
#' @param mat 表达矩阵
#' @param percentile 保留前 N% 方差的特征
filter_low_variance <- function(mat, percentile = 0.8) {
  vars <- apply(mat, 1, var, na.rm = TRUE)
  threshold <- quantile(vars, 1 - percentile, na.rm = TRUE)
  mat[vars > threshold, , drop = FALSE]
}

#' 对数转换（如果数据未取对数）
#' @param mat 表达矩阵
#' @param base 对数底数
log_transform <- function(mat, base = 2) {
  max_val <- max(mat, na.rm = TRUE)
  if (max_val > 100) {
    # 假设是原始 count，需要 log 转换
    mat <- log2(mat + 1)
  }
  mat
}

#' Z-score 标准化（按行）
#' @param mat 表达矩阵
zscore_rows <- function(mat) {
  t(scale(t(mat)))
}

#' 保存 PNG 图
#' @param path 输出路径
#' @param width 宽（像素）
#' @param height 高（像素）
#' @param res 分辨率（dpi）
save_png <- function(path, width = 1200, height = 1000, res = 300) {
  png(path, width = width, height = height, res = res)
}

#' 保存 CSV 表格
#' @param df data.frame
#' @param path 输出路径
save_csv <- function(df, path) {
  write.csv(df, path, row.names = FALSE)
}

#' 中文字体支持（showtext）
setup_chinese_font <- function() {
  tryCatch({
    safe_load("showtext")
    showtext::showtext_auto()
  }, error = function(e) {
    message("showtext not available, using default font.")
  })
}

#' 简单 PCA
#' @param mat 表达矩阵（行=特征，列=样本）
#' @return list(scores = matrix, var_explained = numeric)
run_pca <- function(mat) {
  mat_t <- t(mat)  # 转置：行=样本，列=特征
  pca <- prcomp(mat_t, scale. = TRUE, center = TRUE)
  var_explained <- pca$sdev^2 / sum(pca$sdev^2) * 100
  list(
    scores = pca$x,
    var_explained = var_explained,
    loadings = pca$rotation,
    model = pca
  )
}

#' LIMMA 差异分析
#' @param mat 表达矩阵
#' @param groups 分组向量
#' @param design 设计矩阵（可选）
#' @return data.frame with logFC, P.Value, adj.P.Val
run_limma <- function(mat, groups, design = NULL) {
  safe_load("limma")
  if (is.null(design)) {
    design <- model.matrix(~ 0 + factor(groups))
    colnames(design) <- levels(factor(groups))
  }
  fit <- limma::lmFit(mat, design)
  # 简单两两比较
  if (ncol(design) >= 2) {
    contrast <- limma::makeContrasts(
      contrast = colnames(design)[2] - colnames(design)[1],
      levels = design
    )
    fit2 <- limma::eBayes(limma::contrasts.fit(fit, contrast))
    result <- limma::topTable(fit2, number = Inf, sort.by = "P")
    result$id <- rownames(result)
    return(result)
  }
  fit2 <- limma::eBayes(fit)
  limma::topTable(fit2, number = Inf, sort.by = "P")
}

#' KEGG 富集分析（基于 clusterProfiler）
#' @param gene_ids 差异基因 ID 向量
#' @param universe 背景基因 ID 向量
#' @param organism 物种（如 "hsa"）
#' @return data.frame
run_kegg_enrichment <- function(gene_ids, universe, organism = "hsa") {
  safe_load("clusterProfiler")
  tryCatch({
    ego <- clusterProfiler::enrichKEGG(
      gene = gene_ids,
      universe = universe,
      organism = organism,
      pvalueCutoff = 0.05
    )
    as.data.frame(ego)
  }, error = function(e) {
    message(sprintf("KEGG enrichment failed: %s", e$message))
    data.frame()
  })
}

#' WGCNA 软阈值选择
#' @param mat 表达矩阵
#' @param powers 候选 power 向量
pick_soft_threshold <- function(mat, powers = c(1:10, seq(12, 20, by = 2))) {
  safe_load("WGCNA")
  WGCNA::pickSoftThreshold(t(mat), powerVector = powers, verbose = 0)
}

#' CMeans 软聚类
#' @param mat 表达矩阵
#' @param centers 聚类数
#' @return list
run_cmeans <- function(mat, centers = 6) {
  safe_load("e1071")
  # 标准化
  mat_z <- t(scale(t(mat)))
  cm <- e1071::cmeans(mat_z, centers = centers, m = 1.5)
  list(
    membership = cm$membership,
    centers = cm$centers,
    cluster = cm$cluster,
    data = mat_z
  )
}

#' 打印会话信息到文件
#' @param path 输出路径
save_session_info <- function(path) {
  sink(path)
  print(sessionInfo())
  sink()
}

#' 安全关闭图形设备
safe_dev_off <- function() {
  while (!is.null(dev.list())) {
    dev.off()
  }
}
