# ==============================================================================
# OmicsFlow: Missing Value Filtering
# ==============================================================================
# Filter features based on missing value proportion
# ==============================================================================

#' Filter features by missing value proportion
#'
#' @description Filters features (rows) from the expression matrix based on
#'   missing value proportion. Two strategies are available:
#'   \itemize{
#'     \item \code{"group"}: Filter by per-group missing proportion. A feature
#'       is removed only if ALL groups have missing proportion exceeding the
#'       threshold.
#'     \item \code{"overall"}: Filter by overall missing proportion across
#'       all samples.
#'   }
#'
#' @param expr_matrix A numeric matrix (features x samples) with NA for
#'   missing values.
#' @param sample_info A data.frame with sample metadata. Must contain a
#'   \code{sample_info} column for group labels. Required for
#'   \code{method = "group"}.
#' @param threshold Numeric, missing proportion threshold (0-1). Features with
#'   missing proportion exceeding this value are removed. Default: 0.8 (i.e.,
#'   remove features missing in more than 80% of samples).
#' @param method Character, filtering strategy: \code{"group"} or
#'   \code{"overall"}. Default: "group".
#' @param group_col Column name in sample_info for grouping. Default: "sample_info".
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{filtered_matrix}: Filtered expression matrix.
#'     \item \code{removed_features}: Character vector of removed feature IDs.
#'     \item \code{kept_features}: Character vector of kept feature IDs.
#'     \item \code{missing_report}: Data.frame with missing proportions per feature.
#'   }
#'
#' @examples
#' \dontrun{
#' # Filter features missing in >80% of samples in ALL groups
#' result <- filter_missing_values(expr_matrix, sample_info, threshold = 0.8)
#' filtered_mat <- result$filtered_matrix
#'
#' # Filter by overall missing proportion
#' result <- filter_missing_values(expr_matrix, sample_info,
#'                                  threshold = 0.3, method = "overall")
#' }
#'
#' @export
filter_missing_values <- function(expr_matrix, sample_info = NULL,
                                   threshold = 0.8, method = "group",
                                   group_col = "sample_info",
                                   exclude_groups = NULL) {
  # Validate inputs
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  if (!method %in% c("group", "overall")) {
    stop("method must be 'group' or 'overall'")
  }

  # Exclude specific groups (e.g., QC)
  if (!is.null(exclude_groups) && !is.null(sample_info)) {
    common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
    expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
    sample_info <- sample_info[common_samples, , drop = FALSE]
    keep_samples <- rownames(sample_info)[!(sample_info[[group_col]] %in% exclude_groups)]
    expr_matrix <- expr_matrix[, keep_samples, drop = FALSE]
    sample_info <- sample_info[keep_samples, , drop = FALSE]
  }

  # Calculate missing proportions
  if (method == "group") {
    if (is.null(sample_info)) {
      stop("sample_info is required when method = 'group'")
    }
    if (!group_col %in% colnames(sample_info)) {
      stop(paste("Column", group_col, "not found in sample_info"))
    }

    # Align samples
    common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
    if (length(common_samples) == 0) {
      stop("No common samples between expr_matrix and sample_info")
    }
    expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
    sample_info <- sample_info[common_samples, , drop = FALSE]

    groups <- unique(as.character(sample_info[[group_col]]))
    n_groups <- length(groups)

    # Calculate per-group missing proportions
    group_missing <- matrix(NA, nrow = nrow(expr_matrix), ncol = n_groups,
                            dimnames = list(rownames(expr_matrix), groups))

    for (g in groups) {
      g_samples <- rownames(sample_info)[sample_info[[group_col]] == g]
      g_mat <- expr_matrix[, g_samples, drop = FALSE]
      group_missing[, g] <- rowMeans(is.na(g_mat) | g_mat == 0)
    }

    # A feature is removed only if ALL groups exceed the threshold
    remove_mask <- apply(group_missing, 1, function(x) all(x > threshold))

    missing_report <- data.frame(
      feature_id = rownames(expr_matrix),
      group_missing,
      overall_missing = rowMeans(is.na(expr_matrix) | expr_matrix == 0),
      removed = remove_mask,
      stringsAsFactors = FALSE
    )

  } else {
    # Overall method
    overall_missing <- rowMeans(is.na(expr_matrix) | expr_matrix == 0)
    remove_mask <- overall_missing > threshold

    missing_report <- data.frame(
      feature_id = rownames(expr_matrix),
      overall_missing = overall_missing,
      removed = remove_mask,
      stringsAsFactors = FALSE
    )
  }

  # Filter
  kept_idx <- !remove_mask
  filtered_matrix <- expr_matrix[kept_idx, , drop = FALSE]

  return(list(
    filtered_matrix = filtered_matrix,
    removed_features = rownames(expr_matrix)[remove_mask],
    kept_features = rownames(expr_matrix)[kept_idx],
    missing_report = missing_report
  ))
}
