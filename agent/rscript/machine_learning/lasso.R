# ==============================================================================
# OmicsFlow: Lasso Regression
# ==============================================================================
# Feature selection via L1 regularization
# ==============================================================================

#' Run Lasso regression for feature selection
#'
#' @description Performs Lasso (L1-penalized) regression for identifying important
#'   predictive features. Supports binary and multi-class classification.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param group_col Column name for group labels. Default: "sample_info".
#' @param exclude_groups Optional groups to exclude. Default: "QC".
#' @param control_group Character, reference group. Default: NULL.
#' @param n_folds Number of CV folds for lambda selection. Default: 10.
#' @param alpha Elastic net mixing (1 = lasso, 0 = ridge). Default: 1.
#' @param seed Random seed. Default: 42.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{model}: Fitted cv.glmnet model.
#'     \item \code{selected_features}: Character vector of selected features.
#'     \item \code{coefficients}: Data.frame of non-zero coefficients.
#'     \item \code{lambda}: Selected lambda value.
#'     \item \code{accuracy}: Classification accuracy.
#'     \item \code{confusion_matrix}: Confusion matrix.
#'   }
#'
#' @examples
#' \dontrun{
#' lasso <- run_lasso(expr_matrix, sample_info)
#' print(lasso$selected_features)
#' }
#'
#' @export
run_lasso <- function(expr_matrix, sample_info, group_col = "sample_info",
                     exclude_groups = "QC", control_group = NULL,
                     n_folds = 10, alpha = 1, seed = 42) {
  if (!requireNamespace("glmnet", quietly = TRUE)) {
    stop("Package 'glmnet' is required. Please install it.")
  }

  set.seed(seed)

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
  if (!is.null(control_group)) {
    groups <- stats::relevel(groups, ref = control_group)
  }

  X <- t(as.matrix(expr_matrix))
  n_groups <- nlevels(groups)

  # Family
  if (n_groups == 2) {
    family <- "binomial"
  } else {
    family <- "multinomial"
  }

  # Cross-validated Lasso
  cv_model <- glmnet::cv.glmnet(
    x = X, y = groups, family = family,
    alpha = alpha, nfolds = n_folds, type.measure = "class"
  )

  # Best lambda
  best_lambda <- cv_model$lambda.min

  # Predictions
  predictions <- stats::predict(cv_model, newx = X, s = "lambda.min",
                                  type = "class")
  predicted_class <- factor(predictions, levels = levels(groups))
  accuracy <- mean(predicted_class == groups)
  conf_mat <- as.matrix(table(Predicted = predicted_class, Actual = groups))

  # Extract non-zero coefficients
  coefs <- stats::coef(cv_model, s = "lambda.min")

  if (is.list(coefs)) {
    # Multinomial: list of coefficient matrices
    coef_df <- do.call(rbind, lapply(names(coefs), function(g) {
      coef_mat <- as.matrix(coefs[[g]])
      nz_idx <- which(coef_mat != 0)
      data.frame(
        group = g,
        feature = rownames(coef_mat)[nz_idx],
        coefficient = coef_mat[nz_idx],
        stringsAsFactors = FALSE
      )
    }))
    selected_features <- unique(coef_df$feature)
    selected_features <- setdiff(selected_features, "(Intercept)")
  } else {
    # Binomial
    coefs_mat <- as.matrix(coefs)
    nz_idx <- which(coefs_mat != 0)
    coef_df <- data.frame(
      group = levels(groups)[1],
      feature = rownames(coefs_mat)[nz_idx],
      coefficient = coefs_mat[nz_idx],
      stringsAsFactors = FALSE
    )
    selected_features <- rownames(coefs_mat)[nz_idx]
    selected_features <- setdiff(selected_features, "(Intercept)")
  }

  # Set feature as row names (may have duplicates from multiple groups)
  rownames(coef_df) <- make.unique(coef_df$feature)
  coef_df$feature <- NULL

  return(list(
    model = cv_model,
    selected_features = selected_features,
    coefficients = coef_df,
    lambda = best_lambda,
    accuracy = accuracy,
    confusion_matrix = conf_mat
  ))
}


#' Plot Lasso coefficient path
#'
#' @description Creates a plot of Lasso coefficients vs L1 norm.
#'
#' @param lasso_result Result from \code{run_lasso()}.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' lasso <- run_lasso(expr_matrix, sample_info)
#' p <- plot_lasso_path(lasso)
#' print(p)
#' }
#'
#' @export
plot_lasso_path <- function(lasso_result) {
  model <- lasso_result$model
  all_coefs <- stats::coef(model, s = model$lambda)

  # Build data for plotting
  lambda_seq <- model$lambda
  coef_mat <- stats::coef(model, s = lambda_seq)
  if (is.list(coef_mat)) {
    coef_mat <- coef_mat[[1]]
  }

  plot_data <- data.frame()
  for (i in 1:ncol(coef_mat)) {
    nonzero_idx <- which(coef_mat[, i] != 0)
    nonzero_idx <- setdiff(rownames(coef_mat)[nonzero_idx], "(Intercept)")
    if (length(nonzero_idx) > 0) {
      plot_data <- rbind(plot_data, data.frame(
        feature = nonzero_idx,
        lambda = lambda_seq[i],
        coefficient = coef_mat[nonzero_idx, i],
        stringsAsFactors = FALSE
      ))
    }
  }

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = log(lambda), y = coefficient,
                                               color = feature)) +
    ggplot2::geom_line(linewidth = 0.6) +
    ggplot2::geom_vline(xintercept = log(lasso_result$lambda),
                        color = "#e74c3c", linetype = "dashed") +
    ggplot2::labs(
      title = "Lasso Coefficient Path",
      x = expression(log(lambda)),
      y = "Coefficient",
      color = "Feature"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 10),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right",
      legend.text = ggplot2::element_text(size = 7)
    ) +
    ggplot2::guides(color = ggplot2::guide_legend(ncol = 1))

  return(p)
}
