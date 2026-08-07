# ==============================================================================
# OmicsFlow: 基于 bnlearn 的贝叶斯网络
# ==============================================================================
# 时间序列调控网络构建
# ==============================================================================

#' 使用 bnlearn 构建贝叶斯网络
#'
#' @description 从时间序列或多条件组学数据构建贝叶斯网络模型，以推断Feature之间的
#'   调控关系。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。对于时间序列，列应按时间顺序排列。
#' @param time_points 可选的时间点数值向量。若为 NULL，则使用样本顺序。默认：NULL。
#' @param feature_info 可选的Feature注释数据框，用于节点标签。
#' @param name_col feature_info 中用于节点名称的列。默认："name"。
#' @param algorithm 学习算法："hc"（爬山法）、"tabu"、"gs"
#'   （grow-shrink 生长-收缩）。默认："hc"。
#' @param score 结构学习的评分函数。默认："bic"。
#' @param max_nodes 包含的最大节点数（出于性能考虑）。默认：50。
#' @param seed 随机种子。默认：42。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{network}：bnlearn 网络对象。
#'     \item \code{arcs}：有向边数据框。
#'     \item \code{nodes}：节点名称的字符向量。
#'     \item \code{adjacency}：邻接矩阵。
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

  # 若Feature过多，则挑选变异最大的前若干个
  mat <- as.matrix(expr_matrix)
  if (nrow(mat) > max_nodes) {
    row_vars <- apply(mat, 1, stats::var, na.rm = TRUE)
    top_idx <- order(row_vars, decreasing = TRUE)[1:max_nodes]
    mat <- mat[top_idx, , drop = FALSE]
  }

  # 用Feature名替换Feature ID
  if (!is.null(feature_info) && name_col %in% colnames(feature_info)) {
    feature_names <- feature_info[match(rownames(mat), rownames(feature_info)), name_col]
    feature_names[is.na(feature_names)] <- rownames(mat)
    # Make unique
    feature_names <- make.unique(feature_names)
    rownames(mat) <- feature_names
  }

  # 必要时进行离散化（部分算法要求 bnlearn 使用离散数据）
  # 使用分位数离散化
  mat_disc <- t(apply(mat, 1, function(x) {
    if (stats::sd(x, na.rm = TRUE) == 0) return(rep(1, length(x)))
    cuts <- stats::quantile(x, probs = c(0.33, 0.67), na.rm = TRUE)
    cut(x, breaks = c(-Inf, cuts[1], cuts[2], Inf), labels = FALSE)
  }))

  # 为 bnlearn 创建数据框
  bn_data <- as.data.frame(t(mat_disc))
  for (col in colnames(bn_data)) {
    bn_data[[col]] <- as.factor(bn_data[[col]])
  }

  # 学习结构
  if (algorithm == "hc") {
    bn <- bnlearn::hc(bn_data, score = score)
  } else if (algorithm == "tabu") {
    bn <- bnlearn::tabu(bn_data, score = score)
  } else if (algorithm == "gs") {
    bn <- bnlearn::gs(bn_data)
  } else {
    bn <- bnlearn::hc(bn_data, score = score)
  }

  # 提取有向边
  arcs_df <- bnlearn::arcs(bn)

  # 构建邻接矩阵
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


#' 绘制贝叶斯网络
#'
#' @description 创建贝叶斯网络结构的可视化图形。
#'
#' @param bn_result 来自 \code{run_bnlearn()} 的结果。
#'
#' @return 一个 ggplot 对象。
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

  # 简单的环形布局
  n_nodes <- length(nodes)
  angles <- seq(0, 2 * pi, length.out = n_nodes + 1)[1:n_nodes]
  node_pos <- data.frame(
    node = nodes,
    x = cos(angles),
    y = sin(angles),
    stringsAsFactors = FALSE
  )

  # 边数据
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
