# ==============================================================================
# OmicsFlow：VIP 曼哈顿图（按类别分组）
# ==============================================================================
# 以曼哈顿风格的抖动图，按类别注释（如 super_class）展示来自 PLS-DA 的 VIP
# （投影变量重要性）分数。适合作为出版级配图，呈现每个代谢物类别的 VIP 分布。
# ==============================================================================

#' 按类别注释分组的 VIP 曼哈顿风格抖动图
#'
#' @description 创建一张达到出版质量的曼哈顿风格图，x 轴表示类别注释（如代谢物
#'   super_class，类似于基因组曼哈顿图中的染色体），y 轴为 VIP 分数。每个点是
#'   一个Feature，在各自类别内抖动，配有平滑的密度轮廓，并在 \code{threshold} 处
#'   绘制参考线。
#'
#' @param vip 含 VIP 分数的数据框，行名为Feature ID，并含单个数值列
#'   （通常为 \code{plsda_result$vip}）。
#' @param feature_info 含Feature注释的数据框。必须包含Feature ID 列与类别列。
#' @param feature_id_col \code{feature_info} 中保存Feature ID 的列名。默认："name"。
#' @param category_col \code{feature_info} 中保存分组类别（如 "super_class"）的列名。
#'   默认："super_class"。
#' @param threshold VIP 重要性阈值（参考线）。默认：1.0。
#' @param top_n_labels 用文本标注的 VIP 最高Feature数量（总体，跨所有类别）。
#'   设为 0 则关闭标注。默认：0。
#' @param title 图标题。默认："VIP Manhattan Plot by Category"。
#' @param x_label x 轴标签。默认："Metabolite Category"。
#' @param y_label y 轴标签。默认："VIP Score"。
#' @param base_size 基础字号。默认：12。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_vip_manhattan(plsda_result$vip, feat_info,
#'                         feature_id_col = "name", category_col = "super_class")
#' }
#'
#' @export
plot_vip_manhattan <- function(vip, feature_info,
                               feature_id_col = "name",
                               category_col = "super_class",
                               threshold = 1.0,
                               top_n_labels = 0,
                               title = "VIP Manhattan Plot by Category",
                               x_label = "Metabolite Category",
                               y_label = "VIP Score",
                               base_size = 12) {
  if (missing(vip) || is.null(vip)) {
    stop("'vip' is required (e.g. plsda_result$vip).")
  }
  if (missing(feature_info) || is.null(feature_info)) {
    stop("'feature_info' is required for category grouping.")
  }
  if (!feature_id_col %in% colnames(feature_info)) {
    stop("feature_id_col '", feature_id_col, "' not found in feature_info.")
  }
  if (!category_col %in% colnames(feature_info)) {
    stop("category_col '", category_col, "' not found in feature_info.")
  }
  
  # 确保 vip 为含数值 vip 列的数据框
  if (!is.data.frame(vip)) {
    vip <- as.data.frame(vip, stringsAsFactors = FALSE)
  }
  vip_col <- setdiff(colnames(vip), character(0))
  vip_col <- vip_col[sapply(vip, is.numeric)]
  if (length(vip_col) == 0) {
    stop("'vip' must contain at least one numeric column.")
  }
  vip_col <- vip_col[1]
  vip_df <- data.frame(
    feature_id = rownames(vip),
    vip = vip[[vip_col]],
    stringsAsFactors = FALSE
  )
  
  # 将Feature ID 映射到类别
  info_sub <- feature_info[, c(feature_id_col, category_col), drop = FALSE]
  colnames(info_sub) <- c("feature_id", "category")
  info_sub$feature_id <- as.character(info_sub$feature_id)
  info_sub$category <- as.character(info_sub$category)
  
  plot_df <- merge(vip_df, info_sub, by = "feature_id", all.x = TRUE)
  
  # 丢弃缺失 / 无效的类别
  n_before <- nrow(plot_df)
  valid_cat <- !is.na(plot_df$category) &
    plot_df$category != "" &
    plot_df$category != "NULL"
  plot_df <- plot_df[valid_cat, ]
  n_dropped <- n_before - nrow(plot_df)
  if (n_dropped > 0) {
    warning(sprintf("Dropped %d features with missing '%s'.", n_dropped, category_col))
  }
  if (nrow(plot_df) == 0) {
    stop("No features left after category filtering. Check feature_id_col / category_col.")
  }
  
  # 按平均 VIP（降序）重排类别，以获得更整洁的布局
  cat_order <- names(sort(tapply(plot_df$vip, plot_df$category, mean),
                          decreasing = TRUE))
  plot_df$category <- factor(plot_df$category, levels = cat_order)
  
  # 可选的 top 标注（总体，跨所有类别）
  label_df <- NULL
  if (top_n_labels > 0 && nrow(plot_df) > 0) {
    label_df <- head(plot_df[order(plot_df$vip, decreasing = TRUE), ], top_n_labels)
  }
  
  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = category, y = vip)) +
    # 每个类别的密度轮廓（模拟染色体条带观感）
    ggplot2::geom_violin(ggplot2::aes(fill = category), alpha = 0.12,
                         scale = "width", width = 0.9, color = NA) +
    # 抖动散点，按相对于阈值的显著性着色
    ggplot2::geom_jitter(
      ggplot2::aes(color = vip >= threshold),
      width = 0.28, height = 0, size = 1.6, alpha = 0.8
    ) +
    ggplot2::scale_color_manual(
      name = "VIP >= threshold",
      values = c("FALSE" = "#95a5a6", "TRUE" = "#c0392b"),
      labels = c("FALSE" = "Below", "TRUE" = "Above")
    ) +
    ggplot2::scale_fill_brewer(palette = "Set3", guide = "none") +
    # 参考阈值线
    ggplot2::geom_hline(yintercept = threshold, color = "#e74c3c",
                        linetype = "dashed", linewidth = 0.9) +
    ggplot2::coord_cartesian(clip = "off") +
    ggplot2::labs(title = title, x = x_label, y = y_label) +
    ggplot2::theme_bw(base_size = base_size) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = base_size + 2,
                                         face = "bold", hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1,
                                          size = base_size - 1),
      axis.text.y = ggplot2::element_text(size = base_size - 1),
      axis.title = ggplot2::element_text(size = base_size + 1),
      legend.position = "right",
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank()
    )
  
  if (!is.null(label_df) && nrow(label_df) > 0) {
    p <- p + ggrepel::geom_text_repel(
      data = label_df,
      ggplot2::aes(label = feature_id),
      size = 2.6, max.overlaps = 20,
      color = "#2c3e50", segment.color = "#7f8c8d"
    )
  }
  
  return(p)
}
