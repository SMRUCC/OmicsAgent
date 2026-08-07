# ==============================================================================
# OmicsFlow：火山图
# ==============================================================================
# 可视化差异特征
# ==============================================================================

#' 绘制火山图
#'
#' @description 创建一张达到出版质量的火山图，展示 logFC 对 -log10(p-value) 的关系，
#'   并标注 Top N 个差异特征。
#'
#' @param de_results 来自 \code{run_limma()}$results 的结果，或含以下列的数据框：
#'   feature_id、logFC、p_value 或 p_adj。
#' @param p_col p 值列名。默认："p_adj"。
#' @param logfc_col logFC 列名。默认："logFC"。
#' @param feature_col 特征 ID 列名。默认："feature_id"。
#' @param name_col 可选的特征名称列。默认：NULL。
#' @param p_threshold p 值阈值。默认：0.05。
#' @param logfc_threshold 绝对 logFC 阈值。默认：1。
#' @param top_n 标注的 Top 特征数。默认：5。
#' @param color_up 上调特征的颜色。默认："#e74c3c"。
#' @param color_down 下调特征的颜色。默认："#2ecc71"。
#' @param color_ns 不显著特征的颜色。默认："grey70"。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' de <- run_limma(expr_matrix, sample_info)
#' p <- plot_volcano(de$results, top_n = 5)
#' print(p)
#' }
#'
#' @export
plot_volcano <- function(de_results, p_col = "p_adj", logfc_col = "logFC",
                         feature_col = "feature_id", name_col = NULL,
                         p_threshold = 0.05, logfc_threshold = 1,
                         top_n = 5,
                         color_up = "#e74c3c", color_down = "#2ecc71",
                         color_ns = "grey70") {
  # 准备数据 - 若列中不含 feature_col 则使用行名
  if (feature_col %in% colnames(de_results)) {
    feat_ids <- de_results[[feature_col]]
  } else {
    feat_ids <- rownames(de_results)
  }
  plot_data <- data.frame(
    feature_id = feat_ids,
    logFC = de_results[[logfc_col]],
    p_value = de_results[[p_col]],
    stringsAsFactors = FALSE
  )

  # 若提供了名称列则添加
  if (!is.null(name_col) && name_col %in% colnames(de_results)) {
    plot_data$name <- de_results[[name_col]]
  } else {
    plot_data$name <- plot_data$feature_id
  }

  # 去除 NA
  plot_data <- plot_data[!is.na(plot_data$logFC) & !is.na(plot_data$p_value), ]

  # 计算 -log10 p 值
  plot_data$neg_log10_p <- -log10(plot_data$p_value)

  # 判定显著性
  plot_data$direction <- ifelse(
    plot_data$p_value < p_threshold & plot_data$logFC > logfc_threshold, "Up",
    ifelse(
      plot_data$p_value < p_threshold & plot_data$logFC < -logfc_threshold, "Down",
      "NS"
    )
  )

  # 选取用于标注的 Top 特征
  # 按显著性与效应量的组合排序
  plot_data$score <- abs(plot_data$logFC) * (-log10(plot_data$p_value))
  top_features <- plot_data[order(plot_data$score, decreasing = TRUE), ]
  top_features <- head(top_features[top_features$direction != "NS", ], top_n)

  # 构建图形
  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = logFC, y = neg_log10_p)) +
    ggplot2::geom_point(ggplot2::aes(color = direction), size = 1.5, alpha = 0.7) +
    ggplot2::scale_color_manual(
      values = c("Up" = color_up, "Down" = color_down, "NS" = color_ns),
      name = "Regulation",
      labels = c("Down", "Not Significant", "Up")
    ) +
    ggplot2::geom_hline(yintercept = -log10(p_threshold), color = "grey40",
                        linetype = "dashed", linewidth = 0.5) +
    ggplot2::geom_vline(xintercept = c(-logfc_threshold, logfc_threshold),
                        color = "grey40", linetype = "dashed", linewidth = 0.5) +
    ggrepel::geom_text_repel(
      data = top_features, ggplot2::aes(label = name),
      size = 2.8, max.overlaps = 20, fontface = "italic"
    ) +
    ggplot2::labs(
      title = "Volcano Plot",
      x = expression(log[2]~Fold~Change),
      y = expression(-log[10]~(p~value))
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 11),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right",
      legend.text = ggplot2::element_text(size = 10),
      legend.title = ggplot2::element_text(size = 11)
    )

  return(p)
}
