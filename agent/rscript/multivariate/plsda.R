# ==============================================================================
# OmicsFlow: PLS-DA 分析与可视化
# ==============================================================================
# 偏最小二乘判别分析（Partial Least Squares Discriminant Analysis）
# ==============================================================================

#' 执行 PLS-DA 分析
#'
#' @description 对表达矩阵执行偏最小二乘判别分析（PLS-DA）。PLS-DA 是一种
#'   有监督方法，可最大化预定义分组之间的分离度。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param sample_info 含有样本元数据的数据框。
#' @param group_col 分组标签所在的列名。默认："sample_info"。
#' @param ncomp 组分数量。默认：2。
#' @param exclude_groups 要排除的可选分组字符向量（如 "QC"）。默认：NULL。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{scores}：PLS-DA 得分数据框。
#'     \item \code{loadings}：PLS-DA Loading数据框。
#'     \item \code{vip}：VIP Score数据框。
#'     \item \code{model}：PLS-DA 模型对象。
#'     \item \code{groups}：分组水平。
#'   }
#'
#' @examples
#' \dontrun{
#' plsda <- run_plsda(expr_matrix, sample_info, ncomp = 3)
#' print(head(plsda$vip))
#' }
#'
#' @export
run_plsda <- function(expr_matrix, sample_info, group_col = "sample_info",
                     ncomp = 2, exclude_groups = NULL) {
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

  # 获取分组因子
  groups <- factor(sample_info[[group_col]])

  # 转置以进行分析
  X <- t(expr_matrix)

  # 优先使用 mixOmics，否则使用基础 PLS
  if (requireNamespace("mixOmics", quietly = TRUE)) {
    model <- mixOmics::plsda(X, groups, ncomp = ncomp)
    scores <- as.data.frame(model$variates$X)
    scores$sample_id <- rownames(scores)
    scores$group <- as.character(groups)

    # 计算 VIP
    vip_scores <- .calculate_vip(model)
    loadings <- as.data.frame(model$loadings$X)
    loadings$feature_id <- rownames(loadings)

  } else {
    # 回退方案：使用基础 PLS 实现
    warning("Package 'mixOmics' not installed, using basic PLS implementation.")
    result <- .plsda_base(X, groups, ncomp = ncomp)
    model <- result$model
    scores <- as.data.frame(result$scores)
    scores$sample_id <- rownames(scores)
    scores$group <- as.character(groups)
    vip_scores <- result$vip
    loadings <- as.data.frame(result$loadings)
    loadings$feature_id <- rownames(loadings)
  }

  # 准备 VIP 数据框
  vip_df <- data.frame(
    feature_id = rownames(expr_matrix),
    vip = vip_scores,
    stringsAsFactors = FALSE
  )
  vip_df <- vip_df[order(vip_df$vip, decreasing = TRUE), ]
  rownames(vip_df) <- vip_df$feature_id
  vip_df$feature_id <- NULL

  # 重置 scores/loadings 的行名，以免 export_table 前置重复
  # 的 sample_id/feature_id 列；保留 id 列作为真实列。
  if ("sample_id" %in% colnames(scores)) {
    scores <- scores[, c("sample_id", setdiff(colnames(scores), "sample_id")), drop = FALSE]
  }
  rownames(scores) <- NULL
  if (!is.null(loadings)) {
    loadings <- loadings[, c("feature_id", setdiff(colnames(loadings), "feature_id")), drop = FALSE]
    rownames(loadings) <- NULL
  }

  return(list(
    scores = scores,
    loadings = loadings,
    vip = vip_df,
    model = model,
    groups = levels(groups)
  ))
}


#' 计算 VIP Score（内部函数）
#'
#' @keywords internal
#' @noRd
.calculate_vip <- function(model) {
  # 基于 mixOmics 的 VIP 计算
  if (inherits(model, "mixo_plsda") || inherits(model, "mixo_pls")) {
    # 获取完整 VIP 矩阵
    vip <- mixOmics::vip(model)
    if (is.matrix(vip)) {
      return(vip[, ncol(vip)])
    } else {
      return(vip)
    }
  } else {
    return(rep(1, nrow(model$loadings)))
  }
}


#' 基础 PLS-DA 实现（内部回退函数）
#'
#' @keywords internal
#' @noRd
.plsda_base <- function(X, Y, ncomp = 2) {
  # 简单的 NIPALS PLS
  X <- as.matrix(X)

  # 为 Y 构造哑变量矩阵
  if (is.factor(Y)) {
    Y_dummy <- model.matrix(~ 0 + Y)
    colnames(Y_dummy) <- levels(Y)
  } else {
    Y_dummy <- as.matrix(Y)
  }

  n <- nrow(X)
  p <- ncol(X)
  q <- ncol(Y_dummy)

  # 初始化
  scores_mat <- matrix(0, n, ncomp)
  loadings_mat <- matrix(0, p, ncomp)
  Y_loadings <- matrix(0, q, ncomp)

  X_k <- X
  Y_k <- Y_dummy

  for (a in 1:ncomp) {
    # 交叉乘积的 SVD
    cross <- crossprod(X_k, Y_k)
    svd_result <- svd(cross)
    wa <- svd_result$u[, 1]
    ta <- X_k %*% wa
    ta <- ta / sqrt(sum(ta^2))
    pa <- crossprod(X_k, ta) / as.numeric(crossprod(ta))
    qa <- crossprod(Y_k, ta) / as.numeric(crossprod(ta))

    scores_mat[, a] <- as.vector(ta)
    loadings_mat[, a] <- as.vector(pa)
    Y_loadings[, a] <- as.vector(qa)

    # 收缩（deflation）
    X_k <- X_k - tcrossprod(ta, pa)
    Y_k <- Y_k - tcrossprod(ta, qa)
  }

  colnames(scores_mat) <- paste0("comp", 1:ncomp)
  colnames(loadings_mat) <- paste0("comp", 1:ncomp)
  rownames(loadings_mat) <- colnames(X)

  # 简单 VIP 计算
  # VIP_i = sqrt(p * sum_a(SSY_a * w_ia^2) / sum_a(SSY_a))
  SSY <- colSums(Y_loadings^2)
  vip <- sqrt(p * rowSums(sweep(loadings_mat^2, 2, SSY, "*")) / sum(SSY))

  return(list(
    model = list(
      scores = scores_mat,
      loadings = loadings_mat,
      Y_loadings = Y_loadings
    ),
    scores = scores_mat,
    loadings = loadings_mat,
    vip = vip
  ))
}


#' 绘制 PLS-DA Score Plot
#'
#' @description 创建发表级质量的 PLS-DA Score Plot。
#'
#' @param plsda_result 来自 \code{run_plsda()} 的结果。
#' @param sample_info 样本元数据数据框。
#' @param color_col 用于颜色分组的列名。默认："sample_info"。
#' @param comp_x x 轴使用的组分。默认：1。
#' @param comp_y y 轴使用的组分。默认：2。
#' @param show_ellipse 逻辑值，是否显示置信椭圆。默认：TRUE。
#' @param show_labels 逻辑值，是否显示样本标签。默认：FALSE。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' plsda <- run_plsda(expr_matrix, sample_info)
#' p <- plot_plsda_scores(plsda, sample_info)
#' }
#'
#' @export
plot_plsda_scores <- function(plsda_result, sample_info,
                              color_col = "sample_info",
                              comp_x = 1, comp_y = 2,
                              show_ellipse = TRUE, show_labels = FALSE) {
  scores <- plsda_result$scores

  comp_cols <- paste0("comp", c(comp_x, comp_y))
  if (!comp_cols[1] %in% colnames(scores)) {
    comp_cols <- paste0("Comp", c(comp_x, comp_y))
  }

  plot_data <- data.frame(
    sample_id = scores$sample_id,
    comp_x = scores[[comp_cols[1]]],
    comp_y = scores[[comp_cols[2]]],
    group = scores$group
  )

  # 颜色
  groups <- unique(plot_data$group)
  colors <- make_group_colors(groups)

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = comp_x, y = comp_y)) +
    ggplot2::geom_point(ggplot2::aes(color = group), size = 3, alpha = 0.85) +
    ggplot2::scale_color_manual(values = colors) +
    ggplot2::labs(
      title = "PLS-DA Score Plot",
      x = paste0("Component ", comp_x),
      y = paste0("Component ", comp_y)
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 11),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right"
    ) +
    ggplot2::coord_equal()

  # 椭圆
  if (show_ellipse) {
    for (g in groups) {
      g_data <- plot_data[plot_data$group == g, , drop = FALSE]
      if (nrow(g_data) >= 3) {
        center <- c(mean(g_data$comp_x), mean(g_data$comp_y))
        cov_mat <- stats::cov(g_data[, c("comp_x", "comp_y")])
        if (det(cov_mat) > 1e-10) {
          chi_sq <- stats::qchisq(0.95, 2)
          eig <- eigen(cov_mat)
          angles <- seq(0, 2 * pi, length.out = 100)
          ellipse_df <- data.frame(
            comp_x = center[1] + sqrt(chi_sq) * eig$vectors[1, 1] * sqrt(eig$values[1]) * cos(angles) +
                      sqrt(chi_sq) * eig$vectors[1, 2] * sqrt(eig$values[2]) * sin(angles),
            comp_y = center[2] + sqrt(chi_sq) * eig$vectors[2, 1] * sqrt(eig$values[1]) * cos(angles) +
                      sqrt(chi_sq) * eig$vectors[2, 2] * sqrt(eig$values[2]) * sin(angles)
          )
          p <- p + ggplot2::geom_path(data = ellipse_df,
                                      ggplot2::aes(x = comp_x, y = comp_y),
                                      color = colors[g], linewidth = 0.6,
                                      linetype = "dashed", inherit.aes = FALSE)
        }
      }
    }
  }

  if (show_labels) {
    p <- p + ggrepel::geom_text_repel(
      ggplot2::aes(label = sample_id), size = 2.5, max.overlaps = 20
    )
  }

  return(p)
}


#' 绘制 VIP Score图
#'
#' @description 创建 PLS-DA 前 N 个 VIP Score的条形图。
#'
#' @param plsda_result 来自 \code{run_plsda()} 的结果。
#' @param top_n 展示的前 N 个Feature数量。默认：20。
#' @param threshold VIP 阈值线。默认：1.0。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_vip(plsda_result, top_n = 30)
#' }
#'
#' @export
plot_vip <- function(plsda_result, top_n = 20, threshold = 1.0) {
  vip_df <- plsda_result$vip
  top_df <- head(vip_df, top_n)

  # 重新排序
  top_df$feature_id <- factor(rownames(top_df),
                               levels = rownames(top_df)[nrow(top_df):1])

  p <- ggplot2::ggplot(top_df, ggplot2::aes(x = feature_id, y = vip)) +
    ggplot2::geom_bar(stat = "identity", fill = "#4a90d9") +
    ggplot2::geom_hline(yintercept = threshold, color = "#e74c3c",
                        linetype = "dashed", linewidth = 0.8) +
    ggplot2::coord_flip() +
    ggplot2::labs(
      title = "VIP Scores (Top Features)",
      x = "Feature",
      y = "VIP Score"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 9),
      axis.title = ggplot2::element_text(size = 12)
    )

  return(p)
}
