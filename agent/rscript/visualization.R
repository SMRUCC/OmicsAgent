# ============================================================
# Required packages
# ============================================================
library(ggplot2)
library(grDevices)
library(ggrepel)
library(ggVennDiagram)
library(VennDiagram)
library(RColorBrewer)
library(grid)
library(UpSetR)
library(pheatmap)

#' @title Plot Volcano Plot with Top 5 Feature Labels
#'
#' @description
#' 绘制火山图（Volcano Plot），展示差异分析结果。火山图以logFC为X轴、
#' -log10(P value)为Y轴，每个点代表一个feature。显著差异feature用
#' 不同颜色标记，并标注Top 5差异最大的feature名称。
#'
#' 该图是组学差异分析中最常用的可视化方法，直观展示差异feature的
#' 数量、方向和显著性。
#'
#' @param dea_result 数据框，由perform_limma返回，必须包含Feature、logFC、pvalue_adj、significant列
#' @param feature_anno 数据框，feature注释信息（可选，用于显示feature name）
#' @param pvalue_threshold 数值，P值阈值，默认0.05
#' @param logfc_threshold 数值，logFC阈值，默认1
#' @param top_n 整数，标注的Top feature数，默认5
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认8
#' @param height 数值，图片高度（英寸），默认7
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' dea_result <- perform_limma(expr, meta, strategy = "pvalue_logFC")
#' plot_volcano(dea_result, feature_anno, top_n = 5,
#'             output_dir = "./figures")
#' }
#'
#' @export
plot_volcano <- function(dea_result, feature_anno = NULL,
                         pvalue_threshold = 0.05, logfc_threshold = 1,
                         top_n = 5, output_dir = ".", width = 8, height = 7) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  plot_data <- dea_result
  plot_data$neg_log10_p <- -log10(plot_data$pvalue_adj)

  plot_data$direction <- "Not Significant"
  plot_data$direction[plot_data$pvalue_adj < pvalue_threshold &
                       plot_data$logFC > logfc_threshold] <- "Up"
  plot_data$direction[plot_data$pvalue_adj < pvalue_threshold &
                       plot_data$logFC < -logfc_threshold] <- "Down"

  if (!is.null(feature_anno)) {
    name_map <- setNames(feature_anno$name, feature_anno$ID)
    plot_data$Name <- name_map[plot_data$Feature]
    plot_data$Name[is.na(plot_data$Name)] <- plot_data$Feature[is.na(plot_data$Name)]
  } else {
    plot_data$Name <- plot_data$Feature
  }

  # Select top N features by significance
  sig_data <- plot_data[plot_data$direction != "Not Significant", , drop = FALSE]
  if (nrow(sig_data) > 0) {
    sig_data <- sig_data[order(-abs(sig_data$logFC * -log10(sig_data$pvalue_adj))), ]
    top_features <- head(sig_data, top_n)
  } else {
    top_features <- plot_data[order(-abs(plot_data$logFC * -log10(plot_data$pvalue_adj))), ][1:top_n, ]
  }

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = logFC, y = neg_log10_p,
                                                color = direction)) +
    ggplot2::geom_point(alpha = 0.6, size = 1.5) +
    ggrepel::geom_text_repel(data = top_features,
                              ggplot2::aes(label = Name),
                              size = 3, max.overlaps = 20,
                              color = "black", box.padding = 0.5) +
    ggplot2::geom_hline(yintercept = -log10(pvalue_threshold),
                         linetype = "dashed", color = "grey50") +
    ggplot2::geom_vline(xintercept = c(-logfc_threshold, logfc_threshold),
                         linetype = "dashed", color = "grey50") +
    ggplot2::scale_color_manual(values = c("Up" = "#E64B35",
                                            "Down" = "#4DBBD5",
                                            "Not Significant" = "grey80")) +
    ggplot2::labs(
      title = "Volcano Plot",
      x = expression(log[2]~Fold~Change),
      y = expression(-log[10]~(adjusted~P~value)),
      color = "Direction"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold"),
      legend.position = "right"
    )

  pdf_file <- file.path(output_dir, "Volcano_plot.pdf")
  png_file <- file.path(output_dir, "Volcano_plot.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("Volcano plot saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}


#' @title Plot Venn Diagram
#'
#' @description
#' 绘制文氏图（Venn Diagram），展示多个feature集合之间的交集与并集。
#' 文氏图常用于比较不同差异分析策略、不同比较组或不同组学之间
#' 的差异feature集合重叠情况。
#'
#' @param sets 命名列表，每个元素是一个feature ID向量
#' @param set_names 字符向量，集合名称（可选，默认使用列表名）
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认7
#' @param height 数值，图片高度（英寸），默认7
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' # 比较两种差异分析策略的结果
#' sets <- list(
#'   pvalue_logFC = dea_result1$Feature[dea_result1$significant],
#'   pvalue_vip = dea_result2$Feature[dea_result2$significant]
#' )
#' plot_venn(sets, output_dir = "./figures")
#' }
#'
#' @export
plot_venn <- function(sets, set_names = NULL, output_dir = ".",
                      width = 7, height = 7) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  if (is.null(set_names)) {
    set_names <- names(sets)
    if (is.null(set_names)) set_names <- paste0("Set", seq_along(sets))
  }

  if (length(sets) > 5) {
    stop("Venn diagram supports at most 5 sets. Use plot_upset instead.")
  }

  # Use ggVennDiagram if available, otherwise fall back to VennDiagram
  if (requireNamespace("ggVennDiagram", quietly = TRUE)) {
    p <- ggVennDiagram::ggVennDiagram(sets, label = "count") +
      ggplot2::labs(title = "Venn Diagram") +
      ggplot2::theme(plot.title = ggplot2::element_text(hjust = 0.5,
                                                         size = 14,
                                                         face = "bold"))
  } else if (requireNamespace("VennDiagram", quietly = TRUE)) {
    venn_obj <- VennDiagram::venn.diagram(sets, filename = NULL,
                                           fill = RColorBrewer::brewer.pal(length(sets), "Set2"),
                                           cat.cex = 1.5,
                                           cex = 1.5)
    pdf_file <- file.path(output_dir, "Venn_diagram.pdf")
    png_file <- file.path(output_dir, "Venn_diagram.png")

    grDevices::pdf(pdf_file, width = width, height = height)
    grid::grid.draw(venn_obj)
    grDevices::dev.off()

    grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
    grid::grid.draw(venn_obj)
    grDevices::dev.off()

    message("Venn diagram saved to:\n  ", pdf_file, "\n  ", png_file)
    return(invisible(NULL))
  } else {
    stop("Please install 'ggVennDiagram' or 'VennDiagram' package.")
  }

  pdf_file <- file.path(output_dir, "Venn_diagram.pdf")
  png_file <- file.path(output_dir, "Venn_diagram.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("Venn diagram saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}


#' @title Plot Upset Plot
#'
#' @description
#' 绘制Upset图，展示多个feature集合之间的交集关系。Upset图是文氏图
#' 的替代方案，适用于集合数较多（>5）或集合大小差异较大的情况。
#' 该图通过矩阵形式展示各组合的交集大小。
#'
#' @param sets 命名列表，每个元素是一个feature ID向量
#' @param sets_order 字符向量，集合顺序（可选）
#' @param n_intersections 整数，显示的最大交集数，默认30
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认10
#' @param height 数值，图片高度（英寸），默认6
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' sets <- list(
#'   Set1 = features1,
#'   Set2 = features2,
#'   Set3 = features3,
#'   Set4 = features4,
#'   Set5 = features5,
#'   Set6 = features6
#' )
#' plot_upset(sets, output_dir = "./figures")
#' }
#'
#' @export
plot_upset <- function(sets, sets_order = NULL, n_intersections = 30,
                       output_dir = ".", width = 10, height = 6) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  if (!requireNamespace("UpSetR", quietly = TRUE)) {
    stop("Package 'UpSetR' is required. Please install it.")
  }

  # Build binary matrix
  all_features <- unique(unlist(sets))
  binary_matrix <- matrix(0, nrow = length(all_features),
                          ncol = length(sets),
                          dimnames = list(all_features, names(sets)))
  for (i in seq_along(sets)) {
    binary_matrix[sets[[i]], i] <- 1
  }

  binary_df <- as.data.frame(binary_matrix)

  pdf_file <- file.path(output_dir, "Upset_plot.pdf")
  png_file <- file.path(output_dir, "Upset_plot.png")

  p <- UpSetR::upset(binary_df, nsets = ncol(binary_df),
                     nintersects = n_intersections,
                     order.by = "freq",
                     main.bar.color = "steelblue",
                     sets.bar.color = "darkorange",
                     point.size = 3,
                     line.size = 1)

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("Upset plot saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}


#' @title Plot Heatmap with Hierarchical Clustering
#'
#' @description
#' 绘制热图，行一般为feature维度，列一般为样本维度。列按照样本分组
#' 做排序，feature维度行做层次聚类树。如果feature注释中存在family信息，
#' 还会使用颜色块显示feature的family分类。
#'
#' 该图用于展示feature表达模式、样本聚类关系和分组差异。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param sample_meta 数据框，样本元数据
#' @param feature_anno 数据框，feature注释信息（可选，用于显示family）
#' @param scale_row 逻辑值，是否对行做Z-score标准化，默认TRUE
#' @param cluster_rows 逻辑值，是否对行做层次聚类，默认TRUE
#' @param cluster_cols 逻辑值，是否对列做层次聚类，默认FALSE（按分组排序）
#' @param show_rownames 逻辑值，是否显示行名，默认FALSE（feature数多时）
#' @param show_colnames 逻辑值，是否显示列名，默认FALSE
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认10
#' @param height 数值，图片高度（英寸），默认12
#'
#' @return 不可见地返回pheatmap对象
#'
#' @examples
#' \dontrun{
#' plot_heatmap(expr, meta, feature_anno, output_dir = "./figures")
#' }
#'
#' @export
plot_heatmap <- function(expr_matrix, sample_meta, feature_anno = NULL,
                         scale_row = TRUE, cluster_rows = TRUE,
                         cluster_cols = FALSE, show_rownames = FALSE,
                         show_colnames = FALSE, output_dir = ".",
                         width = 10, height = 12) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  if (!requireNamespace("pheatmap", quietly = TRUE)) {
    stop("Package 'pheatmap' is required. Please install it.")
  }

  # Order samples by group
  matched_meta <- sample_meta[match(colnames(expr_matrix), sample_meta$ID), ]
  group_order <- order(matched_meta$sample_info)
  expr_ordered <- expr_matrix[, group_order, drop = FALSE]
  matched_meta <- matched_meta[group_order, ]

  # Build column annotation
  col_anno <- data.frame(Group = matched_meta$sample_info,
                         row.names = matched_meta$ID)
  anno_colors <- list(Group = setNames(
    RColorBrewer::brewer.pal(nlevels(matched_meta$sample_info), "Set2")[1:nlevels(matched_meta$sample_info)],
    levels(matched_meta$sample_info)
  ))

  # Build row annotation (family)
  row_anno <- NULL
  row_anno_colors <- NULL
  if (!is.null(feature_anno) && "family" %in% colnames(feature_anno)) {
    family_map <- setNames(feature_anno$family, feature_anno$ID)
    families <- family_map[rownames(expr_ordered)]
    families[is.na(families)] <- "Unknown"
    row_anno <- data.frame(Family = factor(families),
                          row.names = rownames(expr_ordered))
    n_families <- min(length(unique(families)), 12)
    row_anno_colors <- list(Family = setNames(
      c(RColorBrewer::brewer.pal(n_families, "Set3"), "grey80")[1:length(unique(families))],
      levels(factor(families))
    ))
  }

  # Scaling
  plot_data <- expr_ordered
  if (scale_row) {
    plot_data <- t(scale(t(plot_data)))
  }

  pdf_file <- file.path(output_dir, "Heatmap.pdf")
  png_file <- file.path(output_dir, "Heatmap.png")

  # PDF
  grDevices::pdf(pdf_file, width = width, height = height)
  p <- pheatmap::pheatmap(plot_data,
                          cluster_rows = cluster_rows,
                          cluster_cols = cluster_cols,
                          annotation_col = col_anno,
                          annotation_row = row_anno,
                          annotation_colors = c(anno_colors, row_anno_colors),
                          show_rownames = show_rownames,
                          show_colnames = show_colnames,
                          color = colorRampPalette(c("blue", "white", "red"))(100),
                          fontsize_row = 8,
                          fontsize_col = 8,
                          border_color = NA,
                          scale = ifelse(scale_row, "row", "none"))
  grDevices::dev.off()

  # PNG
  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  p <- pheatmap::pheatmap(plot_data,
                          cluster_rows = cluster_rows,
                          cluster_cols = cluster_cols,
                          annotation_col = col_anno,
                          annotation_row = row_anno,
                          annotation_colors = c(anno_colors, row_anno_colors),
                          show_rownames = show_rownames,
                          show_colnames = show_colnames,
                          color = colorRampPalette(c("blue", "white", "red"))(100),
                          fontsize_row = 8,
                          fontsize_col = 8,
                          border_color = NA,
                          scale = ifelse(scale_row, "row", "none"))
  grDevices::dev.off()

  message("Heatmap saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}
