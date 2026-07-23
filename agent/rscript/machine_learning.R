# ============================================================
# Required packages
# ============================================================
library(randomForest)
library(dplyr)
library(ggplot2)
library(grDevices)
library(stats)
library(glmnet)
library(reshape2)

#' @title Build Random Forest Classification Model with SHAP Values
#'
#' @description
#' 针对样本进行分组预测，建立随机森林分类模型，并使用SHAP
#' （SHapley Additive exPlanations）值解释模型。SHAP值表示每个feature
#' 对每个样本预测结果的贡献，正值表示支持该分类，负值表示反对。
#'
#' 该函数适用于样本分类预测和重要feature识别。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param sample_meta 数据框，样本元数据
#' @param ntree 整数，树的数量，默认500
#' @param mtry 整数，每次分裂时尝试的feature数（可选，默认自动）
#' @param cv_folds 整数，交叉验证折数，默认5
#' @param importance 逻辑值，是否计算feature重要性，默认TRUE
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item model: 随机森林模型
#'   \item accuracy: 交叉验证准确率
#'   \item confusion_matrix: 混淆矩阵
#'   \item importance: feature重要性
#'   \item shap_values: SHAP值矩阵（如果可计算）
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' meta <- load_sample_metadata("meta.csv")
#'
#' rf_result <- build_random_forest_model(expr, meta, cv_folds = 5)
#' print(rf_result$accuracy)
#' }
#'
#' @export
build_random_forest_model <- function(expr_matrix, sample_meta,
                                       ntree = 500, mtry = NULL,
                                       cv_folds = 5, importance = TRUE) {
  if (!requireNamespace("randomForest", quietly = TRUE)) {
    stop("Package 'randomForest' is required. Please install it.")
  }

  # Prepare data
  groups <- factor(sample_meta$sample_info[match(colnames(expr_matrix),
                                                  sample_meta$ID)])
  train_data <- as.data.frame(t(expr_matrix))
  train_data$Group <- groups

  # Remove features with zero variance
  feature_vars <- apply(train_data[, -ncol(train_data), drop = FALSE], 2, var,
                        na.rm = TRUE)
  keep_features <- names(feature_vars)[feature_vars > 0 & !is.na(feature_vars)]
  train_data <- train_data[, c(keep_features, "Group")]

  # Cross-validation
  set.seed(123)
  fold_ids <- sample(rep(1:cv_folds, length.out = nrow(train_data)))

  cv_predictions <- lapply(seq_len(cv_folds), function(k) {
    test_idx <- which(fold_ids == k)
    train_idx <- which(fold_ids != k)

    train_fold <- train_data[train_idx, , drop = FALSE]
    test_fold <- train_data[test_idx, , drop = FALSE]

    rf_model <- randomForest::randomForest(
      Group ~ ., data = train_fold,
      ntree = ntree, mtry = if (is.null(mtry)) floor(sqrt(ncol(train_fold) - 1)) else mtry,
      importance = importance
    )

    pred <- predict(rf_model, newdata = test_fold)
    list(predictions = pred, true = test_fold$Group, model = rf_model)
  })

  all_predictions <- unlist(lapply(cv_predictions, `[[`, "predictions"))
  all_true <- unlist(lapply(cv_predictions, `[[`, "true"))

  accuracy <- mean(all_predictions == all_true)
  conf_matrix <- table(Predicted = all_predictions, True = all_true)

  # Build final model on all data
  final_model <- randomForest::randomForest(
    Group ~ ., data = train_data,
    ntree = ntree, mtry = if (is.null(mtry)) floor(sqrt(ncol(train_data) - 1)) else mtry,
    importance = importance
  )

  # Get importance
  importance_df <- if (importance) {
    imp <- randomForest::importance(final_model)
    imp_df <- as.data.frame(imp)
    imp_df$Feature <- rownames(imp_df)
    imp_df <- imp_df[order(-imp_df$MeanDecreaseGini), ]
    imp_df
  } else {
    NULL
  }

  # Compute SHAP-like values using permutation importance
  # (True SHAP requires xgboost or fastshap; here we use a permutation-based approximation)
  shap_values <- compute_permutation_shap(final_model, train_data)

  result <- list(
    model = final_model,
    accuracy = accuracy,
    confusion_matrix = conf_matrix,
    importance = importance_df,
    shap_values = shap_values,
    cv_predictions = cv_predictions
  )

  message("Random forest model built. CV accuracy: ",
          round(accuracy * 100, 2), "%")
  return(result)
}


#' @title Compute Permutation-based SHAP Values
#'
#' @description
#' 通过置换方法近似计算SHAP值。对每个feature，通过随机置换其值
#' 观察模型预测的变化，作为该feature对预测的贡献度。
#'
#' @param model 随机森林模型
#' @param data 训练数据
#'
#' @return 返回SHAP值矩阵
#' @keywords internal
compute_permutation_shap <- function(model, data) {
  features <- setdiff(colnames(data), "Group")
  predictions <- predict(model, data, type = "prob")

  shap_matrix <- matrix(0, nrow = nrow(data), ncol = length(features),
                         dimnames = list(rownames(data), features))

  for (feat in features) {
    permuted_data <- data
    permuted_data[[feat]] <- sample(permuted_data[[feat]])
    permuted_pred <- predict(model, permuted_data, type = "prob")
    shap_matrix[, feat] <- rowSums(permuted_pred - predictions)
  }

  return(shap_matrix)
}


#' @title Plot SHAP Summary
#'
#' @description
#' 绘制SHAP值摘要图，展示每个feature对模型预测的贡献。每个点代表
#' 一个样本，颜色表示feature值高低（红高蓝低），X轴为SHAP值。
#'
#' @param rf_result 列表，由build_random_forest_model返回
#' @param expr_matrix 数值矩阵，表达矩阵（用于获取feature值）
#' @param top_n 整数，显示的Top feature数，默认20
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认8
#' @param height 数值，图片高度（英寸），默认10
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' plot_shap_summary(rf_result, expr, top_n = 20, output_dir = "./figures")
#' }
#'
#' @export
plot_shap_summary <- function(rf_result, expr_matrix, top_n = 20,
                              output_dir = ".", width = 8, height = 10) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  shap_values <- rf_result$shap_values
  if (is.null(shap_values) || nrow(shap_values) == 0) {
    stop("No SHAP values available.")
  }

  # Select top features by mean abs SHAP
  mean_abs_shap <- colMeans(abs(shap_values), na.rm = TRUE)
  top_features <- names(sort(mean_abs_shap, decreasing = TRUE))[1:min(top_n, ncol(shap_values))]

  # Build long format
  shap_subset <- shap_values[, top_features, drop = FALSE]
  feature_values <- t(expr_matrix[top_features, , drop = FALSE])

  plot_data <- data.frame()
  for (feat in top_features) {
    feat_data <- data.frame(
      Feature = feat,
      SHAP = shap_subset[, feat],
      Value = feature_values[, feat]
    )
    plot_data <- rbind(plot_data, feat_data)
  }

  # Normalize feature values for color
  plot_data <- plot_data %>%
    dplyr::group_by(Feature) %>%
    dplyr::mutate(Value_norm = scale(Value)[, 1]) %>%
    dplyr::ungroup()

  # Order features by mean abs SHAP
  feature_order <- names(sort(mean_abs_shap[top_features], decreasing = TRUE))
  plot_data$Feature <- factor(plot_data$Feature, levels = rev(feature_order))

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = SHAP, y = Feature,
                                                fill = Value_norm)) +
    ggplot2::geom_jitter(size = 1, alpha = 0.6, shape = 21, color = "black",
                         width = 0.1, height = 0.2) +
    ggplot2::scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                                    midpoint = 0, name = "Feature Value\n(normalized)") +
    ggplot2::geom_vline(xintercept = 0, color = "black", linetype = "dashed") +
    ggplot2::labs(
      title = "SHAP Summary Plot",
      x = "SHAP Value (impact on model output)",
      y = "Feature"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold")
    )

  pdf_file <- file.path(output_dir, "SHAP_summary.pdf")
  png_file <- file.path(output_dir, "SHAP_summary.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("SHAP summary plot saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}


#' @title Build Linear Regression Classification Model
#'
#' @description
#' 针对样本进行分组预测，建立线性回归分类模型。对于二分类问题，
#' 使用线性回归拟合0/1标签；对于多分类问题，使用一对多策略。
#'
#' 该函数适用于样本分类预测和feature系数解释。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param sample_meta 数据框，样本元数据
#' @param cv_folds 整数，交叉验证折数，默认5
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item model: 线性回归模型
#'   \item accuracy: 交叉验证准确率
#'   \item coefficients: feature系数
#'   \item cv_predictions: 交叉验证预测结果
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' meta <- load_sample_metadata("meta.csv")
#'
#' lm_result <- build_linear_model(expr, meta, cv_folds = 5)
#' print(lm_result$accuracy)
#' }
#'
#' @export
build_linear_model <- function(expr_matrix, sample_meta, cv_folds = 5) {
  groups <- factor(sample_meta$sample_info[match(colnames(expr_matrix),
                                                  sample_meta$ID)])
  train_data <- as.data.frame(t(expr_matrix))

  # Remove features with zero variance
  feature_vars <- apply(train_data, 2, var, na.rm = TRUE)
  keep_features <- names(feature_vars)[feature_vars > 0 & !is.na(feature_vars)]
  train_data <- train_data[, keep_features, drop = FALSE]

  # One-vs-all for multi-class
  unique_groups <- levels(groups)
  n_groups <- length(unique_groups)

  # Cross-validation
  set.seed(123)
  fold_ids <- sample(rep(1:cv_folds, length.out = nrow(train_data)))

  cv_predictions <- lapply(seq_len(cv_folds), function(k) {
    test_idx <- which(fold_ids == k)
    train_idx <- which(fold_ids != k)

    train_fold <- train_data[train_idx, , drop = FALSE]
    test_fold <- train_data[test_idx, , drop = FALSE]
    train_groups <- groups[train_idx]
    test_groups <- groups[test_idx]

    # Build one-vs-all models
    predictions <- matrix(0, nrow = nrow(test_fold), ncol = n_groups)
    colnames(predictions) <- unique_groups

    for (g in unique_groups) {
      binary_label <- ifelse(train_groups == g, 1, 0)
      df <- train_fold
      df$label <- binary_label

      fit <- stats::lm(label ~ ., data = df)
      pred <- predict(fit, newdata = test_fold)
      predictions[, g] <- pred
    }

    # Assign to class with highest score
    pred_class <- unique_groups[apply(predictions, 1, which.max)]

    list(predictions = pred_class, true = as.character(test_groups))
  })

  all_predictions <- unlist(lapply(cv_predictions, `[[`, "predictions"))
  all_true <- unlist(lapply(cv_predictions, `[[`, "true"))

  accuracy <- mean(all_predictions == all_true)
  conf_matrix <- table(Predicted = all_predictions, True = all_true)

  # Build final model on all data (for binary case, return single model)
  if (n_groups == 2) {
    binary_label <- ifelse(groups == unique_groups[1], 1, 0)
    df <- train_data
    df$label <- binary_label
    final_model <- stats::lm(label ~ ., data = df)
    coefficients <- stats::coef(final_model)
  } else {
    final_models <- list()
    for (g in unique_groups) {
      binary_label <- ifelse(groups == g, 1, 0)
      df <- train_data
      df$label <- binary_label
      final_models[[g]] <- stats::lm(label ~ ., data = df)
    }
    final_model <- final_models
    coefficients <- sapply(final_models, function(m) stats::coef(m))
  }

  result <- list(
    model = final_model,
    accuracy = accuracy,
    confusion_matrix = conf_matrix,
    coefficients = coefficients,
    cv_predictions = cv_predictions
  )

  message("Linear model built. CV accuracy: ",
          round(accuracy * 100, 2), "%")
  return(result)
}


#' @title Perform Lasso Regression for Feature Selection
#'
#' @description
#' 针对样本预测模型，使用Lasso（L1正则化）回归提取重要feature。
#' Lasso通过L1正则化将不重要feature的系数压缩为0，实现特征选择。
#'
#' 该函数适用于高维数据（feature数>样本数）的特征选择和模型简化。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param sample_meta 数据框，样本元数据
#' @param alpha 数值，弹性网络混合参数，1为Lasso，0为Ridge，默认1
#' @param nfolds 整数，交叉验证折数，默认10
#' @param family 字符串，"binomial"（二分类）或"multinomial"（多分类）
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item cv_model: 交叉验证模型
#'   \item final_model: 最终模型
#'   \item selected_features: 被选中的重要feature
#'   \item coefficients: feature系数
#'   \item lambda: 最优lambda值
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' meta <- load_sample_metadata("meta.csv")
#'
#' lasso_result <- perform_lasso_regression(expr, meta, alpha = 1)
#' print(lasso_result$selected_features)
#' }
#'
#' @export
perform_lasso_regression <- function(expr_matrix, sample_meta,
                                      alpha = 1, nfolds = 10,
                                      family = NULL) {
  if (!requireNamespace("glmnet", quietly = TRUE)) {
    stop("Package 'glmnet' is required. Please install it.")
  }

  groups <- factor(sample_meta$sample_info[match(colnames(expr_matrix),
                                                  sample_meta$ID)])
  unique_groups <- levels(groups)
  n_groups <- length(unique_groups)

  if (is.null(family)) {
    family <- if (n_groups == 2) "binomial" else "multinomial"
  }

  x <- t(expr_matrix)
  y <- groups

  # Remove features with zero variance
  feature_vars <- apply(x, 2, var, na.rm = TRUE)
  keep_features <- names(feature_vars)[feature_vars > 0 & !is.na(feature_vars)]
  x <- x[, keep_features, drop = FALSE]

  # Cross-validation to select lambda
  set.seed(123)
  cv_model <- glmnet::cv.glmnet(x, y, family = family,
                                  alpha = alpha, nfolds = nfolds)

  # Build final model with optimal lambda
  final_model <- glmnet::glmnet(x, y, family = family,
                                 alpha = alpha,
                                 lambda = cv_model$lambda.min)

  # Extract coefficients
  if (family == "binomial") {
    coefs <- as.matrix(stats::coef(final_model))
    selected_idx <- which(coefs != 0)
    selected_features <- rownames(coefs)[selected_idx]
    selected_features <- selected_features[selected_features != "(Intercept)"]
    coefficients <- coefs[selected_idx, , drop = FALSE]
  } else {
    coefs_list <- lapply(seq_along(unique_groups), function(i) {
      coef_mat <- as.matrix(stats::coef(final_model)[[i]])
      colnames(coef_mat) <- unique_groups[i]
      coef_mat
    })
    coefs <- do.call(cbind, coefs_list)
    selected_idx <- which(rowSums(abs(coefs)) > 0)
    selected_features <- rownames(coefs)[selected_idx]
    selected_features <- selected_features[selected_features != "(Intercept)"]
    coefficients <- coefs[selected_idx, , drop = FALSE]
  }

  result <- list(
    cv_model = cv_model,
    final_model = final_model,
    selected_features = selected_features,
    coefficients = coefficients,
    lambda = cv_model$lambda.min,
    lambda_1se = cv_model$lambda.1se
  )

  message("Lasso regression completed. ", length(selected_features),
          " features selected at lambda = ",
          round(cv_model$lambda.min, 4))
  return(result)
}


#' @title Plot Lasso Coefficient Path
#'
#' @description
#' 绘制Lasso回归系数路径图，展示不同lambda值下各feature系数的变化。
#' 该图帮助理解feature选择过程和稳定性。
#'
#' @param lasso_result 列表，由perform_lasso_regression返回
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认10
#' @param height 数值，图片高度（英寸），默认7
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' plot_lasso_path(lasso_result, output_dir = "./figures")
#' }
#'
#' @export
plot_lasso_path <- function(lasso_result, output_dir = ".",
                            width = 10, height = 7) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  cv_model <- lasso_result$cv_model
  final_model <- lasso_result$final_model

  # Get coefficient path
  coefs_path <- stats::predict(final_model, type = "coefficients",
                                s = final_model$lambda)
  if (is.list(coefs_path)) {
    coefs_path <- do.call(cbind, lapply(coefs_path, as.matrix))
  }
  coefs_path <- as.matrix(coefs_path)

  # Build long format
  plot_data <- reshape2::melt(coefs_path,
                               varnames = c("Feature", "Lambda_idx"),
                               value.name = "Coefficient")
  plot_data$LogLambda <- log(final_model$lambda[plot_data$Lambda_idx])

  # Add L1 norm
  l1_norm <- colSums(abs(coefs_path[-1, , drop = FALSE]))
  l1_df <- data.frame(Lambda_idx = seq_along(l1_norm), L1_norm = l1_norm)
  plot_data <- merge(plot_data, l1_df, by = "Lambda_idx")

  p <- ggplot2::ggplot(plot_data[plot_data$Feature != "(Intercept)", ],
                       ggplot2::aes(x = LogLambda, y = Coefficient,
                                    group = Feature)) +
    ggplot2::geom_line(alpha = 0.7, color = "steelblue") +
    ggplot2::geom_vline(xintercept = log(lasso_result$lambda),
                         color = "red", linetype = "dashed") +
    ggplot2::annotate("text", x = log(lasso_result$lambda),
                       y = max(plot_data$Coefficient, na.rm = TRUE),
                       label = "lambda.min", color = "red", hjust = -0.1) +
    ggplot2::labs(
      title = "Lasso Coefficient Path",
      x = "Log(Lambda)",
      y = "Coefficient"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold")
    )

  pdf_file <- file.path(output_dir, "Lasso_coefficient_path.pdf")
  png_file <- file.path(output_dir, "Lasso_coefficient_path.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("Lasso coefficient path plot saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}
