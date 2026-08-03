# ==============================================================================
# OmicsFlow: Linear Regression Model
# ==============================================================================
# Sample classification using linear regression
# ==============================================================================

#' Run linear regression classification model
#'
#' @description Builds a linear regression model for sample group prediction.
#'   For binary classification, uses logistic regression. For multi-class,
#'   uses multinomial logistic regression.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param group_col Column name for group labels. Default: "sample_info".
#' @param exclude_groups Optional groups to exclude. Default: "QC".
#' @param control_group Character, reference group. Default: NULL.
#' @param top_features Optional character vector of features to use. If NULL,
#'   uses all features. Default: NULL.
#' @param cv_folds Number of cross-validation folds. Default: 5.
#' @param seed Random seed. Default: 42.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{model}: Fitted model.
#'     \item \code{coefficients}: Coefficient data.frame.
#'     \item \code{accuracy}: Classification accuracy.
#'     \item \code{predictions}: Predicted labels.
#'     \item \code{confusion_matrix}: Confusion matrix.
#'   }
#'
#' @examples
#' \dontrun{
#' lr <- run_linear_model(expr_matrix, sample_info)
#' print(lr$accuracy)
#' }
#'
#' @export
run_linear_model <- function(expr_matrix, sample_info,
                            group_col = "sample_info",
                            exclude_groups = "QC", control_group = NULL,
                            top_features = NULL, cv_folds = 5, seed = 42) {
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

  # Select top features if specified
  if (!is.null(top_features)) {
    top_features <- intersect(top_features, colnames(X))
    X <- X[, top_features, drop = FALSE]
  }

  # Build data.frame
  X <- as.matrix(X)
  colnames(X) <- make.names(colnames(X), unique = TRUE)
  data_df <- as.data.frame(X)
  data_df$group <- groups

  # Determine model type
  n_groups <- nlevels(groups)

  if (n_groups == 2) {
    # Binary: logistic regression
    feat_names <- colnames(data_df)[-ncol(data_df)]
    # Use . to include all features
    formula_str <- "group ~ ."
    model <- stats::glm(as.formula(formula_str), data = data_df,
                        family = stats::binomial())
    predictions <- stats::predict(model, type = "response")
    predicted_class <- ifelse(predictions > 0.5, levels(groups)[2],
                              levels(groups)[1])
    predicted_class <- factor(predicted_class, levels = levels(groups))
  } else {
    # Multi-class: multinomial
    if (requireNamespace("nnet", quietly = TRUE)) {
      formula_str <- "group ~ ."
      model <- nnet::multinom(as.formula(formula_str), data = data_df,
                               trace = FALSE)
      predictions <- stats::predict(model, type = "class")
      predicted_class <- factor(predictions, levels = levels(groups))
    } else {
      # Fallback: LDA
      if (requireNamespace("MASS", quietly = TRUE)) {
        model <- MASS::lda(x = X, grouping = groups)
        predictions <- stats::predict(model, X)$class
        predicted_class <- factor(predictions, levels = levels(groups))
      } else {
        stop("Either 'nnet' or 'MASS' package is required for multi-class.")
      }
    }
  }

  # Accuracy
  accuracy <- mean(predicted_class == groups)
  conf_mat <- as.matrix(table(Predicted = predicted_class, Actual = groups))

  # Coefficients
  coefs <- stats::coef(model)
  if (is.list(coefs)) {
    coef_df <- do.call(rbind, lapply(names(coefs), function(n) {
      data.frame(group = n, feature = names(coefs[[n]]),
                 coefficient = coefs[[n]], stringsAsFactors = FALSE)
    }))
  } else if (is.matrix(coefs)) {
    # Multinomial: matrix with columns per group
    coef_df <- do.call(rbind, lapply(colnames(coefs), function(g) {
      data.frame(group = g, feature = rownames(coefs),
                 coefficient = coefs[, g], stringsAsFactors = FALSE)
    }))
  } else {
    coef_df <- data.frame(
      group = levels(groups)[1],
      feature = names(coefs),
      coefficient = as.numeric(coefs),
      stringsAsFactors = FALSE
    )
  }

  # Set feature as row names (may have duplicates from multiple groups)
  rownames(coef_df) <- make.unique(coef_df$feature)
  coef_df$feature <- NULL

  return(list(
    model = model,
    coefficients = coef_df,
    accuracy = accuracy,
    predictions = predicted_class,
    confusion_matrix = conf_mat
  ))
}
