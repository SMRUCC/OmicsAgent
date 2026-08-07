# ==============================================================================
# OmicsFlow: Taxonomic Composition Analysis
# ==============================================================================
# 分类学组成分析：在不同分类层级（门/纲/目/科/属/种）绘制堆叠柱状图
# 和饼图，支持按分组聚合样本
# ==============================================================================

#' 按分类层级聚合丰度
#'
#' @description 将 taxa 级别的丰度数据按更高层级（门/纲/目/科/属）聚合。
#'   需要在 feature_info 中有分类层级列。
#'
#' @param expr_matrix 数值矩阵（features × samples），行为 taxa，列为样本。
#' @param feature_info 特征注释 data.frame，需包含分类层级列。
#' @param level 分类层级列名（如 "phylum"、"class"、"order"、"family"、"genus"）。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{matrix}: 聚合后的丰度矩阵（taxa × samples）。
#'     \item \code{level}: 使用的层级名。
#'   }
#'
#' @examples
#' \dontrun{
#' agg <- aggregate_by_taxonomy(expr_matrix, feature_info, level = "phylum")
#' }
#'
#' @export
aggregate_by_taxonomy <- function(expr_matrix, feature_info, level) {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)
  if (!level %in% colnames(feature_info)) {
    stop(sprintf("层级 '%s' 不在 feature_info 中。可用列: %s",
                 level, paste(colnames(feature_info), collapse = ", ")))
  }

  # 获取分类层级
  taxa_levels <- feature_info[[level]]
  taxa_levels[is.na(taxa_levels) | taxa_levels == ""] <- "Unclassified"

  # 按分类层级聚合（求和）
  agg <- stats::aggregate(expr_matrix, list(taxa = taxa_levels), sum)
  rownames(agg) <- agg$taxa
  agg$taxa <- NULL
  agg <- as.matrix(agg)

  # 按总丰度排序
  row_order <- order(rowSums(agg), decreasing = TRUE)
  agg <- agg[row_order, , drop = FALSE]

  cat(sprintf("[taxa-comp] 聚合到 %s 层级: %d 个 taxa\n", level, nrow(agg)))

  return(list(
    matrix = agg,
    level = level
  ))
}


#' 计算相对丰度（带伪计数）
#'
#' @description 将计数矩阵转换为相对丰度矩阵（列归一化），添加伪计数避免零值。
#'   本函数是对 \code{microbiome_utils::calc_relative_abundance()} 的封装。
#'
#' @param expr_matrix 数值矩阵（features × samples）。
#' @param pseudo_count 伪计数，避免除零。默认 1e-6。
#'
#' @return 相对丰度矩阵。
#'
#' @examples
#' \dontrun{
#' rel_abund <- calc_relative_abundance_pseudo(expr_matrix)
#' }
#'
#' @export
calc_relative_abundance_pseudo <- function(expr_matrix, pseudo_count = 1e-6) {
  rel <- calc_relative_abundance(expr_matrix)
  rel + pseudo_count
}


#' 绘制分类学组成堆叠柱状图
#'
#' @description 在指定分类层级绘制堆叠柱状图，可选按分组聚合样本。
#'   默认只展示 Top N 个丰度最高的 taxa，其余合并为 "Others"。
#'
#' @param expr_matrix 数值矩阵（features × samples）或聚合后的矩阵。
#' @param sample_info 样本元数据 data.frame。
#' @param feature_info 特征注释 data.frame（可选，用于按层级聚合）。
#' @param tax_level 分类层级列名（如 "phylum"、"genus"）。默认 NULL（不聚合）。
#' @param group_col 分组列名，按组聚合样本。默认 "sample_info"。
#' @param top_n 展示前 N 个丰度最高的 taxa。默认 10。
#' @param transform 转换方法："relative"（相对丰度）或 "log"（log 变换）。
#'   默认 "relative"。
#' @param palette_name RColorBrewer 调色板名。默认 "Set3"。
#'
#' @return ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_taxa_barplot(expr_matrix, sample_info, feature_info,
#'                        tax_level = "phylum", top_n = 10)
#' }
#'
#' @export
plot_taxa_barplot <- function(expr_matrix, sample_info,
                              feature_info = NULL,
                              tax_level = NULL,
                              group_col = "sample_info",
                              top_n = 10,
                              transform = "relative",
                              palette_name = "Set3") {
  # 按层级聚合
  if (!is.null(tax_level) && !is.null(feature_info)) {
    agg <- aggregate_by_taxonomy(expr_matrix, feature_info, tax_level)
    mat <- agg$matrix
    level_label <- agg$level
  } else {
    mat <- as.matrix(expr_matrix)
    level_label <- "Feature"
  }

  # 转换
  if (transform == "relative") {
    mat <- calc_relative_abundance(mat) * 100
    y_label <- "Relative Abundance (%)"
  } else {
    mat <- log10(mat + 1)
    y_label <- "log10(Abundance + 1)"
  }

  # 按分组聚合
  common <- intersect(colnames(mat), rownames(sample_info))
  mat <- mat[, common, drop = FALSE]
  groups <- sample_info[common, group_col]

  group_mat <- t(stats::aggregate(t(mat), list(groups), mean))
  colnames(group_mat) <- group_mat[1, ]
  group_mat <- group_mat[-1, , drop = FALSE]
  group_mat <- apply(group_mat, 2, as.numeric)
  rownames(group_mat) <- rownames(mat)

  # Top N + Others
  total_abund <- rowSums(group_mat, na.rm = TRUE)
  top_taxa <- names(sort(total_abund, decreasing = TRUE))[1:min(top_n, nrow(group_mat))]
  others <- setdiff(rownames(group_mat), top_taxa)

  if (length(others) > 0) {
    others_row <- colSums(group_mat[others, , drop = FALSE], na.rm = TRUE)
    group_mat <- group_mat[top_taxa, , drop = FALSE]
    group_mat <- rbind(group_mat, Others = others_row)
  }

  # 转长格式
  plot_df <- data.frame(
    taxa = rep(rownames(group_mat), ncol(group_mat)),
    group = rep(colnames(group_mat), each = nrow(group_mat)),
    abundance = as.vector(group_mat),
    stringsAsFactors = FALSE
  )
  plot_df$group <- factor(plot_df$group, levels = colnames(group_mat))
  plot_df$taxa <- factor(plot_df$taxa, levels = rownames(group_mat))

  # 调色板
  n_taxa <- nrow(group_mat)
  if (n_taxa <= 12) {
    colors <- RColorBrewer::brewer.pal(max(3, n_taxa), palette_name)[1:n_taxa]
  } else {
    colors <- grDevices::colorRampPalette(
      RColorBrewer::brewer.pal(12, palette_name)
    )(n_taxa)
  }

  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = group, y = abundance, fill = taxa)) +
    ggplot2::geom_bar(stat = "identity", width = 0.7) +
    ggplot2::scale_fill_manual(values = colors, name = level_label) +
    ggplot2::labs(
      title = sprintf("Taxonomic Composition (%s)", level_label),
      x = NULL,
      y = y_label
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 10),
      legend.position = "right",
      legend.text = ggplot2::element_text(size = 8)
    )

  return(p)
}


#' 绘制分类学组成饼图
#'
#' @description 对一个样本或一组样本的平均组成绘制饼图。
#'
#' @param expr_matrix 数值矩阵（features × samples）或聚合后的矩阵。
#' @param sample_info 样本元数据 data.frame（可选）。
#' @param feature_info 特征注释 data.frame（可选，用于按层级聚合）。
#' @param tax_level 分类层级列名。默认 NULL。
#' @param group_col 分组列名。默认 "sample_info"。
#' @param group_name 指定要绘制的分组名。默认 NULL（全部样本平均）。
#' @param top_n 展示前 N 个 taxa。默认 10。
#' @param palette_name 调色板名。默认 "Set3"。
#'
#' @return ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_taxa_pie(expr_matrix, sample_info, feature_info,
#'                    tax_level = "phylum", group_name = "Control")
#' }
#'
#' @export
plot_taxa_pie <- function(expr_matrix, sample_info = NULL,
                         feature_info = NULL,
                         tax_level = NULL,
                         group_col = "sample_info",
                         group_name = NULL,
                         top_n = 10,
                         palette_name = "Set3") {
  # 按层级聚合
  if (!is.null(tax_level) && !is.null(feature_info)) {
    agg <- aggregate_by_taxonomy(expr_matrix, feature_info, tax_level)
    mat <- agg$matrix
    level_label <- agg$level
  } else {
    mat <- as.matrix(expr_matrix)
    level_label <- "Feature"
  }

  # 按分组取均值
  if (!is.null(sample_info) && !is.null(group_name) && group_col %in% colnames(sample_info)) {
    common <- intersect(colnames(mat), rownames(sample_info))
    mat <- mat[, common, drop = FALSE]
    groups <- sample_info[common, group_col]
    mat <- mat[, groups == group_name, drop = FALSE]
    title_suffix <- paste0(" - ", group_name)
  } else {
    title_suffix <- " - All samples"
  }

  abundances <- rowMeans(mat, na.rm = TRUE)
  total <- sum(abundances)
  percentages <- abundances / total * 100

  # Top N + Others
  ord <- order(percentages, decreasing = TRUE)
  top_idx <- ord[1:min(top_n, length(ord))]
  others_idx <- setdiff(seq_along(percentages), top_idx)

  plot_df <- data.frame(
    taxa = names(percentages)[top_idx],
    percentage = percentages[top_idx],
    stringsAsFactors = FALSE
  )
  if (length(others_idx) > 0) {
    plot_df <- rbind(plot_df, data.frame(
      taxa = "Others",
      percentage = sum(percentages[others_idx]),
      stringsAsFactors = FALSE
    ))
  }

  plot_df$taxa <- factor(plot_df$taxa, levels = plot_df$taxa)
  plot_df$label <- sprintf("%s (%.1f%%)", plot_df$taxa, plot_df$percentage)

  n_taxa <- nrow(plot_df)
  if (n_taxa <= 12) {
    colors <- RColorBrewer::brewer.pal(max(3, n_taxa), palette_name)[1:n_taxa]
  } else {
    colors <- grDevices::colorRampPalette(
      RColorBrewer::brewer.pal(12, palette_name)
    )(n_taxa)
  }

  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = "", y = percentage, fill = taxa)) +
    ggplot2::geom_bar(stat = "identity", width = 1) +
    ggplot2::coord_polar("y", start = 0) +
    ggplot2::scale_fill_manual(values = colors, name = level_label) +
    ggplot2::labs(
      title = sprintf("Composition (%s)%s", level_label, title_suffix),
      x = NULL,
      y = NULL
    ) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      legend.position = "right",
      legend.text = ggplot2::element_text(size = 9)
    )

  return(p)
}
