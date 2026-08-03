# ==============================================================================
# OmicsFlow: CMeans Fuzzy Clustering
# ==============================================================================
# Fuzzy c-means clustering of features
# ==============================================================================

#' CMeans fuzzy clustering
#'
#' @description Performs fuzzy c-means clustering to identify groups of features
#'   with similar expression patterns. Unlike hard clustering, each feature
#'   receives a membership value for each cluster.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param n_clusters Number of clusters. Default: 6.
#' @param m Fuzziness parameter (> 1). Higher = fuzzier. Default: 2.
#' @param max_iter Maximum iterations. Default: 100.
#' @param seed Random seed. Default: 42.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{cluster}: Integer vector of hard cluster assignment.
#'     \item \code{membership}: Membership matrix (features x clusters).
#'     \item \code{centers}: Cluster centers (clusters x samples).
#'     \item \code{model}: Original cluster object.
#'   }
#'
#' @examples
#' \dontrun{
#' cm <- run_cmeans(expr_matrix, n_clusters = 6)
#' print(table(cm$cluster))
#' }
#'
#' @export
run_cmeans <- function(expr_matrix, n_clusters = 6, m = 2,
                      max_iter = 100, seed = 42) {
  if (!requireNamespace("cluster", quietly = TRUE)) {
    stop("Package 'cluster' is required. Please install it.")
  }

  set.seed(seed)

  # Scale features for clustering
  scaled_mat <- t(scale(t(as.matrix(expr_matrix))))
  scaled_mat[is.na(scaled_mat)] <- 0

  # Fuzzy c-means
  cm <- cluster::fanny(scaled_mat, k = n_clusters, memb.exp = m,
                       maxit = max_iter, stand = FALSE)

  # Extract results
  membership <- cm$membership
  rownames(membership) <- rownames(expr_matrix)
  colnames(membership) <- paste0("Cluster", 1:n_clusters)

  # Hard assignment
  cluster <- apply(membership, 1, which.max)
  names(cluster) <- rownames(expr_matrix)

  # Cluster centers
  centers <- t(sapply(1:n_clusters, function(k) {
    colMeans(scaled_mat[cluster == k, , drop = FALSE])
  }))
  rownames(centers) <- paste0("Cluster", 1:n_clusters)
  colnames(centers) <- colnames(expr_matrix)

  return(list(
    cluster = cluster,
    membership = membership,
    centers = centers,
    model = cm
  ))
}


#' Plot CMeans cluster profiles
#'
#' @description Creates line plots showing expression patterns of features within
#'   each cluster.
#'
#' @param cmeans_result Result from \code{run_cmeans()}.
#' @param sample_info Sample metadata.
#' @param group_col Column for group labels. Default: "sample_info".
#' @param feature_names Optional named vector of display names.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' p <- plot_cmeans_profiles(cmeans_result, sample_info)
#' print(p)
#' }
#'
#' @export
plot_cmeans_profiles <- function(cmeans_result, sample_info,
                                 group_col = "sample_info",
                                 feature_names = NULL) {
  centers <- cmeans_result$centers

  # Prepare data for plotting
  plot_data <- data.frame(
    sample_id = colnames(centers),
    t(centers),
    stringsAsFactors = FALSE
  )

  # Add group
  plot_data$group <- sample_info[plot_data$sample_id, group_col]

  # Melt
  plot_data_long <- stats::reshape(plot_data,
                                    direction = "long",
                                    varying = 1:nrow(centers),
                                    v.names = "value",
                                    timevar = "cluster",
                                    times = rownames(centers))
  plot_data_long$cluster <- factor(plot_data_long$cluster,
                                    levels = rownames(centers))

  p <- ggplot2::ggplot(plot_data_long,
                       ggplot2::aes(x = group, y = value,
                                    group = cluster, color = cluster)) +
    ggplot2::geom_line(linewidth = 0.8) +
    ggplot2::geom_point(size = 2) +
    ggplot2::facet_wrap(~ cluster, scales = "free_y") +
    ggplot2::labs(
      title = "CMeans Cluster Profiles",
      x = "Group",
      y = "Expression (scaled)",
      color = "Cluster"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      strip.text = ggplot2::element_text(face = "bold")
    ) +
    ggplot2::scale_color_discrete(guide = "none")

  return(p)
}
