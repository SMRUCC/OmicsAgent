# =====================================================================
# 内部公共绘图函数（不导出）
# =====================================================================
#' @title Internal: Score Plot Drawer
#' @description 通用得分图绘制与保存函数，供 PCA / PLS-DA / OPLS-DA 调用
#' @keywords internal
#' @noRd
.draw_score_plot <- function(plot_df,
                             title,
                             x_lab,
                             y_lab,
                             show_ellipse = TRUE,
                             show_labels  = FALSE,
                             output_prefix,
                             output_dir   = ".",
                             width        = 8,
                             height       = 7) {

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  p <- ggplot2::ggplot(plot_df,
                       ggplot2::aes(x = .data$X, y = .data$Y,
                                    color = .data$Group)) +
    ggplot2::geom_point(size = 3, alpha = 0.8) +
    ggplot2::labs(
      title = title,
      x     = x_lab,
      y     = y_lab,
      color = "Group"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title    = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold"),
      legend.position = "right",
      axis.title    = ggplot2::element_text(size = 12),
      axis.text     = ggplot2::element_text(size = 10)
    )

  if (show_ellipse) {
    p <- p + ggplot2::stat_ellipse(level = 0.95, type = "t", linewidth = 0.8)
  }

  if (show_labels && "SampleName" %in% colnames(plot_df)) {
    p <- p + ggrepel::geom_text_repel(
      ggplot2::aes(label = .data$SampleName),
      size = 3, max.overlaps = 20
    )
  }

  pdf_file <- file.path(output_dir, paste0(output_prefix, "_score_plot.pdf"))
  png_file <- file.path(output_dir, paste0(output_prefix, "_score_plot.png"))

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file,
                 width  = width * 300,
                 height = height * 300,
                 res    = 300)
  print(p)
  grDevices::dev.off()

  message(title, " saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}

# 辅助：构造统一长度的绘图数据框
.build_plot_df <- function(scores, x_col, y_col, matched_meta,
                           include_name = FALSE) {
  plot_df <- data.frame(
    X     = scores[[x_col]],
    Y     = scores[[y_col]],
    Group = matched_meta$sample_info,
    stringsAsFactors = FALSE
  )
  if (include_name) {
    plot_df$SampleName <- matched_meta$sample_name
  }
  plot_df
}


# =====================================================================
# 对外导出函数
# =====================================================================
#' @title Plot PCA Score Plot
#'
#' @description
#' 绘制PCA得分图，展示样本在主成分空间中的分布。不同分组用不同颜色
#' 表示，并绘制各组95%置信椭圆。该图用于评估样本分组是否在PCA空间
#' 中分离，是组学数据分析中最常用的无监督可视化方法。
#'
#' @param pca_result 列表，由 perform_pca 函数返回
#' @param sample_meta 数据框，样本元数据
#' @param pc_x 整数，X轴主成分编号，默认 1
#' @param pc_y 整数，Y轴主成分编号，默认 2
#' @param show_ellipse 逻辑值，是否绘制置信椭圆，默认 TRUE
#' @param show_labels 逻辑值，是否显示样本标签，默认 FALSE
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认 8
#' @param height 数值，图片高度（英寸），默认 7
#'
#' @return 不可见地返回 ggplot 对象
#'
#' @examples
#' \dontrun{
#' pca_result <- perform_pca(expr)
#' plot_pca_scores(pca_result, meta, output_dir = "./figures")
#' }
#'
#' @export
plot_pca_scores <- function(pca_result, sample_meta,
                            pc_x = 1, pc_y = 2,
                            show_ellipse = TRUE,
                            show_labels  = FALSE,
                            output_dir   = ".",
                            width  = 8,
                            height = 7) {

  scores <- as.data.frame(pca_result$scores[, c(pc_x, pc_y)])
  colnames(scores) <- c("PC1", "PC2")

  matched_meta <- sample_meta[match(rownames(scores), sample_meta$ID), ]

  var_x <- pca_result$variance_explained[pc_x] * 100
  var_y <- pca_result$variance_explained[pc_y] * 100

  plot_df <- .build_plot_df(scores, "PC1", "PC2", matched_meta,
                            include_name = show_labels)

  .draw_score_plot(
    plot_df       = plot_df,
    title         = "PCA Score Plot",
    x_lab         = paste0("PC", pc_x, " (", round(var_x, 1), "%)"),
    y_lab         = paste0("PC", pc_y, " (", round(var_y, 1), "%)"),
    show_ellipse  = show_ellipse,
    show_labels   = show_labels,
    output_prefix = "PCA",
    output_dir    = output_dir,
    width         = width,
    height        = height
  )
}


#' @title Plot PLS-DA Score Plot
#'
#' @description
#' 绘制 PLS-DA 得分图，展示样本在判别空间中的分布。不同分组用不同
#' 颜色表示，并绘制各组 95% 置信椭圆。该图用于评估分组判别效果。
#'
#' @param plsda_result 列表，由 perform_plsda 函数返回
#' @param sample_meta 数据框，样本元数据
#' @param comp_x 整数，X 轴成分编号，默认 1
#' @param comp_y 整数，Y 轴成分编号，默认 2
#' @param show_ellipse 逻辑值，是否绘制置信椭圆，默认 TRUE
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认 8
#' @param height 数值，图片高度（英寸），默认 7
#'
#' @return 不可见地返回 ggplot 对象
#'
#' @examples
#' \dontrun{
#' plsda_result <- perform_plsda(expr, meta)
#' plot_plsda_scores(plsda_result, meta, output_dir = "./figures")
#' }
#'
#' @export
plot_plsda_scores <- function(plsda_result, sample_meta,
                              comp_x = 1, comp_y = 2,
                              show_ellipse = TRUE,
                              output_dir   = ".",
                              width  = 8,
                              height = 7) {

  scores <- as.data.frame(plsda_result$scores[, c(comp_x, comp_y)])
  colnames(scores) <- c("Comp1", "Comp2")

  matched_meta <- sample_meta[match(rownames(scores), sample_meta$ID), ]

  plot_df <- .build_plot_df(scores, "Comp1", "Comp2", matched_meta,
                            include_name = FALSE)

  .draw_score_plot(
    plot_df       = plot_df,
    title         = "PLS-DA Score Plot",
    x_lab         = paste0("Comp", comp_x),
    y_lab         = paste0("Comp", comp_y),
    show_ellipse  = show_ellipse,
    show_labels   = FALSE,
    output_prefix = "PLSDA",
    output_dir    = output_dir,
    width         = width,
    height        = height
  )
}


#' @title Plot OPLS-DA Score Plot
#'
#' @description
#' 绘制 OPLS-DA 得分图，展示样本在预测成分与正交成分空间中的分布。
#' 不同分组用不同颜色表示，并绘制各组 95% 置信椭圆。
#'
#' @param oplsda_result 列表，由 perform_oplsda 函数返回
#' @param sample_meta 数据框，样本元数据
#' @param show_ellipse 逻辑值，是否绘制置信椭圆，默认 TRUE
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认 8
#' @param height 数值，图片高度（英寸），默认 7
#'
#' @return 不可见地返回 ggplot 对象
#'
#' @export
plot_oplsda_scores <- function(oplsda_result, sample_meta,
                               show_ellipse = TRUE,
                               output_dir   = ".",
                               width  = 8,
                               height = 7) {

  scores <- as.data.frame(oplsda_result$scores[, 1:2])
  colnames(scores) <- c("Comp1", "OrthComp1")

  matched_meta <- sample_meta[match(rownames(scores), sample_meta$ID), ]

  plot_df <- .build_plot_df(scores, "Comp1", "OrthComp1", matched_meta,
                            include_name = FALSE)

  .draw_score_plot(
    plot_df       = plot_df,
    title         = "OPLS-DA Score Plot",
    x_lab         = "Predictive Component 1",
    y_lab         = "Orthogonal Component 1",
    show_ellipse  = show_ellipse,
    show_labels   = FALSE,
    output_prefix = "OPLSDA",
    output_dir    = output_dir,
    width         = width,
    height        = height
  )
}
