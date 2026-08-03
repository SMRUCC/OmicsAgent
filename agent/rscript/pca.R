# ==============================================================================
# OmicsFlow: PCA Analysis and Visualization
# ==============================================================================
# Principal Component Analysis with score plot
# ==============================================================================

#' Perform PCA analysis
#'
#' @description Performs Principal Component Analysis on the expression matrix.
#'   Returns scores, loadings, and variance explained.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param scale Logical, whether to scale features. Default: TRUE.
#' @param center Logical, whether to center features. Default: TRUE.
#' @param ncomp Number of components to compute. Default: min(n_samples - 1, 10).
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{pca_result}: prcomp result object.
#'     \item \code{scores}: Data.frame of PC scores (samples x components).
#'     \item \code{loadings}: Data.frame of PC loadings (features x components).
#'     \item \code{var_explained}: Numeric vector of variance explained (%).
#'     \item \code{ncomp}: Number of components computed.
#'   }
#'
#' @examples
#' \dontrun{
#' pca <- run_pca(expr_matrix)
#' print(pca$var_explained[1:3])
#' }
#'
#' @export
run_pca <- function(expr_matrix, scale = TRUE, center = TRUE,
                    ncomp = NULL) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # Transpose for PCA (samples as rows)
  data_t <- t(expr_matrix)

  # Remove features with zero variance
  feature_var <- apply(data_t, 2, stats::var, na.rm = TRUE)
  data_t <- data_t[, feature_var > 0, drop = FALSE]

  # Set number of components
  if (is.null(ncomp)) {
    ncomp <- min(nrow(data_t) - 1, ncol(data_t), 10)
  }

  # Perform PCA (compute all components for correct variance)
  pca_result <- stats::prcomp(data_t, scale. = scale, center = center)

  # Extract results
  scores <- as.data.frame(pca_result$x[, 1:ncomp, drop = FALSE])
  scores$sample_id <- rownames(scores)

  loadings <- as.data.frame(pca_result$rotation[, 1:ncomp, drop = FALSE])
  loadings$feature_id <- rownames(loadings)

  # Variance explained: use total variance (sum of all sdev^2)
  var_explained <- (pca_result$sdev^2 / sum(pca_result$sdev^2) * 100)[1:ncomp]

  return(list(
    pca_result = pca_result,
    scores = scores,
    loadings = loadings,
    var_explained = var_explained,
    ncomp = ncomp
  ))
}


#' Plot PCA score plot
#'
#' @description Creates a publication-quality PCA score plot using ggplot2.
#'
#' @param pca_result Result from \code{run_pca()}.
#' @param sample_info A data.frame with sample metadata.
#' @param color_col Column name for color grouping. Default: "sample_info".
#' @param shape_col Column name for shape grouping. Default: NULL.
#' @param pc_x Integer, which PC for x-axis. Default: 1.
#' @param pc_y Integer, which PC for y-axis. Default: 2.
#' @param show_ellipse Logical, whether to draw confidence ellipses. Default: TRUE.
#' @param ellipse_level Numeric, confidence level for ellipses. Default: 0.95.
#' @param show_labels Logical, whether to show sample labels. Default: FALSE.
#' @param label_col Column for labels. Default: "sample_name".
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' pca <- run_pca(expr_matrix)
#' p <- plot_pca_scores(pca, sample_info, color_col = "sample_info")
#' print(p)
#' }
#'
#' @export
plot_pca_scores <- function(pca_result, sample_info,
                            color_col = "sample_info", shape_col = NULL,
                            pc_x = 1, pc_y = 2,
                            show_ellipse = TRUE, ellipse_level = 0.95,
                            show_labels = FALSE, label_col = "sample_name") {
  # Get scores
  scores <- pca_result$scores
  var_explained <- pca_result$var_explained

  # Align sample info
  common_samples <- intersect(scores$sample_id, rownames(sample_info))
  scores <- scores[scores$sample_id %in% common_samples, ]
  sample_info <- sample_info[scores$sample_id, , drop = FALSE]

  # Prepare data
  pc_cols <- paste0("PC", c(pc_x, pc_y))
  plot_data <- data.frame(
    sample_id = scores$sample_id,
    PCx = scores[[pc_cols[1]]],
    PCy = scores[[pc_cols[2]]]
  )

  # Add color
  if (color_col %in% colnames(sample_info)) {
    plot_data$color <- sample_info[[color_col]]
  } else {
    plot_data$color <- "all"
  }

  # Add shape
  if (!is.null(shape_col) && shape_col %in% colnames(sample_info)) {
    plot_data$shape <- sample_info[[shape_col]]
  } else {
    plot_data$shape <- plot_data$color
  }

  # Add labels
  if (show_labels && label_col %in% colnames(sample_info)) {
    plot_data$label <- sample_info[[label_col]]
  } else {
    plot_data$label <- plot_data$sample_id
  }

  # Colors
  groups <- unique(plot_data$color)
  colors <- make_group_colors(groups)

  # Shapes
  n_shapes <- length(unique(plot_data$shape))
  shapes <- 0:(n_shapes - 1) %% 25 + 1

  # Build plot
  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = PCx, y = PCy)) +
    ggplot2::geom_point(ggplot2::aes(color = color, shape = shape),
                        size = 3, alpha = 0.85) +
    ggplot2::scale_color_manual(values = colors, name = color_col) +
    ggplot2::scale_shape_manual(values = shapes, name = ifelse(is.null(shape_col), color_col, shape_col)) +
    ggplot2::labs(
      title = "PCA Score Plot",
      x = paste0("PC", pc_x, " (", round(var_explained[pc_x], 1), "%)"),
      y = paste0("PC", pc_y, " (", round(var_explained[pc_y], 1), "%)")
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 11),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right",
      legend.text = ggplot2::element_text(size = 10),
      legend.title = ggplot2::element_text(size = 11)
    ) +
    ggplot2::coord_equal()

  # Add ellipses
  if (show_ellipse) {
    for (g in groups) {
      g_data <- plot_data[plot_data$color == g, , drop = FALSE]
      if (nrow(g_data) >= 3) {
        # Calculate ellipse using stat_ellipse equivalent
        # Using manual calculation for better control
        center <- c(mean(g_data$PCx), mean(g_data$PCy))
        cov_mat <- stats::cov(g_data[, c("PCx", "PCy")])

        # Skip if singular
        if (det(cov_mat) > 1e-10) {
          chi_sq <- stats::qchisq(ellipse_level, 2)
          eig <- eigen(cov_mat)
          n_pts <- 100
          angles <- seq(0, 2 * pi, length.out = n_pts)
          ellipse_df <- data.frame(
            PCx = center[1] + sqrt(chi_sq) * eig$vectors[1, 1] * sqrt(eig$values[1]) * cos(angles) +
                   sqrt(chi_sq) * eig$vectors[1, 2] * sqrt(eig$values[2]) * sin(angles),
            PCy = center[2] + sqrt(chi_sq) * eig$vectors[2, 1] * sqrt(eig$values[1]) * cos(angles) +
                   sqrt(chi_sq) * eig$vectors[2, 2] * sqrt(eig$values[2]) * sin(angles)
          )
          p <- p + ggplot2::geom_path(data = ellipse_df,
                                      ggplot2::aes(x = PCx, y = PCy),
                                      color = colors[g], linewidth = 0.6,
                                      linetype = "dashed", inherit.aes = FALSE)
        }
      }
    }
  }

  # Add labels
  if (show_labels) {
    p <- p + ggrepel::geom_text_repel(
      ggplot2::aes(label = label), size = 2.5, max.overlaps = 20
    )
  }

  return(p)
}


#' Plot PCA loading plot
#'
#' @description Creates a PCA loading plot showing feature contributions.
#'
#' @param pca_result Result from \code{run_pca()}.
#' @param pc_x Integer, which PC for x-axis. Default: 1.
#' @param pc_y Integer, which PC for y-axis. Default: 2.
#' @param top_n Integer, number of top features to label. Default: 10.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' p <- plot_pca_loadings(pca_result, top_n = 15)
#' }
#'
#' @export
plot_pca_loadings <- function(pca_result, pc_x = 1, pc_y = 2, top_n = 10) {
  loadings <- pca_result$loadings
  pc_cols <- paste0("PC", c(pc_x, pc_y))

  plot_data <- data.frame(
    feature_id = loadings$feature_id,
    loading_x = loadings[[pc_cols[1]]],
    loading_y = loadings[[pc_cols[2]]]
  )

  # Calculate distance from origin
  plot_data$dist <- sqrt(plot_data$loading_x^2 + plot_data$loading_y^2)

  # Select top features
  top_features <- plot_data[order(plot_data$dist, decreasing = TRUE), ][1:min(top_n, nrow(plot_data)), ]

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = loading_x, y = loading_y)) +
    ggplot2::geom_point(size = 1.5, alpha = 0.5, color = "#4a90d9") +
    ggrepel::geom_text_repel(
      data = top_features,
      ggplot2::aes(label = feature_id), size = 2.5, max.overlaps = 20
    ) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
    ggplot2::geom_vline(xintercept = 0, linetype = "dotted", color = "grey50") +
    ggplot2::labs(
      title = "PCA Loading Plot",
      x = paste0("PC", pc_x, " Loading"),
      y = paste0("PC", pc_y, " Loading")
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 11),
      axis.title = ggplot2::element_text(size = 12)
    )

  return(p)
}
