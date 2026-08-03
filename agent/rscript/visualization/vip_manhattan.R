# ==============================================================================
# OmicsFlow: VIP Manhattan Plot (categorical)
# ==============================================================================
# Visualize VIP (Variable Importance in Projection) scores from PLS-DA,
# grouped by a categorical annotation (e.g. super_class), in a Manhattan-style
# jitter plot. Useful as a publication figure to show VIP distribution per
# metabolite category.
# ==============================================================================

#' VIP Manhattan-style jitter plot grouped by annotation
#'
#' @description Creates a publication-quality Manhattan-style plot where the
#'   x-axis represents a categorical annotation (e.g. metabolite super_class,
#'   analogous to chromosomes in a genomic Manhattan plot) and the y-axis is the
#'   VIP score. Each point is a feature, jittered within its category, with a
#'   smooth density outline and a reference line at \code{threshold}.
#'
#' @param vip A data.frame of VIP scores with feature IDs as row names and a
#'   single numeric column (typically \code{plsda_result$vip}).
#' @param feature_info A data.frame with feature annotation. Must contain the
#'   feature ID column and the category column.
#' @param feature_id_col Column name in \code{feature_info} holding feature IDs.
#'   Default: "name".
#' @param category_col Column name in \code{feature_info} holding the grouping
#'   category (e.g. "super_class"). Default: "super_class".
#' @param threshold VIP importance threshold (reference line). Default: 1.0.
#' @param top_n_labels Number of top VIP features (per category, overall) to
#'   label with text. Set to 0 to disable. Default: 0.
#' @param title Plot title. Default: "VIP Manhattan Plot by Category".
#' @param x_label X-axis label. Default: "Metabolite Category".
#' @param y_label Y-axis label. Default: "VIP Score".
#' @param base_size Base font size. Default: 12.
#'
#' @return A ggplot object.
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

  # Ensure vip is a data.frame with a numeric vip column
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

  # Map feature IDs to category
  info_sub <- feature_info[, c(feature_id_col, category_col), drop = FALSE]
  colnames(info_sub) <- c("feature_id", "category")
  info_sub$feature_id <- as.character(info_sub$feature_id)
  info_sub$category <- as.character(info_sub$category)

  plot_df <- merge(vip_df, info_sub, by = "feature_id", all.x = TRUE)

  # Drop missing / invalid category
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

  # Reorder categories by mean VIP (descending) for a cleaner layout
  cat_order <- names(sort(tapply(plot_df$vip, plot_df$category, mean),
                          decreasing = TRUE))
  plot_df$category <- factor(plot_df$category, levels = cat_order)

  # Optional top labels (overall, across all categories)
  label_df <- NULL
  if (top_n_labels > 0 && nrow(plot_df) > 0) {
    label_df <- head(plot_df[order(plot_df$vip, decreasing = TRUE), ], top_n_labels)
  }

  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = category, y = vip)) +
    # Density outline per category (mirrors chromosome band feel)
    ggplot2::geom_violin(ggplot2::aes(fill = category), alpha = 0.12,
                         scale = "width", width = 0.9, color = NA) +
    # Jittered points, colored by importance relative to threshold
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
    # Reference threshold line
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
