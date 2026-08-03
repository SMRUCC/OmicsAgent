# ==============================================================================
# OmicsFlow: Volcano Plot
# ==============================================================================
# Visualize differential features
# ==============================================================================

#' Plot volcano plot
#'
#' @description Creates a publication-quality volcano plot showing logFC vs
#'   -log10(p-value). Top N differential features are labeled.
#'
#' @param de_results Results from \code{run_limma()}$results or a data.frame
#'   with columns: feature_id, logFC, p_value or p_adj.
#' @param p_col Column name for p-value. Default: "p_adj".
#' @param logfc_col Column name for logFC. Default: "logFC".
#' @param feature_col Column name for feature IDs. Default: "feature_id".
#' @param name_col Optional column for feature names. Default: NULL.
#' @param p_threshold P-value threshold. Default: 0.05.
#' @param logfc_threshold Absolute logFC threshold. Default: 1.
#' @param top_n Number of top features to label. Default: 5.
#' @param color_up Color for up-regulated. Default: "#e74c3c".
#' @param color_down Color for down-regulated. Default: "#2ecc71".
#' @param color_ns Color for non-significant. Default: "grey70".
#'
#' @return A ggplot object.
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
  # Prepare data - use rownames if feature_col not in columns
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

  # Add names if provided
  if (!is.null(name_col) && name_col %in% colnames(de_results)) {
    plot_data$name <- de_results[[name_col]]
  } else {
    plot_data$name <- plot_data$feature_id
  }

  # Remove NA
  plot_data <- plot_data[!is.na(plot_data$logFC) & !is.na(plot_data$p_value), ]

  # Calculate -log10 p-value
  plot_data$neg_log10_p <- -log10(plot_data$p_value)

  # Determine significance
  plot_data$direction <- ifelse(
    plot_data$p_value < p_threshold & plot_data$logFC > logfc_threshold, "Up",
    ifelse(
      plot_data$p_value < p_threshold & plot_data$logFC < -logfc_threshold, "Down",
      "NS"
    )
  )

  # Select top features for labeling
  # Rank by combination of significance and effect size
  plot_data$score <- abs(plot_data$logFC) * (-log10(plot_data$p_value))
  top_features <- plot_data[order(plot_data$score, decreasing = TRUE), ]
  top_features <- head(top_features[top_features$direction != "NS", ], top_n)

  # Build plot
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
