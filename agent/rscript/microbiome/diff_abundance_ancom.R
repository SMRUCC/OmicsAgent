# ==============================================================================
# OmicsFlow: ANCOM-BC Differential Abundance Analysis
# ==============================================================================
# ANCOM-BC (Analysis of Composition of Microbiomes with Bias Correction)
# 风格的差异丰度分析，适用于组成性数据
# 包含伪计数对数变换 + 组间比较 + 丰度偏差校正
# ==============================================================================

#' 对组成性数据进行对数变换
#'
#' @description 对微生物组计数数据进行对数变换（添加伪计数），
#'   用于后续线性模型分析。
#'
#' @param expr_matrix 数值矩阵（features × samples）。
#' @param pseudo_count 伪计数。默认 1。
#' @param base 对数底数。默认 exp(1)。
#'
#' @return 变换后的矩阵。
#'
#' @examples
#' \dontrun{
#' log_mat <- log_transform_compositional(expr_matrix)
#' }
#'
#' @export
log_transform_compositional <- function(expr_matrix, pseudo_count = 1,
                                       base = exp(1)) {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)
  log(expr_matrix + pseudo_count, base = base)
}


#' ANCOM-BC 风格的差异丰度分析
#'
#' @description 模仿 ANCOM-BC 分析流程，对组成性微生物组数据进行
#'   组间差异丰度分析。步骤包括：
#'   1. 对数变换（添加伪计数）
#'   2. 计算每个 feature 的组间均值差和组内方差
#'   3. 使用 Welch's t 检验（两组）或 ANOVA（多组）计算 p 值
#'   4. 计算 W 统计量（基于该 feature 与所有其他 feature 的差异比例）
#'   5. 多重检验校正
#'
#' @param expr_matrix 数值矩阵（features × samples），行为 taxa，列为样本。
#' @param sample_info 样本元数据 data.frame。
#' @param group_col 分组列名。默认 "sample_info"。
#' @param p_adjust 多重检验校正方法。默认 "BH"。
#' @param p_threshold p 值阈值。默认 0.05。
#' @param w_threshold W 统计量阈值。默认 0.7。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{results}: 所有 taxa 的差异分析结果。
#'     \item \code{significant}: 显著差异 taxa。
#'     \item \code{volcano_data}: 火山图数据。
#'   }
#'
#' @examples
#' \dontrun{
#' res <- run_ancom_bc(expr_matrix, sample_info, group_col = "sample_info")
#' }
#'
#' @export
run_ancom_bc <- function(expr_matrix, sample_info,
                        group_col = "sample_info",
                        p_adjust = "BH",
                        p_threshold = 0.05,
                        w_threshold = 0.7) {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)

  common <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common, drop = FALSE]
  sample_info <- sample_info[common, , drop = FALSE]
  groups <- sample_info[[group_col]]
  group_levels <- unique(groups)
  n_groups <- length(group_levels)

  if (n_groups < 2) {
    stop("至少需要 2 组进行差异丰度分析。")
  }

  n_features <- nrow(expr_matrix)
  feature_names <- rownames(expr_matrix)

  # 对数变换
  log_mat <- log_transform_compositional(expr_matrix, pseudo_count = 1)

  # 计算每个 feature 的组间差异
  log_fold_change <- numeric(n_features)
  p_values <- numeric(n_features)
  test_statistic <- numeric(n_features)

  if (n_groups == 2) {
    g1_samples <- colnames(expr_matrix)[groups == group_levels[1]]
    g2_samples <- colnames(expr_matrix)[groups == group_levels[2]]

    for (i in seq_len(n_features)) {
      v1 <- log_mat[i, g1_samples]
      v2 <- log_mat[i, g2_samples]

      # Welch's t 检验
      tt <- stats::t.test(v1, v2)
      p_values[i] <- tt$p.value
      test_statistic[i] <- tt$statistic
      log_fold_change[i] <- mean(v1) - mean(v2)
    }
  } else {
    # 多组：ANOVA + 事后比较
    for (i in seq_len(n_features)) {
      aov_res <- stats::aov(log_mat[i, ] ~ groups)
      tukey_res <- stats::TukeyHSD(aov_res)
      p_values[i] <- summary(aov_res)[[1]][["Pr(>F)"]][1]
      test_statistic[i] <- summary(aov_res)[[1]][["F value"]][1]
      # 最大组间差异
      diffs <- tukey_res$`groups`[, "diff"]
      log_fold_change[i] <- diffs[which.max(abs(diffs))]
    }
  }

  p_adj <- stats::p.adjust(p_values, method = p_adjust)

  # W 统计量：该 feature 与其他所有 feature 的差异比例
  # 简化实现：对于每个 feature，计算有多少比例的其他 feature 与其显著不同
  w_stat <- numeric(n_features)
  if (n_groups == 2) {
    for (i in seq_len(n_features)) {
      # 该 feature 与所有其他 feature 的配对比较
      other_idx <- setdiff(seq_len(n_features), i)
      n_sig <- 0
      for (j in other_idx) {
        # 比较 feature i 在两组间的差异 vs feature j 在两组间的差异
        diff_i <- log_mat[i, g1_samples] - log_mat[i, g2_samples]
        diff_j <- log_mat[j, g1_samples] - log_mat[j, g2_samples]
        tt <- stats::t.test(diff_i, diff_j)
        if (tt$p.value < 0.05) n_sig <- n_sig + 1
      }
      w_stat[i] <- n_sig / length(other_idx)
    }
  } else {
    # 多组 W 统计量使用 ANOVA p 值的排名比例
    w_stat <- 1 - rank(p_values, ties.method = "average") / n_features
  }

  results <- data.frame(
    feature = feature_names,
    log_fold_change = log_fold_change,
    statistic = test_statistic,
    p_value = p_values,
    p_adj = p_adj,
    w_stat = w_stat,
    significant = p_adj < p_threshold & w_stat >= w_threshold,
    direction = ifelse(log_fold_change > 0, group_levels[1],
                      ifelse(log_fold_change < 0, group_levels[n_groups], "NS")),
    stringsAsFactors = FALSE
  )

  significant <- results[results$significant, , drop = FALSE]
  significant <- significant[order(-abs(significant$log_fold_change)), ]

  cat(sprintf("[ancom-bc] %d / %d taxa 显著差异 (p_adj < %.2f, W >= %.1f)\n",
              nrow(significant), n_features, p_threshold, w_threshold))

  # 火山图数据
  volcano_data <- data.frame(
    feature = feature_names,
    logFC = log_fold_change,
    neg_log10_p = -log10(p_adj),
    significant = results$significant,
    direction = results$direction,
    stringsAsFactors = FALSE
  )

  return(list(
    results = results,
    significant = significant,
    volcano_data = volcano_data,
    params = list(
      n_groups = n_groups,
      group_levels = group_levels,
      p_adjust = p_adjust,
      p_threshold = p_threshold,
      w_threshold = w_threshold
    )
  ))
}


#' 绘制 ANCOM-BC 火山图
#'
#' @description 绘制差异丰度火山图，x 轴为 log fold change，y 轴为 -log10(p_adj)。
#'
#' @param ancom_result \code{run_ancom_bc()} 的返回结果。
#' @param top_n 标注前 N 个显著 taxa。默认 15。
#' @param feature_info 特征注释 data.frame（可选，用于显示 taxa 名称）。
#' @param name_col 注释中的名称列。默认 "name"。
#'
#' @return ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_ancom_volcano(ancom_result, top_n = 15)
#' }
#'
#' @export
plot_ancom_volcano <- function(ancom_result, top_n = 15,
                               feature_info = NULL,
                               name_col = "name") {
  vd <- ancom_result$volcano_data
  group_levels <- ancom_result$params$group_levels
  group_colors <- make_group_colors(group_levels)

  p <- ggplot2::ggplot(vd, ggplot2::aes(x = logFC, y = neg_log10_p,
                                          color = direction)) +
    ggplot2::geom_point(size = 2, alpha = 0.6) +
    ggplot2::scale_color_manual(values = group_colors, name = "Enriched in") +
    ggplot2::geom_vline(xintercept = 0, linetype = "dotted", color = "grey50") +
    ggplot2::labs(
      title = "ANCOM-BC Differential Abundance",
      x = "Log Fold Change",
      y = "-log10(p_adj)"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 10),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right"
    )

  # 标注显著 taxa
  sig <- vd[vd$significant, , drop = FALSE]
  if (nrow(sig) > 0) {
    if (!is.null(feature_info) && name_col %in% colnames(feature_info)) {
      sig$label <- feature_info[match(sig$feature, rownames(feature_info)), name_col]
    } else {
      sig$label <- sig$feature
    }
    if (nrow(sig) > top_n) {
      sig <- sig[order(-sig$neg_log10_p)[1:top_n], , drop = FALSE]
    }
    p <- p + ggrepel::geom_text_repel(
      data = sig,
      ggplot2::aes(label = label),
      size = 2.5, max.overlaps = 15
    )
  }

  return(p)
}
