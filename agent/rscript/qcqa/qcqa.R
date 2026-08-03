# ==============================================================================
# OmicsFlow: QC/QA Assessment
# ==============================================================================
# Quality control and quality assessment functions
# ==============================================================================

#' Calculate QC sample variation
#'
#' @description Calculates the coefficient of variation (CV) for QC samples to
#'   assess data acquisition stability. Features with high CV in QC samples
#'   indicate poor analytical reproducibility.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param qc_group Character, the group label for QC samples in
#'   \code{sample_info[[group_col]]}. Default: "QC".
#' @param group_col Column name in sample_info for group labels.
#'   Default: "sample_info".
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{qc_cv}: Named numeric vector of CV (%) per feature.
#'     \item \code{qc_mean}: Named numeric vector of mean per feature.
#'     \item \code{qc_sd}: Named numeric vector of SD per feature.
#'     \item \code{summary}: Data.frame with QC statistics.
#'     \item \code{plot}: ggplot object showing CV distribution.
#'   }
#'
#' @examples
#' \dontrun{
#' qc_result <- qc_variation(expr_matrix, sample_info, qc_group = "QC")
#' print(qc_result$summary)
#' }
#'
#' @export
qc_variation <- function(expr_matrix, sample_info, qc_group = "QC",
                         group_col = "sample_info") {
  # Validate
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # Align samples
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]

  # Get QC samples
  qc_samples <- rownames(sample_info)[sample_info[[group_col]] == qc_group]
  if (length(qc_samples) == 0) {
    stop(paste("No QC samples found for group:", qc_group))
  }

  qc_data <- expr_matrix[, qc_samples, drop = FALSE]

  # Calculate statistics
  qc_mean <- rowMeans(qc_data, na.rm = TRUE)
  qc_sd <- apply(qc_data, 1, stats::sd, na.rm = TRUE)
  qc_cv <- (qc_sd / abs(qc_mean)) * 100  # CV as percentage

  # Summary data.frame
  summary_df <- data.frame(
    feature_id = rownames(qc_data),
    qc_mean = qc_mean,
    qc_sd = qc_sd,
    qc_cv = qc_cv,
    stringsAsFactors = FALSE
  )

  # Plot: CV distribution
  cv_df <- data.frame(cv = qc_cv)
  p <- ggplot2::ggplot(cv_df, ggplot2::aes(x = cv)) +
    ggplot2::geom_histogram(bins = 50, fill = "#4a90d9", color = "white") +
    ggplot2::geom_vline(xintercept = 30, color = "#e74c3c", linetype = "dashed",
                        linewidth = 0.8) +
    ggplot2::labs(
      title = "QC Sample Coefficient of Variation",
      x = "CV (%)", y = "Feature Count"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 11),
      axis.title = ggplot2::element_text(size = 12)
    )

  return(list(
    qc_cv = qc_cv,
    qc_mean = qc_mean,
    qc_sd = qc_sd,
    summary = summary_df,
    plot = p
  ))
}


#' PCA-based QC assessment
#'
#' @description Performs PCA on the full dataset (including QC samples) to
#'   visually assess data quality. QC samples should cluster tightly in the
#'   PCA score plot if data quality is good.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param qc_group Character, QC group label. Default: "QC".
#' @param group_col Column name for group labels. Default: "sample_info".
#' @param color_col Column name for color grouping. Default: group_col.
#' @param scale Logical, whether to scale features. Default: TRUE.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{pca_result}: PCA result object.
#'     \item \code{scores}: PC scores data.frame.
#'     \item \code{qc_dispersion}: Dispersion of QC samples (mean distance to QC centroid).
#'     \item \code{plot}: ggplot PCA score plot with QC highlighted.
#'   }
#'
#' @examples
#' \dontrun{
#' qc_pca <- qc_pca_assessment(expr_matrix, sample_info, qc_group = "QC")
#' print(qc_pca$plot)
#' }
#'
#' @export
qc_pca_assessment <- function(expr_matrix, sample_info, qc_group = "QC",
                              group_col = "sample_info", color_col = NULL,
                              scale = TRUE) {
  # Validate
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]

  # Perform PCA
  pca_result <- stats::prcomp(t(expr_matrix), scale. = scale, center = TRUE)

  # Extract scores
  scores <- as.data.frame(pca_result$x[, 1:2])
  colnames(scores) <- c("PC1", "PC2")
  scores$sample_id <- rownames(scores)
  scores$group <- sample_info[rownames(scores), group_col]

  # Color column
  if (is.null(color_col)) color_col <- group_col
  if (color_col %in% colnames(sample_info)) {
    scores$color_group <- sample_info[rownames(scores), color_col]
  } else {
    scores$color_group <- scores$group
  }

  # QC dispersion
  qc_scores <- scores[scores$group == qc_group, ]
  if (nrow(qc_scores) > 0) {
    qc_centroid <- colMeans(qc_scores[, c("PC1", "PC2")])
    qc_dist <- sqrt(rowSums((qc_scores[, c("PC1", "PC2")] - qc_centroid)^2))
    qc_dispersion <- mean(qc_dist)
  } else {
    qc_dispersion <- NA
  }

  # Variance explained
  var_explained <- pca_result$sdev^2 / sum(pca_result$sdev^2) * 100

  # Colors
  groups <- unique(scores$color_group)
  colors <- make_group_colors(groups)

  # Plot
  p <- ggplot2::ggplot(scores, ggplot2::aes(x = PC1, y = PC2)) +
    ggplot2::geom_point(ggplot2::aes(color = color_group, shape = group),
                        size = 3) +
    ggplot2::scale_color_manual(values = colors) +
    ggplot2::labs(
      title = "PCA Score Plot (QC Assessment)",
      x = paste0("PC1 (", round(var_explained[1], 1), "%)"),
      y = paste0("PC2 (", round(var_explained[2], 1), "%)")
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      legend.position = "right"
    ) +
    ggplot2::coord_equal()

  # Add QC ellipse if enough QC samples
  if (nrow(qc_scores) >= 3) {
    # Calculate 95% confidence ellipse for QC
    qc_mat <- as.matrix(qc_scores[, c("PC1", "PC2")])
    if (nrow(qc_mat) >= 3) {
      # Simple ellipse using mean and covariance
      centroid <- colMeans(qc_mat)
      cov_mat <- cov(qc_mat)
      eig <- eigen(cov_mat)
      # 95% CI radius
      chi_sq <- stats::qchisq(0.95, 2)
      n_pts <- 100
      angles <- seq(0, 2 * pi, length.out = n_pts)
      ellipse_pts <- data.frame(
        PC1 = centroid[1] + sqrt(chi_sq) * eig$vectors[1, 1] * eig$values[1] * cos(angles) +
              sqrt(chi_sq) * eig$vectors[1, 2] * eig$values[2] * sin(angles),
        PC2 = centroid[2] + sqrt(chi_sq) * eig$vectors[2, 1] * eig$values[1] * cos(angles) +
              sqrt(chi_sq) * eig$vectors[2, 2] * eig$values[2] * sin(angles)
      )
      p <- p + ggplot2::geom_path(data = ellipse_pts,
                                  ggplot2::aes(x = PC1, y = PC2),
                                  color = colors[qc_group], linewidth = 0.8)
    }
  }

  return(list(
    pca_result = pca_result,
    scores = scores,
    qc_dispersion = qc_dispersion,
    var_explained = var_explained,
    plot = p
  ))
}
