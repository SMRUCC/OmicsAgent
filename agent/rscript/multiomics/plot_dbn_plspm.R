# ==============================================================================
# OmicsFlow: Visualisation for Dynamic Bayesian Networks, Virtual Perturbation
#            and Hierarchical PLS Path Models
# ==============================================================================
# Layout coordinates are computed with igraph where a force-directed placement
# helps, and rendered with ggplot2 so the figures match the style of the other
# plot_* functions in this project and can be passed straight to export_plot().
#
# Every function degrades gracefully: when there is nothing to draw a valid
# ggplot carrying an explanatory message is returned instead of an error, so a
# pipeline step never breaks because a network happened to be empty.
# ==============================================================================


#' Palette used to colour omics layers consistently across all figures
#' @keywords internal
.dbn_omics_palette <- c(
  microbiome    = "#8c6bb1",
  transcriptome = "#4a90d9",
  proteome      = "#41ab5d",
  metabolome    = "#fe9929",
  volatilome    = "#e34a33"
)


#' Resolve colours for a set of omics layers
#'
#' @param layers Character vector of layer names.
#'
#' @return Named character vector of colours.
#'
#' @keywords internal
.dbn_layer_colors <- function(layers) {
  layers <- unique(layers[!is.na(layers)])
  if (length(layers) == 0) return(character(0))
  known <- intersect(layers, names(.dbn_omics_palette))
  unknown <- setdiff(layers, known)
  cols <- .dbn_omics_palette[known]
  if (length(unknown) > 0) {
    extra <- grDevices::hcl.colors(length(unknown), palette = "Dark 3")
    cols <- c(cols, stats::setNames(extra, unknown))
  }
  cols[layers]
}


#' Empty placeholder plot carrying a message
#'
#' @param msg Message to display.
#' @param title Optional plot title.
#'
#' @return A ggplot object.
#'
#' @keywords internal
.dbn_empty_plot <- function(msg, title = NULL) {
  ggplot2::ggplot() +
    ggplot2::annotate("text", x = 0, y = 0, label = msg, size = 4.5,
                      colour = "grey30") +
    ggplot2::labs(title = title) +
    ggplot2::theme_void() +
    ggplot2::theme(plot.title = ggplot2::element_text(size = 14,
                                                      face = "bold"))
}


#' Shorten long labels so the figures stay readable
#'
#' @param x Character vector.
#' @param n Maximum number of characters.
#'
#' @return Character vector of truncated labels.
#'
#' @keywords internal
.dbn_trim <- function(x, n = 26) {
  x <- as.character(x)
  ifelse(nchar(x) > n, paste0(substr(x, 1, n - 1), "\u2026"), x)
}


# ------------------------------------------------------------------------------
# Dynamic Bayesian network figures
# ------------------------------------------------------------------------------

#' Plot a single-omics dynamic Bayesian network
#'
#' @description Draws the two time slices of the DBN as two vertical columns,
#'   the earlier slice (t0) on the left and the later slice (t1) on the right,
#'   so every arrow visualises a temporal transition. Arc width and opacity
#'   encode the bootstrap arc strength.
#'
#' @param dbn_result Result of \code{run_dbn_layer()}.
#' @param title Plot title.
#' @param label_top Maximum number of nodes to label, chosen by degree.
#'   Default: 30.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' export_plot(plot_dbn_layer(dbn, "Metabolome DBN"), fig_dir, "dbn_metabolome")
#' }
#'
#' @export
plot_dbn_layer <- function(dbn_result, title = NULL, label_top = 30) {
  if (is.null(dbn_result)) return(.dbn_empty_plot("No DBN result.", title))
  arcs <- dbn_result$arcs
  nd <- dbn_result$nodes_df
  if (is.null(arcs) || nrow(arcs) == 0) {
    return(.dbn_empty_plot("No time-lagged arc passed the strength filter.",
                           title))
  }

  # keep only nodes that participate in at least one arc
  active <- union(arcs$from, arcs$to)
  nd <- nd[nd$node %in% active, , drop = FALSE]
  if (nrow(nd) == 0) return(.dbn_empty_plot("No connected node.", title))

  pos <- do.call(rbind, lapply(split(nd, nd$time_slice), function(s) {
    s <- s[order(-s$degree), , drop = FALSE]
    s$x <- if (s$time_slice[1] == "t0") 0 else 1
    s$y <- if (nrow(s) == 1) 0.5 else seq(0, 1, length.out = nrow(s))
    s
  }))
  rownames(pos) <- NULL

  ed <- data.frame(
    x = pos$x[match(arcs$from, pos$node)],
    y = pos$y[match(arcs$from, pos$node)],
    xend = pos$x[match(arcs$to, pos$node)],
    yend = pos$y[match(arcs$to, pos$node)],
    strength = if ("strength" %in% colnames(arcs)) arcs$strength else 1,
    self_loop = if ("self_loop" %in% colnames(arcs)) arcs$self_loop else FALSE,
    stringsAsFactors = FALSE)
  ed <- ed[stats::complete.cases(ed[, c("x", "y", "xend", "yend")]), ,
           drop = FALSE]
  ed$strength[is.na(ed$strength)] <- 0.5

  lab <- pos[order(-pos$degree), , drop = FALSE]
  lab <- lab[seq_len(min(label_top, nrow(lab))), , drop = FALSE]
  lab$text <- .dbn_trim(lab$label)

  ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = ed,
      ggplot2::aes(x = x, y = y, xend = xend, yend = yend,
                   linewidth = strength, alpha = strength,
                   colour = self_loop),
      arrow = grid::arrow(length = grid::unit(0.16, "cm"), type = "closed")) +
    ggplot2::geom_point(data = pos,
                        ggplot2::aes(x = x, y = y, fill = time_slice),
                        shape = 21, size = 3.4, colour = "white",
                        stroke = 0.6) +
    ggrepel::geom_text_repel(data = lab,
                             ggplot2::aes(x = x, y = y, label = text),
                             size = 2.4, max.overlaps = 40,
                             segment.size = 0.2, segment.colour = "grey70") +
    ggplot2::scale_linewidth_continuous(range = c(0.25, 1.5),
                                        guide = "none") +
    ggplot2::scale_alpha_continuous(range = c(0.3, 0.9), name = "Arc strength") +
    ggplot2::scale_colour_manual(values = c("FALSE" = "grey45",
                                            "TRUE" = "#e34a33"),
                                 labels = c("FALSE" = "regulatory",
                                            "TRUE" = "auto-regulation"),
                                 name = "Arc type") +
    ggplot2::scale_fill_manual(values = c(t0 = "#4a90d9", t1 = "#fe9929"),
                               labels = c(t0 = "time t", t1 = "time t+1"),
                               name = "Time slice") +
    ggplot2::scale_x_continuous(breaks = c(0, 1),
                                labels = c("t (past)", "t+1 (future)"),
                                limits = c(-0.25, 1.25)) +
    ggplot2::labs(title = title, x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold"),
      panel.grid = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_text(face = "bold", size = 10))
}


#' Plot the merged pan-omics dynamic Bayesian network
#'
#' @description Places the nodes in one column per omics layer, ordered by the
#'   biological hierarchy, so that arcs crossing omics layers become visually
#'   obvious. Inter-omics arcs are highlighted while intra-omics arcs are
#'   drawn faintly, and node size encodes the number of connections.
#'
#' @param dbn_result Result of \code{run_dbn_multiomics()}.
#' @param title Plot title.
#' @param layer_order Column ordering of the omics layers. Default: the order
#'   stored in the result.
#' @param label_top Maximum number of nodes to label. Default: 30.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' export_plot(plot_dbn_multiomics(dbn), fig_dir, "dbn_pan_omics")
#' }
#'
#' @export
plot_dbn_multiomics <- function(dbn_result, title = NULL, layer_order = NULL,
                                label_top = 30) {
  if (is.null(dbn_result)) return(.dbn_empty_plot("No DBN result.", title))
  arcs <- dbn_result$arcs
  nd <- dbn_result$nodes_df
  if (is.null(arcs) || nrow(arcs) == 0) {
    return(.dbn_empty_plot("No time-lagged arc passed the strength filter.",
                           title))
  }
  if (!"omics" %in% colnames(nd)) {
    return(plot_dbn_layer(dbn_result, title = title, label_top = label_top))
  }

  active <- union(arcs$from, arcs$to)
  nd <- nd[nd$node %in% active, , drop = FALSE]
  if (nrow(nd) == 0) return(.dbn_empty_plot("No connected node.", title))

  if (is.null(layer_order)) {
    layer_order <- dbn_result$layer_order %||% unique(nd$omics)
  }
  layer_order <- c(intersect(layer_order, unique(nd$omics)),
                   setdiff(unique(nd$omics), layer_order))
  nd$omics <- factor(nd$omics, levels = layer_order)

  # one column per omics layer, t0 slightly left of t1 inside the column
  pos <- do.call(rbind, lapply(split(nd, nd$omics, drop = TRUE), function(s) {
    s <- s[order(s$time_slice, -s$degree), , drop = FALSE]
    s$x <- as.numeric(s$omics) + ifelse(s$time_slice == "t0", -0.16, 0.16)
    s$y <- if (nrow(s) == 1) 0.5 else seq(0, 1, length.out = nrow(s))
    s
  }))
  rownames(pos) <- NULL

  ed <- data.frame(
    x = pos$x[match(arcs$from, pos$node)],
    y = pos$y[match(arcs$from, pos$node)],
    xend = pos$x[match(arcs$to, pos$node)],
    yend = pos$y[match(arcs$to, pos$node)],
    strength = if ("strength" %in% colnames(arcs)) arcs$strength else 1,
    edge_type = if ("edge_type" %in% colnames(arcs)) arcs$edge_type else
      "intra_omics",
    stringsAsFactors = FALSE)
  ed <- ed[stats::complete.cases(ed[, c("x", "y", "xend", "yend")]), ,
           drop = FALSE]
  ed$strength[is.na(ed$strength)] <- 0.5
  ed$edge_type[is.na(ed$edge_type)] <- "intra_omics"

  lab <- pos[order(-pos$degree), , drop = FALSE]
  lab <- lab[seq_len(min(label_top, nrow(lab))), , drop = FALSE]
  lab$text <- .dbn_trim(lab$label, 24)

  cols <- .dbn_layer_colors(levels(nd$omics))

  ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = ed,
      ggplot2::aes(x = x, y = y, xend = xend, yend = yend,
                   colour = edge_type, alpha = edge_type,
                   linewidth = strength),
      arrow = grid::arrow(length = grid::unit(0.15, "cm"), type = "closed")) +
    ggplot2::geom_point(data = pos,
                        ggplot2::aes(x = x, y = y, fill = omics,
                                     size = degree, shape = time_slice),
                        colour = "white", stroke = 0.5) +
    ggrepel::geom_text_repel(data = lab,
                             ggplot2::aes(x = x, y = y, label = text),
                             size = 2.2, max.overlaps = 40,
                             segment.size = 0.2, segment.colour = "grey75") +
    ggplot2::scale_colour_manual(values = c(inter_omics = "#d7301f",
                                            intra_omics = "grey55"),
                                 name = "Arc type") +
    ggplot2::scale_alpha_manual(values = c(inter_omics = 0.85,
                                           intra_omics = 0.35),
                                guide = "none") +
    ggplot2::scale_linewidth_continuous(range = c(0.25, 1.4), guide = "none") +
    ggplot2::scale_size_continuous(range = c(2, 6), name = "Degree") +
    ggplot2::scale_shape_manual(values = c(t0 = 21, t1 = 24),
                                labels = c(t0 = "time t", t1 = "time t+1"),
                                name = "Time slice") +
    ggplot2::scale_fill_manual(values = cols, name = "Omics layer") +
    ggplot2::scale_x_continuous(breaks = seq_along(levels(nd$omics)),
                                labels = levels(nd$omics)) +
    ggplot2::guides(fill = ggplot2::guide_legend(
      override.aes = list(shape = 21, size = 4))) +
    ggplot2::labs(title = title, x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold"),
      panel.grid = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_text(face = "bold", size = 9,
                                          angle = 20, hjust = 1))
}


# ------------------------------------------------------------------------------
# Perturbation figures
# ------------------------------------------------------------------------------

#' Plot the regulatory importance ranking of perturbed nodes
#'
#' @param importance_df Output of \code{score_regulatory_importance()} or the
#'   stacked \code{importance} table of \code{run_perturbation_panel()}.
#' @param top_n Number of nodes to display per mode. Default: 20.
#' @param title Plot title.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' export_plot(plot_perturbation_ranking(imp), fig_dir, "perturb_ranking")
#' }
#'
#' @export
plot_perturbation_ranking <- function(importance_df, top_n = 20,
                                      title = NULL) {
  if (is.null(importance_df) || nrow(importance_df) == 0) {
    return(.dbn_empty_plot("No perturbation result to display.", title))
  }
  df <- importance_df
  if (!"label" %in% colnames(df)) df$label <- df$node
  if (!"mode" %in% colnames(df)) df$mode <- "perturbation"

  df <- do.call(rbind, lapply(split(df, df$mode), function(s) {
    s <- s[order(-s$impact_score), , drop = FALSE]
    s[seq_len(min(top_n, nrow(s))), , drop = FALSE]
  }))
  df$text <- .dbn_trim(df$label, 30)
  # keep bars sorted within each facet
  df$key <- paste(df$mode, df$text, sep = "|")
  df <- df[order(df$mode, df$impact_score), , drop = FALSE]
  df$key <- factor(df$key, levels = unique(df$key))

  p <- ggplot2::ggplot(df, ggplot2::aes(x = key, y = impact_score))
  if ("omics" %in% colnames(df)) {
    p <- p + ggplot2::geom_col(ggplot2::aes(fill = omics), width = 0.72) +
      ggplot2::scale_fill_manual(values = .dbn_layer_colors(df$omics),
                                 name = "Omics layer")
  } else {
    p <- p + ggplot2::geom_col(fill = "#4a90d9", width = 0.72)
  }

  p +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", impact_score)),
                       hjust = -0.15, size = 2.6) +
    ggplot2::scale_x_discrete(labels = function(x) sub("^[^|]*\\|", "", x)) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.18))) +
    ggplot2::coord_flip() +
    ggplot2::facet_wrap(~ mode, scales = "free_y") +
    ggplot2::labs(title = title, x = NULL, y = "Regulatory impact score") +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold"),
      panel.grid.major.y = ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(fill = "grey92",
                                               colour = "grey70"),
      strip.text = ggplot2::element_text(face = "bold"))
}


#' Heatmap of perturbation effects on downstream nodes
#'
#' @description Shows how strongly each perturbed node shifts the state
#'   distribution of the nodes downstream of it. The fill encodes the signed
#'   probability shift when available, otherwise the total variation distance.
#'
#' @param pair_details The \code{pair_details} table of a perturbation result.
#' @param mode Restrict to a single perturbation mode. Default: the first mode
#'   with usable inference values.
#' @param top_n Maximum number of perturbed nodes to show. Default: 15.
#' @param title Plot title.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' export_plot(plot_perturbation_heatmap(pp$pair_details), fig_dir, "heat")
#' }
#'
#' @export
plot_perturbation_heatmap <- function(pair_details, mode = NULL, top_n = 15,
                                      title = NULL) {
  if (is.null(pair_details) || nrow(pair_details) == 0) {
    return(.dbn_empty_plot("No downstream pair to display.", title))
  }
  df <- pair_details

  if (is.null(mode) && "mode" %in% colnames(df)) {
    with_val <- df[!is.na(df$prob_shift) | !is.na(df$tvd), , drop = FALSE]
    mode <- if (nrow(with_val) > 0) with_val$mode[1] else df$mode[1]
  }
  if (!is.null(mode) && "mode" %in% colnames(df)) {
    df <- df[df$mode == mode, , drop = FALSE]
  }
  if (nrow(df) == 0) {
    return(.dbn_empty_plot("No downstream pair for this mode.", title))
  }

  use_shift <- "prob_shift" %in% colnames(df) && any(!is.na(df$prob_shift))
  df$value <- if (use_shift) df$prob_shift else df$tvd
  if (all(is.na(df$value))) {
    df$value <- 1
    legend_name <- "Downstream link"
  } else {
    legend_name <- if (use_shift) "P(high) shift" else "TVD"
  }

  if (!"perturbed_label" %in% colnames(df)) {
    df$perturbed_label <- df$perturbed_node
  }
  if (!"downstream_label" %in% colnames(df)) {
    df$downstream_label <- df$downstream_node
  }

  keep <- names(sort(table(df$perturbed_label), decreasing = TRUE))
  keep <- keep[seq_len(min(top_n, length(keep)))]
  df <- df[df$perturbed_label %in% keep, , drop = FALSE]

  df$xr <- .dbn_trim(df$perturbed_label, 28)
  df$yr <- .dbn_trim(df$downstream_label, 28)

  p <- ggplot2::ggplot(df, ggplot2::aes(x = xr, y = yr, fill = value)) +
    ggplot2::geom_tile(colour = "white", linewidth = 0.4)

  if (use_shift) {
    lim <- max(abs(df$value), na.rm = TRUE)
    if (!is.finite(lim) || lim == 0) lim <- 1
    p <- p + ggplot2::scale_fill_gradient2(low = "#2c7bb6", mid = "white",
                                           high = "#d7191c", midpoint = 0,
                                           limits = c(-lim, lim),
                                           name = legend_name)
  } else {
    p <- p + ggplot2::scale_fill_viridis_c(option = "C", name = legend_name)
  }

  sub <- if (!is.null(mode)) sprintf("Perturbation mode: %s", mode) else NULL

  p +
    ggplot2::labs(title = title, subtitle = sub,
                  x = "Perturbed node", y = "Downstream node") +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold"),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 7.5),
      axis.text.y = ggplot2::element_text(size = 7.5),
      panel.grid = ggplot2::element_blank())
}


#' Plot the downstream impact sub-network of one perturbed node
#'
#' @description Extracts the node together with everything reachable from it
#'   and draws that sub-network, with the perturbed node highlighted and the
#'   remaining nodes placed in concentric rings by path distance.
#'
#' @param dbn_result A DBN result object.
#' @param node Name of the perturbed node.
#' @param title Plot title.
#' @param max_distance Maximum path length to include. Default: Inf.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' export_plot(plot_perturbation_subnetwork(dbn, top_node), fig_dir, "sub")
#' }
#'
#' @export
plot_perturbation_subnetwork <- function(dbn_result, node, title = NULL,
                                         max_distance = Inf) {
  if (is.null(dbn_result) || is.null(node) || length(node) == 0) {
    return(.dbn_empty_plot("No node supplied.", title))
  }
  desc <- get_downstream_nodes(dbn_result, node, max_distance = max_distance)
  if (nrow(desc) == 0) {
    return(.dbn_empty_plot(sprintf("Node '%s' has no downstream target.", node),
                           title))
  }

  keep <- c(node, desc$node)
  arcs <- dbn_result$arcs
  arcs <- arcs[arcs$from %in% keep & arcs$to %in% keep, , drop = FALSE]
  nd <- dbn_result$nodes_df
  nd <- nd[nd$node %in% keep, , drop = FALSE]

  nd$distance <- 0
  m <- match(nd$node, desc$node)
  nd$distance[!is.na(m)] <- desc$distance[m[!is.na(m)]]

  # concentric rings: the perturbed node in the middle, then one ring per hop
  pos <- do.call(rbind, lapply(split(nd, nd$distance), function(s) {
    d <- s$distance[1]
    if (d == 0) {
      s$x <- 0; s$y <- 0
    } else {
      ang <- seq(0, 2 * pi, length.out = nrow(s) + 1)[seq_len(nrow(s))]
      s$x <- d * cos(ang)
      s$y <- d * sin(ang)
    }
    s
  }))
  rownames(pos) <- NULL
  pos$role <- ifelse(pos$node == node, "perturbed", "downstream")

  ed <- data.frame(
    x = pos$x[match(arcs$from, pos$node)],
    y = pos$y[match(arcs$from, pos$node)],
    xend = pos$x[match(arcs$to, pos$node)],
    yend = pos$y[match(arcs$to, pos$node)],
    stringsAsFactors = FALSE)
  ed <- ed[stats::complete.cases(ed), , drop = FALSE]

  pos$text <- .dbn_trim(pos$label, 24)

  p <- ggplot2::ggplot()
  if (nrow(ed) > 0) {
    p <- p + ggplot2::geom_segment(
      data = ed,
      ggplot2::aes(x = x, y = y, xend = xend, yend = yend),
      arrow = grid::arrow(length = grid::unit(0.18, "cm"), type = "closed"),
      colour = "grey50", alpha = 0.7, linewidth = 0.45)
  }

  aes_point <- if ("omics" %in% colnames(pos)) {
    ggplot2::aes(x = x, y = y, fill = omics, size = role)
  } else {
    ggplot2::aes(x = x, y = y, size = role)
  }

  p <- p + ggplot2::geom_point(data = pos, aes_point, shape = 21,
                               colour = "grey20", stroke = 0.6)
  if ("omics" %in% colnames(pos)) {
    p <- p + ggplot2::scale_fill_manual(values = .dbn_layer_colors(pos$omics),
                                        name = "Omics layer")
  }

  p +
    ggrepel::geom_text_repel(data = pos,
                             ggplot2::aes(x = x, y = y, label = text),
                             size = 2.6, max.overlaps = 40,
                             segment.size = 0.2, segment.colour = "grey70") +
    ggplot2::scale_size_manual(values = c(perturbed = 7, downstream = 3.6),
                               name = NULL) +
    ggplot2::coord_equal() +
    ggplot2::labs(title = title, x = NULL, y = NULL) +
    ggplot2::theme_void(base_size = 11) +
    ggplot2::theme(plot.title = ggplot2::element_text(size = 13,
                                                      face = "bold"))
}


# ------------------------------------------------------------------------------
# PLS path model figure
# ------------------------------------------------------------------------------

#' Plot a hierarchical multi-omics PLS path model
#'
#' @description Arranges the latent variables in one column per omics layer,
#'   following the biological hierarchy, and draws the estimated path
#'   coefficients between them. Edge width encodes the magnitude of the
#'   coefficient, colour its sign, and dashed lines mark non-significant paths.
#'
#' @param plspm_result Output of \code{run_multiomics_plspm()}.
#' @param layer_order Column ordering of the omics layers.
#' @param p_threshold Significance threshold for the line type. Default: 0.05.
#' @param min_abs_coeff Hide paths whose absolute coefficient is below this
#'   value, which keeps dense models readable. Default: 0.
#' @param significant_only Draw only significant paths. Default: FALSE.
#' @param title Plot title.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' export_plot(plot_plspm_hierarchy(res, layer_order), fig_dir, "plspm_paths")
#' }
#'
#' @export
plot_plspm_hierarchy <- function(plspm_result, layer_order = NULL,
                                 p_threshold = 0.05, min_abs_coeff = 0,
                                 significant_only = FALSE, title = NULL) {
  if (is.null(plspm_result)) {
    return(.dbn_empty_plot("No PLS-PM result.", title))
  }
  ip <- plspm_result$inner_paths
  defs <- plspm_result$definitions
  if (is.null(ip) || nrow(ip) == 0 || is.null(defs)) {
    return(.dbn_empty_plot("No path coefficient to display.", title))
  }

  if (isTRUE(significant_only)) {
    ip <- ip[!is.na(ip$p_value) & ip$p_value < p_threshold, , drop = FALSE]
  }
  if (min_abs_coeff > 0) {
    ip <- ip[abs(ip$path_coeff) >= min_abs_coeff, , drop = FALSE]
  }
  if (nrow(ip) == 0) {
    return(.dbn_empty_plot("No path passed the filters.", title))
  }

  if (is.null(layer_order)) layer_order <- unique(defs$layer)
  layer_order <- c(intersect(layer_order, unique(defs$layer)),
                   setdiff(unique(defs$layer), layer_order))
  defs$layer <- factor(defs$layer, levels = layer_order)

  active <- union(ip$from, ip$to)
  pos <- defs[defs$latent %in% active, , drop = FALSE]
  if (nrow(pos) == 0) return(.dbn_empty_plot("No connected latent variable.",
                                             title))

  pos <- do.call(rbind, lapply(split(pos, pos$layer, drop = TRUE), function(s) {
    s$x <- as.numeric(s$layer)
    s$y <- if (nrow(s) == 1) 0.5 else seq(0, 1, length.out = nrow(s))
    s
  }))
  rownames(pos) <- NULL

  ed <- data.frame(
    x = pos$x[match(ip$from, pos$latent)],
    y = pos$y[match(ip$from, pos$latent)],
    xend = pos$x[match(ip$to, pos$latent)],
    yend = pos$y[match(ip$to, pos$latent)],
    coeff = ip$path_coeff,
    sign = ifelse(ip$path_coeff >= 0, "positive", "negative"),
    sig = ifelse(!is.na(ip$p_value) & ip$p_value < p_threshold,
                 "significant", "n.s."),
    stringsAsFactors = FALSE)
  ed <- ed[stats::complete.cases(ed[, c("x", "y", "xend", "yend")]), ,
           drop = FALSE]
  ed$abs_coeff <- abs(ed$coeff)

  pos$text <- .dbn_trim(pos$latent, 24)
  cols <- .dbn_layer_colors(levels(defs$layer))

  # R2 of each endogenous latent variable drives the node size when available
  if (!is.null(plspm_result$fit_summary) &&
      "R2" %in% colnames(plspm_result$fit_summary)) {
    r2 <- plspm_result$fit_summary$R2[match(pos$latent,
                                            plspm_result$fit_summary$latent)]
    pos$r2 <- ifelse(is.na(r2), 0, r2)
  } else {
    pos$r2 <- 0
  }

  ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = ed,
      ggplot2::aes(x = x, y = y, xend = xend, yend = yend,
                   colour = sign, linewidth = abs_coeff, linetype = sig),
      alpha = 0.75,
      arrow = grid::arrow(length = grid::unit(0.15, "cm"), type = "closed")) +
    ggplot2::geom_point(data = pos,
                        ggplot2::aes(x = x, y = y, fill = layer, size = r2),
                        shape = 21, colour = "white", stroke = 0.7) +
    ggrepel::geom_text_repel(data = pos,
                             ggplot2::aes(x = x, y = y, label = text),
                             size = 2.5, max.overlaps = 40,
                             segment.size = 0.2, segment.colour = "grey70") +
    ggplot2::scale_colour_manual(values = c(positive = "#d7191c",
                                            negative = "#2c7bb6"),
                                 name = "Path sign") +
    ggplot2::scale_linetype_manual(values = c(significant = "solid",
                                              "n.s." = "dashed"),
                                   name = sprintf("p < %.2f", p_threshold)) +
    ggplot2::scale_linewidth_continuous(range = c(0.2, 1.8),
                                        name = "|path coeff|") +
    ggplot2::scale_size_continuous(range = c(3, 8), name = expression(R^2)) +
    ggplot2::scale_fill_manual(values = cols, name = "Omics layer") +
    ggplot2::scale_x_continuous(breaks = seq_along(levels(defs$layer)),
                                labels = levels(defs$layer),
                                limits = c(0.6, length(levels(defs$layer)) + 0.4)) +
    ggplot2::guides(fill = ggplot2::guide_legend(
      override.aes = list(size = 4))) +
    ggplot2::labs(title = title, x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold"),
      panel.grid = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_text(face = "bold", size = 9,
                                          angle = 20, hjust = 1))
}


#' Bar chart of the explained variance of every latent variable
#'
#' @param plspm_result Output of \code{run_multiomics_plspm()}.
#' @param title Plot title.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' export_plot(plot_plspm_r2(res), fig_dir, "plspm_r2")
#' }
#'
#' @export
plot_plspm_r2 <- function(plspm_result, title = NULL) {
  fs <- plspm_result$fit_summary
  if (is.null(fs) || nrow(fs) == 0 || !"R2" %in% colnames(fs)) {
    return(.dbn_empty_plot("No R2 information available.", title))
  }
  df <- fs[fs$R2 > 0, , drop = FALSE]
  if (nrow(df) == 0) {
    return(.dbn_empty_plot("All latent variables are exogenous (R2 = 0).",
                           title))
  }
  df$text <- .dbn_trim(df$latent, 30)
  df <- df[order(df$R2), , drop = FALSE]
  df$text <- factor(df$text, levels = unique(df$text))

  ggplot2::ggplot(df, ggplot2::aes(x = text, y = R2, fill = layer)) +
    ggplot2::geom_col(width = 0.72) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.3f", R2)),
                       hjust = -0.15, size = 2.7) +
    ggplot2::scale_fill_manual(values = .dbn_layer_colors(df$layer),
                               name = "Omics layer") +
    ggplot2::scale_y_continuous(limits = c(0, 1),
                                expand = ggplot2::expansion(mult = c(0, 0.15))) +
    ggplot2::coord_flip() +
    ggplot2::labs(title = title, x = NULL,
                  y = expression(paste("Explained variance ", R^2))) +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold"),
      panel.grid.major.y = ggplot2::element_blank())
}
