# ==============================================================================
# OmicsFlow：发酵时间动态分析
# ==============================================================================
# 跨越发酵时间序列的轨迹重建与时间模式聚类，可按分组因子（如样本的地理来源）
# 进行拆分。
# ==============================================================================

#' 重建单个组学层的时间轨迹
#'
#' @description 将样本投影到某层的 PCA 空间，并在每个时间点内对坐标取平均，
#'   生成一条穿过 PCA 空间的有序轨迹。当提供 \code{group_col} 时，会为每组
#'   分别构建轨迹，从而可比较两个生产区域等之间的发酵节律。
#'
#' @param expr_matrix 数值矩阵，行为特征、列为样本。
#' @param sample_info 样本注释 data.frame，其行名与 \code{expr_matrix} 的列对应。
#' @param time_col 保存数值时间坐标的列。默认："day"。
#' @param group_col 可选的用于拆分轨迹的列。默认：NULL。
#' @param phase_col 可选的列，保存附在每个时间点上用于注释的离散阶段标签。默认：NULL。
#' @param n_comp 保留的主成分数量。默认：2。
#' @param verbose 逻辑值，是否打印进度。默认：TRUE。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{trajectory}: 含 group、time、phase、n_samples
#'       与平均 PC 坐标的数据框。
#'     \item \code{scores}: 逐样本 PC 坐标的数据框。
#'     \item \code{variance}: 每个 PC 解释方差（%）的数值向量。
#'     \item \code{path_length}: 每组的累计轨迹长度数据框，概括发酵过程中系统
#'       行进的距离。
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

  # 剔除零方差特征，否则 prcomp 配合 scale. = TRUE 会失败。
  fvar <- apply(expr_matrix, 1, stats::var, na.rm = TRUE)
  keep <- is.finite(fvar) & fvar > 0
  if (sum(keep) < 2) {
    stop("Fewer than 2 informative features remain for trajectory analysis.")
  }
  if (verbose && any(!keep)) {
    cat(sprintf("  Removed %d zero-variance features before PCA.\n", sum(!keep)))
  }
  mat <- expr_matrix[keep, , drop = FALSE]

  # 用特征均值填补残差缺失值，使 prcomp 能够运行。
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

  # 在每个 组 x 时间点 内对 PC 坐标取平均。
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

  # 每组在 PC 空间中累计的欧氏路径长度。
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


#' 对 MultiOmicsData 对象的每个层构建轨迹
#'
#' @description 对每层应用 \code{run_temporal_trajectory()} 并汇总结果，从而可
#'   并排比较不同分子层次的发酵动态。
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param time_col sample_info 中的时间列。默认："day"。
#' @param group_col 可选的拆分列。默认：NULL。
#' @param phase_col 可选的相标签列。默认：NULL。
#' @param layers 可选的层字符向量。默认：NULL（全部）。
#' @param verbose 逻辑值，是否打印进度。默认：TRUE。
#'
#' @return 一个列表，含 \code{per_layer}（轨迹结果的有名列表）与
#'   \code{path_summary}（跨层合并路径长度的数据框）。
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


#' 按时间表达模式对特征聚类
#'
#' @description 对每个特征在各时间点的重复样本上取平均，并用已有的 \code{run_cmeans()}
#'   例程对所得时间轮廓聚类，得到在发酵过程中同步上升、下降或达到峰值的一组组特征。
#'
#' @param expr_matrix 数值矩阵，行为特征、列为样本。
#' @param sample_info 样本注释 data.frame。
#' @param time_col 时间列。默认："day"。
#' @param n_clusters 聚类数。默认：6。
#' @param top_n 聚类前仅保留 \code{top_n} 个变异最大的特征；NULL 表示保留全部。默认：NULL。
#' @param seed 随机种子。默认：42。
#' @param verbose 逻辑值，是否打印进度。默认：TRUE。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{cmeans}: 原始 \code{run_cmeans()} 的结果。
#'     \item \code{profiles}: 标准化聚类轮廓的长格式数据框，含 cluster、time 与均值，
#'       可直接绘图。
#'     \item \code{membership}: 特征到聚类分配的数据框。
#'     \item \code{time_matrix}: 所用的平均特征 x 时间矩阵。
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

  # 合并重复样本：每个时间点一列。
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
  # run_cmeans 内部会做标准化但不返回标准化后的矩阵，因此这里为聚类轮廓
  # 重新计算各特征的 z 分数。
  scaled <- t(scale(t(time_matrix)))

  # 每个聚类、每个时间点的平均标准化轮廓。
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
