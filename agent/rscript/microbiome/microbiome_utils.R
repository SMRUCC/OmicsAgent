# ==============================================================================
# OmicsFlow: Microbiome Shared Utilities
# ==============================================================================
# 微生物组分析共享的辅助函数
# ==============================================================================

#' 计算相对丰度
#'
#' @description 将计数矩阵转换为相对丰度矩阵（每列总和为1）。
#'   封装 \code{normalize_sample_total()} 的便捷函数。
#'
#' @param expr_matrix 数值矩阵（features × samples）。
#' @param multiply_by 缩放倍数。默认 1（比例）。使用 100 得到百分比。
#'
#' @return 相对丰度矩阵。
#'
#' @examples
#' \dontrun{
#' rel_mat <- calc_relative_abundance(expr_matrix)
#' }
#'
#' @export
calc_relative_abundance <- function(expr_matrix, multiply_by = 1) {
  normalize_sample_total(expr_matrix, multiply_by = multiply_by)
}


#' 稀疏化计数矩阵
#'
#' @description 对计数矩阵进行稀疏化（rarefaction），使所有样本达到相同的
#'   测序深度。用于 α/β 多样性分析中消除样本量差异。
#'
#' @param expr_matrix 数值矩阵（features × samples），计数数据。
#' @param depth 稀疏化深度。默认 NULL（使用最小样本深度）。
#' @param n_iter 迭代次数（取均值）。默认 10。
#' @param seed 随机种子。默认 42。
#'
#' @return 稀疏化后的矩阵。
#'
#' @examples
#' \dontrun{
#' rare_mat <- rarefy_matrix(expr_matrix, depth = 5000)
#' }
#'
#' @export
rarefy_matrix <- function(expr_matrix, depth = NULL, n_iter = 10, seed = 42) {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)
  set.seed(seed)

  if (is.null(depth)) {
    depth <- min(colSums(expr_matrix, na.rm = TRUE))
  }
  cat(sprintf("[rarefy] 稀疏化深度: %d\n", depth))

  # 过滤深度不足的样本
  sample_depths <- colSums(expr_matrix, na.rm = TRUE)
  keep_samples <- names(sample_depths)[sample_depths >= depth]
  if (length(keep_samples) < ncol(expr_matrix)) {
    cat(sprintf("[rarefy] 移除 %d 个深度不足的样本\n",
                ncol(expr_matrix) - length(keep_samples)))
  }
  expr_matrix <- expr_matrix[, keep_samples, drop = FALSE]

  # 稀疏化
  result <- matrix(0, nrow = nrow(expr_matrix), ncol = ncol(expr_matrix))
  rownames(result) <- rownames(expr_matrix)
  colnames(result) <- colnames(expr_matrix)

  for (iter in seq_len(n_iter)) {
    for (j in seq_len(ncol(expr_matrix))) {
      counts <- expr_matrix[, j]
      total <- sum(counts)
      if (total == 0) next
      # 多项分布抽样
      rare <- stats::rmultinom(1, depth, prob = counts / total)
      result[, j] <- result[, j] + rare
    }
  }
  result <- result / n_iter

  return(result)
}


#' 计算覆盖率
#'
#' @description 计算每个样本的 Good's coverage 指数：
#'   1 - (n_singletons / n_total)
#'
#' @param expr_matrix 数值矩阵（features × samples），计数数据。
#'
#' @return 数值向量，每个样本的 Good's coverage。
#'
#' @examples
#' \dontrun{
#' cov <- calc_goods_coverage(expr_matrix)
#' }
#'
#' @export
calc_goods_coverage <- function(expr_matrix) {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)
  n_singletons <- colSums(expr_matrix == 1, na.rm = TRUE)
  n_total <- colSums(expr_matrix, na.rm = TRUE)
  coverage <- 1 - n_singletons / n_total
  return(coverage)
}
