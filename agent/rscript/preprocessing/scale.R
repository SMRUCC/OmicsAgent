# ==============================================================================
# OmicsFlow: 数据标度变换（Scaling）
# ==============================================================================
# 在Feature维度上对表达数据进行标度变换
# ==============================================================================

#' 按Feature中位数标度（中心化）
#'
#' @description 将每个Feature（行）按其值的中位数进行中心化。该方法在代谢组学中
#'   常用于使各Feature值具有可比性。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param scale 逻辑值，是否同时按 MAD（中位数绝对偏差）进行标度。默认：FALSE。
#'
#' @return 已按中位数中心化的数值矩阵。
#'
#' @examples
#' \dontrun{
#' # 仅做中位数中心化
#' mat_scaled <- scale_feature_median(expr_matrix)
#'
#' # 中位数中心化 + MAD 标度
#' mat_scaled <- scale_feature_median(expr_matrix, scale = TRUE)
#' }
#'
#' @export
scale_feature_median <- function(expr_matrix, scale = FALSE) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # 中位数中心化
  row_medians <- apply(expr_matrix, 1, stats::median, na.rm = TRUE)
  centered <- expr_matrix - row_medians

  if (scale) {
    # 按 MAD 标度
    row_mads <- apply(expr_matrix, 1, stats::mad, na.rm = TRUE)
    row_mads[row_mads == 0] <- 1
    centered <- centered / row_mads
  }

  return(centered)
}


#' 按Feature均值标度（z-score）
#'
#' @description 使用 z-score 对每个Feature（行）进行标准化：减去均值后除以标准差。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#'
#' @return 已做 z-score 标度的数值矩阵。
#'
#' @examples
#' \dontrun{
#' mat_scaled <- scale_feature_zscore(expr_matrix)
#' }
#'
#' @export
scale_feature_zscore <- function(expr_matrix) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # 使用基础 scale 函数（默认按列操作，因此先转置）
  scaled <- t(scale(t(expr_matrix)))

  # 将 NaN 替换为 0
  scaled[is.nan(scaled)] <- 0

  return(scaled)
}


#' 按Feature极差标度（min-max）
#'
#' @description 使用 min-max 归一化将每个Feature（行）缩放到 [0, 1] 区间。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#'
#' @return 已做 min-max 标度的数值矩阵。
#'
#' @examples
#' \dontrun{
#' mat_scaled <- scale_feature_minmax(expr_matrix)
#' }
#'
#' @export
scale_feature_minmax <- function(expr_matrix) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  row_min <- apply(expr_matrix, 1, min, na.rm = TRUE)
  row_max <- apply(expr_matrix, 1, max, na.rm = TRUE)
  range <- row_max - row_min
  range[range == 0] <- 1

  scaled <- (expr_matrix - row_min) / range

  return(scaled)
}


#' Pareto 标度
#'
#' @description 应用 Pareto 标度：先均值中心化，再除以标准差的平方根。
#'   在代谢组学中广泛使用。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#'
#' @return 已做 Pareto 标度的数值矩阵。
#'
#' @examples
#' \dontrun{
#' mat_scaled <- scale_pareto(expr_matrix)
#' }
#'
#' @export
scale_pareto <- function(expr_matrix) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  row_means <- rowMeans(expr_matrix, na.rm = TRUE)
  centered <- expr_matrix - row_means

  row_sd <- apply(expr_matrix, 1, stats::sd, na.rm = TRUE)
  sqrt_sd <- sqrt(row_sd)
  sqrt_sd[sqrt_sd == 0] <- 1

  scaled <- centered / sqrt_sd

  return(scaled)
}
