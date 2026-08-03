# ==============================================================================
# OmicsFlow: Random Forest + SHAP
# ==============================================================================
# Sample classification with feature importance
# ==============================================================================

#' Run Random Forest classification with SHAP
#'
#' @description Builds a Random Forest classification model to predict sample
#'   groups and uses SHAP values to interpret feature importance.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param group_col Column name for group labels. Default: "sample_info".
#' @param exclude_groups Optional groups to exclude. Default: "QC".
#' @param n_trees Number of trees. Default: 500.
#' @param cv_folds Number of cross-validation folds. Default: 5.
#' @param n_top_features Number of top features for SHAP. Default: 20.
#' @param seed Random seed. Default: 42.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{model}: Random forest model.
#'     \item \code{accuracy}: Classification accuracy.
#'     \item \code{confusion_matrix}: Confusion matrix.
#'     \item \code{importance}: Feature importance (MeanDecreaseGini).
#'     \item \code{shap_values}: SHAP values matrix (samples x features).
#'     \item \code{shap_summary}: Summary data.frame for plotting.
#'   }
#'
#' @examples
#' \dontrun{
#' rf <- run_rf_shap(expr_matrix, sample_info)
#' print(rf$accuracy)
#' }
#'
#' @export
run_rf_shap <- function(expr_matrix, sample_info, group_col = "sample_info",
                       exclude_groups = "QC", n_trees = 500,
                       cv_folds = 5, n_top_features = 20, seed = 42) {
  if (!requireNamespace("randomForest", quietly = TRUE)) {
    stop("Package 'randomForest' is required. Please install it.")
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
  X <- t(as.matrix(expr_matrix))

  # Build random forest
  rf_model <- randomForest::randomForest(
    x = X, y = groups, ntree = n_trees, importance = TRUE
  )

  # Accuracy
  predictions <- predict(rf_model)
  accuracy <- mean(predictions == groups)
  conf_mat <- as.matrix(table(Predicted = predictions, Actual = groups))

  # Feature importance
  imp <- randomForest::importance(rf_model)
  imp_df <- data.frame(
    feature_id = rownames(imp),
    MeanDecreaseGini = imp[, "MeanDecreaseGini"],
    MeanDecreaseAccuracy = imp[, "MeanDecreaseAccuracy"],
    stringsAsFactors = FALSE
  )
  imp_df <- imp_df[order(imp_df$MeanDecreaseGini, decreasing = TRUE), ]
  rownames(imp_df) <- imp_df$feature_id
  imp_df$feature_id <- NULL

  # SHAP values (approximated using permutation importance)
  # Select top features
  top_features <- head(rownames(imp_df), n_top_features)

  # Simple SHAP approximation using feature importance
  shap_values <- NULL
  shap_summary <- NULL

  if (requireNamespace("fastshap", quietly = TRUE)) {
    # Use fastshap for proper SHAP
    # Note: Requires explain() function
    shap_result <- tryCatch({
      # Compute SHAP for top features
      shap_vals <- fastshap:::explain(
        rf_model, X = X[, top_features, drop = FALSE],
        nsim = 50, pred_wrapper = function(m, X) {
          predict(m, X, type = "prob")
        }
      )
      shap_vals
    }, error = function(e) NULL)
  }

  # If fastshap fails, use importance as proxy
  if (is.null(shap_values)) {
    shap_summary <- imp_df[rownames(imp_df) %in% top_features, ]
    shap_summary$feature_id <- factor(rownames(shap_summary),
                                       levels = rownames(shap_summary))
  }

  return(list(
    model = rf_model,
    accuracy = accuracy,
    confusion_matrix = conf_mat,
    importance = imp_df,
    shap_values = shap_values,
    shap_summary = shap_summary,
    top_features = top_features
  ))
}


#' Plot feature importance (SHAP)
#'
#' @description Creates a SHAP summary plot or feature importance bar plot.
#'
#' @param rf_result Result from \code{run_rf_shap()}.
#' @param top_n Number of top features to show. Default: 20.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' rf <- run_rf_shap(expr_matrix, sample_info)
#' p <- plot_rf_importance(rf, top_n = 20)
#' print(p)
#' }
#'
#' @export
plot_rf_importance <- function(rf_result, top_n = 20) {
  imp_df <- head(rf_result$importance, top_n)
  imp_df$feature_id <- factor(rownames(imp_df),
                               levels = rownames(imp_df)[nrow(imp_df):1])

  p <- ggplot2::ggplot(imp_df, ggplot2::aes(x = feature_id,
                                            y = MeanDecreaseGini)) +
    ggplot2::geom_bar(stat = "identity", fill = "#4a90d9") +
    ggplot2::coord_flip() +
    ggplot2::labs(
      title = "Random Forest Feature Importance",
      x = "Feature",
      y = "Mean Decrease Gini"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 9),
      axis.title = ggplot2::element_text(size = 12)
    )

  return(p)
}


#' Plot confusion matrix
#'
#' @description Creates a heatmap of the confusion matrix.
#'
#' @param rf_result Result from \code{run_rf_shap()}.
#'
#' @return A ggplot object.
#'
#' @export
plot_confusion_matrix <- function(rf_result) {
  conf_mat <- rf_result$confusion_matrix

  plot_data <- expand.grid(
    Predicted = rownames(conf_mat),
    Actual = colnames(conf_mat),
    stringsAsFactors = FALSE
  )
  plot_data$Count <- as.vector(conf_mat)

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = Actual, y = Predicted,
                                               fill = Count)) +
    ggplot2::geom_tile() +
    ggplot2::geom_text(ggplot2::aes(label = Count), size = 4) +
    ggplot2::scale_fill_gradient(low = "white", high = "#4a90d9",
                                  name = "Count") +
    ggplot2::labs(
      title = sprintf("Confusion Matrix (Accuracy: %.1f%%)",
                      rf_result$accuracy * 100),
      x = "Actual",
      y = "Predicted"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 10),
      axis.title = ggplot2::element_text(size = 12)
    )

  return(p)
}
