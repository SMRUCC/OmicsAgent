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
#'   The clustering engine is \code{e1071::cmeans} (classic FCM). It is used
#'   instead of \code{cluster::fanny}, which degenerates to uniform memberships
#'   (all \eqn{= 1/k}) on high-dimensional z-scored matrices and assigns every
#'   feature to a single cluster. Because classic FCM can leave some centers
#'   empty (no feature hard-assigned), the function automatically retries with
#'   a progressively smaller fuzziness exponent \code{m} so that all requested
#'   clusters are populated.
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
  if (!requireNamespace("e1071", quietly = TRUE)) {
    stop("Package 'e1071' is required. Please install it.")
  }

  set.seed(seed)

  # Scale features for clustering
  scaled_mat <- t(scale(t(as.matrix(expr_matrix))))
  scaled_mat[is.na(scaled_mat)] <- 0

  # Fuzzy c-means (classic FCM via e1071::cmeans).
  # NOTE: cluster::fanny is not used because the FANNY algorithm degenerates
  # to uniform memberships (all == 1/k) on high-dimensional z-scored data,
  # assigning every feature to cluster 1.
  #
  # Classic FCM can leave some centers empty (no feature hard-assigned to
  # them), which makes those clusters vanish from plots. To guarantee that all
  # requested clusters are populated, retry with progressively smaller
  # fuzziness exponent m if empty clusters are detected.
  candidates <- unique(c(m, 1.5, 1.4, 1.3, 1.2))
  cm <- NULL
  used_m <- m
  for (mm in candidates) {
    set.seed(seed)
    tmp <- e1071::cmeans(scaled_mat, centers = n_clusters, m = mm,
                         iter.max = max_iter)
    if (length(unique(tmp$cluster)) == n_clusters) {
      cm <- tmp
      used_m <- mm
      break
    }
    cm <- tmp
  }

  # Extract results
  membership <- cm$membership
  rownames(membership) <- rownames(expr_matrix)
  colnames(membership) <- paste0("Cluster", 1:n_clusters)

  # Hard assignment
  cluster <- apply(membership, 1, which.max)
  names(cluster) <- rownames(expr_matrix)

  # Cluster centers (clusters x samples)
  centers <- cm$centers
  rownames(centers) <- paste0("Cluster", 1:n_clusters)
  colnames(centers) <- colnames(expr_matrix)

  # Non-empty cluster count
  n_nonempty <- length(unique(cluster))
  if (n_nonempty < n_clusters) {
    message(sprintf(
      "[run_cmeans] WARNING: only %d of %d clusters are non-empty after retry.",
      n_nonempty, n_clusters
    ))
  } else if (used_m != m) {
    message(sprintf(
      "[run_cmeans] Used fuzziness m = %.2f (instead of %.2f) to obtain %d non-empty clusters.",
      used_m, m, n_nonempty
    ))
  }

  return(list(
    cluster = cluster,
    membership = membership,
    centers = centers,
    model = cm
  ))
}


#' Plot CMeans cluster profiles
#'
#' @description Creates line plots showing the group-level expression pattern of
#'   the most representative features within each cluster. The x axis is the
#'   sample group id (\code{sample_info[[group_col]]}) and the y axis is the
#'   z-score of each feature's average expression per group (i.e. each feature's
#'   expression is averaged within each group, then the resulting
#'   feature x group matrix is row-wise z-scored). For every cluster the
#'   \code{top_n} features with the highest membership to that cluster are
#'   selected and drawn as lines. Line thickness (\code{linewidth}) and colour
#'   depth (\code{alpha}) both map to the feature's membership, so that features
#'   with higher membership appear thicker and darker.
#'
#' @param cmeans_result Result from \code{run_cmeans()}.
#' @param sample_info Sample metadata.
#' @param expr_matrix Optional numeric matrix (features x samples) holding the
#'   expression values used to draw the per-feature curves. Should be the same
#'   matrix passed to \code{run_cmeans()}. If \code{NULL}, falls back to drawing
#'   a single cluster-centre line per cluster (legacy behaviour).
#' @param top_n Number of top membership features to draw per cluster.
#'   Default: 100.
#' @param group_col Column for group labels. Default: "sample_info".
#' @param feature_names Optional named vector of display names.
#' @param palette Optional name of an RColorBrewer palette (e.g. "Set1", "Dark2",
#'   "Paired"). When set, each cluster panel uses a distinct colour from the
#'   palette; otherwise all curves are drawn in a single colour
#'   (default: \code{NULL}).
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' p <- plot_cmeans_profiles(cmeans_result, sample_info, expr_matrix = scaled_mat)
#' print(p)
#' }
#'
#' @export
plot_cmeans_profiles <- function(cmeans_result, sample_info,
                                 expr_matrix = NULL,
                                 top_n = 100,
                                 group_col = "sample_info",
                                 feature_names = NULL,
                                 palette = NULL) {
  centers <- cmeans_result$centers
  if (is.null(centers)) {
    stop("cmeans_result$centers is NULL; cannot plot profiles.")
  }

  cluster_names <- rownames(centers)
  sample_ids <- colnames(centers)
  membership <- cmeans_result$membership
  cluster_vec <- cmeans_result$cluster

  if (is.null(membership) || is.null(cluster_vec)) {
    stop("cmeans_result$membership / cluster is NULL; cannot plot feature curves.")
  }

  # Validate and align the expression matrix (features x samples)
  expr_mat <- as.matrix(expr_matrix)
  if (is.null(expr_mat) || nrow(expr_mat) == 0) {
    stop("expr_matrix is required for plotting group-level feature curves.")
  }
  if (!all(sample_ids %in% colnames(expr_mat))) {
    stop("expr_matrix columns do not match cmeans_result sample names.")
  }
  expr_mat <- expr_mat[, sample_ids, drop = FALSE]

  feat_ids <- rownames(expr_mat)
  if (is.null(feat_ids)) feat_ids <- rownames(membership)
  if (is.null(feat_ids)) stop("Cannot determine feature ids from expr_matrix.")

  # Map membership rows to expression rows by feature id
  mb <- membership
  rownames(mb) <- rownames(membership)
  mem_idx <- match(feat_ids, rownames(mb))
  if (any(is.na(mem_idx))) stop("expr_matrix rownames do not match membership rownames.")
  mb <- mb[mem_idx, , drop = FALSE]

  # --- Group-level mean + row-wise z-score --------------------------------
  # Group each sample by its group label, compute the per-feature mean within
  # each group, then z-score across groups for every feature.
  grp_vec <- sample_info[sample_ids, group_col]
  grp_lev <- unique(grp_vec)

  group_mean <- sapply(grp_lev, function(g) {
    cols <- which(grp_vec == g)
    if (length(cols) == 1) {
      return(as.numeric(expr_mat[, cols]))
    }
    rowMeans(expr_mat[, cols, drop = FALSE], na.rm = TRUE)
  })
  group_mean <- as.matrix(group_mean)
  rownames(group_mean) <- feat_ids
  colnames(group_mean) <- grp_lev

  # Row-wise z-score across groups
  gm_z <- t(scale(t(group_mean)))
  gm_z[is.na(gm_z)] <- 0

  # --- Select top membership features per cluster -------------------------
  rows <- list()
  for (cl in cluster_names) {
    k <- match(cl, colnames(mb))
    if (is.na(k)) next
    in_cl <- (as.integer(cluster_vec) == k)
    cl_feats <- feat_ids[in_cl]
    if (length(cl_feats) == 0) next
    cl_mem <- mb[in_cl, k]
    o <- order(cl_mem, decreasing = TRUE)
    top_feats <- head(cl_feats[o], top_n)
    top_mem <- cl_mem[o][seq_len(length(top_feats))]

    for (j in seq_along(top_feats)) {
      rows[[length(rows) + 1L]] <- data.frame(
        cluster = cl,
        group = grp_lev,
        value = as.numeric(gm_z[top_feats[j], , drop = TRUE]),
        membership = top_mem[j],
        feature_id = top_feats[j],
        stringsAsFactors = FALSE
      )
    }
  }
  plot_data_long <- do.call(rbind, rows)
  plot_data_long$feature_id <- as.character(plot_data_long$feature_id)

  # Order cluster factor so all clusters are shown in requested order
  plot_data_long$cluster <- factor(plot_data_long$cluster,
                                    levels = cluster_names)
  # Order group factor consistently
  plot_data_long$group <- factor(plot_data_long$group, levels = grp_lev)

  # Map membership to line thickness and transparency (depth).
  # Moderate linewidth ceiling so overlapping high-membership lines do not
  # coalesce into a solid block; low-membership lines stay faint but visible.
  mem_range <- range(plot_data_long$membership, na.rm = TRUE)
  if (diff(mem_range) == 0) mem_range <- c(mem_range[1] - 1, mem_range[2])

  # --- Palette handling ----------------------------------------------------
  # When a palette name is supplied, each cluster gets its own colour from an
  # RColorBrewer palette. Otherwise all curves share a single colour.
  use_palette <- !is.null(palette) && !is.na(palette) &&
    nzchar(palette) && palette != ""
  cluster_colors <- NULL
  if (use_palette) {
    if (!requireNamespace("RColorBrewer", quietly = TRUE)) {
      stop("Package 'RColorBrewer' is required when 'palette' is set.")
    }
    pal_info <- RColorBrewer::brewer.pal.info
    if (!palette %in% rownames(pal_info)) {
      stop(sprintf("Unknown RColorBrewer palette '%s'.", palette))
    }
    n_cl <- length(cluster_names)
    max_col <- pal_info[palette, "maxcolors"]
    if (n_cl <= max_col) {
      cluster_colors <- RColorBrewer::brewer.pal(n_cl, palette)
    } else {
      base_cols <- RColorBrewer::brewer.pal(max_col, palette)
      cluster_colors <- grDevices::colorRampPalette(base_cols)(n_cl)
    }
    names(cluster_colors) <- cluster_names
  }

  # Common membership scales and theme
  common <- list(
    ggplot2::scale_linewidth(range = c(0.2, 0.9),
                             name = "Membership",
                             breaks = scales::pretty_breaks(4)),
    ggplot2::scale_alpha_continuous(range = c(0.20, 0.75),
                                    name = "Membership",
                                    breaks = scales::pretty_breaks(4)),
    ggplot2::labs(
      title = "CMeans Cluster Profiles (top features)",
      subtitle = paste0(
        "Top ", top_n, " features per cluster; ",
        "x = group mean z-score, line thickness/colour map to membership"
      ),
      x = "Group",
      y = "Group-mean expression (z-score)"
    ),
    ggplot2::theme_bw(),
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      plot.subtitle = ggplot2::element_text(size = 10, hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      strip.text = ggplot2::element_text(face = "bold")
    )
  )

  if (use_palette) {
    # One colour per cluster
    p <- ggplot2::ggplot(plot_data_long,
                         ggplot2::aes(x = group, y = value,
                                      group = feature_id,
                                      color = cluster,
                                      linewidth = membership,
                                      alpha = membership)) +
      ggplot2::geom_line() +
      ggplot2::geom_point(size = 0.5) +
      ggplot2::facet_wrap(~ cluster, scales = "free_y") +
      ggplot2::scale_color_manual(values = cluster_colors,
                                  name = "Cluster",
                                  breaks = cluster_names,
                                  drop = FALSE) +
      ggplot2::guides(color = ggplot2::guide_legend(title = "Cluster",
                                                    override.aes = list(
                                                      linewidth = 1.2,
                                                      alpha = 1
                                                    )))
  } else {
    # Single colour for all curves (default)
    p <- ggplot2::ggplot(plot_data_long,
                         ggplot2::aes(x = group, y = value,
                                      group = feature_id,
                                      linewidth = membership,
                                      alpha = membership)) +
      ggplot2::geom_line(color = "#2c3e50") +
      ggplot2::geom_point(color = "#2c3e50", size = 0.5) +
      ggplot2::facet_wrap(~ cluster, scales = "free_y")
  }

  # Append shared membership scales, legend guides and theme
  p <- p +
    ggplot2::guides(linewidth = ggplot2::guide_legend(title = "Membership"),
                    alpha = ggplot2::guide_legend(title = "Membership")) +
    common

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
