# ==============================================================================
# OmicsFlow: Heatmap with hierarchical clustering
# ==============================================================================
# Complex heatmap with family color blocks
# ==============================================================================

#' 绘制带层次聚类的热图
#'
#' @description 创建一张达到出版质量的热图，对Feature（行）做层次聚类，并对样本分组
#'   （列）着色。可选地显示家族分类的颜色色块。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param sample_info 含样本元数据的 data.frame。
#' @param feature_info 可选，含Feature注释的 data.frame。
#' @param group_col sample_info 中用于分组标签的列。默认："sample_info"。
#' @param name_col feature_info 中用于显示名称的列。默认："name"。
#' @param family_col feature_info 中用于家族分类的可选列。若提供，则以色块显示家族。
#'   默认："super_class"。
#' @param scale 字符，标准化方式："row"、"column" 或 "none"。默认："row"。
#' @param clustering_method 层次聚类的连接方法。默认："ward.D2"。
#' @param distance_method 距离方法。默认："euclidean"。
#' @param show_rownames 逻辑值，是否显示行名。默认：TRUE。
#' @param show_colnames 逻辑值，是否显示列名。默认：FALSE。
#' @param n_features 显示的最大Feature数。若 nrow > n_features，则显示变异最大的Feature。
#'   默认：50。
#'
#' @return 一个 ComplexHeatmap 对象。
#'
#' @examples
#' \dontrun{
#' hm <- plot_heatmap(expr_matrix, sample_info, feature_info,
#'                    family_col = "super_class", n_features = 50)
#' }
#'
#' @export
plot_heatmap <- function(expr_matrix, sample_info, feature_info = NULL,
                         group_col = "sample_info", name_col = "name",
                         family_col = "super_class", scale = "row",
                         clustering_method = "ward.D2",
                         distance_method = "euclidean",
                         show_rownames = TRUE, show_colnames = FALSE,
                         n_features = 50) {
  # 输入校验：空矩阵会在 hclust 阶段抛出难以定位的错误，此处提前给出明确信息
  if (is.null(expr_matrix) || nrow(expr_matrix) < 2) {
    stop(sprintf(
      "plot_heatmap requires at least 2 features, got %d.",
      if (is.null(expr_matrix)) 0L else nrow(expr_matrix)))
  }
  
  # 对齐样本
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  if (length(common_samples) < 2) {
    stop(sprintf(
      "plot_heatmap requires at least 2 shared samples between expr_matrix and sample_info, got %d.",
      length(common_samples)))
  }
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]
  
  # 必要时选取变异最大的Feature
  if (nrow(expr_matrix) > n_features) {
    row_vars <- apply(expr_matrix, 1, stats::var, na.rm = TRUE)
    top_idx <- order(row_vars, decreasing = TRUE)[1:n_features]
    expr_matrix <- expr_matrix[top_idx, , drop = FALSE]
  }
  
  # 先记录原始Feature ID。下方会用 name_col 覆盖 rownames 作为显示名，
  # 若之后仍用 rownames(expr_matrix) 去 match(rownames(feature_info))
  # 取家族注释，则匹配全部落空（显示名 != Feature ID）。
  feature_ids <- rownames(expr_matrix)
  
  # 若可用，则用名称替换Feature ID
  if (!is.null(feature_info) && name_col %in% colnames(feature_info)) {
    feature_names <- feature_info[match(feature_ids,
                                        rownames(feature_info)), name_col]
    display_names <- ifelse(is.na(feature_names) | !nzchar(feature_names),
                            feature_ids, feature_names)
    # name_col 可能存在重复值，直接作为 rownames 会触发
    # "duplicate row.names are not allowed"，用 make.unique 去重。
    rownames(expr_matrix) <- make.unique(as.character(display_names))
  }
  
  # 标准化
  if (scale == "row") {
    expr_matrix <- t(scale(t(expr_matrix)))
  } else if (scale == "column") {
    expr_matrix <- scale(expr_matrix)
  }
  
  # 处理标准化产生的 NA
  expr_matrix[is.na(expr_matrix)] <- 0
  
  # 距离与聚类
  dist_method <- get("dist", asNamespace("stats"))
  row_dist <- stats::dist(expr_matrix, method = distance_method)
  col_dist <- stats::dist(t(expr_matrix), method = distance_method)
  
  row_hc <- stats::hclust(row_dist, method = clustering_method)
  col_order <- order(sample_info[[group_col]])
  
  # 列注释
  groups <- sample_info[[group_col]]
  group_colors <- make_group_colors(unique(groups))
  
  # 检查 ComplexHeatmap 是否可用
  if (requireNamespace("ComplexHeatmap", quietly = TRUE)) {
    # 列注释
    col_anno <- ComplexHeatmap::HeatmapAnnotation(
      Group = groups,
      col = list(Group = group_colors),
      show_annotation_name = TRUE,
      annotation_name_side = "left"
    )
    
    # 行注释（家族）
    row_anno <- NULL
    if (!is.null(feature_info) && !is.null(family_col) &&
        family_col %in% colnames(feature_info)) {
      family_info <- as.character(feature_info[match(feature_ids,
                                        rownames(feature_info)), family_col])
      family_info[is.na(family_info) | !nzchar(family_info)] <- "Unknown"
      family_colors <- make_group_colors(unique(family_info),
                                         palette_name = "Set3")
      row_anno <- ComplexHeatmap::rowAnnotation(
        Family = family_info,
        col = list(Family = family_colors),
        show_annotation_name = TRUE,
        annotation_name_side = "top"
      )
    }
    
    # 创建热图
    hm <- ComplexHeatmap::Heatmap(
      expr_matrix,
      name = "Expression",
      col = grDevices::colorRampPalette(c("#2c7bb6", "white", "#d7191c"))(100),
      cluster_rows = row_hc,
      cluster_columns = FALSE,
      column_order = col_order,
      top_annotation = col_anno,
      left_annotation = row_anno,
      show_row_names = show_rownames,
      show_column_names = show_colnames,
      row_names_gp = grid::gpar(fontsize = 7),
      column_names_gp = grid::gpar(fontsize = 8),
      heatmap_legend_param = list(title = "Z-score")
    )
    
  } else if (requireNamespace("pheatmap", quietly = TRUE)) {
    # 退而使用 pheatmap
    annotation_col <- data.frame(
      Group = groups,
      row.names = colnames(expr_matrix)
    )
    annotation_colors <- list(Group = group_colors)
    
    annotation_row <- NULL
    if (!is.null(feature_info) && !is.null(family_col) &&
        family_col %in% colnames(feature_info)) {
      family_info <- as.character(feature_info[match(feature_ids,
                                        rownames(feature_info)), family_col])
      family_info[is.na(family_info) | !nzchar(family_info)] <- "Unknown"
      annotation_row <- data.frame(
        Family = family_info,
        row.names = rownames(expr_matrix)
      )
      annotation_colors$Family <- make_group_colors(unique(family_info),
                                                    palette_name = "Set3")
    }
    
    hm <- pheatmap::pheatmap(
      expr_matrix,
      cluster_rows = TRUE,
      cluster_cols = FALSE,
      clustering_method = clustering_method,
      annotation_col = annotation_col,
      annotation_row = annotation_row,
      annotation_colors = annotation_colors,
      show_rownames = show_rownames,
      show_colnames = show_colnames,
      color = grDevices::colorRampPalette(c("#2c7bb6", "white", "#d7191c"))(100),
      fontsize_row = 7,
      fontsize_col = 8,
      silent = TRUE
    )
    
  } else {
    stop("Either 'ComplexHeatmap' or 'pheatmap' package is required.")
  }
  
  return(hm)
}
