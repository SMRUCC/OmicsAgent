# ==============================================================================
# OmicsFlow: Bayesian Network with bnlearn
# ==============================================================================
# Time-series regulatory network construction
# ==============================================================================

#' Build Bayesian network with bnlearn
#'
#' @description Constructs a Bayesian network model from time-series or
#'   multi-condition omics data to infer regulatory relationships between features.
#'
#' @param expr_matrix A numeric matrix (features x samples). For time series,
#'   columns should be ordered by time.
#' @param time_points Optional numeric vector of time points. If NULL, uses
#'   sample order. Default: NULL.
#' @param feature_info Optional feature annotation for node labels.
#' @param name_col Column in feature_info for node names. Default: "name".
#' @param algorithm Learning algorithm: "hc" (hill-climbing), "tabu", "gs"
#'   (grow-shrink). Default: "hc".
#' @param score Score function for structure learning. Default: "bic".
#' @param max_nodes Maximum nodes to include (for performance). Default: 50.
#' @param seed Random seed. Default: 42.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{network}: bnlearn network object.
#'     \item \code{arcs}: Data.frame of directed edges.
#'     \item \code{nodes}: Character vector of node names.
#'     \item \code{adjacency}: Adjacency matrix.
#'   }
#'
#' @examples
#' \dontrun{
#' bn <- run_bnlearn(expr_matrix, algorithm = "hc")
#' print(head(bn$arcs))
#' }
#'
#' @export
run_bnlearn <- function(expr_matrix, time_points = NULL, feature_info = NULL,
                       name_col = "name", algorithm = "hc", score = "bic",
                       max_nodes = 50, seed = 42) {
  if (!requireNamespace("bnlearn", quietly = TRUE)) {
    stop("Package 'bnlearn' is required. Please install it.")
  }

  set.seed(seed)

  # Select top variable features if too many
  mat <- as.matrix(expr_matrix)
  if (nrow(mat) > max_nodes) {
    row_vars <- apply(mat, 1, stats::var, na.rm = TRUE)
    top_idx <- order(row_vars, decreasing = TRUE)[1:max_nodes]
    mat <- mat[top_idx, , drop = FALSE]
  }

  # Replace feature IDs with names
  if (!is.null(feature_info) && name_col %in% colnames(feature_info)) {
    feature_names <- feature_info[match(rownames(mat), rownames(feature_info)), name_col]
    feature_names[is.na(feature_names)] <- rownames(mat)
    # Make unique
    feature_names <- make.unique(feature_names)
    rownames(mat) <- feature_names
  }

  # Discretize if needed (bnlearn requires discrete data for some algorithms)
  # Use quantile discretization
  mat_disc <- t(apply(mat, 1, function(x) {
    if (stats::sd(x, na.rm = TRUE) == 0) return(rep(1, length(x)))
    cuts <- stats::quantile(x, probs = c(0.33, 0.67), na.rm = TRUE)
    cut(x, breaks = c(-Inf, cuts[1], cuts[2], Inf), labels = FALSE)
  }))

  # Create data.frame for bnlearn
  bn_data <- as.data.frame(t(mat_disc))
  for (col in colnames(bn_data)) {
    bn_data[[col]] <- as.factor(bn_data[[col]])
  }

  # Learn structure
  if (algorithm == "hc") {
    bn <- bnlearn::hc(bn_data, score = score)
  } else if (algorithm == "tabu") {
    bn <- bnlearn::tabu(bn_data, score = score)
  } else if (algorithm == "gs") {
    bn <- bnlearn::gs(bn_data)
  } else {
    bn <- bnlearn::hc(bn_data, score = score)
  }

  # Extract arcs
  arcs_df <- bnlearn::arcs(bn)

  # Build adjacency matrix
  nodes <- bnlearn::nodes(bn)
  adj_mat <- matrix(0, length(nodes), length(nodes))
  rownames(adj_mat) <- colnames(adj_mat) <- nodes
  if (nrow(arcs_df) > 0) {
    for (i in 1:nrow(arcs_df)) {
      adj_mat[arcs_df[i, "from"], arcs_df[i, "to"]] <- 1
    }
  }

  return(list(
    network = bn,
    arcs = arcs_df,
    nodes = nodes,
    adjacency = adj_mat
  ))
}


#' Plot Bayesian network
#'
#' @description Creates a visualization of the Bayesian network structure.
#'
#' @param bn_result Result from \code{run_bnlearn()}.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' bn <- run_bnlearn(expr_matrix)
#' p <- plot_bnlearn_network(bn)
#' print(p)
#' }
#'
#' @export
plot_bnlearn_network <- function(bn_result) {
  arcs_df <- bn_result$arcs
  nodes <- bn_result$nodes

  if (nrow(arcs_df) == 0) {
    return(ggplot2::ggplot() +
           ggplot2::labs(title = "No edges in network") +
           ggplot2::theme_void())
  }

  # Simple circular layout
  n_nodes <- length(nodes)
  angles <- seq(0, 2 * pi, length.out = n_nodes + 1)[1:n_nodes]
  node_pos <- data.frame(
    node = nodes,
    x = cos(angles),
    y = sin(angles),
    stringsAsFactors = FALSE
  )

  # Edge data
  edge_data <- merge(arcs_df, node_pos, by.x = "from", by.y = "node")
  colnames(edge_data)[3:4] <- c("x_from", "y_from")
  edge_data <- merge(edge_data, node_pos, by.x = "to", by.y = "node")
  colnames(edge_data)[5:6] <- c("x_to", "y_to")

  p <- ggplot2::ggplot() +
    ggplot2::geom_segment(data = edge_data,
                          ggplot2::aes(x = x_from, y = y_from,
                                       xend = x_to, yend = y_to),
                          arrow = grid::arrow(length = grid::unit(0.2, "cm")),
                          color = "grey50", alpha = 0.6) +
    ggplot2::geom_point(data = node_pos, ggplot2::aes(x = x, y = y),
                        size = 4, color = "#4a90d9") +
    ggrepel::geom_label_repel(data = node_pos,
                              ggplot2::aes(x = x, y = y, label = node),
                              size = 2.5) +
    ggplot2::labs(title = "Bayesian Network") +
    ggplot2::theme_void() +
    ggplot2::theme(plot.title = ggplot2::element_text(size = 14, face = "bold"))

  return(p)
}
