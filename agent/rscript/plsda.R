# ==============================================================================
# OmicsFlow: PLS-DA Analysis and Visualization
# ==============================================================================
# Partial Least Squares Discriminant Analysis
# ==============================================================================

#' Perform PLS-DA analysis
#'
#' @description Performs Partial Least Squares Discriminant Analysis (PLS-DA)
#'   on the expression matrix. PLS-DA is a supervised method that maximizes
#'   separation between predefined groups.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param group_col Column name for group labels. Default: "sample_info".
#' @param ncomp Number of components. Default: 2.
#' @param exclude_groups Optional character vector of groups to exclude
#'   (e.g., "QC"). Default: NULL.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{scores}: Data.frame of PLS-DA scores.
#'     \item \code{loadings}: Data.frame of PLS-DA loadings.
#'     \item \code{vip}: VIP scores data.frame.
#'     \item \code{model}: PLS-DA model object.
#'     \item \code{groups}: Group levels.
#'   }
#'
#' @examples
#' \dontrun{
#' plsda <- run_plsda(expr_matrix, sample_info, ncomp = 3)
#' print(head(plsda$vip))
#' }
#'
#' @export
run_plsda <- function(expr_matrix, sample_info, group_col = "sample_info",
                     ncomp = 2, exclude_groups = NULL) {
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

  # Get group factor
  groups <- factor(sample_info[[group_col]])

  # Transpose for analysis
  X <- t(expr_matrix)

  # Use mixOmics if available, otherwise use base pls
  if (requireNamespace("mixOmics", quietly = TRUE)) {
    model <- mixOmics::plsda(X, groups, ncomp = ncomp)
    scores <- as.data.frame(model$variates$X)
    scores$sample_id <- rownames(scores)
    scores$group <- as.character(groups)

    # VIP calculation
    vip_scores <- .calculate_vip(model)
    loadings <- as.data.frame(model$loadings$X)
    loadings$feature_id <- rownames(loadings)

  } else {
    # Fallback: use base PLS implementation
    warning("Package 'mixOmics' not available. Using base PLS implementation.")
    result <- .plsda_base(X, groups, ncomp = ncomp)
    model <- result$model
    scores <- as.data.frame(result$scores)
    scores$sample_id <- rownames(scores)
    scores$group <- as.character(groups)
    vip_scores <- result$vip
    loadings <- as.data.frame(result$loadings)
    loadings$feature_id <- rownames(loadings)
  }

  # Prepare VIP data.frame
  vip_df <- data.frame(
    feature_id = rownames(expr_matrix),
    vip = vip_scores,
    stringsAsFactors = FALSE
  )
  vip_df <- vip_df[order(vip_df$vip, decreasing = TRUE), ]
  rownames(vip_df) <- vip_df$feature_id
  vip_df$feature_id <- NULL

  return(list(
    scores = scores,
    loadings = loadings,
    vip = vip_df,
    model = model,
    groups = levels(groups)
  ))
}


#' Calculate VIP scores (internal)
#'
#' @keywords internal
#' @noRd
.calculate_vip <- function(model) {
  # VIP calculation based on mixOmics
  if (inherits(model, "mixo_plsda") || inherits(model, "mixo_pls")) {
    # Get the full VIP matrix
    vip <- mixOmics::vip(model)
    if (is.matrix(vip)) {
      return(vip[, ncol(vip)])
    } else {
      return(vip)
    }
  } else {
    return(rep(1, nrow(model$loadings)))
  }
}


#' Base PLS-DA implementation (internal fallback)
#'
#' @keywords internal
#' @noRd
.plsda_base <- function(X, Y, ncomp = 2) {
  # Simple NIPALS PLS
  X <- as.matrix(X)

  # Dummy matrix for Y
  if (is.factor(Y)) {
    Y_dummy <- model.matrix(~ 0 + Y)
    colnames(Y_dummy) <- levels(Y)
  } else {
    Y_dummy <- as.matrix(Y)
  }

  n <- nrow(X)
  p <- ncol(X)
  q <- ncol(Y_dummy)

  # Initialize
  scores_mat <- matrix(0, n, ncomp)
  loadings_mat <- matrix(0, p, ncomp)
  Y_loadings <- matrix(0, q, ncomp)

  X_k <- X
  Y_k <- Y_dummy

  for (a in 1:ncomp) {
    # SVD of cross-product
    cross <- crossprod(X_k, Y_k)
    svd_result <- svd(cross)
    wa <- svd_result$u[, 1]
    ta <- X_k %*% wa
    ta <- ta / sqrt(sum(ta^2))
    pa <- crossprod(X_k, ta) / as.numeric(crossprod(ta))
    qa <- crossprod(Y_k, ta) / as.numeric(crossprod(ta))

    scores_mat[, a] <- as.vector(ta)
    loadings_mat[, a] <- as.vector(pa)
    Y_loadings[, a] <- as.vector(qa)

    # Deflation
    X_k <- X_k - tcrossprod(ta, pa)
    Y_k <- Y_k - tcrossprod(ta, qa)
  }

  colnames(scores_mat) <- paste0("comp", 1:ncomp)
  colnames(loadings_mat) <- paste0("comp", 1:ncomp)
  rownames(loadings_mat) <- colnames(X)

  # Simple VIP calculation
  # VIP_i = sqrt(p * sum_a(SSY_a * w_ia^2) / sum_a(SSY_a))
  SSY <- colSums(Y_loadings^2)
  vip <- sqrt(p * rowSums(sweep(loadings_mat^2, 2, SSY, "*")) / sum(SSY))

  return(list(
    model = list(
      scores = scores_mat,
      loadings = loadings_mat,
      Y_loadings = Y_loadings
    ),
    scores = scores_mat,
    loadings = loadings_mat,
    vip = vip
  ))
}


#' Plot PLS-DA score plot
#'
#' @description Creates a publication-quality PLS-DA score plot.
#'
#' @param plsda_result Result from \code{run_plsda()}.
#' @param sample_info Sample metadata data.frame.
#' @param color_col Column for color grouping. Default: "sample_info".
#' @param comp_x Component for x-axis. Default: 1.
#' @param comp_y Component for y-axis. Default: 2.
#' @param show_ellipse Logical, show confidence ellipses. Default: TRUE.
#' @param show_labels Logical, show sample labels. Default: FALSE.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' plsda <- run_plsda(expr_matrix, sample_info)
#' p <- plot_plsda_scores(plsda, sample_info)
#' }
#'
#' @export
plot_plsda_scores <- function(plsda_result, sample_info,
                              color_col = "sample_info",
                              comp_x = 1, comp_y = 2,
                              show_ellipse = TRUE, show_labels = FALSE) {
  scores <- plsda_result$scores

  comp_cols <- paste0("comp", c(comp_x, comp_y))
  if (!comp_cols[1] %in% colnames(scores)) {
    comp_cols <- paste0("Comp", c(comp_x, comp_y))
  }

  plot_data <- data.frame(
    sample_id = scores$sample_id,
    comp_x = scores[[comp_cols[1]]],
    comp_y = scores[[comp_cols[2]]],
    group = scores$group
  )

  # Colors
  groups <- unique(plot_data$group)
  colors <- make_group_colors(groups)

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = comp_x, y = comp_y)) +
    ggplot2::geom_point(ggplot2::aes(color = group), size = 3, alpha = 0.85) +
    ggplot2::scale_color_manual(values = colors) +
    ggplot2::labs(
      title = "PLS-DA Score Plot",
      x = paste0("Component ", comp_x),
      y = paste0("Component ", comp_y)
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 11),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right"
    ) +
    ggplot2::coord_equal()

  # Ellipses
  if (show_ellipse) {
    for (g in groups) {
      g_data <- plot_data[plot_data$group == g, , drop = FALSE]
      if (nrow(g_data) >= 3) {
        center <- c(mean(g_data$comp_x), mean(g_data$comp_y))
        cov_mat <- stats::cov(g_data[, c("comp_x", "comp_y")])
        if (det(cov_mat) > 1e-10) {
          chi_sq <- stats::qchisq(0.95, 2)
          eig <- eigen(cov_mat)
          angles <- seq(0, 2 * pi, length.out = 100)
          ellipse_df <- data.frame(
            comp_x = center[1] + sqrt(chi_sq) * eig$vectors[1, 1] * sqrt(eig$values[1]) * cos(angles) +
                      sqrt(chi_sq) * eig$vectors[1, 2] * sqrt(eig$values[2]) * sin(angles),
            comp_y = center[2] + sqrt(chi_sq) * eig$vectors[2, 1] * sqrt(eig$values[1]) * cos(angles) +
                      sqrt(chi_sq) * eig$vectors[2, 2] * sqrt(eig$values[2]) * sin(angles)
          )
          p <- p + ggplot2::geom_path(data = ellipse_df,
                                      ggplot2::aes(x = comp_x, y = comp_y),
                                      color = colors[g], linewidth = 0.6,
                                      linetype = "dashed", inherit.aes = FALSE)
        }
      }
    }
  }

  if (show_labels) {
    p <- p + ggrepel::geom_text_repel(
      ggplot2::aes(label = sample_id), size = 2.5, max.overlaps = 20
    )
  }

  return(p)
}


#' Plot VIP scores
#'
#' @description Creates a bar plot of top VIP scores from PLS-DA.
#'
#' @param plsda_result Result from \code{run_plsda()}.
#' @param top_n Number of top features to show. Default: 20.
#' @param threshold VIP threshold line. Default: 1.0.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' p <- plot_vip(plsda_result, top_n = 30)
#' }
#'
#' @export
plot_vip <- function(plsda_result, top_n = 20, threshold = 1.0) {
  vip_df <- plsda_result$vip
  top_df <- head(vip_df, top_n)

  # Reorder
  top_df$feature_id <- factor(rownames(top_df),
                               levels = rownames(top_df)[nrow(top_df):1])

  p <- ggplot2::ggplot(top_df, ggplot2::aes(x = feature_id, y = vip)) +
    ggplot2::geom_bar(stat = "identity", fill = "#4a90d9") +
    ggplot2::geom_hline(yintercept = threshold, color = "#e74c3c",
                        linetype = "dashed", linewidth = 0.8) +
    ggplot2::coord_flip() +
    ggplot2::labs(
      title = "VIP Scores (Top Features)",
      x = "Feature",
      y = "VIP Score"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 9),
      axis.title = ggplot2::element_text(size = 12)
    )

  return(p)
}
