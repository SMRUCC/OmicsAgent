# ==============================================================================
# OmicsFlow: OPLS-DA 分析与可视化
# ==============================================================================
# 正交偏最小二乘判别分析（Orthogonal Partial Least Squares Discriminant Analysis）
# ==============================================================================

#' 执行 OPLS-DA 分析
#'
#' @description 对表达矩阵执行正交偏最小二乘判别分析（OPLS-DA）。OPLS-DA 将
#'   预测性变异与正交变异分离，以提升可解释性。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param sample_info 含有样本元数据的数据框。
#' @param group_col 分组标签所在的列名。默认："sample_info"。
#' @param ncomp_pred 预测性组分数。默认：1。
#' @param ncomp_orth 正交组分数。默认：1。
#' @param exclude_groups 要排除的可选分组字符向量。默认：NULL。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{scores}：含预测性与正交得分的数据框。
#'     \item \code{loadings}：OPLS-DA Loading数据框（Feature x 组分），首列为
#'       \code{feature_id}。
#'     \item \code{vip}：VIP Score数据框。
#'     \item \code{model}：OPLS-DA 模型对象。
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
  X <- t(expr_matrix)

  # 检查 mixOmics 是否可用
  loadings_mat <- NULL
  if (requireNamespace("metaboanalyst", quietly = TRUE)) {
    # 使用 MetaboAnalyst 的 OPLS-DA
    model <- metaboanalyst:::oplsda(X, groups, ncomp_pred = ncomp_pred, ncomp_orth = ncomp_orth)
    scores <- as.data.frame(model$scores)
    if (is.null(colnames(scores)) || any(colnames(scores) == "")) {
      colnames(scores) <- c(paste0("t", 1:ncomp_pred), paste0("to", 1:ncomp_orth))
    }
    # MetaboAnalyst 的 OPLS-DA 通过模型矩阵暴露载荷
    if (!is.null(model$loadings)) {
      loadings_mat <- as.matrix(model$loadings)
      if (!is.null(colnames(loadings_mat))) {
        colnames(loadings_mat) <- c(paste0("p", 1:ncomp_pred), paste0("po", 1:ncomp_orth))
      }
    }
    vip_scores <- if (!is.null(model$vip)) model$vip else model$vipVn
  } else if (requireNamespace("mixOmics", quietly = TRUE)) {
    # 使用 mixOmics —— 它没有直接提供 OPLS-DA，但可用 PLS-DA
    # 并区分预测性/正交组分
    model <- mixOmics::plsda(X, groups, ncomp = ncomp_pred + ncomp_orth)

    # 提取得分
    scores <- as.data.frame(model$variates$X)
    colnames(scores) <- c(paste0("t", 1:ncomp_pred), paste0("to", 1:ncomp_orth))

    # Loading
    loadings_mat <- as.matrix(model$loadings$X)
    colnames(loadings_mat) <- c(paste0("p", 1:ncomp_pred), paste0("po", 1:ncomp_orth))

    # VIP
    vip_scores <- mixOmics::vip(model)
    if (is.matrix(vip_scores)) {
      vip_scores <- vip_scores[, ncol(vip_scores)]
    }
  } else {
    # 回退方案：手动 OPLS 实现
    warning("Neither 'metaboanalyst' nor 'mixOmics' available, using simplified OPLS-DA.")
    result <- .oplsda_base(X, groups, ncomp_pred = ncomp_pred, ncomp_orth = ncomp_orth)
    model <- result$model
    scores <- as.data.frame(result$scores)
    colnames(scores) <- c(paste0("t", 1:ncomp_pred), paste0("to", 1:ncomp_orth))
    loadings_mat <- as.matrix(result$loadings)
    vip_scores <- result$vip
  }

  # 准备得分数据框
  scores$sample_id <- rownames(scores)
  scores$group <- as.character(groups)
  scores <- scores[, c("sample_id", setdiff(colnames(scores), "sample_id")), drop = FALSE]
  rownames(scores) <- NULL

  # 准备 VIP 数据框
  vip_df <- data.frame(
    feature_id = rownames(expr_matrix),
    vip = vip_scores,
    stringsAsFactors = FALSE
  )
  vip_df <- vip_df[order(vip_df$vip, decreasing = TRUE), ]
  rownames(vip_df) <- vip_df$feature_id
  vip_df$feature_id <- NULL

  # 准备载荷数据框（Feature x 组分），首列为 feature_id
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


#' 基础 OPLS-DA 实现（内部函数）
#'
#' @keywords internal
#' @noRd
.oplsda_base <- function(X, Y, ncomp_pred = 1, ncomp_orth = 1) {
  # 使用带正交化的 NIPALS 的简化版 OPLS
  X <- as.matrix(X)

  # 哑变量 Y 矩阵
  if (is.factor(Y)) {
    Y_dummy <- model.matrix(~ 0 + Y)
  } else {
    Y_dummy <- as.matrix(Y)
  }

  n <- nrow(X)
  p <- ncol(X)
  q <- ncol(Y_dummy)

  # 总组分数
  ncomp_total <- ncomp_pred + ncomp_orth

  scores_mat <- matrix(0, n, ncomp_total)
  loadings_mat <- matrix(0, p, ncomp_total)
  Y_loadings <- matrix(0, q, ncomp_total)

  X_k <- X
  Y_k <- Y_dummy

  for (a in 1:ncomp_total) {
    if (a <= ncomp_pred) {
      # 预测性组分：交叉乘积中使用 Y
      cross <- crossprod(X_k, Y_k)
    } else {
      # 正交组分：仅使用 X
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

    # 收缩（deflation）
    X_k <- X_k - tcrossprod(ta, pa)
    if (a <= ncomp_pred) {
      Y_k <- Y_k - tcrossprod(ta, qa)
    }
  }

  colnames(scores_mat) <- c(paste0("t", 1:ncomp_pred), paste0("to", 1:ncomp_orth))
  colnames(loadings_mat) <- c(paste0("p", 1:ncomp_pred), paste0("po", 1:ncomp_orth))
  rownames(loadings_mat) <- colnames(X)

  # VIP 计算
  SSY <- colSums(Y_loadings^2)
  vip <- sqrt(p * rowSums(sweep(loadings_mat^2, 2, SSY, "*")) / sum(SSY))

  return(list(
    model = list(scores = scores_mat, loadings = loadings_mat, Y_loadings = Y_loadings),
    scores = scores_mat,
    loadings = loadings_mat,
    vip = vip
  ))
}


#' 绘制 OPLS-DA Score Plot
#'
#' @description 创建发表级质量的 OPLS-DA Score Plot，展示预测性组分与正交组分的对比。
#'
#' @param oplsda_result 来自 \code{run_oplsda()} 的结果。
#' @param color_col 用于颜色分组的列名（未使用，颜色基于分组）。
#'
#' @return 一个 ggplot 对象。
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

  # 查找预测性与正交得分列
  pred_col <- grep("^t[0-9]", colnames(scores), value = TRUE)[1]
  orth_col <- grep("^to[0-9]", colnames(scores), value = TRUE)[1]

  if (is.na(pred_col) || is.na(orth_col)) {
    # 回退到前 two 列
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

  # 添加椭圆
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
