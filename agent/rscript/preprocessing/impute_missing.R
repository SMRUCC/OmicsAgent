# ==============================================================================
# OmicsFlow: Missing Value Imputation
# ==============================================================================
# Impute missing values in expression matrix
# ==============================================================================

#' Impute missing values using minimum positive value half
#'
#' @description Fills missing values (NA and optionally zero) with half of the
#'   minimum positive value of each feature. This is a simple and widely used
#'   imputation strategy in metabolomics.
#'
#' @param expr_matrix A numeric matrix (features x samples) with NA for
#'   missing values.
#' @param treat_zero_as_missing Logical, whether to treat zero values as
#'   missing. Default: TRUE.
#' @param factor Numeric, multiplier for the minimum positive value.
#'   Default: 0.5 (half).
#'
#' @return A numeric matrix with missing values imputed.
#'
#' @examples
#' \dontrun{
#' mat_imputed <- impute_min_half(expr_matrix)
#' }
#'
#' @export
impute_min_half <- function(expr_matrix, treat_zero_as_missing = TRUE,
                            factor = 0.5) {
  # Convert to matrix if needed
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # Treat zeros as NA if specified
  if (treat_zero_as_missing) {
    expr_matrix[expr_matrix == 0] <- NA
  }

  # Impute per feature
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
        # All values are NA - fill with 0
        expr_matrix[i, na_mask] <- 0
      }
    }
  }

  return(expr_matrix)
}


#' Impute missing values using KNN
#'
#' @description Fills missing values using K-Nearest Neighbors imputation.
#'   Uses the \code{impute} package's KNN implementation.
#'
#' @param expr_matrix A numeric matrix (features x samples) with NA for
#'   missing values.
#' @param k Number of nearest neighbors. Default: 10.
#' @param treat_zero_as_missing Logical, whether to treat zero values as
#'   missing. Default: TRUE.
#' @param max_na_prop Maximum proportion of NA allowed per feature. Features
#'   exceeding this are removed. Default: 0.5.
#'
#' @return A numeric matrix with missing values imputed.
#'
#' @examples
#' \dontrun{
#' mat_imputed <- impute_knn(expr_matrix, k = 10)
#' }
#'
#' @export
impute_knn <- function(expr_matrix, k = 10, treat_zero_as_missing = TRUE,
                       max_na_prop = 0.5) {
  # Convert to matrix if needed
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # Treat zeros as NA if specified
  if (treat_zero_as_missing) {
    expr_matrix[expr_matrix == 0] <- NA
  }

  # Remove features with too many NAs
  na_prop <- rowMeans(is.na(expr_matrix))
  high_na_features <- rownames(expr_matrix)[na_prop > max_na_prop]
  if (length(high_na_features) > 0) {
    warning(paste("Removing", length(high_na_features),
                  "features with >", max_na_prop, "NA proportion"))
    expr_matrix <- expr_matrix[na_prop <= max_na_prop, , drop = FALSE]
  }

  # Check if impute package is available
  if (!requireNamespace("impute", quietly = TRUE)) {
    # Fallback: use simple KNN implementation
    warning("Package 'impute' not available. Using simple KNN implementation.")
    return(.impute_knn_simple(expr_matrix, k))
  }

  # Use impute.knn
  result <- impute::impute.knn(as.matrix(expr_matrix), k = k,
                                maxp = nrow(expr_matrix))
  return(result$data)
}


#' Simple KNN imputation (internal fallback)
#'
#' @keywords internal
#' @noRd
.impute_knn_simple <- function(mat, k) {
  # Calculate distance matrix between features
  # For each feature with NAs, find k nearest features and impute
  for (i in 1:nrow(mat)) {
    na_mask <- is.na(mat[i, ])
    if (!any(na_mask)) next

    # Calculate correlations with other features
    other_features <- mat[-i, , drop = FALSE]
    correlations <- apply(other_features, 1, function(x) {
      common <- !is.na(mat[i, ]) & !is.na(x)
      if (sum(common) < 2) return(0)
      cor(mat[i, common], x[common], use = "everything")
    })

    # Get k nearest (highest absolute correlation)
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
