# =============================================================================
# OmicsFlow: Association Network Visualisation
# -----------------------------------------------------------------------------
# 基于 run_cross_omics_association() / run_intra_omics_association() 返回的
# 9 列边表，构建显著关联网络并可视化。
#
# 绘图风格沿用 plot_multiomics.R（igraph::layout_with_fr + 手工 ggplot
# geom_segment / geom_point），不引入 ggraph，避免新增仓库依赖。
#   - 节点按所属组学层着色（make_group_colors）
#   - 节点大小随连接度（degree）变化
#   - 边色区分 positive / negative / nonlinear
#   - 边粗细反映关联 score
#   - ggrepel 标注 degree 最高的枢纽节点
# =============================================================================

# -----------------------------------------------------------------------------
# 由边表构建显著关联子图（igraph 对象）
# -----------------------------------------------------------------------------
#' Build an igraph network from a significant-association edge table
#'
#' @param edges A data.frame from \code{run_*_association} with columns
#'   source, target, score, association (and spearman-rho, MIC).
#' @param p_threshold Numeric, keep edges whose adjusted merged p
#'   (\code{pvalue}) is below this cutoff.
#' @param max_edges Integer, cap on number of edges kept (top by |score|).
#' @param node_omics Optional named character vector mapping node name -> omics
#'   layer. If NULL, the omics is inferred from node names that contain "__"
#'   (cross-omics) or taken from \code{default_omics}.
#' @param default_omics Character, omics label applied when inference fails.
#' @param verbose Logical.
#'
#' @return An \code{igraph} graph, or \code{NULL} if no significant edge exists.
#'
#' @examples
#' \dontrun{
#'   g <- build_association_network(res$edges, p_threshold = 0.05)
#' }
#'
#' @export
build_association_network <- function(edges, p_threshold = 0.05, max_edges = 5000,
                                      node_omics = NULL, default_omics = "feature",
                                      verbose = TRUE) {
  if (is.null(edges) || nrow(edges) == 0) {
    if (isTRUE(verbose)) cat("[assoc-plot] empty edge table -> no network.\n")
    return(NULL)
  }
  sig <- edges[edges$pvalue < p_threshold & edges$association != "not_significant", ,
               drop = FALSE]
  if (nrow(sig) == 0) {
    if (isTRUE(verbose)) cat("[assoc-plot] no significant edges -> no network.\n")
    return(NULL)
  }
  if (nrow(sig) > max_edges) {
    sig <- sig[order(abs(sig$score), decreasing = TRUE)[seq_len(max_edges)], ,
                drop = FALSE]
    if (isTRUE(verbose)) {
      cat(sprintf("[assoc-plot] capped to top %d edges by |score|.\n", max_edges))
    }
  }

  g <- igraph::graph_from_data_frame(sig[, c("source", "target", "association",
                                             "score", "spearman-rho", "MIC")],
                                     directed = FALSE)

  # 节点 omics 标注
  vnames <- igraph::V(g)$name
  if (!is.null(node_omics)) {
    om <- node_omics[match(vnames, names(node_omics))]
  } else {
    om <- character(length(vnames))
    for (i in seq_along(vnames)) {
      nm <- vnames[i]
      if (grepl("__", nm)) {
        om[i] <- sub("__.*", "", nm)
      } else {
        om[i] <- default_omics
      }
    }
  }
  om[is.na(om) | om == ""] <- default_omics
  igraph::V(g)$omics <- om
  igraph::V(g)$degree <- igraph::degree(g)
  if (isTRUE(verbose)) {
    cat(sprintf("[assoc-plot] network built: %d nodes, %d edges.\n",
                igraph::vcount(g), igraph::ecount(g)))
  }
  g
}


# -----------------------------------------------------------------------------
# 显著关联网络图（ggplot + layout_with_fr）
# -----------------------------------------------------------------------------
#' Plot a significant-association network
#'
#' @param g An \code{igraph} graph from \code{build_association_network}, or
#'   an edge table (data.frame) which will be converted on the fly.
#' @param p_threshold Numeric, used only when \code{g} is an edge table.
#' @param label_top_n Integer, number of top-degree hubs to label.
#' @param title Character, plot title.
#'
#' @return A ggplot object, or \code{NULL} if the graph is empty.
#'
#' @examples
#' \dontrun{
#'   p <- plot_association_network(g, label_top_n = 12, title = "Microbiome x Volatilome")
#' }
#'
#' @export
plot_association_network <- function(g, p_threshold = 0.05, label_top_n = 12,
                                     title = "Association Network") {
  # 若为边表则先转图
  if (is.data.frame(g)) {
    g <- build_association_network(g, p_threshold = p_threshold)
  }
  if (is.null(g) || igraph::vcount(g) == 0) {
    cat("[assoc-plot] (skip plot: empty network)\n")
    return(NULL)
  }

  # 布局
  set.seed(42)
  lay <- igraph::layout_with_fr(g)
  colnames(lay) <- c("x", "y")
  V <- data.frame(name = igraph::V(g)$name, x = lay[, 1], y = lay[, 2],
                  omics = igraph::V(g)$omics, degree = igraph::V(g)$degree,
                  stringsAsFactors = FALSE)
  E <- data.frame(igraph::as_data_frame(g, what = "edges"), stringsAsFactors = FALSE)
  E <- merge(E, data.frame(name = V$name, x = V$x, y = V$y,
                           stringsAsFactors = FALSE),
             by.x = "from", by.y = "name", sort = FALSE)
  colnames(E)[match(c("x", "y"), colnames(E))] <- c("x_from", "y_from")
  E <- merge(E, data.frame(name = V$name, x = V$x, y = V$y,
                           stringsAsFactors = FALSE),
             by.x = "to", by.y = "name", sort = FALSE)
  colnames(E)[match(c("x", "y"), colnames(E))] <- c("x_to", "y_to")

  edge_color <- function(a) {
    ifelse(a == "positive",  "#d73027",
           ifelse(a == "negative", "#4575b4", "#1a9850"))
  }
  E$ecol <- edge_color(E$association)
  E$ewidth <- pmax(0.3, abs(E$score) * 2)

  node_colors <- make_group_colors(V$omics)
  V$fill <- node_colors[match(V$omics, names(node_colors))]
  V$size <- 3 + sqrt(V$degree) * 2

  # 枢纽标签
  hub <- V[order(V$degree, decreasing = TRUE), ]
  hub <- head(hub, label_top_n)

  p <- ggplot2::ggplot() +
    ggplot2::geom_segment(data = E,
                          ggplot2::aes(x = x_from, y = y_from,
                                       xend = x_to, yend = y_to),
                          color = E$ecol, linewidth = E$ewidth,
                          alpha = 0.45) +
    ggplot2::geom_point(data = V, ggplot2::aes(x = x, y = y,
                                               color = omics, size = size),
                        fill = V$fill, shape = 21, stroke = 0.4) +
    ggplot2::scale_color_manual(values = node_colors) +
    ggplot2::scale_size_identity() +
    ggrepel::geom_text_repel(data = hub,
                             ggplot2::aes(x = x, y = y, label = name),
                             size = 3, max.overlaps = 30,
                             box.padding = 0.3, segment.color = "grey40") +
    ggplot2::theme_void() +
    ggplot2::theme(legend.position = "right",
                   plot.title = ggplot2::element_text(hjust = 0.5, size = 13)) +
    ggplot2::guides(size = "none", fill = "none") +
    ggplot2::labs(title = title, color = "Omics layer")
  p
}


# -----------------------------------------------------------------------------
# 各组合显著边数量 / 关联类型构成（堆叠柱状图）
# -----------------------------------------------------------------------------
#' Summary bar plot of association counts per combo
#'
#' @param results A named list of \code{run_*_association} results (each with
#'   \code{edges} and \code{params}).
#' @param title Character.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#'   p <- plot_association_summary(list(microbiome_x_volatilome = res))
#' }
#'
#' @export
plot_association_summary <- function(results, title = "Association Summary") {
  rows <- list()
  for (nm in names(results)) {
    e <- results[[nm]]$edges
    rows[[nm]] <- data.frame(
      combo = nm,
      positive  = sum(e$association == "positive"),
      negative  = sum(e$association == "negative"),
      nonlinear = sum(e$association == "nonlinear"),
      stringsAsFactors = FALSE)
  }
  df <- do.call(rbind, rows)
  m <- reshape2::melt(df, id.vars = "combo",
                      variable.name = "type", value.name = "count")
  ggplot2::ggplot(m, ggplot2::aes(x = combo, y = count, fill = type)) +
    ggplot2::geom_col(position = "stack") +
    ggplot2::scale_fill_brewer(palette = "Set2") +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
                   plot.title = ggplot2::element_text(hjust = 0.5)) +
    ggplot2::labs(title = title, x = "Omics combo", y = "Significant edges",
                  fill = "Association")
}


# -----------------------------------------------------------------------------
# 枢纽节点表（按 degree 排序）
# -----------------------------------------------------------------------------
#' Extract hub nodes by degree
#'
#' @param g An \code{igraph} graph from \code{build_association_network}.
#' @param top_n Integer, number of top hubs to return.
#'
#' @return A data.frame with name, omics, degree (sorted descending), or NULL.
#'
#' @examples
#' \dontrun{
#'   hubs <- get_association_hubs(g, top_n = 20)
#' }
#'
#' @export
get_association_hubs <- function(g, top_n = 20) {
  if (is.null(g) || igraph::vcount(g) == 0) return(NULL)
  df <- data.frame(
    name = igraph::V(g)$name,
    omics = igraph::V(g)$omics,
    degree = igraph::V(g)$degree,
    stringsAsFactors = FALSE)
  df <- df[order(df$degree, decreasing = TRUE), , drop = FALSE]
  head(df, top_n)
}
