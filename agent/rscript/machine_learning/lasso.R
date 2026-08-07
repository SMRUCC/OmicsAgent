# ==============================================================================
# OmicsFlow: Lasso 回归
# ==============================================================================
# 通过 L1 正则化进行特征选择
# ==============================================================================

#' 运行 Lasso 回归以进行特征选择
#'
#' @description 执行 Lasso（L1 惩罚）回归，用于识别重要的预测性特征。
#'   支持二分类与多分类。
#'
#' @param expr_matrix 数值矩阵（特征 x 样本）。
#' @param sample_info 含有样本元数据的数据框。
#' @param group_col 分组标签所在的列名。默认："sample_info"。
#' @param exclude_groups 要排除的可选分组。默认："QC"。
#' @param control_group 字符型，参考分组。默认：NULL。
#' @param n_folds 用于选择 lambda 的 CV 折数。默认：10。
#' @param alpha 弹性网络混合参数（1 = lasso，0 = ridge）。默认：1。
#' @param seed 随机种子。默认：42。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{model}：拟合的 cv.glmnet 模型。
#'     \item \code{selected_features}：所选特征的字符向量。
#'     \item \code{coefficients}：非零系数的数据框。
#'     \item \code{lambda}：所选的 lambda 值。
#'     \item \code{accuracy}：分类准确率。
#'     \item \code{confusion_matrix}：混淆矩阵。
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
  if (!is.null(control_group)) {
    groups <- stats::relevel(groups, ref = control_group)
  }

  X <- t(as.matrix(expr_matrix))
  n_groups <- nlevels(groups)

  # 模型族
  if (n_groups == 2) {
    family <- "binomial"
  } else {
    family <- "multinomial"
  }

  # 交叉验证 Lasso
  cv_model <- glmnet::cv.glmnet(
    x = X, y = groups, family = family,
    alpha = alpha, nfolds = n_folds, type.measure = "class"
  )

  # 最佳 lambda
  best_lambda <- cv_model$lambda.min

  # 预测
  predictions <- stats::predict(cv_model, newx = X, s = "lambda.min",
                                  type = "class")
  predicted_class <- factor(predictions, levels = levels(groups))
  accuracy <- mean(predicted_class == groups)
  conf_mat <- as.matrix(table(Predicted = predicted_class, Actual = groups))

  # 提取非零系数
  coefs <- stats::coef(cv_model, s = "lambda.min")

  if (is.list(coefs)) {
    # 多分类：系数矩阵列表
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
    # 二分类
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

  # 将特征设为行名（多个分组可能产生重复）
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


#' 绘制 Lasso 系数路径
#'
#' @description 创建 Lasso 系数随 L1 范数变化的曲线图。
#'
#' @param lasso_result 来自 \code{run_lasso()} 的结果。
#'
#' @return 一个 ggplot 对象。
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

  # 构建用于绘图的数据
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
      title = "Lasso 系数路径",
      x = expression(log(lambda)),
      y = "系数",
      color = "特征"
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
