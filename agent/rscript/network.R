#' @title Build Dynamic Bayesian Network with bnlearn
#'
#' @description
#' 对于时间序列数据，使用bnlearn包构建动态贝叶斯调控网络。该函数
#' 通过结构学习算法（如hc - Hill Climbing）从数据中推断feature之间
#' 的调控关系，构建有向无环图（DAG）。
#'
#' 动态网络通过将时间点t-1的feature作为父节点，时间点t的feature
#' 作为子节点，建模时间序列的因果调控关系。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param time_points 数值向量，每个样本对应的时间点
#' @param algorithm 字符串，结构学习算法，"hc"、"tabu"、"gs"等，默认"hc"
#' @param discretize 逻辑值，是否离散化数据，默认FALSE
#' @param n_bins 整数，离散化时的分箱数，默认4
#' @param whitelist 数据框，必须包含的边（可选）
#' @param blacklist 数据框，必须排除的边（可选）
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item network: bnlearn网络对象
#'   \item arcs: 网络中的边（data.frame）
#'   \item nodes: 网络中的节点
#'   \item score: 网络得分
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' time_points <- c(0, 0, 1, 1, 2, 2, 4, 4)  # 时间点
#'
#' bn_result <- build_bnlearn_network(expr, time_points, algorithm = "hc")
#' }
#'
#' @export
build_bnlearn_network <- function(expr_matrix, time_points,
                                  algorithm = "hc", discretize = FALSE,
                                  n_bins = 4, whitelist = NULL,
                                  blacklist = NULL) {
  if (!requireNamespace("bnlearn", quietly = TRUE)) {
    stop("Package 'bnlearn' is required. Please install it.")
  }

  # Build dynamic network data: combine t-1 and t features
  unique_times <- sort(unique(time_points))
  if (length(unique_times) < 2) {
    stop("At least 2 time points are required for dynamic network.")
  }

  # For each consecutive time pair, build lagged data
  lagged_data_list <- list()
  for (i in seq_len(length(unique_times) - 1)) {
    t_prev <- unique_times[i]
    t_curr <- unique_times[i + 1]

    samples_prev <- colnames(expr_matrix)[time_points == t_prev]
    samples_curr <- colnames(expr_matrix)[time_points == t_curr]

    if (length(samples_prev) == 0 || length(samples_curr) == 0) next

    # Average across replicates
    expr_prev <- rowMeans(expr_matrix[, samples_prev, drop = FALSE], na.rm = TRUE)
    expr_curr <- rowMeans(expr_matrix[, samples_curr, drop = FALSE], na.rm = TRUE)

    lagged_df <- data.frame(
      expr_prev,
      expr_curr
    )
    colnames(lagged_df) <- c(paste0(rownames(expr_matrix), "_t0"),
                             paste0(rownames(expr_matrix), "_t1"))
    lagged_data_list[[i]] <- lagged_df
  }

  lagged_data <- do.call(cbind, lagged_data_list)
  lagged_data <- lagged_data[, !duplicated(colnames(lagged_data))]

  # Discretize if requested
  if (discretize) {
    lagged_data <- as.data.frame(
      sapply(lagged_data, function(x) {
        cut(x, breaks = n_bins, labels = paste0("L", 1:n_bins),
            include.lowest = TRUE)
      })
    )
  }

  # Build blacklist to prevent edges from t1 to t0
  features_t0 <- grep("_t0$", colnames(lagged_data), value = TRUE)
  features_t1 <- grep("_t1$", colnames(lagged_data), value = TRUE)

  bl_from <- rep(features_t1, each = length(features_t0))
  bl_to <- rep(features_t0, length(features_t1))
  dynamic_blacklist <- data.frame(from = bl_from, to = bl_to)

  if (!is.null(blacklist)) {
    dynamic_blacklist <- rbind(dynamic_blacklist, blacklist)
  }

  # Structure learning
  fit <- bnlearn::hc(lagged_data, blacklist = dynamic_blacklist,
                     whitelist = whitelist)

  # Extract arcs
  arcs_df <- bnlearn::arcs(fit)

  result <- list(
    network = fit,
    arcs = arcs_df,
    nodes = bnlearn::nodes(fit),
    score = bnlearn::score(fit, lagged_data),
    data = lagged_data
  )

  message("bnlearn network built with ", nrow(arcs_df), " edges and ",
          length(result$nodes), " nodes.")
  return(result)
}


#' @title Plot Bayesian Network
#'
#' @description
#' 绘制贝叶斯调控网络图，展示feature之间的调控关系。节点代表feature，
#' 有向边代表调控关系（从父节点指向子节点）。
#'
#' @param bn_result 列表，由build_bnlearn_network返回
#' @param feature_anno 数据框，feature注释信息（可选，用于显示feature name）
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认12
#' @param height 数值，图片高度（英寸），默认10
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' plot_bn_network(bn_result, feature_anno, output_dir = "./figures")
#' }
#'
#' @export
plot_bn_network <- function(bn_result, feature_anno = NULL,
                            output_dir = ".", width = 12, height = 10) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  if (!requireNamespace("igraph", quietly = TRUE)) {
    stop("Package 'igraph' is required for network plotting.")
  }

  arcs_df <- bn_result$arcs
  if (nrow(arcs_df) == 0) {
    warning("No edges in the network.")
    return(invisible(NULL))
  }

  # Build igraph object
  g <- igraph::graph_from_data_frame(arcs_df, directed = TRUE)

  # Get layout
  layout_mat <- igraph::layout_with_fr(g)

  # Build node data frame
  node_df <- data.frame(
    Node = igraph::V(g)$name,
    x = layout_mat[, 1],
    y = layout_mat[, 2]
  )

  # Add feature names if available
  if (!is.null(feature_anno)) {
    node_df$Label <- sapply(node_df$Node, function(n) {
      feat_id <- sub("_(t0|t1)$", "", n)
      name <- feature_anno$name[feature_anno$ID == feat_id]
      if (length(name) > 0 && !is.na(name[1])) {
        return(paste0(name[1], " (", n, ")"))
      } else {
        return(n)
      }
    })
  } else {
    node_df$Label <- node_df$Node
  }

  # Build edge data frame
  edge_df <- do.call(rbind, lapply(seq_len(nrow(arcs_df)), function(i) {
    from_node <- arcs_df$from[i]
    to_node <- arcs_df$to[i]
    from_coords <- node_df[node_df$Node == from_node, c("x", "y")]
    to_coords <- node_df[node_df$Node == to_node, c("x", "y")]
    data.frame(x = from_coords$x, y = from_coords$y,
               xend = to_coords$x, yend = to_coords$y)
  }))

  p <- ggplot2::ggplot() +
    ggplot2::geom_segment(data = edge_df,
                          ggplot2::aes(x = x, y = y, xend = xend, yend = yend),
                          arrow = grid::arrow(length = grid::unit(0.15, "inches")),
                          color = "grey50", alpha = 0.6) +
    ggplot2::geom_point(data = node_df, ggplot2::aes(x = x, y = y),
                        color = "steelblue", size = 4) +
    ggrepel::geom_text_repel(data = node_df,
                              ggplot2::aes(x = x, y = y, label = Label),
                              size = 3, max.overlaps = 50) +
    ggplot2::labs(
      title = "Dynamic Bayesian Regulatory Network",
      x = "", y = ""
    ) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold")
    )

  pdf_file <- file.path(output_dir, "BN_network.pdf")
  png_file <- file.path(output_dir, "BN_network.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("Bayesian network plot saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}


#' @title Perform PLS-PM (Partial Least Squares Path Modeling)
#'
#' @description
#' 对于多组学或单组学数据，使用PLS-PM（偏最小二乘路径建模）构建潜变量
#' 之间的调控网络。可以以family或者kegg通路作为潜变量，计算潜变量
#' 之间的因果调控关系。
#'
#' PLS-PM通过将相关feature聚合为潜变量（latent variable），建模潜变量
#' 之间的有向因果关系，适用于多组学数据整合分析。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param sample_meta 数据框，样本元数据
#' @param feature_anno 数据框，feature注释信息
#' @param latent_var_col 字符串，用于构建潜变量的列名（如"family"或"kegg"）
#' @param path_matrix 矩阵，路径矩阵定义潜变量之间的因果关系（可选）
#' @param modes 字符向量，每个潜变量的模式，"A"（反映型）或"B"（形成型）
#' @param ncomp 整数，每个潜变量的成分数，默认2
#'
#' @return 返回一个列表，包含：
#' \itemize{
#'   \item plspm: plspm结果对象
#'   \item latent_scores: 潜变量得分
#'   \item path_coefficients: 路径系数
#'   \item inner_model: 内模型
#'   \item outer_model: 外模型
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' meta <- load_sample_metadata("meta.csv")
#' anno <- load_feature_annotation("anno.csv")
#'
#' # 使用family作为潜变量
#' result <- perform_plspm(expr, meta, anno, latent_var_col = "family")
#' }
#'
#' @export
perform_plspm <- function(expr_matrix, sample_meta, feature_anno,
                         latent_var_col, path_matrix = NULL,
                         modes = "A", ncomp = 2) {
  if (!requireNamespace("plspm", quietly = TRUE)) {
    stop("Package 'plspm' is required. Please install it.")
  }

  # Build latent variable data
  if (!latent_var_col %in% colnames(feature_anno)) {
    stop("Column '", latent_var_col, "' not found in feature_anno.")
  }

  latent_groups <- as.character(feature_anno[[latent_var_col]])
  names(latent_groups) <- feature_anno$ID

  # Aggregate features by latent variable (mean)
  latent_data_list <- lapply(unique(latent_groups[!is.na(latent_groups)]),
                              function(lv) {
    features_in_lv <- names(latent_groups)[latent_groups == lv]
    features_in_lv <- intersect(features_in_lv, rownames(expr_matrix))
    if (length(features_in_lv) == 0) return(NULL)
    colMeans(expr_matrix[features_in_lv, , drop = FALSE], na.rm = TRUE)
  })
  names(latent_data_list) <- unique(latent_groups[!is.na(latent_groups)])
  latent_data_list <- latent_data_list[!sapply(latent_data_list, is.null)]

  latent_data <- as.data.frame(do.call(rbind, latent_data_list))
  latent_data <- t(latent_data)  # samples as rows

  latent_vars <- colnames(latent_data)
  n_vars <- length(latent_vars)

  # Build path matrix if not provided
  if (is.null(path_matrix)) {
    path_matrix <- matrix(0, nrow = n_vars, ncol = n_vars,
                          dimnames = list(latent_vars, latent_vars))
    # Default: chain structure
    for (i in seq_len(n_vars - 1)) {
      path_matrix[i, i + 1] <- 1
    }
  }

  # Run PLS-PM
  plspm_result <- plspm::plspm(latent_data, path_matrix,
                                modes = rep(modes, n_vars),
                                scaled = TRUE)

  result <- list(
    plspm = plspm_result,
    latent_scores = plspm_result$scores,
    path_coefficients = plspm_result$inner_model$path_coefs,
    inner_model = plspm_result$inner_model,
    outer_model = plspm_result$outer_model,
    latent_data = latent_data
  )

  message("PLS-PM completed with ", n_vars, " latent variables.")
  return(result)
}


#' @title Plot PLS-PM Path Diagram
#'
#' @description
#' 绘制PLS-PM路径图，展示潜变量之间的因果调控关系。节点代表潜变量，
#' 有向边代表路径系数，边的粗细和颜色表示路径系数大小和方向。
#'
#' @param plspm_result 列表，由perform_plspm返回
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认10
#' @param height 数值，图片高度（英寸），默认8
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' plot_plspm_path(plspm_result, output_dir = "./figures")
#' }
#'
#' @export
plot_plspm_path <- function(plspm_result, output_dir = ".",
                            width = 10, height = 8) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  if (!requireNamespace("igraph", quietly = TRUE)) {
    stop("Package 'igraph' is required for path diagram.")
  }

  path_coefs <- plspm_result$path_coefficients
  latent_vars <- rownames(path_coefs)

  # Build edge list
  edges_list <- list()
  for (i in seq_len(nrow(path_coefs))) {
    for (j in seq_len(ncol(path_coefs))) {
      if (path_coefs[i, j] != 0) {
        edges_list[[length(edges_list) + 1]] <- data.frame(
          from = rownames(path_coefs)[i],
          to = colnames(path_coefs)[j],
          weight = path_coefs[i, j]
        )
      }
    }
  }
  edges_df <- do.call(rbind, edges_list)

  if (is.null(edges_df) || nrow(edges_df) == 0) {
    warning("No significant paths found.")
    return(invisible(NULL))
  }

  # Build igraph
  g <- igraph::graph_from_data_frame(edges_df, directed = TRUE)
  layout_mat <- igraph::layout_in_circle(g)

  node_df <- data.frame(
    Node = igraph::V(g)$name,
    x = layout_mat[, 1],
    y = layout_mat[, 2]
  )

  edge_df <- do.call(rbind, lapply(seq_len(nrow(edges_df)), function(i) {
    from_node <- edges_df$from[i]
    to_node <- edges_df$to[i]
    from_coords <- node_df[node_df$Node == from_node, c("x", "y")]
    to_coords <- node_df[node_df$Node == to_node, c("x", "y")]
    data.frame(x = from_coords$x, y = from_coords$y,
               xend = to_coords$x, yend = to_coords$y,
               weight = edges_df$weight[i])
  }))

  p <- ggplot2::ggplot() +
    ggplot2::geom_segment(data = edge_df,
                          ggplot2::aes(x = x, y = y, xend = xend, yend = yend,
                                        linewidth = abs(weight),
                                        color = weight),
                          arrow = grid::arrow(length = grid::unit(0.15, "inches")),
                          alpha = 0.7) +
    ggplot2::scale_color_gradient2(low = "blue", mid = "grey80", high = "red",
                                    midpoint = 0, name = "Path Coefficient") +
    ggplot2::geom_point(data = node_df, ggplot2::aes(x = x, y = y),
                        color = "steelblue", size = 6) +
    ggrepel::geom_text_repel(data = node_df,
                              ggplot2::aes(x = x, y = y, label = Node),
                              size = 4, max.overlaps = 50) +
    ggplot2::labs(
      title = "PLS-PM Path Diagram",
      x = "", y = ""
    ) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold"),
      legend.position = "right"
    )

  pdf_file <- file.path(output_dir, "PLSPM_path_diagram.pdf")
  png_file <- file.path(output_dir, "PLSPM_path_diagram.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("PLS-PM path diagram saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}
