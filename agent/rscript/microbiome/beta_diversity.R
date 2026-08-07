# ==============================================================================
# OmicsFlow: Beta Diversity Analysis
# ==============================================================================
# 计算β多样性距离矩阵（Bray-Curtis, Jaccard, Sørensen 等），进行
# PCoA/NMDS 排序分析和 PERMANOVA (adonis2) 统计检验
# ==============================================================================

#' 计算样本间β多样性距离矩阵
#'
#' @description 计算样本间的β多样性距离。支持 Bray-Curtis（丰度型）
#'   和 Jaccard/Sørensen（有无型）距离。输入可以是绝对计数或相对丰度矩阵。
#'
#' @param expr_matrix 数值矩阵（features × samples），行为 taxa，列为样本。
#' @param method 距离方法，可选 "bray"、"jaccard"、"sorensen"、"euclidean"。
#'   默认 "bray"。
#' @param method_type 数据类型，"count" 使用绝对计数，"abundance" 使用相对丰度。
#'   默认 "count"。
#'
#' @return dist 对象。
#'
#' @examples
#' \dontrun{
#' dist_mat <- calc_beta_diversity(expr_matrix, method = "bray")
#' }
#'
#' @export
calc_beta_diversity <- function(expr_matrix, method = "bray",
                                method_type = "count") {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)
  method <- match.arg(method, c("bray", "jaccard", "sorensen", "euclidean"))
  
  # 转置：样本 × features
  mat_t <- t(expr_matrix)
  
  if (method == "bray") {
    # 如果有负值（标准化后），先平移
    if (any(mat_t < 0, na.rm = TRUE)) {
      mat_t <- mat_t - min(mat_t, na.rm = TRUE)
    }
    if (method_type == "abundance") {
      mat_t <- mat_t * 1e5  # 放大相对丰度
    }
    if (requireNamespace("vegan", quietly = TRUE)) {
      return(vegan::vegdist(mat_t, method = "bray"))
    } else {
      # 手动实现 Bray-Curtis
      return(.bray_curtis_manual(mat_t))
    }
  } else if (method == "jaccard") {
    # 二值化
    mat_bin <- ifelse(mat_t > 0, 1, 0)
    return(.jaccard_manual(mat_bin))
  } else if (method == "sorensen") {
    mat_bin <- ifelse(mat_t > 0, 1, 0)
    return(.sorensen_manual(mat_bin))
  } else {
    return(stats::dist(mat_t, method = "euclidean"))
  }
}


#' Bray-Curtis 距离手动实现（不依赖 vegan）
#'
#' @param mat 样本 × features 数值矩阵。
#' @return dist 对象。
#' @keywords internal
.bray_curtis_manual <- function(mat) {
  n <- nrow(mat)
  d <- matrix(0, n, n)
  for (i in 1:(n - 1)) {
    for (j in (i + 1):n) {
      d[i, j] <- sum(abs(mat[i, ] - mat[j, ])) / sum(mat[i, ] + mat[j, ])
    }
  }
  d[is.na(d)] <- 0
  d <- d + t(d)
  rownames(d) <- colnames(d) <- rownames(mat)
  return(stats::as.dist(d))
}


#' Jaccard 距离手动实现
#'
#' @param mat_bin 二值样本 × features 矩阵。
#' @return dist 对象。
#' @keywords internal
.jaccard_manual <- function(mat_bin) {
  n <- nrow(mat_bin)
  d <- matrix(0, n, n)
  for (i in 1:(n - 1)) {
    for (j in (i + 1):n) {
      a <- mat_bin[i, ]
      b <- mat_bin[j, ]
      intersection <- sum(a & b)
      union <- sum(a | b)
      d[i, j] <- if (union > 0) 1 - intersection / union else 0
    }
  }
  d <- d + t(d)
  rownames(d) <- colnames(d) <- rownames(mat_bin)
  return(stats::as.dist(d))
}


#' Sørensen 距离手动实现
#'
#' @param mat_bin 二值样本 × features 矩阵。
#' @return dist 对象。
#' @keywords internal
.sorensen_manual <- function(mat_bin) {
  n <- nrow(mat_bin)
  d <- matrix(0, n, n)
  for (i in 1:(n - 1)) {
    for (j in (i + 1):n) {
      a <- mat_bin[i, ]
      b <- mat_bin[j, ]
      intersection <- sum(a & b)
      union_sum <- sum(a) + sum(b)
      d[i, j] <- if (union_sum > 0) 1 - 2 * intersection / union_sum else 0
    }
  }
  d <- d + t(d)
  rownames(d) <- colnames(d) <- rownames(mat_bin)
  return(stats::as.dist(d))
}


#' PERMANOVA 检验
#'
#' @description 使用 vegan::adonis2 进行 PERMANOVA 检验，评估组间差异的
#'   显著性。需要安装 vegan 包。
#'
#' @param dist_mat 距离矩阵（dist 对象）。
#' @param sample_info 样本元数据 data.frame。
#' @param group_col 分组列名。默认 "sample_info"。
#' @param permutations 置换次数。默认 999。
#' @param strata_col 分层变量列名（如位置/批次），用于控制置换范围。默认 NULL。
#'
#' @return adonis2 结果对象。
#'
#' @examples
#' \dontrun{
#' res <- run_permanova(dist_mat, sample_info, group_col = "sample_info")
#' }
#'
#' @export
run_permanova <- function(dist_mat, sample_info,
                          group_col = "sample_info",
                          permutations = 999,
                          strata_col = NULL) {
  if (!requireNamespace("vegan", quietly = TRUE)) {
    stop("Package 'vegan' is required for PERMANOVA. ",
         "Install it with install.packages('vegan').")
  }
  
  common <- intersect(attr(dist_mat, "Labels"), rownames(sample_info))
  if (length(common) < 4) {
    stop("At least 4 shared samples are required.")
  }
  
  dist_mat <- as.dist(as.matrix(dist_mat)[common, common])
  sub_info <- sample_info[common, , drop = FALSE]
  
  # 构建公式
  if (!is.null(strata_col) && strata_col %in% colnames(sub_info)) {
    strata <- sub_info[[strata_col]]
    res <- vegan::adonis2(dist_mat ~ sub_info[[group_col]],
                          permutations = permutations, strata = strata)
  } else {
    res <- vegan::adonis2(dist_mat ~ sub_info[[group_col]],
                          permutations = permutations)
  }
  
  cat(sprintf("[permanova] %s: R2 = %.3f, F = %.2f, p = %.3f\n",
              group_col, res$R2[1], res$F[1], res$`Pr(>F)`[1]))
  return(res)
}


#' PCoA 排序分析
#'
#' @description 对距离矩阵进行主坐标分析（PCoA），返回坐标和方差解释率。
#'
#' @param dist_mat 距离矩阵（dist 对象）。
#' @param ncomp 保留的坐标轴数。默认 2。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{points}: 样本坐标矩阵（samples × ncomp）。
#'     \item \code{variance_explained}: 各轴方差解释率。
#'     \item \code{eigenvalues}: Feature值。
#'   }
#'
#' @examples
#' \dontrun{
#' pcoa_res <- run_pcoa(dist_mat, ncomp = 2)
#' }
#'
#' @export
run_pcoa <- function(dist_mat, ncomp = 2) {
  dist_mat <- as.dist(dist_mat)
  
  # 处理负Feature值（对欧氏距离不会出现，但 Bray-Curtis 可能）
  pcoa <- stats::cmdscale(dist_mat, k = ncomp, eig = TRUE)
  
  # 计算方差解释率
  eig <- pcoa$eig
  eig_pos <- eig[eig > 0]
  var_explained <- eig_pos / sum(eig_pos) * 100
  
  n_axes <- min(ncomp, ncol(pcoa$points))
  var_explained <- var_explained[1:n_axes]
  
  points <- pcoa$points[, 1:n_axes, drop = FALSE]
  colnames(points) <- paste0("PCoA", 1:n_axes)
  
  return(list(
    points = points,
    variance_explained = var_explained,
    eigenvalues = eig
  ))
}


#' NMDS 排序分析
#'
#' @description 对距离矩阵进行非度量多维尺度分析（NMDS）。
#'
#' @param dist_mat 距离矩阵（dist 对象）。
#' @param ncomp 维度数。默认 2。
#' @param maxit 最大迭代次数。默认 500。
#' @param try_n 尝试次数。默认 20。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{points}: 样本坐标矩阵。
#'     \item \code{stress}: 应力值。
#'   }
#'
#' @examples
#' \dontrun{
#' nmds_res <- run_nmds(dist_mat, ncomp = 2)
#' }
#'
#' @export
run_nmds <- function(dist_mat, ncomp = 2, maxit = 500, try_n = 20) {
  if (!requireNamespace("vegan", quietly = TRUE)) {
    stop("Package 'vegan' is required for NMDS. ",
         "Install it with install.packages('vegan').")
  }
  
  dist_mat <- as.dist(dist_mat)
  nmds <- vegan::metaMDS(dist_mat, k = ncomp, trace = 0,
                         maxit = maxit, try = try_n)
  
  points <- nmds$points
  colnames(points) <- paste0("NMDS", 1:ncomp)
  
  cat(sprintf("[nmds] Stress = %.4f\n", nmds$stress))
  
  return(list(
    points = points,
    stress = nmds$stress
  ))
}


#' 绘制 PCoA/NMDS 排序图
#'
#' @description 绘制样本排序图（PCoA 或 NMDS），支持按分组着色和形状。
#'
#' @param ordination_result \code{run_pcoa()} 或 \code{run_nmds()} 的返回结果。
#' @param sample_info 样本元数据 data.frame。
#' @param group_col 分组列名（着色）。默认 "sample_info"。
#' @param shape_col 形状分组列名（可选）。默认 NULL。
#' @param color_by 样本子集着色逻辑（可选）。默认 NULL。
#' @param title 图标题。默认 "PCoA"。
#' @param show_ellipses 是否绘制 68% 置信椭圆。默认 TRUE。
#' @param show_centroids 是否标记各组中心。默认 FALSE。
#'
#' @return ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_ordination(pcoa_res, sample_info, group_col = "sample_info")
#' }
#'
#' @export
plot_ordination <- function(ordination_result, sample_info,
                            group_col = "sample_info",
                            shape_col = NULL,
                            title = "PCoA",
                            show_ellipses = TRUE,
                            show_centroids = FALSE) {
  points <- ordination_result$points
  common <- intersect(rownames(points), rownames(sample_info))
  if (length(common) == 0) {
    stop("Sample names do not match.")
  }
  
  points <- points[common, , drop = FALSE]
  sub_info <- sample_info[common, , drop = FALSE]
  
  plot_df <- data.frame(
    axis1 = points[, 1],
    axis2 = points[, 2],
    group = sub_info[[group_col]],
    stringsAsFactors = FALSE
  )
  rownames(plot_df) <- common
  
  if (!is.null(shape_col) && shape_col %in% colnames(sub_info)) {
    plot_df$shape <- sub_info[[shape_col]]
  }
  
  group_colors <- make_group_colors(unique(plot_df$group))
  
  # 方差解释率（仅 PCoA）
  var_label <- ""
  if (!is.null(ordination_result$variance_explained)) {
    ve <- ordination_result$variance_explained
    var_label <- sprintf(" (%.1f%% / %.1f%%)", ve[1], ve[2])
  }
  
  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = axis1, y = axis2,
                                             color = group)) +
    ggplot2::geom_point(size = 3, alpha = 0.7)
  
  if (!is.null(shape_col) && "shape" %in% colnames(plot_df)) {
    p <- p + ggplot2::geom_point(ggplot2::aes(shape = shape), size = 3, alpha = 0.7)
    n_shapes <- length(unique(plot_df$shape))
    p <- p + ggplot2::scale_shape_manual(values = 0:(n_shapes - 1) %% 25 + 1)
  }
  
  p <- p +
    ggplot2::scale_color_manual(values = group_colors) +
    ggplot2::labs(
      title = title,
      x = paste0("Axis 1", var_label),
      y = paste0("Axis 2")
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 10),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right"
    )
  
  # 置信椭圆
  if (isTRUE(show_ellipses)) {
    p <- p + ggplot2::stat_ellipse(ggplot2::aes(group = group),
                                   type = "t", level = 0.68,
                                   show.legend = FALSE)
  }
  
  # 各组中心
  if (isTRUE(show_centroids)) {
    centroids <- stats::aggregate(plot_df[, c("axis1", "axis2")],
                                  list(group = plot_df$group), mean)
    p <- p + ggplot2::geom_point(data = centroids,
                                 ggplot2::aes(x = axis1, y = axis2),
                                 size = 5, shape = 3, stroke = 1.5)
  }
  
  return(p)
}
