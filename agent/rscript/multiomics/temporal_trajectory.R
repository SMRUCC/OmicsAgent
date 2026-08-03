# ==============================================================================
# OmicsFlow: Fermentation Temporal Dynamics
# ==============================================================================
# Trajectory reconstruction and temporal pattern clustering across the
# fermentation time course, optionally split by a grouping factor such as the
# geographic origin of the samples.
# ==============================================================================

#' Reconstruct the temporal trajectory of one omics layer
#'
#' @description Projects samples onto the principal component space of a layer
#'   and averages the coordinates within each time point, producing an ordered
#'   trajectory through PCA space. When \code{group_col} is supplied a separate
#'   trajectory is built for every group so that fermentation rhythms can be
#'   compared between, for example, two production regions.
#'
#' @param expr_matrix Numeric matrix, features in rows and samples in columns.
#' @param sample_info data.frame of sample annotation, rownames matching the
#'   columns of \code{expr_matrix}.
#' @param time_col Column holding the numeric time coordinate. Default: "day".
#' @param group_col Optional column splitting the trajectory. Default: NULL.
#' @param phase_col Optional column holding a discrete phase label attached to
#'   each time point for annotation. Default: NULL.
#' @param n_comp Number of principal components retained. Default: 2.
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{trajectory}: data.frame with group, time, phase, n_samples
#'       and the mean PC coordinates.
#'     \item \code{scores}: data.frame of per-sample PC coordinates.
#'     \item \code{variance}: Numeric vector of variance explained per PC (%).
#'     \item \code{path_length}: data.frame of cumulative trajectory length per
#'       group, a summary of how far the system travels during fermentation.
#'   }
#'
#' @examples
#' \dontrun{
#' traj <- run_temporal_trajectory(mat, sample_info, time_col = "day",
#'                                 group_col = "location")
#' }
#'
#' @export
run_temporal_trajectory <- function(expr_matrix, sample_info,
                                    time_col = "day",
                                    group_col = NULL,
                                    phase_col = NULL,
                                    n_comp = 2,
                                    verbose = TRUE) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
  }
  if (!time_col %in% colnames(sample_info)) {
    stop(sprintf("Time column '%s' not found in sample_info.", time_col))
  }

  common <- intersect(colnames(expr_matrix), rownames(sample_info))
  if (length(common) < 3) {
    stop("Fewer than 3 samples shared between expression matrix and sample_info.")
  }
  expr_matrix <- expr_matrix[, common, drop = FALSE]
  sample_info <- sample_info[common, , drop = FALSE]

  # Drop zero-variance features, otherwise prcomp with scale. = TRUE fails.
  fvar <- apply(expr_matrix, 1, stats::var, na.rm = TRUE)
  keep <- is.finite(fvar) & fvar > 0
  if (sum(keep) < 2) {
    stop("Fewer than 2 informative features remain for trajectory analysis.")
  }
  if (verbose && any(!keep)) {
    cat(sprintf("  Removed %d zero-variance features before PCA.\n", sum(!keep)))
  }
  mat <- expr_matrix[keep, , drop = FALSE]

  # Impute residual missing values with the feature mean so prcomp can run.
  if (anyNA(mat)) {
    rmeans <- rowMeans(mat, na.rm = TRUE)
    idx <- which(is.na(mat), arr.ind = TRUE)
    mat[idx] <- rmeans[idx[, 1]]
  }

  n_comp <- max(1, min(n_comp, nrow(mat), ncol(mat) - 1))
  pca <- stats::prcomp(t(mat), center = TRUE, scale. = TRUE)
  variance <- (pca$sdev^2 / sum(pca$sdev^2)) * 100
  pc_names <- paste0("PC", seq_len(n_comp))
  scores <- as.data.frame(pca$x[, seq_len(n_comp), drop = FALSE])
  colnames(scores) <- pc_names

  time_vals <- suppressWarnings(as.numeric(as.character(sample_info[[time_col]])))
  if (all(is.na(time_vals))) {
    stop(sprintf("Time column '%s' cannot be coerced to numeric.", time_col))
  }
  scores$sample_id <- rownames(scores)
  scores$time <- time_vals

  if (!is.null(group_col) && group_col %in% colnames(sample_info)) {
    scores$group <- as.character(sample_info[[group_col]])
  } else {
    scores$group <- "all"
  }
  if (!is.null(phase_col) && phase_col %in% colnames(sample_info)) {
    scores$phase <- as.character(sample_info[[phase_col]])
  } else {
    scores$phase <- NA_character_
  }

  # Average PC coordinates within each group x time point.
  key <- paste(scores$group, scores$time, sep = "||")
  traj_list <- lapply(split(seq_len(nrow(scores)), key), function(idx) {
    sub <- scores[idx, , drop = FALSE]
    phases <- sub$phase[!is.na(sub$phase)]
    row <- data.frame(
      group = sub$group[1],
      time = sub$time[1],
      phase = if (length(phases) > 0) names(sort(table(phases), decreasing = TRUE))[1] else NA_character_,
      n_samples = nrow(sub),
      stringsAsFactors = FALSE
    )
    for (pc in pc_names) {
      row[[pc]] <- mean(sub[[pc]], na.rm = TRUE)
    }
    row
  })
  trajectory <- do.call(rbind, traj_list)
  trajectory <- trajectory[order(trajectory$group, trajectory$time), , drop = FALSE]
  rownames(trajectory) <- NULL

  # Cumulative euclidean path length through PC space per group.
  path_list <- lapply(split(trajectory, trajectory$group), function(sub) {
    sub <- sub[order(sub$time), , drop = FALSE]
    coords <- as.matrix(sub[, pc_names, drop = FALSE])
    if (nrow(coords) < 2) {
      len <- 0
    } else {
      steps <- sqrt(rowSums((coords[-1, , drop = FALSE] -
                               coords[-nrow(coords), , drop = FALSE])^2))
      len <- sum(steps)
    }
    data.frame(
      group = sub$group[1],
      n_timepoints = nrow(sub),
      path_length = len,
      stringsAsFactors = FALSE
    )
  })
  path_length <- do.call(rbind, path_list)
  rownames(path_length) <- NULL

  if (verbose) {
    cat(sprintf("  Trajectory built: %d group(s), %d time point(s), PC1 %.1f%% / PC2 %.1f%%\n",
                length(unique(trajectory$group)),
                length(unique(trajectory$time)),
                variance[1],
                if (length(variance) > 1) variance[2] else 0))
  }

  list(
    trajectory = trajectory,
    scores = scores,
    variance = variance[seq_len(n_comp)],
    path_length = path_length
  )
}


#' Trajectories for every layer of a MultiOmicsData object
#'
#' @description Applies \code{run_temporal_trajectory()} to each omics layer and
#'   collects the results, allowing the fermentation dynamics of the different
#'   molecular levels to be compared side by side.
#'
#' @param mo A MultiOmicsData object.
#' @param time_col Time column in sample_info. Default: "day".
#' @param group_col Optional splitting column. Default: NULL.
#' @param phase_col Optional phase label column. Default: NULL.
#' @param layers Optional character vector of layers. Default: NULL (all).
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A list with \code{per_layer} (named list of trajectory results) and
#'   \code{path_summary} (data.frame combining path lengths across layers).
#'
#' @examples
#' \dontrun{
#' res <- run_all_temporal_trajectories(mo, time_col = "day",
#'                                      group_col = "location")
#' }
#'
#' @export
run_all_temporal_trajectories <- function(mo,
                                          time_col = "day",
                                          group_col = NULL,
                                          phase_col = NULL,
                                          layers = NULL,
                                          verbose = TRUE) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (is.null(layers)) {
    layers <- mo$metadata$omics_names
  }
  layers <- intersect(layers, mo$metadata$omics_names)
  if (length(layers) == 0) {
    stop("No valid layers selected.")
  }

  per_layer <- list()
  summaries <- list()
  for (nm in layers) {
    if (verbose) cat(sprintf("  [%s]\n", nm))
    res <- tryCatch(
      run_temporal_trajectory(
        expr_matrix = mo$omics[[nm]]$expression,
        sample_info = mo$sample_info,
        time_col = time_col,
        group_col = group_col,
        phase_col = phase_col,
        verbose = verbose
      ),
      error = function(e) {
        cat(sprintf("  Trajectory failed for '%s': %s\n", nm, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(res)) next
    per_layer[[nm]] <- res
    pl <- res$path_length
    pl$omics <- nm
    summaries[[nm]] <- pl
  }

  path_summary <- if (length(summaries) > 0) {
    out <- do.call(rbind, summaries)
    rownames(out) <- NULL
    out[, c("omics", "group", "n_timepoints", "path_length")]
  } else {
    data.frame()
  }

  list(per_layer = per_layer, path_summary = path_summary)
}


#' Cluster features by their temporal expression pattern
#'
#' @description Averages each feature across the replicates of every time point
#'   and clusters the resulting temporal profiles with the existing
#'   \code{run_cmeans()} routine, yielding groups of features that rise, fall or
#'   peak together during fermentation.
#'
#' @param expr_matrix Numeric matrix, features in rows and samples in columns.
#' @param sample_info data.frame of sample annotation.
#' @param time_col Time column. Default: "day".
#' @param n_clusters Number of clusters. Default: 6.
#' @param top_n Retain only the \code{top_n} most variable features before
#'   clustering; NULL keeps everything. Default: NULL.
#' @param seed Random seed. Default: 42.
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{cmeans}: The raw \code{run_cmeans()} result.
#'     \item \code{profiles}: Long data.frame of scaled cluster profiles with
#'       cluster, time and mean value, ready for plotting.
#'     \item \code{membership}: data.frame of feature to cluster assignment.
#'     \item \code{time_matrix}: The averaged feature x time matrix used.
#'   }
#'
#' @examples
#' \dontrun{
#' cl <- run_temporal_clustering(mat, sample_info, time_col = "day",
#'                               n_clusters = 6)
#' }
#'
#' @export
run_temporal_clustering <- function(expr_matrix, sample_info,
                                    time_col = "day",
                                    n_clusters = 6,
                                    top_n = NULL,
                                    seed = 42,
                                    verbose = TRUE) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
  }
  if (!time_col %in% colnames(sample_info)) {
    stop(sprintf("Time column '%s' not found in sample_info.", time_col))
  }
  if (!exists("run_cmeans")) {
    stop("run_cmeans() is required but not available. Load network/cmeans.R first.")
  }

  common <- intersect(colnames(expr_matrix), rownames(sample_info))
  if (length(common) < 3) {
    stop("Fewer than 3 samples shared between expression matrix and sample_info.")
  }
  expr_matrix <- expr_matrix[, common, drop = FALSE]
  sample_info <- sample_info[common, , drop = FALSE]

  time_vals <- suppressWarnings(as.numeric(as.character(sample_info[[time_col]])))
  if (all(is.na(time_vals))) {
    stop(sprintf("Time column '%s' cannot be coerced to numeric.", time_col))
  }
  time_levels <- sort(unique(time_vals[!is.na(time_vals)]))

  # Collapse replicates: one column per time point.
  time_matrix <- vapply(time_levels, function(tp) {
    idx <- which(time_vals == tp)
    rowMeans(expr_matrix[, idx, drop = FALSE], na.rm = TRUE)
  }, numeric(nrow(expr_matrix)))
  colnames(time_matrix) <- paste0("T", time_levels)
  rownames(time_matrix) <- rownames(expr_matrix)

  fvar <- apply(time_matrix, 1, stats::var, na.rm = TRUE)
  keep <- is.finite(fvar) & fvar > 0
  if (verbose && any(!keep)) {
    cat(sprintf("  Removed %d features with no temporal variation.\n", sum(!keep)))
  }
  time_matrix <- time_matrix[keep, , drop = FALSE]
  if (nrow(time_matrix) < n_clusters) {
    stop("Fewer features than requested clusters.")
  }

  if (!is.null(top_n) && top_n < nrow(time_matrix)) {
    ord <- order(fvar[keep], decreasing = TRUE)[seq_len(top_n)]
    time_matrix <- time_matrix[ord, , drop = FALSE]
    if (verbose) {
      cat(sprintf("  Restricted to the %d most variable features.\n", top_n))
    }
  }

  cm <- run_cmeans(time_matrix, n_clusters = n_clusters, seed = seed)

  cluster_vec <- cm$cluster
  # run_cmeans scales internally but does not return the scaled matrix, so the
  # per-feature z-scores are recomputed here for the cluster profiles.
  scaled <- t(scale(t(time_matrix)))

  # Mean scaled profile per cluster and time point.
  prof_list <- lapply(sort(unique(cluster_vec)), function(k) {
    members <- names(cluster_vec)[cluster_vec == k]
    members <- intersect(members, rownames(scaled))
    if (length(members) == 0) return(NULL)
    sub <- scaled[members, , drop = FALSE]
    data.frame(
      cluster = paste0("Cluster_", k),
      time = time_levels,
      value = colMeans(sub, na.rm = TRUE),
      n_features = length(members),
      stringsAsFactors = FALSE
    )
  })
  profiles <- do.call(rbind, prof_list[!vapply(prof_list, is.null, logical(1))])
  rownames(profiles) <- NULL

  membership <- data.frame(
    feature = names(cluster_vec),
    cluster = paste0("Cluster_", as.integer(cluster_vec)),
    stringsAsFactors = FALSE
  )
  if (!is.null(cm$membership)) {
    mm <- cm$membership
    if (is.matrix(mm) && nrow(mm) == nrow(membership)) {
      membership$max_membership <- apply(mm, 1, max, na.rm = TRUE)
    }
  }

  if (verbose) {
    cat(sprintf("  Temporal clustering: %d features into %d clusters over %d time points.\n",
                nrow(time_matrix), length(unique(cluster_vec)), length(time_levels)))
  }

  list(
    cmeans = cm,
    profiles = profiles,
    membership = membership,
    time_matrix = time_matrix
  )
}
