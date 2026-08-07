# ==============================================================================
# OmicsFlow: Protein-Protein Interaction (PPI) Network
# ==============================================================================
# 蛋白质-蛋白质相互作用网络分析
# 通过 STRING 数据库 API 查询 PPI，构建网络并分析拓扑Feature
# ==============================================================================

#' 从 STRING 数据库查询 PPI 网络
#'
#' @description 通过 STRING 数据库 API 查询给定蛋白质列表的 PPI 网络。
#'   返回边表和节点表，可用于后续网络分析。
#'
#' @param protein_ids 蛋白质 ID 向量（建议使用 UniProt ID 或基因符号）。
#' @param species 物种。默认 9606 (Homo sapiens)。
#'   烟草为 4097 (Nicotiana tabacum)。
#' @param score_threshold STRING score 阈值（0-1000）。默认 400。
#' @param network_type 网络类型，"functional" 或 "physical"。默认 "functional"。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{edges}: 边表 (source, target, score)。
#'     \item \code{nodes}: 节点表 (id, degree)。
#'     \item \code{string_ids}: STRING ID 映射。
#'   }
#'
#' @examples
#' \dontrun{
#' ppi <- query_string_ppi(c("TP53", "MDM2", "BRCA1"), species = 9606)
#' }
#'
#' @export
query_string_ppi <- function(protein_ids, species = 9606,
                             score_threshold = 400,
                             network_type = "functional") {
  if (!requireNamespace("httr", quietly = TRUE)) {
    stop("Package 'httr' is required for STRING API queries.")
  }

  base_url <- "https://string-db.org/api"
  output_format <- "tsv"

  # Step 1: 映射蛋白 ID 到 STRING ID
  map_url <- paste0(base_url, "/get_string_ids/", output_format)
  map_body <- list(
    identifiers = paste(protein_ids, collapse = "\n"),
    species = species,
    limit = 5
  )

  map_resp <- httr::POST(map_url, body = map_body, encode = "form")
  httr::stop_for_status(map_resp)
  map_data <- httr::content(map_resp, as = "text", encoding = "UTF-8")
  map_df <- tryCatch(
    utils::read.delim(text = map_data, stringsAsFactors = FALSE),
    error = function(e) {
      cat(sprintf("[ppi] STRING ID mapping failed: %s\n", conditionMessage(e)))
      return(data.frame())
    }
  )

  if (nrow(map_df) == 0) {
    warning("No matching STRING IDs found. Check protein_ids and species.")
    return(list(edges = data.frame(), nodes = data.frame(),
                string_ids = data.frame()))
  }

  string_ids <- unique(map_df$stringId)
  cat(sprintf("[ppi] %d proteins mapped to %d STRING IDs\n",
              length(protein_ids), length(string_ids)))

  # Step 2: 查询 PPI 边
  net_url <- paste0(base_url, "/network/", output_format)
  net_body <- list(
    identifiers = paste(string_ids, collapse = "%0d"),
    species = species,
    required_score = score_threshold,
    network_type = network_type
  )

  net_resp <- httr::POST(net_url, body = net_body, encode = "form")
  httr::stop_for_status(net_resp)
  net_data <- httr::content(net_resp, as = "text", encoding = "UTF-8")
  edges <- tryCatch(
    utils::read.delim(text = net_data, stringsAsFactors = FALSE),
    error = function(e) {
      cat(sprintf("[ppi] PPI network query failed: %s\n", conditionMessage(e)))
      return(data.frame())
    }
  )

  if (nrow(edges) == 0) {
    warning("No PPI edges found. Score threshold may be too high or species data insufficient.")
    return(list(edges = data.frame(), nodes = data.frame(),
                string_ids = map_df))
  }

  # 清理边表
  edge_cols <- c("stringId_A" = "source", "stringId_B" = "target",
                 "score" = "score")
  edges <- edges[, intersect(names(edge_cols), colnames(edges))]
  colnames(edges)[match(names(edge_cols), colnames(edges))] <- edge_cols

  # 节点表
  node_names <- unique(c(edges$source, edges$target))
  degree <- table(c(edges$source, edges$target))
  nodes <- data.frame(
    id = names(degree),
    degree = as.integer(degree),
    stringsAsFactors = FALSE
  )

  cat(sprintf("[ppi] %d nodes, %d edges\n", nrow(nodes), nrow(edges)))

  return(list(
    edges = edges,
    nodes = nodes,
    string_ids = map_df,
    params = list(
      species = species,
      score_threshold = score_threshold,
      network_type = network_type
    )
  ))
}


#' 构建 PPI 网络（无 API 调用版本）
#'
#' @description 基于本地数据构建 PPI 网络。当无法访问 STRING API 时，
#'   可以使用已知的 PPI 数据或基于共表达推断 PPI。
#'
#' @param expr_matrix 数值矩阵（features × samples），行为蛋白质。
#' @param protein_ids 需要分析的蛋白质 ID 向量。默认使用矩阵所有行。
#' @param cor_method 相关方法。默认 "pearson"。
#' @param cor_threshold 相关Coefficient阈值。默认 0.7。
#' @param p_adjust p 值校正方法。默认 "BH"。
#' @param p_threshold p 值阈值。默认 0.01。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{edges}: 边表。
#'     \item \code{nodes}: 节点表。
#'     \item \code{cor_matrix}: 相关Coefficient矩阵。
#'   }
#'
#' @examples
#' \dontrun{
#' ppi <- build_local_ppi(expr_matrix, cor_threshold = 0.8)
#' }
#'
#' @export
build_local_ppi <- function(expr_matrix, protein_ids = NULL,
                           cor_method = "pearson",
                           cor_threshold = 0.7,
                           p_adjust = "BH",
                           p_threshold = 0.01) {
  if (!is.matrix(expr_matrix)) expr_matrix <- as.matrix(expr_matrix)

  if (!is.null(protein_ids)) {
    protein_ids <- intersect(protein_ids, rownames(expr_matrix))
    expr_matrix <- expr_matrix[protein_ids, , drop = FALSE]
  }

  n_proteins <- nrow(expr_matrix)
  if (n_proteins < 2) stop("At least 2 proteins are required.")

  # 计算相关矩阵
  cor_mat <- stats::cor(t(expr_matrix), method = cor_method,
                        use = "pairwise.complete.obs")

  # 计算 p 值矩阵
  n <- ncol(expr_matrix)
  p_mat <- matrix(NA_real_, n_proteins, n_proteins)
  ut <- which(upper.tri(cor_mat), arr.ind = TRUE)
  for (k in seq_len(nrow(ut))) {
    i <- ut[k, 1]
    j <- ut[k, 2]
    r <- cor_mat[i, j]
    if (is.na(r)) next
    t_stat <- r * sqrt(n - 2) / sqrt(1 - r^2)
    p_mat[i, j] <- 2 * stats::pt(-abs(t_stat), df = n - 2)
    p_mat[j, i] <- p_mat[i, j]
  }

  # 提取边
  edges <- data.frame(
    source = rownames(cor_mat)[ut[, 1]],
    target = rownames(cor_mat)[ut[, 2]],
    correlation = cor_mat[ut],
    p_value = p_mat[ut],
    stringsAsFactors = FALSE
  )
  edges$p_adj <- stats::p.adjust(edges$p_value, method = p_adjust)

  # 过滤
  edges <- edges[!is.na(edges$correlation) &
                  abs(edges$correlation) >= cor_threshold &
                  edges$p_adj < p_threshold, , drop = FALSE]

  # 节点表
  node_names <- unique(c(edges$source, edges$target))
  if (length(node_names) == 0) {
    return(list(edges = data.frame(), nodes = data.frame(),
                cor_matrix = cor_mat))
  }
  degree <- table(c(edges$source, edges$target))
  nodes <- data.frame(
    id = names(degree),
    degree = as.integer(degree),
    stringsAsFactors = FALSE
  )

  cat(sprintf("[ppi-local] %d proteins, %d edges (|cor| >= %.2f, p_adj < %.3f)\n",
              n_proteins, nrow(edges), cor_threshold, p_threshold))

  return(list(
    edges = edges,
    nodes = nodes,
    cor_matrix = cor_mat,
    params = list(
      cor_method = cor_method,
      cor_threshold = cor_threshold,
      p_adjust = p_adjust,
      p_threshold = p_threshold
    )
  ))
}


#' 绘制 PPI 网络
#'
#' @description 使用 igraph + ggraph 绘制 PPI 网络图。
#'
#' @param ppi_result \code{query_string_ppi()} 或 \code{build_local_ppi()} 的返回结果。
#' @param layout 布局算法。默认 "fr"。
#' @param node_size_by_degree 按度数调整节点大小。默认 TRUE。
#' @param edge_weight_by_score 按分数调整边宽度。默认 TRUE。
#'
#' @return ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_ppi_network(ppi_result)
#' }
#'
#' @export
plot_ppi_network <- function(ppi_result, layout = "fr",
                             node_size_by_degree = TRUE,
                             edge_weight_by_score = TRUE) {
  if (!requireNamespace("igraph", quietly = TRUE)) {
    stop("Package 'igraph' is required for network visualization.")
  }

  edges <- ppi_result$edges
  if (nrow(edges) == 0) stop("No PPI edges to plot.")

  # 确定边权重列
  weight_col <- NULL
  if (edge_weight_by_score) {
    if ("score" %in% colnames(edges)) {
      weight_col <- "score"
    } else if ("correlation" %in% colnames(edges)) {
      weight_col <- "correlation"
    }
  }

  # 构建图
  g <- igraph::graph_from_data_frame(edges, directed = FALSE)

  # 节点属性
  if (!is.null(ppi_result$nodes)) {
    m <- match(igraph::V(g)$name, ppi_result$nodes$id)
    igraph::V(g)$degree <- ifelse(is.na(m), 0, ppi_result$nodes$degree[m])
  } else {
    igraph::V(g)$degree <- igraph::degree(g)
  }

  # 布局
  if (layout == "fr") {
    igraph::V(g)$x <- igraph::layout_with_fr(g)[, 1]
    igraph::V(g)$y <- igraph::layout_with_fr(g)[, 2]
  } else if (layout == "circle") {
    coords <- igraph::layout_in_circle(g)
    igraph::V(g)$x <- coords[, 1]
    igraph::V(g)$y <- coords[, 2]
  } else {
    coords <- igraph::layout_nicely(g)
    igraph::V(g)$x <- coords[, 1]
    igraph::V(g)$y <- coords[, 2]
  }

  # 使用 ggraph 绘图
  if (requireNamespace("ggraph", quietly = TRUE)) {
    p <- ggraph::ggraph(g, layout = "fr") +
      ggraph::geom_edge_link(
        ggplot2::aes(width = if (edge_weight_by_score && !is.null(weight_col))
                      get(weight_col) else 0.5),
        alpha = 0.4, color = "grey70"
      ) +
      ggraph::geom_node_point(
        ggplot2::aes(size = if (node_size_by_degree) degree else 3),
        color = "#4a90d9", alpha = 0.8
      ) +
      ggraph::geom_node_text(ggplot2::aes(label = name),
                              repel = TRUE, size = 2.5, max.overlaps = 20) +
      ggplot2::theme_void() +
      ggplot2::labs(title = "PPI Network") +
      ggplot2::theme(plot.title = ggplot2::element_text(size = 14,
                                                        face = "bold",
                                                        hjust = 0.5))
    return(p)
  } else {
    # 基础 igraph 绘图
    plot(g,
         vertex.size = if (node_size_by_degree) igraph::degree(g) * 2 else 10,
         vertex.color = "#4a90d9",
         vertex.label.cex = 0.6,
         edge.width = if (edge_weight_by_score && !is.null(weight_col))
                      abs(edges[[weight_col]]) * 3 else 1,
         layout = cbind(igraph::V(g)$x, igraph::V(g)$y),
         main = "PPI Network")
    return(invisible(g))
  }
}


#' 计算 PPI 网络拓扑指标
#'
#' @description 计算 PPI 网络的拓扑Feature，包括度分布、聚类Coefficient、
#'   介数中心性、紧密中心性等。
#'
#' @param ppi_result \code{query_string_ppi()} 或 \code{build_local_ppi()} 的返回结果。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{global_metrics}: 全局网络指标。
#'     \item \code{node_metrics}: 节点级别指标。
#'     \item \code{hub_proteins}: Hub 蛋白（按度排序前 10%）。
#'   }
#'
#' @examples
#' \dontrun{
#' topo <- calc_ppi_topology(ppi_result)
#' }
#'
#' @export
calc_ppi_topology <- function(ppi_result) {
  if (!requireNamespace("igraph", quietly = TRUE)) {
    stop("Package 'igraph' is required for network analysis.")
  }

  edges <- ppi_result$edges
  if (nrow(edges) == 0) stop("No PPI edges to analyze.")

  g <- igraph::graph_from_data_frame(edges, directed = FALSE)

  # 全局指标
  global_metrics <- list(
    n_nodes = igraph::vcount(g),
    n_edges = igraph::ecount(g),
    density = igraph::edge_density(g),
    avg_degree = mean(igraph::degree(g)),
    transitivity = igraph::transitivity(g, type = "global"),
    n_components = igraph::count_components(g),
    diameter = igraph::diameter(g, unconnected = "na"),
    avg_path_length = igraph::mean_distance(g, unconnected = "na")
  )

  # 节点级别指标
  node_metrics <- data.frame(
    protein = igraph::V(g)$name,
    degree = igraph::degree(g),
    betweenness = igraph::betweenness(g, normalized = TRUE),
    closeness = igraph::closeness(g, normalized = TRUE),
    eigenvector = igraph::eigen_centrality(g)$vector,
    stringsAsFactors = FALSE
  )
  node_metrics <- node_metrics[order(-node_metrics$degree), ]
  rownames(node_metrics) <- NULL

  # Hub 蛋白（前 10%）
  n_hub <- max(1, ceiling(nrow(node_metrics) * 0.1))
  hub_proteins <- node_metrics[1:n_hub, , drop = FALSE]

  cat(sprintf("[ppi-topo] Nodes: %d, edges: %d, density: %.4f, components: %d\n",
              global_metrics$n_nodes, global_metrics$n_edges,
              global_metrics$density, global_metrics$n_components))
  cat(sprintf("[ppi-topo] Hub proteins (top %d): %s\n",
              n_hub, paste(hub_proteins$protein, collapse = ", ")))

  return(list(
    global_metrics = global_metrics,
    node_metrics = node_metrics,
    hub_proteins = hub_proteins
  ))
}
