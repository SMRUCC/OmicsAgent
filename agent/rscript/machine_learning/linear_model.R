# ==============================================================================
# OmicsFlow: 线性回归模型
# ==============================================================================
# 使用线性回归进行样本分类
# ==============================================================================

#' 运行线性回归分类模型
#'
#' @description 构建用于样本分组预测的线性回归模型。二分类时使用逻辑回归，
#'   多分类时使用多项逻辑回归。
#'
#'   此外，对每个比较（对照组编码为 a=0，其余各组编码为 b=1）执行逐特征的
#'   单变量普通最小二乘（OLS）回归。响应变量 y 为数值型分组编码，x 为
#'   特征丰度。完整的统计量（斜率、截距、R2、调整后 R2、p 值、线性方程字符串、
#'   比较标签）在 \code{coefficients} 表中返回。
#'
#' @param expr_matrix 数值矩阵（特征 x 样本）。
#' @param sample_info 含有样本元数据的数据框。
#' @param group_col 分组标签所在的列名。默认："sample_info"。
#' @param exclude_groups 要排除的可选分组。默认："QC"。
#' @param control_group 字符型，参考分组。该组样本在每个线性回归比较中编码为
#'   a=0。默认：NULL（使用第一个因子水平）。
#' @param top_features 可选的特征字符向量。若为 NULL，则使用全部特征。默认：NULL。
#' @param cv_folds 交叉验证折数。默认：5。
#' @param seed 随机种子。默认：42。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{model}：拟合的分类模型。
#'     \item \code{coefficients}：逐特征单变量线性回归结果（数据框）。列：
#'       \code{feature_id} 特征名；
#'       \code{comparison} 分组比较标签，例如
#'         "Standard (control)(a=0) vs Clostridium difficile infection(b=1)"；
#'       \code{slope} 回归斜率（y = a*x + b 中的 a）；
#'       \code{intercept} 回归截距（y = a*x + b 中的 b）；
#'       \code{r2} R 平方；
#'       \code{adj_r2} 调整后的 R 平方；
#'       \code{p_value} 斜率的 p 值；
#'       \code{p_adj} 每个比较内的 BH 校正 p 值；
#'       \code{n} 比较中使用的样本数；
#'       \code{equation} 线性方程字符串，例如 "y = 0.4275*x + 0.5388"。
#'     \item \code{classification_coefficients}：分类模型的回归系数
#'       （列：group、feature、coefficient）。
#'     \item \code{accuracy}：分类准确率。
#'     \item \code{predictions}：预测标签。
#'     \item \code{confusion_matrix}：混淆矩阵。
#'   }
#'
#' @examples
#' \dontrun{
#' lr <- run_linear_model(expr_matrix, sample_info)
#' print(lr$accuracy)
#' print(lr$coefficients)
#' }
#'
#' @export
run_linear_model <- function(expr_matrix, sample_info,
                            group_col = "sample_info",
                            exclude_groups = "QC", control_group = NULL,
                            top_features = NULL, cv_folds = 5, seed = 42) {
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

  # 若指定则筛选前 N 个特征
  if (!is.null(top_features)) {
    top_features <- intersect(top_features, colnames(X))
    X <- X[, top_features, drop = FALSE]
  }

  # 在 make.names 之前保留原始特征名（以便输出时还原）
  orig_feat_names <- colnames(X)

  # 构建数据框
  X <- as.matrix(X)
  colnames(X) <- make.names(colnames(X), unique = TRUE)
  safe_feat_names <- colnames(X)
  feat_name_map <- stats::setNames(orig_feat_names, safe_feat_names)
  data_df <- as.data.frame(X)
  data_df$group <- groups

  # 确定模型类型
  n_groups <- nlevels(groups)

  if (n_groups == 2) {
    # 二分类：逻辑回归
    formula_str <- "group ~ ."
    model <- stats::glm(as.formula(formula_str), data = data_df,
                        family = stats::binomial())
    predictions <- stats::predict(model, type = "response")
    predicted_class <- ifelse(predictions > 0.5, levels(groups)[2],
                              levels(groups)[1])
    predicted_class <- factor(predicted_class, levels = levels(groups))
  } else {
    # 多分类：多项逻辑回归
    if (requireNamespace("nnet", quietly = TRUE)) {
      formula_str <- "group ~ ."
      model <- nnet::multinom(as.formula(formula_str), data = data_df,
                               trace = FALSE)
      predictions <- stats::predict(model, type = "class")
      predicted_class <- factor(predictions, levels = levels(groups))
    } else {
      # 回退：LDA
      if (requireNamespace("MASS", quietly = TRUE)) {
        model <- MASS::lda(x = X, grouping = groups)
        predictions <- stats::predict(model, X)$class
        predicted_class <- factor(predictions, levels = levels(groups))
      } else {
        stop("多分类需要 'nnet' 或 'MASS' 包。")
      }
    }
  }

  # 准确率
  accuracy <- mean(predicted_class == groups)
  conf_mat <- as.matrix(table(Predicted = predicted_class, Actual = groups))

  # 分类系数（保留以兼容旧版本）
  class_coefs <- stats::coef(model)
  if (is.list(class_coefs)) {
    class_coef_df <- do.call(rbind, lapply(names(class_coefs), function(n) {
      data.frame(group = n, feature = names(class_coefs[[n]]),
                 coefficient = class_coefs[[n]], stringsAsFactors = FALSE)
    }))
    rownames(class_coef_df) <- NULL
  } else if (is.matrix(class_coefs)) {
    if (length(rownames(class_coefs)) > 1 &&
        all(rownames(class_coefs) %in% levels(groups))) {
      # Rows are group levels (multinomial logit)
      class_coef_df <- do.call(rbind, lapply(rownames(class_coefs), function(g) {
        data.frame(group = g, feature = colnames(class_coefs),
                   coefficient = as.numeric(class_coefs[g, ]),
                   stringsAsFactors = FALSE)
      }))
    } else {
      # Rows are features (e.g. LDA scaling), columns are group levels
      class_coef_df <- do.call(rbind, lapply(colnames(class_coefs), function(g) {
        data.frame(group = g, feature = rownames(class_coefs),
                   coefficient = as.numeric(class_coefs[, g]),
                   stringsAsFactors = FALSE)
      }))
    }
    rownames(class_coef_df) <- NULL
  } else {
    class_coef_df <- data.frame(
      group = levels(groups)[1],
      feature = names(class_coefs),
      coefficient = as.numeric(class_coefs),
      stringsAsFactors = FALSE
    )
    rownames(class_coef_df) <- NULL
  }

  # ============================================================================
  # Per-feature univariate linear regression:
  #   y = 0/1 group encoding (control a=0, each other group b=1)
  #   x = single feature abundance
  #   for each comparison: fit y ~ x and export slope/intercept/R2/adjR2/pvalue
  # ============================================================================
  ref_group <- levels(groups)[1]
  case_groups <- levels(groups)[-1]

  lm_parts <- list()
  for (cg in case_groups) {
    # Keep only samples belonging to the two groups of this comparison
    idx <- groups %in% c(ref_group, cg)
    x_sub <- X[idx, , drop = FALSE]
    y <- ifelse(as.character(groups[idx]) == cg, 1, 0)
    n <- length(y)
    if (n < 3 || length(unique(y)) < 2) {
      warning("Skipping comparison '", ref_group, "' vs '", cg,
              "': not enough samples for linear regression.")
      next
    }
    comparison_label <- paste0(ref_group, "(a=0) vs ", cg, "(b=1)")

    comp_rows <- lapply(seq_len(ncol(x_sub)), function(j) {
      safe_name <- colnames(x_sub)[j]
      feat_id <- if (safe_name %in% names(feat_name_map)) {
        feat_name_map[[safe_name]]
      } else {
        safe_name
      }
      x <- x_sub[, j]

      fit <- tryCatch(stats::lm(y ~ x), error = function(e) NULL)
      if (is.null(fit)) {
        warning("Linear regression failed for feature '", feat_id,
                "' in comparison '", comparison_label, "'.")
        return(data.frame(
          feature_id = feat_id, comparison = comparison_label,
          slope = NA_real_, intercept = NA_real_,
          r2 = NA_real_, adj_r2 = NA_real_,
          p_value = NA_real_, p_adj = NA_real_,
          n = as.integer(n), equation = NA_character_,
          stringsAsFactors = FALSE
        ))
      }

      s <- summary(fit)
      slope <- unname(stats::coef(fit)[2])
      intercept <- unname(stats::coef(fit)[1])
      r2 <- s$r.squared
      adj_r2 <- s$adj.r.squared
      p_value <- if (nrow(s$coefficients) >= 2) s$coefficients[2, 4] else NA_real_
      # Equation string "y = a*x + b" (handles negative intercept sign)
      eq_slope <- formatC(slope, format = "g", digits = 4)
      eq_intercept <- formatC(abs(intercept), format = "g", digits = 4)
      eq_sign <- ifelse(intercept < 0, "-", "+")
      equation <- paste0("y = ", eq_slope, "*x ", eq_sign, " ", eq_intercept)

      data.frame(
        feature_id = feat_id, comparison = comparison_label,
        slope = slope, intercept = intercept,
        r2 = r2, adj_r2 = adj_r2,
        p_value = p_value, p_adj = NA_real_,
        n = as.integer(n), equation = equation,
        stringsAsFactors = FALSE
      )
    })

    comp_df <- do.call(rbind, comp_rows)
    # BH adjust p-values within this comparison
    non_na <- !is.na(comp_df$p_value)
    if (any(non_na)) {
      comp_df$p_adj[non_na] <- stats::p.adjust(comp_df$p_value[non_na],
                                               method = "BH")
    }
    lm_parts[[cg]] <- comp_df
  }

  if (length(lm_parts) == 0) {
    coef_df <- data.frame(
      feature_id = character(0), comparison = character(0),
      slope = numeric(0), intercept = numeric(0),
      r2 = numeric(0), adj_r2 = numeric(0),
      p_value = numeric(0), p_adj = numeric(0),
      n = integer(0), equation = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    coef_df <- do.call(rbind, lm_parts)
    rownames(coef_df) <- NULL
  }

  return(list(
    model = model,
    coefficients = coef_df,
    classification_coefficients = class_coef_df,
    accuracy = accuracy,
    predictions = predicted_class,
    confusion_matrix = conf_mat
  ))
}
