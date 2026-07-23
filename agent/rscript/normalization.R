#' @title Normalize by Sample Sum (Relative Abundance)
#'
#' @description
#' 按照样本总和做相对丰度归一化。该归一化方法将每个样本中所有feature
#' 的表达值除以该样本的总和，转换为相对丰度（通常乘以缩放因子如1e6
#' 转换为ppm单位）。该方法常用于微生物组和代谢组学数据，
#' 消除样本间总体载量差异。
#'
#' 公式：normalized[i,j] = raw[i,j] / sum(raw[,j]) * scale_factor
#'
#' @param expr_matrix 数值矩阵，表达矩阵（行：feature，列：样本）
#' @param scale_factor 数值，缩放因子，默认1e6（即ppm）
#' @param pseudo_count 数值，伪计数，避免除零，默认1
#'
#' @return 返回归一化后的数值矩阵
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#'
#' # 相对丰度归一化（ppm单位）
#' normalized_expr <- normalize_sample_sum(expr, scale_factor = 1e6)
#'
#' # 使用百分比
#' normalized_expr <- normalize_sample_sum(expr, scale_factor = 100)
#' }
#'
#' @export
normalize_sample_sum <- function(expr_matrix, scale_factor = 1e6,
                                 pseudo_count = 1) {
  sample_sums <- colSums(expr_matrix, na.rm = TRUE) + pseudo_count
  normalized_matrix <- sweep(expr_matrix, 2, sample_sums, "/") * scale_factor

  message("Sample-sum normalization completed. Scale factor: ", scale_factor)
  return(normalized_matrix)
}


#' @title Scale by Feature Median
#'
#' @description
#' 按照feature做中位数数据缩放。对每个feature（行），计算所有样本的
#' 中位数，然后将该feature的所有值除以中位数。该方法保留了feature
#' 之间的相对差异，同时消除了不同feature间绝对值量级的差异，
#' 适用于跨feature比较和热图可视化。
#'
#' 公式：scaled[i,j] = raw[i,j] / median(raw[i,])
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param log_transform 逻辑值，是否在缩放前做log2转换，默认FALSE
#'
#' @return 返回缩放后的数值矩阵
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#'
#' # 中位数缩放
#' scaled_expr <- scale_feature_median(expr)
#'
#' # 先log2转换再做中位数缩放
#' scaled_expr <- scale_feature_median(expr, log_transform = TRUE)
#' }
#'
#' @export
scale_feature_median <- function(expr_matrix, log_transform = FALSE) {
  if (log_transform) {
    expr_matrix <- log2(expr_matrix + 1)
    message("Applied log2(x+1) transformation before scaling.")
  }

  feature_medians <- apply(expr_matrix, 1, median, na.rm = TRUE)
  feature_medians[feature_medians == 0] <- 1  # avoid division by zero

  scaled_matrix <- sweep(expr_matrix, 1, feature_medians, "/")

  message("Feature-median scaling completed for ", nrow(scaled_matrix), " features.")
  return(scaled_matrix)
}


#' @title Z-score Scaling by Feature
#'
#' @description
#' 按照feature做Z-score标准化。对每个feature（行），计算均值和标准差，
#' 然后将该feature的所有值转换为Z-score。该方法使每个feature的均值为0、
#' 标准差为1，适用于热图可视化和机器学习模型输入。
#'
#' 公式：z[i,j] = (raw[i,j] - mean(raw[i,])) / sd(raw[i,])
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#'
#' @return 返回Z-score标准化后的数值矩阵
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' zscore_expr <- scale_zscore(expr)
#' }
#'
#' @export
scale_zscore <- function(expr_matrix) {
  feature_means <- rowMeans(expr_matrix, na.rm = TRUE)
  feature_sds <- apply(expr_matrix, 1, sd, na.rm = TRUE)
  feature_sds[feature_sds == 0 | is.na(feature_sds)] <- 1

  scaled_matrix <- sweep(expr_matrix, 1, feature_means, "-")
  scaled_matrix <- sweep(scaled_matrix, 1, feature_sds, "/")

  message("Z-score scaling completed for ", nrow(scaled_matrix), " features.")
  return(scaled_matrix)
}


#' @title Quantile Normalization
#'
#' @description
#' 对表达矩阵做分位数归一化。该方法将所有样本的值分布统一为相同分布，
#' 消除样本间的技术差异。常用于转录组学（microarray）数据。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#'
#' @return 返回分位数归一化后的数值矩阵
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' normalized_expr <- normalize_quantile(expr)
#' }
#'
#' @export
normalize_quantile <- function(expr_matrix) {
  # Implementation of quantile normalization
  sorted_matrix <- apply(expr_matrix, 2, sort)
  if (!is.matrix(sorted_matrix)) {
    sorted_matrix <- matrix(sorted_matrix, ncol = 1)
  }

  row_means <- rowMeans(sorted_matrix, na.rm = TRUE)

  normalized_matrix <- apply(expr_matrix, 2, function(col) {
    ranks <- rank(col, ties.method = "average")
    row_means[ranks]
  })

  rownames(normalized_matrix) <- rownames(expr_matrix)
  colnames(normalized_matrix) <- colnames(expr_matrix)

  message("Quantile normalization completed.")
  return(normalized_matrix)
}


#' @title Apply Log Transformation
#'
#' @description
#' 对表达矩阵做对数转换。提供log2、log10和自然对数三种选择。
#' 对数转换使数据分布更接近正态分布，是组学数据分析中常用的预处理步骤。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param base 数值，对数底，2、10或exp(1)，默认2
#' @param pseudo_count 数值，伪计数，避免log(0)，默认1
#'
#' @return 返回对数转换后的数值矩阵
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' log_expr <- transform_log(expr, base = 2, pseudo_count = 1)
#' }
#'
#' @export
transform_log <- function(expr_matrix, base = 2, pseudo_count = 1) {
  if (base == 2) {
    transformed <- log2(expr_matrix + pseudo_count)
  } else if (base == 10) {
    transformed <- log10(expr_matrix + pseudo_count)
  } else {
    transformed <- log(expr_matrix + pseudo_count)
  }

  message("Log", base, " transformation completed with pseudo count ", pseudo_count, ".")
  return(transformed)
}
