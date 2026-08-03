# ==============================================================================
# OmicsFlow: Cross-Omics Association Network
# ==============================================================================
# Assembles significant cross-layer correlations into a single graph so that
# hub taxa, hub metabolites and hub aroma compounds can be identified.
# ==============================================================================

#' Build a cross-omics association network
#'
#' @description Merges the significant pair tables produced by
#'   \code{run_cross_correlation()} into one \pkg{igraph} object. Nodes are
#'   annotated with their omics layer and edges with the sign and strength of
#'   the correlation, giving a network view of microbe to metabolite to aroma
#'   relationships.
#'
#' @param pairs_list Named list of pair data.frames. Each element must contain
#'   the columns feature_x, feature_y, r and padj, and the element name is
#'   expected to follow the "layerX_vs_layerY" convention used by
#'   \code{run_all_pairwise_correlation()}.
#' @param r_threshold Minimum absolute correlation retained. Default: 0.7.
#' @param padj_threshold Maximum adjusted p-value retained. Default: 0.05.
#' @param max_edges Upper bound on the number of edges; when exceeded the
#'   strongest associations are kept. Default: 2000.
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A list (NULL when no edge survives) with:
#'   \itemize{
#'     \item \code{graph}: The igraph object.
#'     \item \code{edges}: data.frame of retained edges.
#'     \item \code{nodes}: data.frame of nodes with omics layer and degree.
#'   }
#'
#' @examples
#' \dontrun{
#' net <- build_cross_omics_network(list(microbiome_vs_metabolome = res$pairs))
#' }
#'
#' @export
build_cross_omics_network <- function(pairs_list,
                                      r_threshold = 0.7,
                                      padj_threshold = 0.05,
                                      max_edges = 2000,
                                      verbose = TRUE) {
  if (!requireNamespace("igraph", quietly = TRUE)) {
    stop("Package 'igraph' is required. Install it with install.packages('igraph').")
  }
  if (is.null(pairs_list) || length(pairs_list) == 0) {
    stop("pairs_list is empty.")
  }
  if (is.data.frame(pairs_list)) {
    pairs_list <- list(pair = pairs_list)
  }

  collected <- list()
  for (nm in names(pairs_list)) {
    df <- pairs_list[[nm]]
    if (is.null(df) || !is.data.frame(df) || nrow(df) == 0) next
    required <- c("feature_x", "feature_y", "r")
    if (!all(required %in% colnames(df))) {
      warning(sprintf("Element '%s' lacks the required columns; skipped.", nm))
      next
    }
    keep <- abs(df$r) >= r_threshold
    if ("padj" %in% colnames(df)) {
      keep <- keep & !is.na(df$padj) & df$padj <= padj_threshold
    }
    df <- df[keep, , drop = FALSE]
    if (nrow(df) == 0) next

    # Recover the layer names from the "a_vs_b" element name.
    parts <- strsplit(nm, "_vs_", fixed = TRUE)[[1]]
    layer_x <- if (length(parts) == 2) parts[1] else "layer_x"
    layer_y <- if (length(parts) == 2) parts[2] else "layer_y"

    collected[[nm]] <- data.frame(
      from = as.character(df$feature_x),
      to = as.character(df$feature_y),
      r = df$r,
      padj = if ("padj" %in% colnames(df)) df$padj else NA_real_,
      from_layer = layer_x,
      to_layer = layer_y,
      comparison = nm,
      stringsAsFactors = FALSE
    )
  }

  if (length(collected) == 0) {
    if (verbose) {
      cat(sprintf("  No edge passes |r| >= %.2f and padj <= %.3f.\n",
                  r_threshold, padj_threshold))
    }
    return(NULL)
  }

  edges <- do.call(rbind, collected)
  rownames(edges) <- NULL

  if (nrow(edges) > max_edges) {
    if (verbose) {
      cat(sprintf("  %d edges exceed max_edges=%d; keeping the strongest.\n",
                  nrow(edges), max_edges))
    }
    edges <- edges[order(-abs(edges$r)), , drop = FALSE][seq_len(max_edges), , drop = FALSE]
  }

  edges$direction <- ifelse(edges$r >= 0, "positive", "negative")
  edges$weight <- abs(edges$r)

  # Node table: a feature keeps the layer it first appeared in.
  node_names <- unique(c(edges$from, edges$to))
  node_layer <- c(
    stats::setNames(edges$from_layer, edges$from),
    stats::setNames(edges$to_layer, edges$to)
  )
  node_layer <- node_layer[!duplicated(names(node_layer))]
  nodes <- data.frame(
    name = node_names,
    omics = unname(node_layer[node_names]),
    stringsAsFactors = FALSE
  )

  graph <- igraph::graph_from_data_frame(
    d = edges[, c("from", "to", "r", "padj", "weight", "direction", "comparison")],
    directed = FALSE,
    vertices = nodes
  )
  nodes$degree <- as.integer(igraph::degree(graph)[nodes$name])

  if (verbose) {
    cat(sprintf("  Network: %d nodes, %d edges (%d positive, %d negative).\n",
                nrow(nodes), nrow(edges),
                sum(edges$direction == "positive"),
                sum(edges$direction == "negative")))
  }

  list(graph = graph, edges = edges, nodes = nodes)
}


#' Extract hub nodes from a cross-omics network
#'
#' @description Ranks nodes by degree and betweenness centrality to nominate the
#'   taxa or compounds that sit at the centre of the association network and are
#'   therefore candidate drivers of flavour formation.
#'
#' @param network Result of \code{build_cross_omics_network()}, or a bare igraph
#'   object.
#' @param top_n Number of hubs returned. Default: 20.
#' @param by Ranking criterion, "degree" or "betweenness". Default: "degree".
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A data.frame with name, omics, degree, betweenness, closeness and the
#'   mean absolute correlation of the incident edges.
#'
#' @examples
#' \dontrun{
#' hubs <- get_network_hubs(net, top_n = 20)
#' }
#'
#' @export
get_network_hubs <- function(network, top_n = 20, by = "degree",
                             verbose = TRUE) {
  if (!requireNamespace("igraph", quietly = TRUE)) {
    stop("Package 'igraph' is required. Install it with install.packages('igraph').")
  }
  by <- match.arg(by, c("degree", "betweenness"))

  graph <- if (inherits(network, "igraph")) network else network$graph
  if (is.null(graph) || igraph::vcount(graph) == 0) {
    stop("The network contains no node.")
  }

  deg <- igraph::degree(graph)
  btw <- igraph::betweenness(graph, normalized = TRUE)
  clo <- suppressWarnings(igraph::closeness(graph, normalized = TRUE))

  vnames <- igraph::V(graph)$name
  omics <- if (!is.null(igraph::V(graph)$omics)) {
    igraph::V(graph)$omics
  } else {
    rep(NA_character_, length(vnames))
  }

  # Mean absolute correlation over the edges incident to each node.
  ew <- igraph::E(graph)$weight
  mean_r <- vapply(seq_along(vnames), function(i) {
    inc <- igraph::incident(graph, v = i, mode = "all")
    if (length(inc) == 0) return(NA_real_)
    mean(ew[as.integer(inc)], na.rm = TRUE)
  }, numeric(1))

  hubs <- data.frame(
    name = vnames,
    omics = omics,
    degree = as.integer(deg),
    betweenness = as.numeric(btw),
    closeness = as.numeric(clo),
    mean_abs_r = mean_r,
    stringsAsFactors = FALSE
  )

  ord <- if (by == "degree") {
    order(-hubs$degree, -hubs$betweenness)
  } else {
    order(-hubs$betweenness, -hubs$degree)
  }
  hubs <- hubs[ord, , drop = FALSE]
  rownames(hubs) <- NULL
  if (top_n < nrow(hubs)) hubs <- hubs[seq_len(top_n), , drop = FALSE]

  if (verbose) {
    cat(sprintf("  Top hub: %s (%s), degree = %d.\n",
                hubs$name[1], hubs$omics[1], hubs$degree[1]))
  }
  hubs
}
