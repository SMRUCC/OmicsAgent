# ==============================================================================
# OmicsFlow: Data Scaling
# ==============================================================================
# Scale expression data across features
# ==============================================================================

#' Scale by feature median (centering)
#'
#' @description Centers each feature (row) by its median value. This is
#'   commonly used in metabolomics to make feature values comparable.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param scale Logical, whether to also scale by MAD (median absolute
#'   deviation). Default: FALSE.
#'
#' @return A numeric matrix with median-centered features.
#'
#' @examples
#' \dontrun{
#' # Median centering only
#' mat_scaled <- scale_feature_median(expr_matrix)
#'
#' # Median centering + MAD scaling
#' mat_scaled <- scale_feature_median(expr_matrix, scale = TRUE)
#' }
#'
#' @export
scale_feature_median <- function(expr_matrix, scale = FALSE) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # Median center
  row_medians <- apply(expr_matrix, 1, stats::median, na.rm = TRUE)
  centered <- expr_matrix - row_medians

  if (scale) {
    # Scale by MAD
    row_mads <- apply(expr_matrix, 1, stats::mad, na.rm = TRUE)
    row_mads[row_mads == 0] <- 1
    centered <- centered / row_mads
  }

  return(centered)
}


#' Scale by feature mean (z-score)
#'
#' @description Standardizes each feature (row) using z-score: subtract mean
#'   and divide by standard deviation.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#'
#' @return A numeric matrix with z-scored features.
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

  # Use base scale function (operates on columns, so transpose)
  scaled <- t(scale(t(expr_matrix)))

  # Replace NaN with 0
  scaled[is.nan(scaled)] <- 0

  return(scaled)
}


#' Scale by feature range (min-max)
#'
#' @description Scales each feature (row) to [0, 1] range using min-max
#'   normalization.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#'
#' @return A numeric matrix with min-max scaled features.
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


#' Pareto scaling
#'
#' @description Applies Pareto scaling: mean centering followed by division by
#'   the square root of the standard deviation. Widely used in metabolomics.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#'
#' @return A numeric matrix with Pareto-scaled features.
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
