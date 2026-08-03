# ==============================================================================
# OmicsFlow: Heatmap with hierarchical clustering
# ==============================================================================
# Complex heatmap with family color blocks
# ==============================================================================

#' Plot heatmap with hierarchical clustering
#'
#' @description Creates a publication-quality heatmap with hierarchical
#'   clustering of features (rows) and sample grouping (columns). Optionally
#'   displays family classification color blocks.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param sample_info A data.frame with sample metadata.
#' @param feature_info Optional data.frame with feature annotations.
#' @param group_col Column in sample_info for group labels. Default: "sample_info".
#' @param name_col Column in feature_info for display names. Default: "name".
#' @param family_col Optional column in feature_info for family classification.
#'   If provided, a color block will show family. Default: "super_class".
#' @param scale Character, scaling method: "row", "column", or "none".
#'   Default: "row".
#' @param clustering_method Linkage method for hierarchical clustering.
#'   Default: "ward.D2".
#' @param distance_method Distance method. Default: "euclidean".
#' @param show_rownames Logical, whether to show row names. Default: TRUE.
#' @param show_colnames Logical, whether to show column names. Default: FALSE.
#' @param n_features Maximum number of features to display. If nrow > n_features,
#'   shows top variable features. Default: 50.
#'
#' @return A ComplexHeatmap object.
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
  # Align samples
  common_samples <- intersect(colnames(expr_matrix), rownames(sample_info))
  expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
  sample_info <- sample_info[common_samples, , drop = FALSE]

  # Select top variable features if needed
  if (nrow(expr_matrix) > n_features) {
    row_vars <- apply(expr_matrix, 1, stats::var, na.rm = TRUE)
    top_idx <- order(row_vars, decreasing = TRUE)[1:n_features]
    expr_matrix <- expr_matrix[top_idx, , drop = FALSE]
  }

  # Replace feature IDs with names if available
  if (!is.null(feature_info) && name_col %in% colnames(feature_info)) {
    feature_names <- feature_info[match(rownames(expr_matrix),
                                        rownames(feature_info)), name_col]
    rownames(expr_matrix) <- ifelse(is.na(feature_names),
                                     rownames(expr_matrix), feature_names)
  }

  # Scale
  if (scale == "row") {
    expr_matrix <- t(scale(t(expr_matrix)))
  } else if (scale == "column") {
    expr_matrix <- scale(expr_matrix)
  }

  # Handle NAs from scaling
  expr_matrix[is.na(expr_matrix)] <- 0

  # Distance and clustering
  dist_method <- get("dist", asNamespace("stats"))
  row_dist <- stats::dist(expr_matrix, method = distance_method)
  col_dist <- stats::dist(t(expr_matrix), method = distance_method)

  row_hc <- stats::hclust(row_dist, method = clustering_method)
  col_order <- order(sample_info[[group_col]])

  # Column annotation
  groups <- sample_info[[group_col]]
  group_colors <- make_group_colors(unique(groups))

  # Check for ComplexHeatmap
  if (requireNamespace("ComplexHeatmap", quietly = TRUE)) {
    # Column annotation
    col_anno <- ComplexHeatmap::HeatmapAnnotation(
      Group = groups,
      col = list(Group = group_colors),
      show_annotation_name = TRUE,
      annotation_name_side = "left"
    )

    # Row annotation (family)
    row_anno <- NULL
    if (!is.null(feature_info) && !is.null(family_col) &&
        family_col %in% colnames(feature_info)) {
      family_info <- feature_info[match(rownames(expr_matrix),
                                        rownames(feature_info)), family_col]
      family_info[is.na(family_info)] <- "Unknown"
      family_colors <- make_group_colors(unique(family_info),
                                          palette_name = "Set3")
      row_anno <- ComplexHeatmap::rowAnnotation(
        Family = family_info,
        col = list(Family = family_colors),
        show_annotation_name = TRUE,
        annotation_name_side = "top"
      )
    }

    # Create heatmap
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
    # Fallback to pheatmap
    annotation_col <- data.frame(
      Group = groups,
      row.names = colnames(expr_matrix)
    )
    annotation_colors <- list(Group = group_colors)

    annotation_row <- NULL
    if (!is.null(feature_info) && !is.null(family_col) &&
        family_col %in% colnames(feature_info)) {
      family_info <- feature_info[match(rownames(expr_matrix),
                                        rownames(feature_info)), family_col]
      family_info[is.na(family_info)] <- "Unknown"
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
