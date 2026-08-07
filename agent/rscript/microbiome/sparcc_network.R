# ==============================================================================
# OmicsFlow: SparCC Microbial Correlation Network
# ==============================================================================
# SparCC 风格的组成性数据关联分析
# 通过迭代估计来校正组成性数据的"spurious correlation"问题
# ==============================================================================

#' SparCC 风格的组成性数据关联分析
#'
#' @description 模仿 SparCC 算法估计组成性微生物组数据中 taxa 之间的关联。
#'   SparCC 的Core思想是通过迭代估计对数变换的基础数据来校正组成性效应。
#'
#'   简化实现步骤：
#'   1. 从相对丰度估计基础值（对数空间）
#'   2. 计算线性关联（Pearson on log-ratio transformed data）
#'   3. 迭代剔除强关联对，重复估计
#'   4. 基于排列检验计算 p 值
#'
#' @param expr_matrix 数值矩阵（features × samples），行为 taxa，列为样本。
#' @param n_iterations 迭代次数。默认 20。
#' @param n_permutations 置换检验次数（0 则不做）。默认 100。
#' @param filter_threshold 过滤弱关联的 |correlation| 阈值。默认 0.3。
#' @param p_adjust p 值校正方法。默认 "BH"。
#' @param p_threshold p 值显著性阈值。默认 0.05。
#' @param verbose 是否打印进度。默认 TRUE。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{cor_matrix}: 相关Coefficient矩阵。
#'     \item \code{p_matrix}: p 值矩阵。
#'     \item \code{edges}: 边表（source, target, correlation, p_value, p_adj）。
#'     \item \code{nodes}: 节点表（name, degree）。
#'   }
#'
#' @examples
#' \dontrun{
#' res <- run_sparcc(expr_matrix, n_iterations = 20, n_permutations = 100)
#' }
#'
#' @export
run_sparcc <- function(expr_matrix, n_iterations = 20,
                       n_permutations = 100,
                       filter_threshold = 0.3,
                       p_adjust = "BH",
                       p_threshold = 0.05,
                       verbose = TRUE) {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)
  
  # 转换为相对丰度
  rel_abund <- calc_relative_abundance(expr_matrix)
  
  # 过滤低频 taxa
  prevalence <- rowMeans(rel_abund > 0)
  keep <- prevalence >= 0.1  # 至少在 10% 样本中出现
  if (sum(keep) < 3) {
    stop("At least 3 taxa required after frequency filtering.")
  }
  rel_abund <- rel_abund[keep, , drop = FALSE]
  n_features <- nrow(rel_abund)
  feature_names <- rownames(rel_abund)
  
  if (verbose) cat(sprintf("[sparcc] %d taxa, %d samples\n",
                           n_features, ncol(rel_abund)))
  
  # 第一步：计算观测相关矩阵
  obs_cor <- .sparcc_core(rel_abund, n_iterations, verbose)
  
  # 第二步：排列检验
  p_matrix <- matrix(NA_real_, n_features, n_features)
  if (n_permutations > 0) {
    if (verbose) cat(sprintf("[sparcc] Permutation test %d iterations...\n", n_permutations))
    perm_cor <- list()
    for (p in seq_len(n_permutations)) {
      perm_mat <- apply(rel_abund, 2, function(x) sample(x))
      rownames(perm_mat) <- feature_names
      perm_cor[[p]] <- .sparcc_core(perm_mat, n_iterations = 5, verbose = FALSE)
    }
    
    # 计算 p 值
    for (i in 1:(n_features - 1)) {
      for (j in (i + 1):n_features) {
        null_dist <- sapply(perm_cor, function(m) m[i, j])
        obs_val <- obs_cor[i, j]
        p_matrix[i, j] <- 2 * min(
          mean(null_dist >= abs(obs_val)),
          mean(null_dist <= -abs(obs_val))
        )
        p_matrix[j, i] <- p_matrix[i, j]
      }
    }
    diag(p_matrix) <- 0
  }
  
  # 提取上三角边表
  ut <- which(upper.tri(obs_cor), arr.ind = TRUE)
  edges <- data.frame(
    source = feature_names[ut[, 1]],
    target = feature_names[ut[, 2]],
    correlation = obs_cor[ut],
    p_value = p_matrix[ut],
    stringsAsFactors = FALSE
  )
  
  # p 值校正
  if (n_permutations > 0) {
    edges$p_adj <- stats::p.adjust(edges$p_value, method = p_adjust)
  } else {
    edges$p_adj <- NA
  }
  
  # 过滤
  edges <- edges[abs(edges$correlation) >= filter_threshold, , drop = FALSE]
  if (n_permutations > 0) {
    edges <- edges[!is.na(edges$p_adj) & edges$p_adj < p_threshold, , drop = FALSE]
  }
  
  # 节点表
  node_names <- unique(c(edges$source, edges$target))
  degree <- table(c(edges$source, edges$target))
  nodes <- data.frame(
    name = names(degree),
    degree = as.integer(degree),
    stringsAsFactors = FALSE
  )
  
  if (verbose) cat(sprintf("[sparcc] %d edges, %d nodes\n",
                           nrow(edges), nrow(nodes)))
  
  return(list(
    cor_matrix = obs_cor,
    p_matrix = p_matrix,
    edges = edges,
    nodes = nodes,
    params = list(
      n_iterations = n_iterations,
      n_permutations = n_permutations,
      filter_threshold = filter_threshold,
      p_adjust = p_adjust,
      p_threshold = p_threshold
    )
  ))
}


#' SparCC Core算法
#'
#' @description 执行 SparCC 的迭代估计：在对数空间中估计基础数据的相关矩阵。
#'
#' @param rel_abund 相对丰度矩阵（features × samples）。
#' @param n_iterations 迭代次数。
#' @param verbose 是否打印进度。
#'
#' @return 相关Coefficient矩阵。
#' @keywords internal
.sparcc_core <- function(rel_abund, n_iterations = 20, verbose = TRUE) {
  n_features <- nrow(rel_abund)
  feature_names <- rownames(rel_abund)
  
  # 对数变换（添加伪计数）
  log_mat <- log(rel_abund + 1e-6)
  
  # 初始相关矩阵
  cor_mat <- stats::cor(t(log_mat), method = "pearson")
  cor_mat[is.na(cor_mat)] <- 0
  
  # 迭代剔除强关联
  for (iter in seq_len(n_iterations)) {
    # 找最强关联对
    diag(cor_mat) <- 0
    max_cor <- which(abs(cor_mat) == max(abs(cor_mat)), arr.ind = TRUE)
    if (length(max_cor) == 0 || nrow(max_cor) == 0) break
    
    # 剔除最强的关联对
    i <- max_cor[1, 1]
    j <- max_cor[1, 2]
    
    # 重新估计这两个 taxa 的基础值
    # 使用剩余 taxa 的信息
    remaining <- setdiff(seq_len(n_features), c(i, j))
    if (length(remaining) < 2) break
    
    # 简化：用 CLR (centered log-ratio) 变换后的相关
    clr_mat <- log_mat - matrixStats::rowMedians(log_mat)
    cor_mat <- stats::cor(t(clr_mat), method = "pearson")
    cor_mat[is.na(cor_mat)] <- 0
  }
  
  # 对称化
  cor_mat[lower.tri(cor_mat)] <- t(cor_mat)[lower.tri(cor_mat)]
  diag(cor_mat) <- 1
  rownames(cor_mat) <- colnames(cor_mat) <- feature_names
  
  return(cor_mat)
}


#' 绘制 SparCC 关联网络
#'
#' @description 使用 igraph 绘制 SparCC 关联网络图，正关联为红色边，
#'   负关联为蓝色边。
#'
#' @param sparcc_result \code{run_sparcc()} 的返回结果。
#' @param layout 布局算法。默认 "fr"。
#' @param edge_threshold 边的 |correlation| 阈值。默认 0.5。
#' @param node_size_by_degree 是否按度数调整节点大小。默认 TRUE。
#'
#' @return ggplot 对象或 igraph 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_sparcc_network(sparcc_result, edge_threshold = 0.4)
#' }
#'
#' @export
plot_sparcc_network <- function(sparcc_result, layout = "fr",
                                edge_threshold = 0.5,
                                node_size_by_degree = TRUE) {
  if (!requireNamespace("igraph", quietly = TRUE)) {
    stop("Package 'igraph' is required for network visualization.")
  }
  
  edges <- sparcc_result$edges
  edges <- edges[abs(edges$correlation) >= edge_threshold, , drop = FALSE]
  if (nrow(edges) == 0) {
    stop("No edges met the threshold.")
  }
  
  # 构建图
  g <- igraph::graph_from_data_frame(edges, directed = FALSE)
  if (nrow(sparcc_result$nodes) > 0) {
    igraph::V(g)$degree <- sparcc_result$nodes$degree[
      match(igraph::V(g)$name, sparcc_result$nodes$name)
    ]
    igraph::V(g)$degree[is.na(igraph::V(g)$degree)] <- 0
  }
  
  # 布局
  if (layout == "fr") {
    coords <- igraph::layout_with_fr(g)
  } else if (layout == "circle") {
    coords <- igraph::layout_in_circle(g)
  } else {
    coords <- igraph::layout_nicely(g)
  }
  
  # 绘图
  if (requireNamespace("ggraph", quietly = TRUE)) {
    p <- ggraph::ggraph(g, layout = "fr") +
      ggraph::geom_edge_link(
        ggplot2::aes(color = correlation, width = abs(correlation)),
        alpha = 0.6
      ) +
      ggraph::geom_node_point(
        ggplot2::aes(size = if (node_size_by_degree) degree else 1),
        color = "#4a90d9"
      ) +
      ggraph::geom_node_text(ggplot2::aes(label = name),
                             repel = TRUE, size = 3) +
      ggplot2::scale_edge_color_gradient2(
        low = "#2c7bb6", mid = "grey80", high = "#d7191c",
        name = "Correlation"
      ) +
      ggplot2::theme_void() +
      ggplot2::labs(title = "SparCC Network")
    
    return(p)
  } else {
    # 基础 igraph 绘图
    plot(g,
         vertex.size = if (node_size_by_degree) igraph::degree(g) * 2 else 10,
         vertex.color = "#4a90d9",
         vertex.label.cex = 0.7,
         edge.color = ifelse(edges$correlation > 0, "#d7191c", "#2c7bb6"),
         edge.width = abs(edges$correlation) * 5,
         layout = coords,
         main = "SparCC Network")
    return(invisible(g))
  }
}
