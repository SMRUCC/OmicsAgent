# ==============================================================================
# OmicsFlow：跨组学线性回归
# ==============================================================================
# 在两个组学层的特征之间拟合单变量线性模型，其中一个层作为解释变量（x），
# 另一个层作为响应变量（y）。支持特征级别的斜率 / p 值 / R2 表，以及带拟合
# 线的逐对散点图。
# ==============================================================================

#' 两个组学层之间的单变量线性回归
#'
#' @description 对于在相同样本上共享的每一对 (x 特征, y 特征)，用 \code{lm()}
#'   拟合 y ~ x，并记录斜率、截距、显著性与拟合优度。p 值在所有被测特征对上
#'   进行校正。这是一种直接的线性关联筛查，与别处使用的基于秩的相关互为补充。
#'
#' @param x_matrix 解释变量层的数值矩阵（特征 x 样本）。
#' @param y_matrix 响应变量层的数值矩阵（特征 x 样本）。
#' @param x_name 解释变量层的标签。默认："x"。
#' @param y_name 响应变量层的标签。默认："y"。
#' @param p_adjust 多重检验校正方法。默认："BH"。
#' @param min_samples 所需的最小共享样本数。默认：6。
#' @param verbose 逻辑值，是否打印简短摘要。默认：TRUE。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{pairs}: 数据框，含 x_feature、y_feature、x_name、y_name、
#'       slope、intercept、se、t_stat、p_value、padj、r_squared 与 n_samples。
#'     \item \code{x_summary}: 每个 x 特征对应的显著 y 响应计数。
#'     \item \code{y_summary}: 每个 y 特征对应的显著 x 预测因子计数。
#'   }
#'
#' @examples
#' \dontrun{
#' reg <- run_cross_omics_regression(get_omics_matrix(mo, "microbiome"),
#'                                   get_omics_matrix(mo, "volatilome"),
#'                                   x_name = "microbiome", y_name = "volatilome")
#' }
#'
#' @export
run_cross_omics_regression <- function(x_matrix, y_matrix,
                                       x_name = "x", y_name = "y",
                                       p_adjust = "BH",
                                       min_samples = 6,
                                       verbose = TRUE) {
  if (!is.matrix(x_matrix)) x_matrix <- as.matrix(x_matrix)
  if (!is.matrix(y_matrix)) y_matrix <- as.matrix(y_matrix)

  common <- intersect(colnames(x_matrix), colnames(y_matrix))
  if (length(common) < min_samples) {
    stop(sprintf("Only %d shared samples; need at least %d.", length(common), min_samples))
  }
  X <- x_matrix[, common, drop = FALSE]
  Y <- y_matrix[, common, drop = FALSE]

  # 去除任一层中零方差的特征。
  X <- drop_zero_variance(X, label = x_name, verbose = verbose)
  Y <- drop_zero_variance(Y, label = y_name, verbose = verbose)

  if (nrow(X) == 0 || nrow(Y) == 0) {
    stop("At least one of the layers has no usable feature after filtering.")
  }

  # ---------------------------------------------------------------------------
  # 对于单变量模型 y ~ x，回归统计量可直接由 Pearson 相关系数 r 与特征矩得出：
  #   slope      = r * sd(y) / sd(x)
  #   intercept  = mean(y) - slope * mean(x)
  #   t_stat     = r * sqrt((n - 2) / (1 - r^2))
  #   p_value    = 2 * pt(-abs(t), df = n - 2)
  #   r_squared  = r^2
  #   se_slope   = slope / t_stat
  # 这与 stats::lm(y ~ x) 完全等价，但避免了每对特征调用一次 lm() 的巨大开销，
  # 从而使大规模的 x×y 筛查变得可行。
  # ---------------------------------------------------------------------------
  n <- length(common)
  df <- n - 2L

  # 对每个特征在样本方向上中心化；其叉积即给出
  # 特征间交叉乘积之和（n_features_x x n_features_y）。
  Xc <- X - rowMeans(X)             # features x samples
  Yc <- Y - rowMeans(Y)             # features x samples
  Sxx <- rowSums(Xc * Xc)
  Syy <- rowSums(Yc * Yc)
  Sxy <- Xc %*% t(Yc)               # n_features_x x n_features_y

  r <- Sxy / sqrt(outer(Sxx, Syy))
  r <- pmax(pmin(r, 1), -1)         # guard against rounding beyond [-1, 1]

  t_val <- r * sqrt(df / pmax(1 - r * r, .Machine$double.eps))
  p_val <- 2 * stats::pt(-abs(t_val), df = df)

  sx <- sqrt(Sxx / (n - 1))
  sy <- sqrt(Syy / (n - 1))
  mx <- rowMeans(X)
  my <- rowMeans(Y)

  slope <- r * outer(1 / sx, sy)
  intercept <- outer(rep(1, nrow(X)), my) - t(t(slope) * mx)
  r2 <- r * r
  se_slope <- abs(slope) / pmax(abs(t_val), .Machine$double.eps)

  is_finite <- !is.na(r) & is.finite(t_val) & abs(r) < 1

  # 以 x_feature 在前的 expand.grid 让 x 变化最快，从而与斜率 / p 值矩阵
  # 的按列（as.vector）存储顺序一致。
  pairs <- expand.grid(x_feature = rownames(X), y_feature = rownames(Y),
                       KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  pairs$x_name <- x_name
  pairs$y_name <- y_name
  pairs$slope <- as.vector(slope)
  pairs$intercept <- as.vector(intercept)
  pairs$se <- as.vector(se_slope)
  pairs$t_stat <- as.vector(t_val)
  pairs$p_value <- as.vector(p_val)
  pairs$r_squared <- as.vector(r2)
  pairs$n_samples <- n
  pairs <- pairs[is_finite, , drop = FALSE]

  if (nrow(pairs) == 0) {
    cat(sprintf("  [regression] %s -> %s: no valid fit produced.\n", x_name, y_name))
    return(list(pairs = data.frame(), x_summary = data.frame(), y_summary = data.frame()))
  }
  out <- pairs
  out$padj <- stats::p.adjust(out$p_value, method = p_adjust)
  out$significant <- out$padj < 0.05
  out <- out[order(out$padj, -abs(out$slope)), , drop = FALSE]
  rownames(out) <- NULL

  x_summary <- do.call(rbind, lapply(split(out, out$x_feature), function(sub) {
    data.frame(
      x_feature = sub$x_feature[1],
      x_name = sub$x_name[1],
      n_responses_tested = nrow(sub),
      n_significant = sum(sub$significant),
      best_y = sub$y_feature[1],
      best_padj = sub$padj[1],
      best_r2 = sub$r_squared[1],
      stringsAsFactors = FALSE
    )
  }))
  x_summary <- x_summary[order(-x_summary$n_significant, -x_summary$best_r2), , drop = FALSE]
  rownames(x_summary) <- NULL

  y_summary <- do.call(rbind, lapply(split(out, out$y_feature), function(sub) {
    data.frame(
      y_feature = sub$y_feature[1],
      y_name = sub$y_name[1],
      n_predictors_tested = nrow(sub),
      n_significant = sum(sub$significant),
      best_x = sub$x_feature[1],
      best_padj = sub$padj[1],
      best_r2 = sub$r_squared[1],
      stringsAsFactors = FALSE
    )
  }))
  y_summary <- y_summary[order(-y_summary$n_significant, -y_summary$best_r2), , drop = FALSE]
  rownames(y_summary) <- NULL

  if (verbose) {
    cat(sprintf("  [regression] %s -> %s: %d pairs tested, %d significant (padj<0.05)\n",
                x_name, y_name, nrow(out), sum(out$significant)))
  }

  list(pairs = out, x_summary = x_summary, y_summary = y_summary)
}


#' 单个跨组学回归特征对的散点图
#'
#' @description 绘制某一对 x-y 特征在各样本上的散点，并叠加拟合回归线及
#'   95% 置信带。
#'
#' @param x_values 解释变量特征在各样本上的数值向量。
#' @param y_values 响应变量特征在各样本上的数值向量。
#' @param x_label x 轴标签（特征 + 层）。
#' @param y_label y 轴标签（特征 + 层）。
#' @param title 可选标题。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_regression_pair(x_values, y_values, "gene A (transcriptome)", "metabolite B")
#' }
#'
#' @export
plot_regression_pair <- function(x_values, y_values,
                                 x_label = "x", y_label = "y", title = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' is required.")
  }
  dat <- data.frame(x = as.numeric(x_values), y = as.numeric(y_values))
  dat <- dat[stats::complete.cases(dat), ]
  p <- ggplot2::ggplot(dat, ggplot2::aes(x = x, y = y)) +
    ggplot2::geom_point(color = "#4a90d9", alpha = 0.7, size = 2) +
    ggplot2::geom_smooth(method = "lm", se = TRUE,
                         color = "#d7191c", fill = "#d7191c", alpha = 0.15) +
    ggplot2::labs(title = if (is.null(title)) "Cross-omics regression" else title,
                  x = x_label, y = y_label) +
    ggplot2::theme_bw() +
    ggplot2::theme(plot.title = ggplot2::element_text(size = 12, face = "bold", hjust = 0.5))
  return(p)
}


#' 选取用于绘图的 Top 显著回归特征对
#'
#' @description 从回归结果中提取最显著（或 R2 最高）的 x-y 特征对，
#'   以便生成数量可控的散点图。
#'
#' @param reg \code{run_cross_omics_regression()} 的结果。
#' @param top_n 返回的特征对数量。默认：12。
#' @param by 排序依据："padj" 或 "r2"。默认："padj"。
#'
#' @return 包含 \code{reg$pairs} 中前 \code{top_n} 行的数据框。
#'
#' @export
top_regression_pairs <- function(reg, top_n = 12, by = "padj") {
  if (is.null(reg$pairs) || nrow(reg$pairs) == 0) {
    return(data.frame())
  }
  by <- match.arg(by, c("padj", "r2"))
  ord <- if (by == "padj") {
    order(reg$pairs$padj, -abs(reg$pairs$slope))
  } else {
    order(-reg$pairs$r_squared, reg$pairs$padj)
  }
  head(reg$pairs[ord, , drop = FALSE], top_n)
}
