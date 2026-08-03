# ==============================================================================
# OmicsFlow: Data Normalization
# ==============================================================================
# Normalize expression data
# ==============================================================================

#' Normalize by sample total (relative abundance)
#'
#' @description Normalizes each sample by its total sum, converting values to
#'   relative abundance. This is commonly used in metabolomics and microbiome
#'   data to correct for differences in total signal intensity between samples.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param scale_factor Numeric, scaling factor. Default: 1e6 (for ppm).
#'   Use 1 for proportional values, 1e6 for parts-per-million.
#' @param multiply_by Numeric multiplier applied after normalization.
#'   Default: 1e6.
#'
#' @return A numeric matrix normalized by sample total.
#'
#' @examples
#' \dontrun{
#' # Normalize to relative abundance (proportions summing to 1)
#' mat_norm <- normalize_sample_total(expr_matrix, multiply_by = 1)
#'
#' # Normalize to parts-per-million
#' mat_norm <- normalize_sample_total(expr_matrix, multiply_by = 1e6)
#' }
#'
#' @export
normalize_sample_total <- function(expr_matrix, scale_factor = 1, multiply_by = 1e6) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # Calculate column sums
  col_sums <- colSums(expr_matrix, na.rm = TRUE)

  # Avoid division by zero
  col_sums[col_sums == 0] <- 1

  # Normalize
  normalized <- t(t(expr_matrix) / col_sums) * multiply_by

  return(normalized)
}


#' Normalize by median (sample median)
#'
#' @description Normalizes each sample by its median value.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#'
#' @return A numeric matrix normalized by sample median.
#'
#' @examples
#' \dontrun{
#' mat_norm <- normalize_median(expr_matrix)
#' }
#'
#' @export
normalize_median <- function(expr_matrix) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  col_medians <- apply(expr_matrix, 2, stats::median, na.rm = TRUE)
  col_medians[col_medians == 0] <- 1

  normalized <- t(t(expr_matrix) / col_medians)

  return(normalized)
}
