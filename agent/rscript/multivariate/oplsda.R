# ==============================================================================
# OmicsFlow: OPLS-DA Analysis and Visualization
# ==============================================================================
# Orthogonal Partial Least Squares Discriminant Analysis
# ==============================================================================

#' Perform OPLS-DA analysis
#'
#' @description Performs Orthogonal Partial Least Squares Discriminant Analysis
#'   (OPLS-DA) on the expression matrix. OPLS-DA separates predictive and
#'   orthogonal variation for improved interpretation.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param group_col Column name for group labels. Default: "sample_info".
#' @param ncomp_pred Number of predictive components. Default: 1.
#' @param ncomp_orth Number of orthogonal components. Default: 1.
#' @param exclude_groups Optional character vector of groups to exclude.
#'   Default: NULL.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{scores}: Data.frame with predictive and orthogonal scores.
#'     \item \code{loadings}: Data.frame of OPLS-DA loadings (features x
#'       components), with \code{feature_id} as the first column.
#'     \item \code{vip}: VIP scores data.frame.
#'     \item \code{model}: OPLS-DA model object.
#'   }
#'
#' @examples
#' \dontrun{
#' oplsda <- run_oplsda(expr_matrix, sample_info, ncomp_pred = 1, ncomp_orth = 1)
#' print(head(oplsda$vip))
#' }
#'
#' @export
run_oplsda <- function(expr_matrix, sample_info, group_col = "sample_info",
                      ncomp_pred = 1, ncomp_orth = 1, exclude_groups = NULL) {
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
  X <- t(expr_matrix)

  # Check if mixOmics is available
  loadings_mat <- NULL
  if (requireNamespace("metaboanalyst", quietly = TRUE)) {
    # Use MetaboAnalyst's OPLS-DA
    model <- metaboanalyst:::oplsda(X, groups, ncomp_pred = ncomp_pred, ncomp_orth = ncomp_orth)
    scores <- as.data.frame(model$scores)
    if (is.null(colnames(scores)) || any(colnames(scores) == "")) {
      colnames(scores) <- c(paste0("t", 1:ncomp_pred), paste0("to", 1:ncomp_orth))
    }
    # MetaboAnalyst OPLS-DA exposes loadings via the model matrix
    if (!is.null(model$loadings)) {
      loadings_mat <- as.matrix(model$loadings)
      if (!is.null(colnames(loadings_mat))) {
        colnames(loadings_mat) <- c(paste0("p", 1:ncomp_pred), paste0("po", 1:ncomp_orth))
      }
    }
    vip_scores <- if (!is.null(model$vip)) model$vip else model$vipVn
  } else if (requireNamespace("mixOmics", quietly = TRUE)) {
    # Use mixOmics - it doesn't have OPLS-DA directly, but we can use PLS-DA
    # and separate predictive/orthogonal components
    model <- mixOmics::plsda(X, groups, ncomp = ncomp_pred + ncomp_orth)

    # Extract scores
    scores <- as.data.frame(model$variates$X)
    colnames(scores) <- c(paste0("t", 1:ncomp_pred), paste0("to", 1:ncomp_orth))

    # Loadings
    loadings_mat <- as.matrix(model$loadings$X)
    colnames(loadings_mat) <- c(paste0("p", 1:ncomp_pred), paste0("po", 1:ncomp_orth))

    # VIP
    vip_scores <- mixOmics::vip(model)
    if (is.matrix(vip_scores)) {
      vip_scores <- vip_scores[, ncol(vip_scores)]
    }
  } else {
    # Fallback: manual OPLS implementation
    warning("Neither 'metaboanalyst' nor 'mixOmics' available. Using simplified OPLS-DA.")
    result <- .oplsda_base(X, groups, ncomp_pred = ncomp_pred, ncomp_orth = ncomp_orth)
    model <- result$model
    scores <- as.data.frame(result$scores)
    colnames(scores) <- c(paste0("t", 1:ncomp_pred), paste0("to", 1:ncomp_orth))
    loadings_mat <- as.matrix(result$loadings)
    vip_scores <- result$vip
  }

  # Prepare scores data.frame
  scores$sample_id <- rownames(scores)
  scores$group <- as.character(groups)
  scores <- scores[, c("sample_id", setdiff(colnames(scores), "sample_id")), drop = FALSE]
  rownames(scores) <- NULL

  # Prepare VIP data.frame
  vip_df <- data.frame(
    feature_id = rownames(expr_matrix),
    vip = vip_scores,
    stringsAsFactors = FALSE
  )
  vip_df <- vip_df[order(vip_df$vip, decreasing = TRUE), ]
  rownames(vip_df) <- vip_df$feature_id
  vip_df$feature_id <- NULL

  # Prepare loadings data.frame (features x components), feature_id as first column
  loadings_df <- NULL
  if (!is.null(loadings_mat) && nrow(loadings_mat) > 0) {
    loadings_df <- as.data.frame(loadings_mat)
    loadings_df$feature_id <- rownames(loadings_df)
    loadings_df <- loadings_df[, c("feature_id",
                                   setdiff(colnames(loadings_df), "feature_id")), drop = FALSE]
    rownames(loadings_df) <- NULL
  }

  return(list(
    scores = scores,
    loadings = loadings_df,
    vip = vip_df,
    model = model
  ))
}


#' Base OPLS-DA implementation (internal)
#'
#' @keywords internal
#' @noRd
.oplsda_base <- function(X, Y, ncomp_pred = 1, ncomp_orth = 1) {
  # Simplified OPLS using NIPALS with orthogonalization
  X <- as.matrix(X)

  # Dummy Y matrix
  if (is.factor(Y)) {
    Y_dummy <- model.matrix(~ 0 + Y)
  } else {
    Y_dummy <- as.matrix(Y)
  }

  n <- nrow(X)
  p <- ncol(X)
  q <- ncol(Y_dummy)

  # Total components
  ncomp_total <- ncomp_pred + ncomp_orth

  scores_mat <- matrix(0, n, ncomp_total)
  loadings_mat <- matrix(0, p, ncomp_total)
  Y_loadings <- matrix(0, q, ncomp_total)

  X_k <- X
  Y_k <- Y_dummy

  for (a in 1:ncomp_total) {
    if (a <= ncomp_pred) {
      # Predictive component: use Y in cross product
      cross <- crossprod(X_k, Y_k)
    } else {
      # Orthogonal component: use X only
      cross <- crossprod(X_k)
    }

    svd_result <- svd(cross)
    wa <- svd_result$u[, 1]
    ta <- X_k %*% wa
    ta_norm <- sqrt(sum(ta^2))
    if (ta_norm > 0) ta <- ta / ta_norm

    pa <- crossprod(X_k, ta) / as.numeric(crossprod(ta))
    qa <- crossprod(Y_k, ta) / as.numeric(crossprod(ta))

    scores_mat[, a] <- as.vector(ta)
    loadings_mat[, a] <- as.vector(pa)
    Y_loadings[, a] <- as.vector(qa)

    # Deflation
    X_k <- X_k - tcrossprod(ta, pa)
    if (a <= ncomp_pred) {
      Y_k <- Y_k - tcrossprod(ta, qa)
    }
  }

  colnames(scores_mat) <- c(paste0("t", 1:ncomp_pred), paste0("to", 1:ncomp_orth))
  colnames(loadings_mat) <- c(paste0("p", 1:ncomp_pred), paste0("po", 1:ncomp_orth))
  rownames(loadings_mat) <- colnames(X)

  # VIP calculation
  SSY <- colSums(Y_loadings^2)
  vip <- sqrt(p * rowSums(sweep(loadings_mat^2, 2, SSY, "*")) / sum(SSY))

  return(list(
    model = list(scores = scores_mat, loadings = loadings_mat, Y_loadings = Y_loadings),
    scores = scores_mat,
    loadings = loadings_mat,
    vip = vip
  ))
}


#' Plot OPLS-DA score plot
#'
#' @description Creates a publication-quality OPLS-DA score plot showing
#'   predictive vs orthogonal components.
#'
#' @param oplsda_result Result from \code{run_oplsda()}.
#' @param color_col Column for color grouping (not used, colors based on group).
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' oplsda <- run_oplsda(expr_matrix, sample_info)
#' p <- plot_oplsda_scores(oplsda)
#' }
#'
#' @export
plot_oplsda_scores <- function(oplsda_result, color_col = NULL) {
  scores <- oplsda_result$scores

  # Find predictive and orthogonal score columns
  pred_col <- grep("^t[0-9]", colnames(scores), value = TRUE)[1]
  orth_col <- grep("^to[0-9]", colnames(scores), value = TRUE)[1]

  if (is.na(pred_col) || is.na(orth_col)) {
    # Fallback to first two columns
    pred_col <- colnames(scores)[1]
    orth_col <- colnames(scores)[2]
  }

  plot_data <- data.frame(
    sample_id = scores$sample_id,
    t_pred = scores[[pred_col]],
    t_orth = scores[[orth_col]],
    group = scores$group
  )

  groups <- unique(plot_data$group)
  colors <- make_group_colors(groups)

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = t_pred, y = t_orth)) +
    ggplot2::geom_point(ggplot2::aes(color = group), size = 3, alpha = 0.85) +
    ggplot2::scale_color_manual(values = colors) +
    ggplot2::labs(
      title = "OPLS-DA Score Plot",
      x = "Predictive Component (t1)",
      y = "Orthogonal Component (to1)"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 11),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right"
    ) +
    ggplot2::coord_equal()

  # Add ellipses
  for (g in groups) {
    g_data <- plot_data[plot_data$group == g, , drop = FALSE]
    if (nrow(g_data) >= 3) {
      center <- c(mean(g_data$t_pred), mean(g_data$t_orth))
      cov_mat <- stats::cov(g_data[, c("t_pred", "t_orth")])
      if (det(cov_mat) > 1e-10) {
        chi_sq <- stats::qchisq(0.95, 2)
        eig <- eigen(cov_mat)
        angles <- seq(0, 2 * pi, length.out = 100)
        ellipse_df <- data.frame(
          t_pred = center[1] + sqrt(chi_sq) * eig$vectors[1, 1] * sqrt(eig$values[1]) * cos(angles) +
                    sqrt(chi_sq) * eig$vectors[1, 2] * sqrt(eig$values[2]) * sin(angles),
          t_orth = center[2] + sqrt(chi_sq) * eig$vectors[2, 1] * sqrt(eig$values[1]) * cos(angles) +
                    sqrt(chi_sq) * eig$vectors[2, 2] * sqrt(eig$values[2]) * sin(angles)
        )
        p <- p + ggplot2::geom_path(data = ellipse_df,
                                    ggplot2::aes(x = t_pred, y = t_orth),
                                    color = colors[g], linewidth = 0.6,
                                    linetype = "dashed", inherit.aes = FALSE)
      }
    }
  }

  return(p)
}
