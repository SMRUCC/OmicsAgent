# ==============================================================================
# OmicsFlow: F 检验差异分析
# ==============================================================================
# 使用 F 检验进行总体差异分析
# ==============================================================================

#' F 检验总体差异分析
#'
#' @description 对每个Feature执行 F 检验（单因素方差分析），以检验各组之间的
#'   总体差异。返回 F 统计量、p 值与校正后的 p 值。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param sample_info 含有样本元数据的数据框。
#' @param group_col 分组标签所在的列名。默认："sample_info"。
#' @param exclude_groups 可选的要排除的分组字符向量。默认："QC"。
#' @param p_adj_method P 值校正方法。默认："BH"。
#'
#' @return 一个数据框，包含：
#'   \itemize{
#'     \item \code{feature_id}：Feature ID。
#'     \item \code{F_stat}：F 统计量。
#'     \item \code{p_value}：原始 p 值。
#'     \item \code{p_adj}：校正后的 p 值。
#'     \item \code{significant}：逻辑值，p_adj < 0.05 时为显著。
#'   }
#'
#' @examples
#' \dontrun{
#' ftest_result <- run_f_test(expr_matrix, sample_info, exclude_groups = "QC")
#' head(ftest_result)
#' }
#'
#' @export
run_f_test <- function(expr_matrix, sample_info, group_col = "sample_info",
                       exclude_groups = "QC", p_adj_method = "BH") {
  # 对齐样本
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]
  
  # 排除分组
  if (!is.null(exclude_groups)) {
    keep_samples <- rownames(sample_info)[!(sample_info[[group_col]] %in% exclude_groups)]
    expr_matrix <- expr_matrix[, keep_samples, drop = FALSE]
    sample_info <- sample_info[keep_samples, , drop = FALSE]
  }
  
  # as.character 后再转 factor：若 group_col 本身已是 factor，
  # 过滤样本后会残留无样本的空水平，导致 aov 的设计矩阵秩亏。
  groups <- factor(as.character(sample_info[[group_col]]))

  # 空输入保护：0 行时 rownames() 返回 NULL，data.frame(feature_id = NULL, ...)
  # 会直接丢掉该列，随后 rownames(results) <- results$feature_id 因列不存在
  # 而破坏返回结构。此处提前返回列结构完整的空表。
  n_features <- nrow(expr_matrix)
  empty_result <- data.frame(
    F_stat = numeric(0), p_value = numeric(0),
    p_adj = numeric(0), significant = logical(0),
    stringsAsFactors = FALSE
  )
  if (n_features == 0 || ncol(expr_matrix) == 0) {
    warning("run_f_test: 过滤后无可分析的特征或样本，返回空结果。")
    return(empty_result)
  }
  if (nlevels(groups) < 2) {
    warning("run_f_test: 分组水平数不足 2，无法做 F 检验，返回空结果。")
    return(empty_result)
  }

  # 对每个Feature运行 F 检验
  feature_ids <- rownames(expr_matrix)
  if (is.null(feature_ids)) feature_ids <- paste0("feature_", seq_len(n_features))

  # 预填 NA 而非 0：某特征检验失败时应保持缺失语义，
  # 若残留 0 会被 p.adjust 当作真实 p = 0 参与校正，污染全部结果。
  results <- data.frame(
    feature_id = feature_ids,
    F_stat = rep(NA_real_, n_features),
    p_value = rep(NA_real_, n_features),
    stringsAsFactors = FALSE
  )

  for (i in seq_len(n_features)) {
    y <- as.numeric(expr_matrix[i, ])
    # 常量特征或有效值不足时 aov 会报错/无法给出 F 值，跳过并保留 NA
    if (all(is.na(y)) || length(unique(y[!is.na(y)])) < 2) next
    f_summary <- tryCatch(
      summary(stats::aov(y ~ groups))[[1]],
      error = function(e) NULL
    )
    if (is.null(f_summary)) next
    fv <- f_summary[["F value"]]
    pv <- f_summary[["Pr(>F)"]]
    if (!is.null(fv) && length(fv) >= 1) results$F_stat[i] <- fv[1]
    if (!is.null(pv) && length(pv) >= 1) results$p_value[i] <- pv[1]
  }

  # 校正 p 值（p.adjust 默认忽略 NA，不会把缺失当成显著）
  results$p_adj <- stats::p.adjust(results$p_value, method = p_adj_method)
  results$significant <- !is.na(results$p_adj) & results$p_adj < 0.05

  # 将 feature_id 设为行名（去重避免重复特征名导致 rownames<- 报错）
  rownames(results) <- make.unique(as.character(results$feature_id))
  results$feature_id <- NULL

  return(results)
}
