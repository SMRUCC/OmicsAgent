#' @title Filter Features by Missing Value Proportion
#'
#' @description
#' 按照缺失值比例阈值过滤feature。提供两种过滤策略：
#'
#' 策略1（分组过滤）：按照所有分组中缺失比例超过百分比阈值后删除，
#' 任意一个分组中缺失比例没有超过阈值就保留。该策略适用于存在样本分组信息
#' 且希望保留至少在一个分组中表达稳定的feature的场景。
#'
#' 策略2（总体过滤）：按照总体样本中缺失比例超过百分比阈值后删除。
#' 该策略不考虑分组信息，适用于无分组或全局质控场景。
#'
#' @param expr_matrix 数值矩阵，表达矩阵（行：feature，列：样本）
#' @param sample_meta 数据框，样本元数据，必须包含ID和sample_info列
#' @param threshold 数值，缺失比例阈值，默认0.8（即缺失比例超过80%的feature被删除）
#' @param method 字符串，过滤方法，"group"为分组过滤，"overall"为总体过滤，默认"group"
#'
#' @return 返回过滤后的表达矩阵，仅保留满足阈值的feature
#'
#' @examples
#' \dontrun{
#' # 加载数据
#' expr <- load_expression_matrix("expr.csv")
#' meta <- load_sample_metadata("meta.csv")
#'
#' # 分组过滤：保留至少在一个分组中缺失比例不超过80%的feature
#' filtered_expr <- filter_missing_values(expr, meta, threshold = 0.8,
#'                                        method = "group")
#'
#' # 总体过滤：保留总体缺失比例不超过50%的feature
#' filtered_expr <- filter_missing_values(expr, meta, threshold = 0.5,
#'                                        method = "overall")
#'
#' message("Original features: ", nrow(expr), " | Filtered: ", nrow(filtered_expr))
#' }
#'
#' @export
filter_missing_values <- function(expr_matrix, sample_meta,
                                  threshold = 0.8, method = "group") {
  if (!method %in% c("group", "overall")) {
    stop("method must be 'group' or 'overall'")
  }

  if (method == "overall") {
    na_ratio <- rowMeans(is.na(expr_matrix))
    keep_features <- names(na_ratio)[na_ratio <= threshold]
  } else {
    if (is.null(sample_meta) || !"sample_info" %in% colnames(sample_meta)) {
      stop("sample_meta with 'sample_info' column is required for group method")
    }

    matched_meta <- sample_meta[match(colnames(expr_matrix), sample_meta$ID), ]
    groups <- split(colnames(expr_matrix), matched_meta$sample_info)

    na_ratio_by_group <- sapply(groups, function(samples) {
      rowMeans(is.na(expr_matrix[, samples, drop = FALSE]))
    })

    if (!is.matrix(na_ratio_by_group)) {
      na_ratio_by_group <- matrix(na_ratio_by_group, ncol = 1,
                                   dimnames = list(names(na_ratio_by_group),
                                                   "Group"))
    }

    keep_mask <- apply(na_ratio_by_group, 1, function(x) any(x <= threshold))
    keep_features <- names(keep_mask)[keep_mask]
  }

  filtered_matrix <- expr_matrix[keep_features, , drop = FALSE]
  message("Missing value filter (", method, "): kept ", nrow(filtered_matrix),
          " / ", nrow(expr_matrix), " features (",
          round(100 * nrow(filtered_matrix) / nrow(expr_matrix), 1), "%).")

  return(filtered_matrix)
}


#' @title Impute Missing Values by Half Minimum Positive Value
#'
#' @description
#' 按照feature最小阳性值的一半对缺失值进行填充。该策略是代谢组学和
#' 蛋白质组学中常用的缺失值填充方法，假设缺失值通常低于检测限，
#' 因此使用最小检测值的一半作为填充值，避免引入偏置。
#'
#' 对于每个feature，找到所有非缺失值中的最小正值，取其一半作为填充值。
#' 如果某个feature所有值都缺失或都为0，则填充为0。
#'
#' @param expr_matrix 数值矩阵，表达矩阵（行：feature，列：样本）
#'
#' @return 返回填充后的数值矩阵，无NA值
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#'
#' # 使用最小阳性值一半填充
#' imputed_expr <- impute_half_min(expr)
#'
#' # 检查是否还有缺失值
#' sum(is.na(imputed_expr))  # 应为0
#' }
#'
#' @export
impute_half_min <- function(expr_matrix) {
  if (!any(is.na(expr_matrix))) {
    message("No NA values detected. No imputation performed.")
    return(expr_matrix)
  }

  imputed_matrix <- expr_matrix

  for (i in seq_len(nrow(imputed_matrix))) {
    row_vals <- imputed_matrix[i, ]
    na_idx <- is.na(row_vals)
    if (any(na_idx)) {
      positive_vals <- row_vals[!is.na(row_vals) & row_vals > 0]
      if (length(positive_vals) > 0) {
        fill_val <- min(positive_vals) / 2
      } else {
        fill_val <- 0
      }
      imputed_matrix[i, na_idx] <- fill_val
    }
  }

  message("Imputed ", sum(is.na(expr_matrix)), " missing values using half-minimum strategy.")
  return(imputed_matrix)
}


#' @title Impute Missing Values by KNN Algorithm
#'
#' @description
#' 使用K近邻（K-Nearest Neighbors）算法对缺失值进行填充。KNN填充
#' 通过寻找与目标feature最相似的K个feature，使用它们的加权平均值
#' 来填充缺失值。该方法保留了feature之间的相关性结构，适用于
#' 转录组学和蛋白质组学数据。
#'
#' 该函数基于impute包的impute.knn函数实现，使用欧氏距离度量相似性。
#'
#' @param expr_matrix 数值矩阵，表达矩阵（行：feature，列：样本）
#' @param k 整数，近邻数，默认10
#' @param rowmax 数值，单行最大缺失比例，超过此值的行被删除，默认0.8
#' @param colmax 数值，单列最大缺失比例，超过此值的列被删除，默认0.8
#'
#' @return 返回KNN填充后的数值矩阵
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#'
#' # 使用KNN填充，k=10
#' imputed_expr <- impute_knn(expr, k = 10)
#'
#' # 使用更小的k值
#' imputed_expr <- impute_knn(expr, k = 5)
#' }
#'
#' @export
impute_knn <- function(expr_matrix, k = 10, rowmax = 0.8, colmax = 0.8) {
  if (!requireNamespace("impute", quietly = TRUE)) {
    stop("Package 'impute' is required for KNN imputation. ",
         "Please install it from Bioconductor: ",
         "BiocManager::install('impute')")
  }

  if (!any(is.na(expr_matrix))) {
    message("No NA values detected. No imputation performed.")
    return(expr_matrix)
  }

  # Remove rows/columns with too many NAs
  row_na_ratio <- rowMeans(is.na(expr_matrix))
  col_na_ratio <- colMeans(is.na(expr_matrix))

  keep_rows <- row_na_ratio <= rowmax
  keep_cols <- col_na_ratio <= colmax

  if (any(!keep_rows)) {
    message("Removed ", sum(!keep_rows), " features with >",
            round(rowmax * 100), "% missing values.")
  }
  if (any(!keep_cols)) {
    message("Removed ", sum(!keep_cols), " samples with >",
            round(colmax * 100), "% missing values.")
  }

  filtered_matrix <- expr_matrix[keep_rows, keep_cols, drop = FALSE]

  if (nrow(filtered_matrix) < k + 1) {
    warning("Too few features for KNN with k=", k, ". Falling back to half-min imputation.")
    return(impute_half_min(filtered_matrix))
  }

  imputed_result <- impute::impute.knn(as.matrix(filtered_matrix),
                                        k = min(k, nrow(filtered_matrix) - 1),
                                        rowmax = rowmax,
                                        colmax = colmax,
                                        maxp = nrow(filtered_matrix))

  message("KNN imputation completed with k=", k, ".")
  return(imputed_result$data)
}


#' @title Get Missing Value Statistics
#'
#' @description
#' 计算并返回表达矩阵中缺失值的统计信息，包括总体缺失比例、
#' 每个feature的缺失比例和每个样本的缺失比例。该函数用于
#' 数据质量评估和缺失值填充策略选择。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item overall_ratio: 总体缺失比例
#'   \item feature_ratio: 每个feature的缺失比例向量
#'   \item sample_ratio: 每个样本的缺失比例向量
#'   \item summary: 缺失值统计摘要
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' na_stats <- get_missing_stats(expr)
#' print(na_stats$summary)
#' }
#'
#' @export
get_missing_stats <- function(expr_matrix) {
  overall_ratio <- mean(is.na(expr_matrix))
  feature_ratio <- rowMeans(is.na(expr_matrix))
  sample_ratio <- colMeans(is.na(expr_matrix))

  summary_text <- paste(
    "Total cells:", prod(dim(expr_matrix)), "\n",
    "Missing cells:", sum(is.na(expr_matrix)), "\n",
    "Overall missing ratio:", round(overall_ratio * 100, 2), "%\n",
    "Features with >50% missing:", sum(feature_ratio > 0.5), "\n",
    "Samples with >50% missing:", sum(sample_ratio > 0.5)
  )

  return(list(
    overall_ratio = overall_ratio,
    feature_ratio = feature_ratio,
    sample_ratio = sample_ratio,
    summary = summary_text
  ))
}
