# ==============================================================================
# OmicsFlow: F-test Differential Analysis
# ==============================================================================
# Overall differential analysis using F-test
# ==============================================================================

#' F-test overall differential analysis
#'
#' @description Performs an F-test (one-way ANOVA) for each feature to test
#'   for overall differences among groups. Returns F-statistic, p-value, and
#'   adjusted p-value.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param group_col Column name for group labels. Default: "sample_info".
#' @param exclude_groups Optional character vector of groups to exclude.
#'   Default: "QC".
#' @param p_adj_method P-value adjustment method. Default: "BH".
#'
#' @return A data.frame with:
#'   \itemize{
#'     \item \code{feature_id}: Feature ID.
#'     \item \code{F_stat}: F-statistic.
#'     \item \code{p_value}: Raw p-value.
#'     \item \code{p_adj}: Adjusted p-value.
#'     \item \code{significant}: Logical, significance at p_adj < 0.05.
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
  # Align samples
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]

  # Exclude groups
  if (!is.null(exclude_groups)) {
    keep_samples <- rownames(sample_info)[!(sample_info[[group_col]] %in% exclude_groups)]
    expr_matrix <- expr_matrix[, keep_samples, drop = FALSE]
    sample_info <- sample_info[keep_samples, , drop = FALSE]
  }

  groups <- factor(sample_info[[group_col]])

  # Run F-test for each feature
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

  # Adjust p-values
  results$p_adj <- stats::p.adjust(results$p_value, method = p_adj_method)
  results$significant <- results$p_adj < 0.05

  # Set feature_id as row names
  rownames(results) <- results$feature_id
  results$feature_id <- NULL

  return(results)
}
