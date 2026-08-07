# ==============================================================================
# OmicsFlow: 缺失值填补
# ==============================================================================
# 对表达矩阵中的缺失值进行填补
# ==============================================================================

#' 使用最小正值的一半填补缺失值
#'
#' @description 将缺失值（NA，以及可选地将 0）用每个Feature的最小正值的一半进行
#'   填补。这是代谢组学中一种简单且广泛使用的填补策略。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本），缺失值用 NA 表示。
#' @param treat_zero_as_missing 逻辑值，是否将零值视为缺失。默认：TRUE。
#' @param factor 数值型，最小正值的乘子。默认：0.5（一半）。
#'
#' @return 已填补缺失值的数值矩阵。
#'
#' @examples
#' \dontrun{
#' mat_imputed <- impute_min_half(expr_matrix)
#' }
#'
#' @export
impute_min_half <- function(expr_matrix, treat_zero_as_missing = TRUE,
                            factor = 0.5) {
  # 必要时转换为矩阵
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # 若指定则把零值当作 NA
  if (treat_zero_as_missing) {
    expr_matrix[expr_matrix == 0] <- NA
  }

  # 按Feature逐个填补
  for (i in 1:nrow(expr_matrix)) {
    row_vals <- expr_matrix[i, ]
    na_mask <- is.na(row_vals)
    if (any(na_mask)) {
      positive_vals <- row_vals[!is.na(row_vals) & row_vals > 0]
      if (length(positive_vals) > 0) {
        min_positive <- min(positive_vals)
        fill_value <- min_positive * factor
        expr_matrix[i, na_mask] <- fill_value
      } else {
        # 所有值都是 NA —— 以 0 填充
        expr_matrix[i, na_mask] <- 0
      }
    }
  }

  return(expr_matrix)
}


#' 使用 KNN 填补缺失值
#'
#' @description 使用 K 近邻（K-Nearest Neighbors）填补缺失值。
#'   底层调用 \code{impute} 包的 KNN 实现。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本），缺失值用 NA 表示。
#' @param k 近邻数量。默认：10。
#' @param treat_zero_as_missing 逻辑值，是否将零值视为缺失。默认：TRUE。
#' @param max_na_prop 每个Feature允许的最大 NA 比例。超过该比例的Feature将被
#'   移除。默认：0.5。
#'
#' @return 已填补缺失值的数值矩阵。
#'
#' @examples
#' \dontrun{
#' mat_imputed <- impute_knn(expr_matrix, k = 10)
#' }
#'
#' @export
impute_knn <- function(expr_matrix, k = 10, treat_zero_as_missing = TRUE,
                       max_na_prop = 0.5) {
  # 必要时转换为矩阵
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # 若指定则把零值当作 NA
  if (treat_zero_as_missing) {
    expr_matrix[expr_matrix == 0] <- NA
  }

  # 移除含过多 NA 的Feature
  na_prop <- rowMeans(is.na(expr_matrix))
  high_na_features <- rownames(expr_matrix)[na_prop > max_na_prop]
  if (length(high_na_features) > 0) {
    warning(paste("Removing", length(high_na_features),
                  "features with >", max_na_prop, "NA proportion"))
    expr_matrix <- expr_matrix[na_prop <= max_na_prop, , drop = FALSE]
  }

  # 检查 impute 包是否可用
  if (!requireNamespace("impute", quietly = TRUE)) {
    # 回退：使用简化版 KNN 实现
    warning("Package 'impute' not available. Using simple KNN implementation.")
    return(.impute_knn_simple(expr_matrix, k))
  }

  # 使用 impute.knn
  result <- impute::impute.knn(as.matrix(expr_matrix), k = k,
                                maxp = nrow(expr_matrix))
  return(result$data)
}


#' 简化版 KNN 填补（内部回退实现）
#'
#' @keywords internal
#' @noRd
.impute_knn_simple <- function(mat, k) {
  # 计算Feature之间的距离矩阵
  # 对每个含 NA 的Feature，找出 k 个最近邻Feature并进行填补
  for (i in 1:nrow(mat)) {
    na_mask <- is.na(mat[i, ])
    if (!any(na_mask)) next

    # 与其他Feature计算相关性
    other_features <- mat[-i, , drop = FALSE]
    correlations <- apply(other_features, 1, function(x) {
      common <- !is.na(mat[i, ]) & !is.na(x)
      if (sum(common) < 2) return(0)
      cor(mat[i, common], x[common], use = "everything")
    })

    # 取 k 个最近邻（绝对相关性最高）
    k_actual <- min(k, length(correlations))
    nearest_idx <- order(abs(correlations), decreasing = TRUE)[1:k_actual]

    for (j in which(na_mask)) {
      neighbor_vals <- mat[nearest_idx, j]
      neighbor_vals <- neighbor_vals[!is.na(neighbor_vals)]
      if (length(neighbor_vals) > 0) {
        mat[i, j] <- mean(neighbor_vals)
      } else {
        mat[i, j] <- 0
      }
    }
  }
  return(mat)
}
