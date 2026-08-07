# ==============================================================================
# OmicsFlow: 缺失值过滤
# ==============================================================================
# 基于缺失值比例对特征进行过滤
# ==============================================================================

#' 按缺失值比例过滤特征
#'
#' @description 根据缺失值比例从表达矩阵中过滤掉特征（行）。提供两种策略：
#'   \itemize{
#'     \item \code{"group"}：按各分组的缺失比例过滤。仅当所有分组缺失比例都
#'       超过阈值时才移除该特征。
#'     \item \code{"overall"}：按全部样本的总体缺失比例过滤。
#'   }
#'
#' @param expr_matrix 数值矩阵（特征 x 样本），缺失值用 NA 表示。
#' @param sample_info 含有样本元数据的数据框。必须包含用于分组标签的
#'   \code{sample_info} 列。当 \code{method = "group"} 时必填。
#' @param threshold 数值型，缺失比例阈值（0-1）。缺失比例超过该值的特征将被
#'   移除。默认：0.8（即移除在超过 80% 样本中缺失的特征）。
#' @param method 字符型，过滤策略：\code{"group"} 或
#'   \code{"overall"}。默认："group"。
#' @param group_col sample_info 中用于分组的列名。默认："sample_info"。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{filtered_matrix}：过滤后的表达矩阵。
#'     \item \code{removed_features}：被移除特征 ID 的字符向量。
#'     \item \code{kept_features}：保留特征 ID 的字符向量。
#'     \item \code{missing_report}：含每个特征缺失比例的数据框。
#'   }
#'
#' @examples
#' \dontrun{
#' # 过滤在所有分组中缺失比例超过 80% 的特征
#' result <- filter_missing_values(expr_matrix, sample_info, threshold = 0.8)
#' filtered_mat <- result$filtered_matrix
#'
#' # 按总体缺失比例过滤
#' result <- filter_missing_values(expr_matrix, sample_info,
#'                                  threshold = 0.3, method = "overall")
#' }
#'
#' @export
filter_missing_values <- function(expr_matrix, sample_info = NULL,
                                   threshold = 0.8, method = "group",
                                   group_col = "sample_info",
                                   exclude_groups = NULL) {
  # 校验输入
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  if (!method %in% c("group", "overall")) {
    stop("method must be 'group' or 'overall'")
  }

  # 排除特定分组（例如 QC 质控组）
  if (!is.null(exclude_groups) && !is.null(sample_info)) {
    common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
    expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
    sample_info <- sample_info[common_samples, , drop = FALSE]
    keep_samples <- rownames(sample_info)[!(sample_info[[group_col]] %in% exclude_groups)]
    expr_matrix <- expr_matrix[, keep_samples, drop = FALSE]
    sample_info <- sample_info[keep_samples, , drop = FALSE]
  }

  # 计算缺失比例
  if (method == "group") {
    if (is.null(sample_info)) {
      stop("sample_info is required when method = 'group'")
    }
    if (!group_col %in% colnames(sample_info)) {
      stop(paste("Column", group_col, "not found in sample_info"))
    }

    # 对齐样本
    common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
    if (length(common_samples) == 0) {
      stop("No common samples between expr_matrix and sample_info")
    }
    expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
    sample_info <- sample_info[common_samples, , drop = FALSE]

    groups <- unique(as.character(sample_info[[group_col]]))
    n_groups <- length(groups)

    # 计算各分组的缺失比例
    group_missing <- matrix(NA, nrow = nrow(expr_matrix), ncol = n_groups,
                            dimnames = list(rownames(expr_matrix), groups))

    for (g in groups) {
      g_samples <- rownames(sample_info)[sample_info[[group_col]] == g]
      g_mat <- expr_matrix[, g_samples, drop = FALSE]
      group_missing[, g] <- rowMeans(is.na(g_mat) | g_mat == 0)
    }

    # 仅当所有分组都超过阈值时才移除该特征
    remove_mask <- apply(group_missing, 1, function(x) all(x > threshold))

    missing_report <- data.frame(
      feature_id = rownames(expr_matrix),
      group_missing,
      overall_missing = rowMeans(is.na(expr_matrix) | expr_matrix == 0),
      removed = remove_mask,
      stringsAsFactors = FALSE
    )

  } else {
    # 总体法
    overall_missing <- rowMeans(is.na(expr_matrix) | expr_matrix == 0)
    remove_mask <- overall_missing > threshold

    missing_report <- data.frame(
      feature_id = rownames(expr_matrix),
      overall_missing = overall_missing,
      removed = remove_mask,
      stringsAsFactors = FALSE
    )
  }

  # 过滤
  kept_idx <- !remove_mask
  filtered_matrix <- expr_matrix[kept_idx, , drop = FALSE]

  return(list(
    filtered_matrix = filtered_matrix,
    removed_features = rownames(expr_matrix)[remove_mask],
    kept_features = rownames(expr_matrix)[kept_idx],
    missing_report = missing_report
  ))
}
