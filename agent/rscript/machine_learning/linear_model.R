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
#'   此外，对每个比较（对照组编码为 a=0，其余各组编码为 b=1）执行逐Feature的
#'   单变量普通最小二乘（OLS）回归。响应变量 y 为数值型分组编码，x 为
#'   Feature丰度。完整的统计量（斜率、截距、R2、调整后 R2、p 值、线性方程字符串、
#'   比较标签）在 \code{coefficients} 表中返回。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param sample_info 含有样本元数据的数据框。
#' @param group_col 分组标签所在的列名。默认："sample_info"。
#' @param exclude_groups 要排除的可选分组。默认："QC"。
#' @param control_group 字符型，参考分组。该组样本在每个线性回归比较中编码为
#'   a=0。默认：NULL（使用第一个因子水平）。
#' @param top_features 可选的Feature字符向量。若为 NULL，则使用全部Feature。默认：NULL。
#' @param cv_folds 交叉验证折数。默认：5。
#' @param seed 随机种子。默认：42。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{model}：拟合的分类模型。
#'     \item \code{coefficients}：逐Feature单变量线性回归结果（数据框）。列：
#'       \code{feature_id} Feature名；
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
#'     \item \code{classification_coefficients}：分类模型的回归Coefficient
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
  
  # 先转 character 再建 factor：若 sample_info 列本身是 factor，
  # 排除分组后原水平仍会残留，导致 nlevels() 虚高、模型出现空分组。
  groups <- factor(as.character(sample_info[[group_col]]))
  if (nlevels(groups) < 2) {
    stop(sprintf("Column '%s' has %d level(s) after exclusion; need >= 2.",
                 group_col, nlevels(groups)))
  }
  if (!is.null(control_group)) {
    if (!control_group %in% levels(groups)) {
      stop(sprintf("control_group '%s' not found in '%s'. Available: %s",
                   control_group, group_col,
                   paste(levels(groups), collapse = ", ")))
    }
    groups <- stats::relevel(groups, ref = control_group)
  }
  
  X <- t(as.matrix(expr_matrix))
  
  # 若指定则筛选前 N 个Feature
  if (!is.null(top_features)) {
    top_features <- intersect(top_features, colnames(X))
    X <- X[, top_features, drop = FALSE]
  }
  
  # 在 make.names 之前保留原始Feature名（以便输出时还原）
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
  
  if (ncol(X) >= nrow(X)) {
    warning(sprintf(
      paste0("Feature count (%d) >= sample count (%d). The classifier is ",
             "saturated and will separate the training data perfectly; ",
             "training accuracy is meaningless. Pass 'top_features' to ",
             "restrict the predictor set."),
      ncol(X), nrow(X)))
  }
  
  # 单次拟合（在全部样本上），用于返回模型对象与Coefficient
  .fit_model <- function(df, grp) {
    if (n_groups == 2) {
      stats::glm(group ~ ., data = df, family = stats::binomial())
    } else if (requireNamespace("nnet", quietly = TRUE)) {
      nnet::multinom(group ~ ., data = df, trace = FALSE)
    } else if (requireNamespace("MASS", quietly = TRUE)) {
      MASS::lda(group ~ ., data = df)
    } else {
      stop("Multi-class classification requires 'nnet' or 'MASS' package.")
    }
  }
  
  .predict_class <- function(m, newdata, lv) {
    if (inherits(m, "glm")) {
      pr <- stats::predict(m, newdata = newdata, type = "response")
      factor(ifelse(pr > 0.5, lv[2], lv[1]), levels = lv)
    } else if (inherits(m, "lda")) {
      factor(stats::predict(m, newdata)$class, levels = lv)
    } else {
      factor(stats::predict(m, newdata = newdata, type = "class"), levels = lv)
    }
  }
  
  model <- suppressWarnings(.fit_model(data_df, groups))
  lv <- levels(groups)
  predicted_class <- suppressWarnings(.predict_class(model, data_df, lv))
  
  # 训练集（重代入）准确率——在 p >= n 时通常为 1，不能作为泛化能力指标
  train_accuracy <- mean(predicted_class == groups)
  conf_mat <- as.matrix(table(Predicted = predicted_class, Actual = groups))
  
  # ---- K 折交叉验证 ----
  # 此前 cv_folds 虽在函数签名与文档中声明，但从未被使用，
  # 返回的 accuracy 实际是重代入准确率。此处补齐真正的交叉验证。
  cv_accuracy <- NA_real_
  cv_predictions <- NULL
  cv_confusion_matrix <- NULL
  if (!is.null(cv_folds) && cv_folds >= 2 && nrow(data_df) >= cv_folds) {
    # 分层抽样，保证每折都覆盖所有分组
    fold_id <- integer(nrow(data_df))
    for (g in lv) {
      gi <- which(groups == g)
      fold_id[gi] <- sample(rep_len(seq_len(cv_folds), length(gi)))
    }
    cv_pred <- factor(rep(NA_character_, nrow(data_df)), levels = lv)
    for (k in seq_len(cv_folds)) {
      tr <- fold_id != k
      te <- !tr
      if (!any(te)) next
      # 训练折必须包含全部分组，否则模型无法预测缺失类别
      if (nlevels(droplevels(groups[tr])) < n_groups) next
      mk <- tryCatch(suppressWarnings(.fit_model(data_df[tr, , drop = FALSE],
                                                 groups[tr])),
                     error = function(e) NULL)
      if (is.null(mk)) next
      pk <- tryCatch(
        suppressWarnings(.predict_class(mk, data_df[te, , drop = FALSE], lv)),
        error = function(e) NULL)
      if (is.null(pk)) next
      cv_pred[te] <- pk
    }
    ok <- !is.na(cv_pred)
    if (any(ok)) {
      cv_accuracy <- mean(cv_pred[ok] == groups[ok])
      cv_predictions <- cv_pred
      cv_confusion_matrix <- as.matrix(
        table(Predicted = cv_pred[ok], Actual = groups[ok]))
    }
  }
  
  # accuracy 保持向后兼容语义（重代入准确率），
  # 泛化能力请参考 cv_accuracy。
  accuracy <- train_accuracy
  
  # 分类Coefficient（保留以兼容旧版本）
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
      # 行表示分组水平（多项 logit）
      class_coef_df <- do.call(rbind, lapply(rownames(class_coefs), function(g) {
        data.frame(group = g, feature = colnames(class_coefs),
                   coefficient = as.numeric(class_coefs[g, ]),
                   stringsAsFactors = FALSE)
      }))
    } else {
      # 行表示Feature（如 LDA 缩放值），列表示分组水平
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
  # 逐Feature单变量线性回归：
  #   y = 0/1 分组编码（对照组 a=0，其余各组 b=1）
  #   x = 单个Feature丰度
  #   对每个比较拟合 y ~ x，并导出 斜率/截距/R2/调整后R2/p值
  # ============================================================================
  ref_group <- levels(groups)[1]
  case_groups <- levels(groups)[-1]
  
  lm_parts <- list()
  for (cg in case_groups) {
    # 仅保留该比较中两个分组的样本
    idx <- groups %in% c(ref_group, cg)
    x_sub <- X[idx, , drop = FALSE]
    y <- ifelse(as.character(groups[idx]) == cg, 1, 0)
    n <- length(y)
    if (n < 3 || length(unique(y)) < 2) {
      warning("Skipping comparison '", ref_group, "' vs '", cg,
              "': insufficient samples for linear regression.")
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
        warning("Feature '", feat_id, "' in comparison '", comparison_label,
                "' failed in linear regression.")
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
      # 方程字符串 "y = a*x + b"（处理负截距符号）
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
    # 在该比较内对 p 值进行 BH 校正
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
    train_accuracy = train_accuracy,
    cv_accuracy = cv_accuracy,
    cv_folds = cv_folds,
    predictions = predicted_class,
    cv_predictions = cv_predictions,
    confusion_matrix = conf_mat,
    cv_confusion_matrix = cv_confusion_matrix,
    n_features = ncol(X),
    n_samples = nrow(X),
    groups = lv
  ))
}
