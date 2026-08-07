# ==============================================================================
# OmicsFlow: 数据归一化
# ==============================================================================
# 对表达数据进行归一化
# ==============================================================================

#' 按样本总和归一化（相对丰度）
#'
#' @description 将每个样本按其总和归一化，转换为相对丰度。该方法在代谢组学
#'   与微生物组数据中常用于校正样本间总信号强度的差异。
#'
#' @param expr_matrix 数值矩阵（特征 x 样本）。
#' @param scale_factor 数值型，缩放因子。默认：1e6（用于 ppm）。
#'   比例值用 1，百万分比（ppm）用 1e6。
#' @param multiply_by 归一化后乘上的数值型倍数。默认：1e6。
#'
#' @return 按样本总和归一化后的数值矩阵。
#'
#' @examples
#' \dontrun{
#' # 归一化为相对丰度（各比例之和为 1）
#' mat_norm <- normalize_sample_total(expr_matrix, multiply_by = 1)
#'
#' # 归一化为百万分比（ppm）
#' mat_norm <- normalize_sample_total(expr_matrix, multiply_by = 1e6)
#' }
#'
#' @export
normalize_sample_total <- function(expr_matrix, scale_factor = 1, multiply_by = 1e6) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # 计算列总和
  col_sums <- colSums(expr_matrix, na.rm = TRUE)

  # 避免除以零
  col_sums[col_sums == 0] <- 1

  # 归一化
  normalized <- t(t(expr_matrix) / col_sums) * multiply_by

  return(normalized)
}


#' 按中位数归一化（样本中位数）
#'
#' @description 将每个样本按其中位数取值进行归一化。
#'
#' @param expr_matrix 数值矩阵（特征 x 样本）。
#'
#' @return 按样本中位数归一化后的数值矩阵。
#'
#' @examples
#' \dontrun{
#' mat_norm <- normalize_median(expr_matrix)
#' }
#'
#' @export
normalize_median <- function(expr_matrix) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  col_medians <- apply(expr_matrix, 2, stats::median, na.rm = TRUE)
  col_medians[col_medians == 0] <- 1

  normalized <- t(t(expr_matrix) / col_medians)

  return(normalized)
}
