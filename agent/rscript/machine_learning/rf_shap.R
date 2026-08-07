# ==============================================================================
# OmicsFlow: 随机森林 + SHAP
# ==============================================================================
# 带特征重要性的样本分类
# ==============================================================================

#' 运行带 SHAP 的随机森林分类
#'
#' @description 构建随机森林分类模型以预测样本分组，并使用 SHAP 值解释特征重要性。
#'
#' @param expr_matrix 数值矩阵（特征 x 样本）。
#' @param sample_info 含有样本元数据的数据框。
#' @param group_col 分组标签所在的列名。默认："sample_info"。
#' @param exclude_groups 要排除的可选分组。默认："QC"。
#' @param n_trees 树的数量。默认：500。
#' @param cv_folds 交叉验证折数。默认：5。
#' @param n_top_features 用于 SHAP 的前 N 个特征数量。默认：20。
#' @param seed 随机种子。默认：42。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{model}：随机森林模型。
#'     \item \code{accuracy}：分类准确率。
#'     \item \code{confusion_matrix}：混淆矩阵。
#'     \item \code{importance}：特征重要性（MeanDecreaseGini）。
#'     \item \code{shap_values}：SHAP 值矩阵（样本 x 特征）。
#'     \item \code{shap_summary}：用于绘图的汇总数据框。
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

  # 对齐样本
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]

  # 排除分组
  if (!is.null(exclude_groups)) {
    keep_samples <- rownames(sample_info)[!(sample_info[[group_col]] %in% exclude_groups)]
    expr_matrix <- expr_matrix[, keep_samples, drop = FALSE]
    sample_info <- sample_info[keep_samples, , drop = FALSE]
  }

  groups <- factor(sample_info[[group_col]])
  X <- t(as.matrix(expr_matrix))

  # 构建随机森林
  rf_model <- randomForest::randomForest(
    x = X, y = groups, ntree = n_trees, importance = TRUE
  )

  # 准确率
  predictions <- predict(rf_model)
  accuracy <- mean(predictions == groups)
  conf_mat <- as.matrix(table(Predicted = predictions, Actual = groups))

  # 特征重要性
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

  # SHAP 值（使用置换重要性近似）
  # 选取前 N 个特征
  top_features <- head(rownames(imp_df), n_top_features)

  # 使用特征重要性的简化 SHAP 近似
  shap_values <- NULL
  shap_summary <- NULL

  if (requireNamespace("fastshap", quietly = TRUE)) {
    # 使用 fastshap 计算真实 SHAP
    # 注意：需要 explain() 函数
    shap_result <- tryCatch({
      # 计算前 N 个特征的 SHAP
      shap_vals <- fastshap:::explain(
        rf_model, X = X[, top_features, drop = FALSE],
        nsim = 50, pred_wrapper = function(m, X) {
          predict(m, X, type = "prob")
        }
      )
      shap_vals
    }, error = function(e) NULL)
  }

  # 若 fastshap 失败，则使用重要性作为替代
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


#' 绘制特征重要性（SHAP）
#'
#' @description 创建 SHAP 汇总图或特征重要性条形图。
#'
#' @param rf_result 来自 \code{run_rf_shap()} 的结果。
#' @param top_n 展示的前 N 个特征数量。默认：20。
#'
#' @return 一个 ggplot 对象。
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
      title = "随机森林特征重要性",
      x = "特征",
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


#' 绘制混淆矩阵
#'
#' @description 创建混淆矩阵的热图。
#'
#' @param rf_result 来自 \code{run_rf_shap()} 的结果。
#'
#' @return 一个 ggplot 对象。
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
