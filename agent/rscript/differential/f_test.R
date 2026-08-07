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

  groups <- factor(sample_info[[group_col]])

  # 对每个Feature运行 F 检验
  n_features <- nrow(expr_matrix)
  results <- data.frame(
    feature_id = rownames(expr_matrix),
    F_stat = numeric(n_features),
    p_value = numeric(n_features),
    stringsAsFactors = FALSE
  )

  for (i in 1:n_features) {
    fit <- stats::aov(expr_matrix[i, ] ~ groups)
    f_summary <- summary(fit)[[1]]
    results$F_stat[i] <- f_summary$`F value`[1]
    results$p_value[i] <- f_summary$`Pr(>F)`[1]
  }

  # 校正 p 值
  results$p_adj <- stats::p.adjust(results$p_value, method = p_adj_method)
  results$significant <- results$p_adj < 0.05

  # 将 feature_id 设为行名
  rownames(results) <- results$feature_id
  results$feature_id <- NULL

  return(results)
}
