# ==============================================================================
# OmicsFlow: Protein Expression Pattern Clustering
# ==============================================================================
# 蛋白表达模式聚类：K-means、层次聚类、模糊c-means
# 用于识别蛋白质的时序表达模式
# ==============================================================================

#' 蛋白表达模式聚类
#'
#' @description 对蛋白质表达矩阵进行聚类分析，识别具有相似表达模式的蛋白。
#'   支持 K-means、层次聚类和模糊 c-means (FCM) 三种方法。
#'
#' @param expr_matrix 数值矩阵（features × samples），行为蛋白质，列为样本。
#' @param sample_info 样本元数据 data.frame。
#' @param group_col 分组列名，用于定义时间/条件顺序。默认 "sample_info"。
#' @param method 聚类方法，"kmeans"、"hierarchical" 或 "fcm"。默认 "kmeans"。
#' @param n_clusters 聚类数。默认 6。
#' @param scale 是否行标准化。默认 TRUE。
#' @param nstart K-means 随机起始次数。默认 25。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{clusters}: 聚类分配向量。
#'     \item \code{centers}: 聚类中心。
#'     \item \code{profiles}: 按聚类分组的表达谱数据（用于绘图）。
#'     \item \code{silhouette}: 轮廓Coefficient（如果计算了）。
#'   }
#'
#' @examples
#' \dontrun{
#' res <- cluster_protein_profiles(expr_matrix, sample_info,
#'                                 method = "kmeans", n_clusters = 6)
#' }
#'
#' @export
cluster_protein_profiles <- function(expr_matrix, sample_info,
                                     group_col = "sample_info",
                                     method = "kmeans",
                                     n_clusters = 6,
                                     scale = TRUE,
                                     nstart = 25) {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)

  # 过滤零方差
  vars <- apply(expr_matrix, 1, stats::var, na.rm = TRUE)
  keep <- !is.na(vars) & vars > 0
  if (sum(keep) < n_clusters) {
    stop(sprintf("Only %d proteins remained after zero-variance filtering, insufficient for %d clusters.",
                sum(keep), n_clusters))
  }
  expr_matrix <- expr_matrix[keep, , drop = FALSE]

  # 行标准化
  if (scale) {
    expr_scaled <- t(scale(t(expr_matrix)))
  } else {
    expr_scaled <- expr_matrix
  }

  # 填充 NA
  expr_scaled[is.na(expr_scaled)] <- 0

  # 按分组聚合
  common <- intersect(colnames(expr_matrix), rownames(sample_info))
  groups <- sample_info[common, group_col]
  group_levels <- unique(groups)

  # 计算每组均值
  group_means <- sapply(group_levels, function(g) {
    g_samples <- common[groups == g]
    if (length(g_samples) == 0) return(rep(NA, nrow(expr_scaled)))
    rowMeans(expr_scaled[, g_samples, drop = FALSE], na.rm = TRUE)
  })
  if (!is.matrix(group_means)) group_means <- t(as.matrix(group_means))
  colnames(group_means) <- group_levels

  # 聚类
  if (method == "kmeans") {
    km <- stats::kmeans(group_means, centers = n_clusters, nstart = nstart)
    clusters <- km$cluster
    centers <- km$centers
    rownames(centers) <- paste0("Cluster", 1:n_clusters)
  } else if (method == "hierarchical") {
    # 层次聚类
    dist_mat <- stats::dist(group_means, method = "euclidean")
    hc <- stats::hclust(dist_mat, method = "ward.D2")
    clusters <- stats::cutree(hc, k = n_clusters)
    # 计算中心
    centers <- t(sapply(1:n_clusters, function(k) {
      if (sum(clusters == k) > 0) colMeans(group_means[clusters == k, , drop = FALSE])
      else rep(0, ncol(group_means))
    }))
    rownames(centers) <- paste0("Cluster", 1:n_clusters)
  } else if (method == "fcm") {
    # 模糊 c-means
    if (requireNamespace("e1071", quietly = TRUE)) {
      fcm <- e1071::cmeans(group_means, centers = n_clusters)
      clusters <- fcm$cluster
      centers <- fcm$centers
      rownames(centers) <- paste0("Cluster", 1:n_clusters)
    } else {
      stop("Package 'e1071' is required for FCM clustering.")
    }
  } else {
    stop("Unsupported method. Use 'kmeans', 'hierarchical', or 'fcm'.")
  }

  # 轮廓Coefficient
  sil <- NA
  if (n_clusters > 1) {
    dist_mat <- stats::dist(group_means, method = "euclidean")
    if (length(unique(clusters)) > 1) {
      sil_obj <- cluster::silhouette(clusters, dist_mat)
      sil <- summary(sil_obj)$avg.width
    }
  }

  # 按聚类大小排序
  cluster_sizes <- table(clusters)
  size_order <- order(-cluster_sizes)
  old_names <- paste0("Cluster", size_order)
  new_names <- paste0("C", seq_along(size_order))
  names(new_names) <- old_names
  clusters <- new_names[paste0("Cluster", clusters)]
  names(clusters) <- rownames(expr_matrix)
  rownames(centers) <- new_names

  cat(sprintf("[cluster] Method: %s, clusters: %d, silhouette: %.3f\n",
              method, n_clusters, sil))
  cat("[cluster] Cluster sizes:")
  for (cl in sort(unique(clusters))) {
    cat(sprintf(" %s=%d", cl, sum(clusters == cl)))
  }
  cat("\n")

  # 构建绘图数据
  profile_df <- data.frame()
  for (cl in sort(unique(clusters))) {
    cl_proteins <- names(clusters)[clusters == cl]
    cl_data <- group_means[cl_proteins, , drop = FALSE]
    profile_df <- rbind(profile_df, data.frame(
      protein = cl_proteins,
      cluster = cl,
      group = rep(colnames(cl_data), each = nrow(cl_data)),
      value = as.vector(cl_data),
      stringsAsFactors = FALSE
    ))
  }

  return(list(
    clusters = clusters,
    centers = centers,
    profiles = profile_df,
    group_means = group_means,
    silhouette = sil,
    method = method,
    n_clusters = n_clusters
  ))
}


#' 绘制蛋白表达模式聚类图
#'
#' @description 绘制聚类后的蛋白表达模式图，每个聚类一个子图，
#'   展示该类所有蛋白的表达曲线和聚类中心。
#'
#' @param cluster_result \code{cluster_protein_profiles()} 的返回结果。
#' @param show_centers 是否显示聚类中心线。默认 TRUE。
#' @param line_alpha 单条线透明度。默认 0.2。
#'
#' @return ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_profile_clusters(cluster_result)
#' }
#'
#' @export
plot_profile_clusters <- function(cluster_result, show_centers = TRUE,
                                  line_alpha = 0.2) {
  profile_df <- cluster_result$profiles
  centers <- cluster_result$centers

  # 确保 group 按原始顺序排列
  group_levels <- colnames(cluster_result$group_means)
  profile_df$group <- factor(profile_df$group, levels = group_levels)

  p <- ggplot2::ggplot(profile_df, ggplot2::aes(x = group, y = value,
                                                 group = protein)) +
    ggplot2::geom_line(color = "#4a90d9", alpha = line_alpha, linewidth = 0.3) +
    ggplot2::facet_wrap(~ cluster, scales = "free_y") +
    ggplot2::labs(
      title = sprintf("Protein Expression Profiles (%s, k=%d)",
                      cluster_result$method, cluster_result$n_clusters),
      x = NULL,
      y = "Expression (z-score)"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 8),
      strip.text = ggplot2::element_text(size = 10, face = "bold")
    )

  # 添加聚类中心线
  if (show_centers) {
    center_df <- data.frame(
      cluster = rep(rownames(centers), each = ncol(centers)),
      group = rep(colnames(centers), nrow(centers)),
      value = as.vector(t(centers)),
      stringsAsFactors = FALSE
    )
    center_df$group <- factor(center_df$group, levels = group_levels)

    p <- p + ggplot2::geom_line(data = center_df,
                                ggplot2::aes(x = group, y = value,
                                             group = cluster),
                                color = "#e74c3c", linewidth = 1.2)
  }

  return(p)
}


#' 绘制聚类中心对比图
#'
#' @description 将所有聚类中心绘制在同一图中，比较不同聚类的表达模式。
#'
#' @param cluster_result \code{cluster_protein_profiles()} 的返回结果。
#'
#' @return ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_cluster_centers(cluster_result)
#' }
#'
#' @export
plot_cluster_centers <- function(cluster_result) {
  centers <- cluster_result$centers
  group_levels <- colnames(cluster_result$group_means)

  plot_df <- data.frame(
    cluster = rep(rownames(centers), each = ncol(centers)),
    group = rep(group_levels, nrow(centers)),
    value = as.vector(t(centers)),
    stringsAsFactors = FALSE
  )
  plot_df$group <- factor(plot_df$group, levels = group_levels)

  cluster_colors <- make_group_colors(rownames(centers))

  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = group, y = value,
                                              color = cluster,
                                              group = cluster)) +
    ggplot2::geom_line(linewidth = 1) +
    ggplot2::geom_point(size = 2) +
    ggplot2::scale_color_manual(values = cluster_colors, name = "Cluster") +
    ggplot2::labs(
      title = "Cluster Centers Comparison",
      x = NULL,
      y = "Expression (z-score)"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 9),
      legend.position = "right"
    )

  return(p)
}
