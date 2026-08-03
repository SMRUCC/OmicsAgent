# ==============================================================================
# OmicsFlow: Cross-Omics Linear Regression
# ==============================================================================
# Fits univariate linear models between features of two omics layers, one
# treated as the explanatory variable (x) and the other as the response (y).
# Supports feature-level slope / p-value / R2 tables and per-pair scatter plots
# with the fitted line.
# ==============================================================================

#' Univariate linear regression across two omics layers
#'
#' @description For every (x feature, y feature) pair shared across the same
#'   samples, fits y ~ x with \code{lm()} and records the slope, intercept,
#'   significance and goodness of fit. P-values are adjusted across all tested
#'   pairs. This is a direct linear association screen complementary to the
#'   rank-based correlation used elsewhere.
#'
#' @param x_matrix A numeric matrix (features x samples) of the explanatory
#'   layer.
#' @param y_matrix A numeric matrix (features x samples) of the response layer.
#' @param x_name Label for the explanatory layer. Default: "x".
#' @param y_name Label for the response layer. Default: "y".
#' @param p_adjust Multiple testing adjustment. Default: "BH".
#' @param min_samples Minimum number of shared samples required. Default: 6.
#' @param verbose Logical, print a short summary. Default: TRUE.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{pairs}: data.frame of x_feature, y_feature, x_name, y_name,
#'       slope, intercept, se, t_stat, p_value, padj, r_squared and n_samples.
#'     \item \code{x_summary}: per-x-feature count of significant y responses.
#'     \item \code{y_summary}: per-y-feature count of significant x predictors.
#'   }
#'
#' @examples
#' \dontrun{
#' reg <- run_cross_omics_regression(get_omics_matrix(mo, "microbiome"),
#'                                   get_omics_matrix(mo, "volatilome"),
#'                                   x_name = "microbiome", y_name = "volatilome")
#' }
#'
#' @export
run_cross_omics_regression <- function(x_matrix, y_matrix,
                                       x_name = "x", y_name = "y",
                                       p_adjust = "BH",
                                       min_samples = 6,
                                       verbose = TRUE) {
  if (!is.matrix(x_matrix)) x_matrix <- as.matrix(x_matrix)
  if (!is.matrix(y_matrix)) y_matrix <- as.matrix(y_matrix)

  common <- intersect(colnames(x_matrix), colnames(y_matrix))
  if (length(common) < min_samples) {
    stop(sprintf("Only %d shared samples; need at least %d.", length(common), min_samples))
  }
  X <- x_matrix[, common, drop = FALSE]
  Y <- y_matrix[, common, drop = FALSE]

  # Drop zero-variance features in either layer.
  X <- drop_zero_variance(X, label = x_name, verbose = verbose)
  Y <- drop_zero_variance(Y, label = y_name, verbose = verbose)

  if (nrow(X) == 0 || nrow(Y) == 0) {
    stop("At least one of the layers has no usable feature after filtering.")
  }

  # ---------------------------------------------------------------------------
  # For a univariate model y ~ x the regression statistics follow directly from
  # the Pearson correlation r and the feature moments:
  #   slope      = r * sd(y) / sd(x)
  #   intercept  = mean(y) - slope * mean(x)
  #   t_stat     = r * sqrt((n - 2) / (1 - r^2))
  #   p_value    = 2 * pt(-abs(t), df = n - 2)
  #   r_squared  = r^2
  #   se_slope   = slope / t_stat
  # This is exactly equivalent to stats::lm(y ~ x) but avoids the huge overhead
  # of one lm() call per pair, which makes large x-by-y screens tractable.
  # ---------------------------------------------------------------------------
  n <- length(common)
  df <- n - 2L

  # Centre every feature across samples; the cross product then yields the
  # feature x feature sum of cross products (n_features_x x n_features_y).
  Xc <- X - rowMeans(X)             # features x samples
  Yc <- Y - rowMeans(Y)             # features x samples
  Sxx <- rowSums(Xc * Xc)
  Syy <- rowSums(Yc * Yc)
  Sxy <- Xc %*% t(Yc)               # n_features_x x n_features_y

  r <- Sxy / sqrt(outer(Sxx, Syy))
  r <- pmax(pmin(r, 1), -1)         # guard against rounding beyond [-1, 1]

  t_val <- r * sqrt(df / pmax(1 - r * r, .Machine$double.eps))
  p_val <- 2 * stats::pt(-abs(t_val), df = df)

  sx <- sqrt(Sxx / (n - 1))
  sy <- sqrt(Syy / (n - 1))
  mx <- rowMeans(X)
  my <- rowMeans(Y)

  slope <- r * outer(1 / sx, sy)
  intercept <- outer(rep(1, nrow(X)), my) - t(t(slope) * mx)
  r2 <- r * r
  se_slope <- abs(slope) / pmax(abs(t_val), .Machine$double.eps)

  is_finite <- !is.na(r) & is.finite(t_val) & abs(r) < 1

  # expand.grid with x_feature first iterates x fastest, matching the column-
  # major (as.vector) order of the slope / p-value matrices.
  pairs <- expand.grid(x_feature = rownames(X), y_feature = rownames(Y),
                       KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  pairs$x_name <- x_name
  pairs$y_name <- y_name
  pairs$slope <- as.vector(slope)
  pairs$intercept <- as.vector(intercept)
  pairs$se <- as.vector(se_slope)
  pairs$t_stat <- as.vector(t_val)
  pairs$p_value <- as.vector(p_val)
  pairs$r_squared <- as.vector(r2)
  pairs$n_samples <- n
  pairs <- pairs[is_finite, , drop = FALSE]

  if (nrow(pairs) == 0) {
    cat(sprintf("  [regression] %s -> %s: no valid fit produced.\n", x_name, y_name))
    return(list(pairs = data.frame(), x_summary = data.frame(), y_summary = data.frame()))
  }
  out <- pairs
  out$padj <- stats::p.adjust(out$p_value, method = p_adjust)
  out$significant <- out$padj < 0.05
  out <- out[order(out$padj, -abs(out$slope)), , drop = FALSE]
  rownames(out) <- NULL

  x_summary <- do.call(rbind, lapply(split(out, out$x_feature), function(sub) {
    data.frame(
      x_feature = sub$x_feature[1],
      x_name = sub$x_name[1],
      n_responses_tested = nrow(sub),
      n_significant = sum(sub$significant),
      best_y = sub$y_feature[1],
      best_padj = sub$padj[1],
      best_r2 = sub$r_squared[1],
      stringsAsFactors = FALSE
    )
  }))
  x_summary <- x_summary[order(-x_summary$n_significant, -x_summary$best_r2), , drop = FALSE]
  rownames(x_summary) <- NULL

  y_summary <- do.call(rbind, lapply(split(out, out$y_feature), function(sub) {
    data.frame(
      y_feature = sub$y_feature[1],
      y_name = sub$y_name[1],
      n_predictors_tested = nrow(sub),
      n_significant = sum(sub$significant),
      best_x = sub$x_feature[1],
      best_padj = sub$padj[1],
      best_r2 = sub$r_squared[1],
      stringsAsFactors = FALSE
    )
  }))
  y_summary <- y_summary[order(-y_summary$n_significant, -y_summary$best_r2), , drop = FALSE]
  rownames(y_summary) <- NULL

  if (verbose) {
    cat(sprintf("  [regression] %s -> %s: %d pairs tested, %d significant (padj<0.05)\n",
                x_name, y_name, nrow(out), sum(out$significant)))
  }

  list(pairs = out, x_summary = x_summary, y_summary = y_summary)
}


#' Scatter plot of a single cross-omics regression pair
#'
#' @description Draws the samples of one x-y feature pair with the fitted
#'   regression line and 95% confidence band.
#'
#' @param x_values Numeric vector of the explanatory feature across samples.
#' @param y_values Numeric vector of the response feature across samples.
#' @param x_label Label for the x axis (feature + layer).
#' @param y_label Label for the y axis (feature + layer).
#' @param title Optional title.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' p <- plot_regression_pair(x_values, y_values, "gene A (transcriptome)", "metabolite B")
#' }
#'
#' @export
plot_regression_pair <- function(x_values, y_values,
                                 x_label = "x", y_label = "y", title = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' is required.")
  }
  dat <- data.frame(x = as.numeric(x_values), y = as.numeric(y_values))
  dat <- dat[stats::complete.cases(dat), ]
  p <- ggplot2::ggplot(dat, ggplot2::aes(x = x, y = y)) +
    ggplot2::geom_point(color = "#4a90d9", alpha = 0.7, size = 2) +
    ggplot2::geom_smooth(method = "lm", se = TRUE,
                         color = "#d7191c", fill = "#d7191c", alpha = 0.15) +
    ggplot2::labs(title = if (is.null(title)) "Cross-omics regression" else title,
                  x = x_label, y = y_label) +
    ggplot2::theme_bw() +
    ggplot2::theme(plot.title = ggplot2::element_text(size = 12, face = "bold", hjust = 0.5))
  return(p)
}


#' Pick the top significant regression pairs for plotting
#'
#' @description Extracts the most significant (or highest-R2) x-y feature pairs
#'   from a regression result so a manageable number of scatter plots can be
#'   produced.
#'
#' @param reg Result of \code{run_cross_omics_regression()}.
#' @param top_n Number of pairs to return. Default: 12.
#' @param by Ordering criterion: "padj" or "r2". Default: "padj".
#'
#' @return A data.frame with the top \code{top_n} rows of \code{reg$pairs}.
#'
#' @export
top_regression_pairs <- function(reg, top_n = 12, by = "padj") {
  if (is.null(reg$pairs) || nrow(reg$pairs) == 0) {
    return(data.frame())
  }
  by <- match.arg(by, c("padj", "r2"))
  ord <- if (by == "padj") {
    order(reg$pairs$padj, -abs(reg$pairs$slope))
  } else {
    order(-reg$pairs$r_squared, reg$pairs$padj)
  }
  head(reg$pairs[ord, , drop = FALSE], top_n)
}
