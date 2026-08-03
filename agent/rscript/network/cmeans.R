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
  # Cluster centers: rows = clusters, cols = samples (z-scored expression)
  centers <- cmeans_result$centers
  if (is.null(centers)) {
    stop("cmeans_result$centers is NULL; cannot plot profiles.")
  }

  # Build a tidy data frame: one row per (cluster, sample)
  # centers has samples as columns -> pivot to long format robustly
  cluster_names <- rownames(centers)
  sample_ids <- colnames(centers)

  # Matrix of centers (clusters x samples) -> long data frame
  centers_mat <- as.matrix(centers)
  plot_data_long <- data.frame(
    cluster = rep(cluster_names, each = length(sample_ids)),
    sample_id = rep(sample_ids, times = nrow(centers_mat)),
    value = as.numeric(t(centers_mat)),
    stringsAsFactors = FALSE
  )

  # Add group label from sample metadata
  plot_data_long$group <- sample_info[plot_data_long$sample_id, group_col]

  # Ensure cluster is an ordered factor for consistent faceting
  plot_data_long$cluster <- factor(plot_data_long$cluster,
                                    levels = cluster_names)

  p <- ggplot2::ggplot(plot_data_long,
                       ggplot2::aes(x = group, y = value,
                                    group = cluster, color = cluster)) +
    ggplot2::geom_line(linewidth = 0.8) +
    ggplot2::geom_point(size = 2) +
    ggplot2::facet_wrap(~ cluster, scales = "free_y") +
    ggplot2::labs(
      title = "CMeans Cluster Profiles",
      x = "Group",
      y = "Expression (z-score)",
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


#' Export CMeans membership table to CSV
#'
#' @description Exports the fuzzy c-means clustering result as a CSV file.
#'   The output has one row per feature and one column per cluster
#'   (membership degree / 归属度), plus an additional \code{cluster} column
#'   recording the hard cluster assignment (the cluster with the highest
#'   membership for each feature).
#'
#' @param cmeans_result Result from \code{run_cmeans()}.
#' @param output_dir Directory for output.
#' @param filename Base filename (without extension). Default: "cmeans_membership".
#' @param id_col_name Name for the feature-id column. Default: "feature_id".
#'
#' @return Invisible path to the exported CSV file.
#'
#' @examples
#' \dontrun{
#' export_cmeans_membership(cm, "results/tables", "cmeans_membership")
#' }
#'
#' @export
export_cmeans_membership <- function(cmeans_result, output_dir = ".",
                                      filename = "cmeans_membership",
                                      id_col_name = "feature_id") {
  membership <- cmeans_result$membership
  if (is.null(membership)) {
    stop("cmeans_result$membership is NULL; nothing to export.")
  }

  # Build data frame: feature rows, cluster-membership columns
  out <- as.data.frame(membership)
  out[[id_col_name]] <- rownames(membership)
  out$cluster <- cmeans_result$cluster

  # Reorder so feature id and hard-assignment columns come first,
  # then the per-cluster membership columns
  member_cols <- setdiff(colnames(out), c(id_col_name, "cluster"))
  out <- out[, c(id_col_name, member_cols, "cluster")]

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  if (!grepl("\\.csv$", filename)) filename <- paste0(filename, ".csv")
  file_path <- file.path(output_dir, filename)
  utils::write.csv(out, file_path, row.names = FALSE)

  invisible(file_path)
}
