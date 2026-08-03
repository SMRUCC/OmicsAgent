# ==============================================================================
# OmicsFlow: Multi-Omics Visualisation
# ==============================================================================
# Plotting companions for the multi-omics analysis functions. Every function
# returns a ggplot object, or a pheatmap object where a heatmap is the natural
# representation, so that the existing export_plot() and export_heatmap()
# helpers can be used directly.
# ==============================================================================

#' Heatmap of a cross-omics correlation matrix
#'
#' @description Displays the strongest cross-layer correlations as a heatmap,
#'   restricted to the features involved in the most significant associations so
#'   that the picture stays readable even for large layers.
#'
#' @param cor_result Result of \code{run_cross_correlation()}.
#' @param top_n Number of features per axis retained, chosen by the strongest
#'   absolute correlation. Default: 30.
#' @param title Plot title. Default: "Cross-omics correlation".
#' @param cluster Logical, cluster rows and columns. Default: TRUE.
#'
#' @return A pheatmap object, or NULL when the matrix is empty.
#'
#' @examples
#' \dontrun{
#' hm <- plot_cross_correlation_heatmap(res, top_n = 30)
#' export_heatmap(hm, fig_dir, "cross_cor")
#' }
#'
#' @export
plot_cross_correlation_heatmap <- function(cor_result, top_n = 30,
                                           title = "Cross-omics correlation",
                                           cluster = TRUE) {
  if (!requireNamespace("pheatmap", quietly = TRUE)) {
    stop("Package 'pheatmap' is required. Install it with install.packages('pheatmap').")
  }
  cm <- cor_result$cor_matrix
  if (is.null(cm) || nrow(cm) == 0 || ncol(cm) == 0) {
    cat("  Empty correlation matrix, nothing to plot.\n")
    return(NULL)
  }

  # Keep the features carrying the strongest associations.
  row_score <- apply(abs(cm), 1, max, na.rm = TRUE)
  col_score <- apply(abs(cm), 2, max, na.rm = TRUE)
  row_score[!is.finite(row_score)] <- 0
  col_score[!is.finite(col_score)] <- 0
  ridx <- order(row_score, decreasing = TRUE)[seq_len(min(top_n, nrow(cm)))]
  cidx <- order(col_score, decreasing = TRUE)[seq_len(min(top_n, ncol(cm)))]
  sub <- cm[sort(ridx), sort(cidx), drop = FALSE]
  sub[!is.finite(sub)] <- 0

  # Clustering needs at least two rows and columns.
  do_cluster <- cluster && nrow(sub) > 1 && ncol(sub) > 1
  limit <- max(abs(sub), na.rm = TRUE)
  if (!is.finite(limit) || limit == 0) limit <- 1
  breaks <- seq(-limit, limit, length.out = 101)

  pheatmap::pheatmap(
    sub,
    color = grDevices::colorRampPalette(
      c("#2166AC", "#67A9CF", "#F7F7F7", "#EF8A62", "#B2182B"))(100),
    breaks = breaks,
    cluster_rows = do_cluster,
    cluster_cols = do_cluster,
    fontsize_row = 7,
    fontsize_col = 7,
    main = title,
    silent = TRUE
  )
}


#' Bar chart of Mantel statistics
#'
#' @description Summarises the Mantel correlations between omics layers, and
#'   between each layer and the environmental variables, as a bar chart with the
#'   significant comparisons highlighted.
#'
#' @param mantel_result Result of \code{run_mantel_test()}.
#' @param title Plot title. Default: "Mantel test".
#' @param alpha Significance cutoff used for the fill. Default: 0.05.
#'
#' @return A ggplot object, or NULL when there is nothing to plot.
#'
#' @examples
#' \dontrun{
#' p <- plot_mantel_network(mantel_res)
#' }
#'
#' @export
plot_mantel_network <- function(mantel_result, title = "Mantel test",
                                alpha = 0.05) {
  parts <- list()
  # Layer-to-layer congruence.
  oo <- mantel_result$omics_omics
  if (!is.null(oo) && is.data.frame(oo) && nrow(oo) > 0) {
    parts[[length(parts) + 1L]] <- data.frame(
      comparison = paste(oo$layer_x, oo$layer_y, sep = " vs "),
      r = as.numeric(oo$mantel_r),
      p = as.numeric(oo$p_value),
      type = "omics vs omics",
      stringsAsFactors = FALSE
    )
  }
  # Layer against each environmental variable.
  oe <- mantel_result$omics_env
  if (!is.null(oe) && is.data.frame(oe) && nrow(oe) > 0) {
    parts[[length(parts) + 1L]] <- data.frame(
      comparison = paste(oe$layer, oe$variable, sep = " vs "),
      r = as.numeric(oe$mantel_r),
      p = as.numeric(oe$p_value),
      type = "omics vs environment",
      stringsAsFactors = FALSE
    )
  }
  if (length(parts) == 0) {
    cat("  No Mantel result to plot.\n")
    return(NULL)
  }
  pd <- do.call(rbind, parts)
  pd <- pd[is.finite(pd$r), , drop = FALSE]
  if (nrow(pd) == 0) {
    cat("  No finite Mantel statistic to plot.\n")
    return(NULL)
  }
  pd$significant <- ifelse(!is.na(pd$p) & pd$p < alpha, "Significant", "n.s.")
  pd <- pd[order(pd$r), , drop = FALSE]
  pd$comparison <- factor(pd$comparison, levels = pd$comparison)

  ggplot2::ggplot(pd, ggplot2::aes(x = .data$comparison, y = .data$r,
                                   fill = .data$significant)) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::coord_flip() +
    ggplot2::facet_wrap(~ type, scales = "free_y", ncol = 1) +
    ggplot2::scale_fill_manual(values = c("Significant" = "#B2182B",
                                          "n.s." = "#BDBDBD")) +
    ggplot2::labs(title = title, x = NULL, y = "Mantel r", fill = NULL) +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
}


#' Procrustes displacement plot
#'
#' @description Draws the sample-wise displacement between two ordinations,
#'   each arrow joining the position of a sample in the first configuration to
#'   its position in the second. Short arrows indicate good agreement.
#'
#' @param proc_result Result of \code{run_procrustes()}.
#' @param sample_info Optional sample annotation for colouring. Default: NULL.
#' @param color_col Column used for colouring. Default: NULL.
#' @param title Plot title. Default: "Procrustes analysis".
#'
#' @return A ggplot object, or NULL when coordinates are unavailable.
#'
#' @examples
#' \dontrun{
#' p <- plot_procrustes(proc, sample_info, color_col = "location")
#' }
#'
#' @export
plot_procrustes <- function(proc_result, sample_info = NULL, color_col = NULL,
                            title = "Procrustes analysis") {
  coords <- proc_result$coordinates
  if (is.null(coords) || !is.data.frame(coords) || nrow(coords) == 0) {
    cat("  No Procrustes coordinates to plot.\n")
    return(NULL)
  }
  if (!all(c("x1", "y1", "x2", "y2") %in% colnames(coords))) {
    cat("  Procrustes coordinates lack the x1/y1/x2/y2 columns.\n")
    return(NULL)
  }

  coords$group <- "all"
  if (!is.null(sample_info) && !is.null(color_col) &&
      color_col %in% colnames(sample_info)) {
    hit <- match(coords$sample, rownames(sample_info))
    coords$group <- as.character(sample_info[[color_col]])[hit]
    coords$group[is.na(coords$group)] <- "unknown"
  }

  cols <- make_group_colors(unique(coords$group))
  subtitle <- NULL
  if (!is.null(proc_result$correlation) && !is.null(proc_result$p_value)) {
    subtitle <- sprintf("Procrustes r = %.3f, p = %.3f",
                        proc_result$correlation, proc_result$p_value)
  }

  ggplot2::ggplot(coords) +
    ggplot2::geom_segment(
      ggplot2::aes(x = .data$x1, y = .data$y1, xend = .data$x2, yend = .data$y2,
                   color = .data$group),
      arrow = ggplot2::arrow(length = ggplot2::unit(0.15, "cm")),
      alpha = 0.7) +
    ggplot2::geom_point(ggplot2::aes(x = .data$x1, y = .data$y1,
                                     color = .data$group), size = 1.4) +
    ggplot2::scale_color_manual(values = cols) +
    ggplot2::labs(title = title, subtitle = subtitle,
                  x = "Dimension 1", y = "Dimension 2", color = NULL) +
    ggplot2::theme_bw(base_size = 11)
}


#' DIABLO score plots for every block
#'
#' @description Draws the sample scores of each omics block on the first two
#'   DIABLO components, coloured by the discriminated group.
#'
#' @param diablo_result Result of \code{run_diablo()}.
#' @param title Plot title. Default: "DIABLO sample scores".
#'
#' @return A ggplot object faceted by omics block, or NULL when unavailable.
#'
#' @examples
#' \dontrun{
#' p <- plot_diablo_scores(diablo_res)
#' }
#'
#' @export
plot_diablo_scores <- function(diablo_result, title = "DIABLO sample scores") {
  if (is.null(diablo_result) || is.null(diablo_result$scores) ||
      length(diablo_result$scores) == 0) {
    cat("  No DIABLO scores to plot.\n")
    return(NULL)
  }

  parts <- list()
  for (nm in names(diablo_result$scores)) {
    sc <- diablo_result$scores[[nm]]
    if (is.null(sc) || nrow(sc) == 0) next
    comp_cols <- grep("^comp", colnames(sc), value = TRUE)
    if (length(comp_cols) < 2) next
    grp <- if ("group" %in% colnames(sc)) as.character(sc$group) else "all"
    parts[[nm]] <- data.frame(
      omics = nm,
      comp1 = as.numeric(sc[[comp_cols[1]]]),
      comp2 = as.numeric(sc[[comp_cols[2]]]),
      group = grp,
      stringsAsFactors = FALSE
    )
  }
  if (length(parts) == 0) {
    cat("  DIABLO scores contain fewer than two components.\n")
    return(NULL)
  }
  pd <- do.call(rbind, parts)
  cols <- make_group_colors(unique(pd$group))

  ggplot2::ggplot(pd, ggplot2::aes(x = .data$comp1, y = .data$comp2,
                                   color = .data$group)) +
    ggplot2::geom_point(size = 1.8, alpha = 0.8) +
    ggplot2::stat_ellipse(level = 0.95, linewidth = 0.4, na.rm = TRUE) +
    ggplot2::facet_wrap(~ omics, scales = "free") +
    ggplot2::scale_color_manual(values = cols) +
    ggplot2::labs(title = title, x = "Component 1", y = "Component 2",
                  color = NULL) +
    ggplot2::theme_bw(base_size = 11)
}


#' Fermentation trajectory plot
#'
#' @description Plots the averaged position of each time point in PCA space and
#'   joins consecutive time points, one path per group, revealing how the
#'   fermentation progresses and whether the regions follow different rhythms.
#'
#' @param traj_result Result of \code{run_temporal_trajectory()}.
#' @param title Plot title. Default: "Fermentation trajectory".
#' @param show_samples Logical, draw the individual samples behind the path.
#'   Default: TRUE.
#'
#' @return A ggplot object, or NULL when the trajectory is empty.
#'
#' @examples
#' \dontrun{
#' p <- plot_temporal_trajectory(traj)
#' }
#'
#' @export
plot_temporal_trajectory <- function(traj_result,
                                     title = "Fermentation trajectory",
                                     show_samples = TRUE) {
  traj <- traj_result$trajectory
  if (is.null(traj) || nrow(traj) == 0) {
    cat("  No trajectory to plot.\n")
    return(NULL)
  }
  if (!all(c("PC1", "PC2") %in% colnames(traj))) {
    cat("  Trajectory lacks PC1/PC2.\n")
    return(NULL)
  }

  cols <- make_group_colors(unique(traj$group))
  var_exp <- traj_result$variance
  xlab <- if (!is.null(var_exp) && length(var_exp) >= 1) {
    sprintf("PC1 (%.1f%%)", var_exp[1])
  } else "PC1"
  ylab <- if (!is.null(var_exp) && length(var_exp) >= 2) {
    sprintf("PC2 (%.1f%%)", var_exp[2])
  } else "PC2"

  p <- ggplot2::ggplot()
  if (show_samples && !is.null(traj_result$scores) &&
      all(c("PC1", "PC2") %in% colnames(traj_result$scores))) {
    p <- p + ggplot2::geom_point(
      data = traj_result$scores,
      ggplot2::aes(x = .data$PC1, y = .data$PC2, color = .data$group),
      alpha = 0.18, size = 1.1)
  }

  p +
    ggplot2::geom_path(
      data = traj,
      ggplot2::aes(x = .data$PC1, y = .data$PC2, color = .data$group),
      linewidth = 0.9,
      arrow = ggplot2::arrow(length = ggplot2::unit(0.2, "cm"),
                             type = "closed")) +
    ggplot2::geom_point(
      data = traj,
      ggplot2::aes(x = .data$PC1, y = .data$PC2, color = .data$group),
      size = 3) +
    ggrepel::geom_text_repel(
      data = traj,
      ggplot2::aes(x = .data$PC1, y = .data$PC2, label = .data$time),
      size = 3, show.legend = FALSE, max.overlaps = 20) +
    ggplot2::scale_color_manual(values = cols) +
    ggplot2::labs(title = title, x = xlab, y = ylab, color = NULL) +
    ggplot2::theme_bw(base_size = 11)
}


#' Temporal cluster profile plot
#'
#' @description Draws the mean scaled profile of each temporal cluster across
#'   the fermentation time course, one facet per cluster.
#'
#' @param cluster_result Result of \code{run_temporal_clustering()}.
#' @param title Plot title. Default: "Temporal expression clusters".
#'
#' @return A ggplot object, or NULL when profiles are unavailable.
#'
#' @examples
#' \dontrun{
#' p <- plot_temporal_clusters(cl)
#' }
#'
#' @export
plot_temporal_clusters <- function(cluster_result,
                                   title = "Temporal expression clusters") {
  prof <- cluster_result$profiles
  if (is.null(prof) || nrow(prof) == 0) {
    cat("  No cluster profile to plot.\n")
    return(NULL)
  }
  labels <- unique(prof[, c("cluster", "n_features")])
  labels$label <- sprintf("%s (n=%d)", labels$cluster, labels$n_features)
  prof$facet <- labels$label[match(prof$cluster, labels$cluster)]

  ggplot2::ggplot(prof, ggplot2::aes(x = .data$time, y = .data$value,
                                     group = .data$cluster)) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed",
                        color = "grey60", linewidth = 0.3) +
    ggplot2::geom_line(color = "#2166AC", linewidth = 0.9) +
    ggplot2::geom_point(color = "#2166AC", size = 1.8) +
    ggplot2::facet_wrap(~ facet) +
    ggplot2::labs(title = title, x = "Fermentation day",
                  y = "Mean scaled abundance") +
    ggplot2::theme_bw(base_size = 11)
}


#' Cross-omics network plot
#'
#' @description Renders the association network with nodes coloured by omics
#'   layer, node size proportional to degree and edge colour encoding the sign
#'   of the correlation.
#'
#' @param network Result of \code{build_cross_omics_network()}.
#' @param label_top Number of highest-degree nodes labelled. Default: 15.
#' @param title Plot title. Default: "Cross-omics association network".
#' @param seed Random seed for the layout. Default: 42.
#'
#' @return A ggplot object, or NULL when the network is empty.
#'
#' @examples
#' \dontrun{
#' p <- plot_cross_omics_network(net)
#' }
#'
#' @export
plot_cross_omics_network <- function(network, label_top = 15,
                                     title = "Cross-omics association network",
                                     seed = 42) {
  if (!requireNamespace("igraph", quietly = TRUE)) {
    stop("Package 'igraph' is required. Install it with install.packages('igraph').")
  }
  if (is.null(network)) {
    cat("  No network to plot.\n")
    return(NULL)
  }
  graph <- if (inherits(network, "igraph")) network else network$graph
  if (is.null(graph) || igraph::vcount(graph) == 0) {
    cat("  Empty network, nothing to plot.\n")
    return(NULL)
  }

  set.seed(seed)
  lay <- igraph::layout_with_fr(graph)
  vnames <- igraph::V(graph)$name
  nodes <- data.frame(
    name = vnames,
    x = lay[, 1],
    y = lay[, 2],
    omics = if (!is.null(igraph::V(graph)$omics)) igraph::V(graph)$omics else "unknown",
    degree = as.integer(igraph::degree(graph)),
    stringsAsFactors = FALSE
  )

  el <- igraph::as_edgelist(graph, names = FALSE)
  edges <- data.frame(
    x = lay[el[, 1], 1], y = lay[el[, 1], 2],
    xend = lay[el[, 2], 1], yend = lay[el[, 2], 2],
    direction = if (!is.null(igraph::E(graph)$direction)) {
      igraph::E(graph)$direction
    } else "positive",
    stringsAsFactors = FALSE
  )

  cols <- make_group_colors(unique(nodes$omics))
  lab <- nodes[order(-nodes$degree), , drop = FALSE]
  if (label_top < nrow(lab)) lab <- lab[seq_len(label_top), , drop = FALSE]

  ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = edges,
      ggplot2::aes(x = .data$x, y = .data$y, xend = .data$xend,
                   yend = .data$yend, color = .data$direction),
      alpha = 0.3, linewidth = 0.25) +
    ggplot2::scale_color_manual(values = c("positive" = "#B2182B",
                                           "negative" = "#2166AC"),
                                name = "Correlation") +
    ggplot2::geom_point(
      data = nodes,
      ggplot2::aes(x = .data$x, y = .data$y, fill = .data$omics,
                   size = .data$degree),
      shape = 21, color = "grey30", stroke = 0.2, alpha = 0.9) +
    ggplot2::scale_fill_manual(values = cols, name = "Omics") +
    ggplot2::scale_size_continuous(range = c(1.5, 7), name = "Degree") +
    ggrepel::geom_text_repel(
      data = lab,
      ggplot2::aes(x = .data$x, y = .data$y, label = .data$name),
      size = 2.6, max.overlaps = 30, segment.size = 0.2) +
    ggplot2::labs(title = title, x = NULL, y = NULL) +
    ggplot2::theme_void(base_size = 11) +
    ggplot2::theme(legend.position = "right")
}


#' Pathway bridging heatmap
#'
#' @description Shows the correlation of each shared annotation module between
#'   consecutive omics layers, so that modules propagating coherently from gene
#'   to aroma stand out as a bright row.
#'
#' @param bridge_result Result of \code{run_pathway_bridge()}.
#' @param top_n Number of modules displayed, ranked by mean absolute
#'   correlation. Default: 30.
#' @param title Plot title. Default: "Pathway bridging across omics layers".
#'
#' @return A ggplot object, or NULL when there is nothing to plot.
#'
#' @examples
#' \dontrun{
#' p <- plot_pathway_bridge_heatmap(bridge)
#' }
#'
#' @export
plot_pathway_bridge_heatmap <- function(bridge_result, top_n = 30,
                                        title = "Pathway bridging across omics layers") {
  links <- bridge_result$links
  if (is.null(links) || nrow(links) == 0) {
    cat("  No pathway link to plot.\n")
    return(NULL)
  }
  links$transition <- paste(links$from_layer, links$to_layer, sep = " -> ")

  strength <- stats::aggregate(abs(links$r), by = list(module = links$module),
                               FUN = mean, na.rm = TRUE)
  strength <- strength[order(-strength$x), , drop = FALSE]
  keep <- utils::head(strength$module, top_n)
  pd <- links[links$module %in% keep, , drop = FALSE]
  pd$module <- factor(pd$module, levels = rev(keep))
  pd$star <- ifelse(!is.na(pd$padj) & pd$padj < 0.001, "***",
             ifelse(!is.na(pd$padj) & pd$padj < 0.01, "**",
             ifelse(!is.na(pd$padj) & pd$padj < 0.05, "*", "")))

  limit <- max(abs(pd$r), na.rm = TRUE)
  if (!is.finite(limit) || limit == 0) limit <- 1

  ggplot2::ggplot(pd, ggplot2::aes(x = .data$transition, y = .data$module,
                                   fill = .data$r)) +
    ggplot2::geom_tile(color = "white", linewidth = 0.3) +
    ggplot2::geom_text(ggplot2::aes(label = .data$star), size = 3,
                       color = "grey10") +
    ggplot2::scale_fill_gradient2(low = "#2166AC", mid = "#F7F7F7",
                                  high = "#B2182B", midpoint = 0,
                                  limits = c(-limit, limit), name = "r") +
    ggplot2::labs(title = title, x = NULL, y = NULL) +
    ggplot2::theme_bw(base_size = 10) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 30, hjust = 1),
      panel.grid = ggplot2::element_blank())
}


#' Bar chart of correlation partner counts
#'
#' @description Ranks features by how many significant cross-omics partners
#'   they have, nominating the taxa that drive the largest share of the
#'   metabolite or aroma variation.
#'
#' @param summary_df Result of \code{summarise_correlation_partners()}.
#' @param top_n Number of features displayed. Default: 20.
#' @param title Plot title. Default: "Top correlation partners".
#'
#' @return A ggplot object, or NULL when the summary is empty.
#'
#' @examples
#' \dontrun{
#' p <- plot_correlation_partners(summary_df)
#' }
#'
#' @export
plot_correlation_partners <- function(summary_df, top_n = 20,
                                      title = "Top correlation partners") {
  if (is.null(summary_df) || !is.data.frame(summary_df) || nrow(summary_df) == 0) {
    cat("  No correlation partner summary to plot.\n")
    return(NULL)
  }
  fcol <- intersect(c("feature", "feature_x", "name"), colnames(summary_df))[1]
  ncol_ <- intersect(c("n_partners", "n", "count"), colnames(summary_df))[1]
  if (is.na(fcol) || is.na(ncol_)) {
    cat("  Summary lacks the feature or partner-count column.\n")
    return(NULL)
  }

  pd <- data.frame(
    feature = as.character(summary_df[[fcol]]),
    n_partners = as.numeric(summary_df[[ncol_]]),
    stringsAsFactors = FALSE
  )
  if ("mean_abs_r" %in% colnames(summary_df)) {
    pd$mean_abs_r <- as.numeric(summary_df$mean_abs_r)
  } else {
    pd$mean_abs_r <- NA_real_
  }
  pd <- pd[order(-pd$n_partners), , drop = FALSE]
  if (top_n < nrow(pd)) pd <- pd[seq_len(top_n), , drop = FALSE]
  pd$feature <- factor(pd$feature, levels = rev(pd$feature))

  p <- ggplot2::ggplot(pd, ggplot2::aes(x = .data$feature, y = .data$n_partners))
  if (all(is.na(pd$mean_abs_r))) {
    p <- p + ggplot2::geom_col(fill = "#4393C3", width = 0.7)
  } else {
    p <- p + ggplot2::geom_col(ggplot2::aes(fill = .data$mean_abs_r), width = 0.7) +
      ggplot2::scale_fill_gradient(low = "#D1E5F0", high = "#B2182B",
                                   name = "mean |r|")
  }
  p +
    ggplot2::coord_flip() +
    ggplot2::labs(title = title, x = NULL, y = "Number of significant partners") +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
}
