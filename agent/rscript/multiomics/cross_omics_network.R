# ==============================================================================
# OmicsFlow：跨组学关联网络
# ==============================================================================
# 将显著的跨层相关性整合为单一图，从而识别枢纽类群、枢纽代谢物
# 以及枢纽香气化合物。
# ==============================================================================

#' 构建跨组学关联网络
#'
#' @description 将 \code{run_cross_correlation()} 生成的显著Feature对表合并为一个
#'   \pkg{igraph} 对象。节点标注其所属组学层，边标注相关的符号与强度，从而形成
#'   "Microbe-Metabolite-Aroma"关系的网络视图。
#'
#' @param pairs_list Feature对数据框的有名列表。每个元素必须包含
#'   feature_x、feature_y、r 与 padj 列，且元素名称应遵循
#'   \code{run_all_pairwise_correlation()} 使用的 "layerX_vs_layerY" 命名约定。
#' @param r_threshold 保留的最小绝对相关Coefficient。默认：0.7。
#' @param padj_threshold 保留的最大校正后 p 值。默认：0.05。
#' @param max_edges 边数的上限；超出时保留关联最强者。默认：2000。
#' @param verbose 逻辑值，是否打印进度。默认：TRUE。
#'
#' @return 一个列表（当没有边保留时为 NULL），含有：
#'   \itemize{
#'     \item \code{graph}: igraph 对象。
#'     \item \code{edges}: 保留边的数据框。
#'     \item \code{nodes}: 含组学层与度数的节点数据框。
#'   }
#'
#' @examples
#' \dontrun{
#' net <- build_cross_omics_network(list(microbiome_vs_metabolome = res$pairs))
#' }
#'
#' @export
build_cross_omics_network <- function(pairs_list,
                                      r_threshold = 0.7,
                                      padj_threshold = 0.05,
                                      max_edges = 2000,
                                      verbose = TRUE) {
  if (!requireNamespace("igraph", quietly = TRUE)) {
    stop("Package 'igraph' is required. Install it with install.packages('igraph').")
  }
  if (is.null(pairs_list) || length(pairs_list) == 0) {
    stop("pairs_list is empty.")
  }
  if (is.data.frame(pairs_list)) {
    pairs_list <- list(pair = pairs_list)
  }
  
  collected <- list()
  for (nm in names(pairs_list)) {
    df <- pairs_list[[nm]]
    if (is.null(df) || !is.data.frame(df) || nrow(df) == 0) next
    required <- c("feature_x", "feature_y", "r")
    if (!all(required %in% colnames(df))) {
      warning(sprintf("Element '%s' lacks the required columns; skipped.", nm))
      next
    }
    keep <- abs(df$r) >= r_threshold
    if ("padj" %in% colnames(df)) {
      keep <- keep & !is.na(df$padj) & df$padj <= padj_threshold
    }
    df <- df[keep, , drop = FALSE]
    if (nrow(df) == 0) next
    
    # 从 "a_vs_b" 的元素名中还原层名称。
    parts <- strsplit(nm, "_vs_", fixed = TRUE)[[1]]
    layer_x <- if (length(parts) == 2) parts[1] else "layer_x"
    layer_y <- if (length(parts) == 2) parts[2] else "layer_y"
    
    collected[[nm]] <- data.frame(
      from = as.character(df$feature_x),
      to = as.character(df$feature_y),
      r = df$r,
      padj = if ("padj" %in% colnames(df)) df$padj else NA_real_,
      from_layer = layer_x,
      to_layer = layer_y,
      comparison = nm,
      stringsAsFactors = FALSE
    )
  }
  
  if (length(collected) == 0) {
    if (verbose) {
      cat(sprintf("  No edge passes |r| >= %.2f and padj <= %.3f.\n",
                  r_threshold, padj_threshold))
    }
    return(NULL)
  }
  
  edges <- do.call(rbind, collected)
  rownames(edges) <- NULL
  
  if (nrow(edges) > max_edges) {
    if (verbose) {
      cat(sprintf("  %d edges exceed max_edges=%d; keeping the strongest.\n",
                  nrow(edges), max_edges))
    }
    edges <- edges[order(-abs(edges$r)), , drop = FALSE][seq_len(max_edges), , drop = FALSE]
  }
  
  edges$direction <- ifelse(edges$r >= 0, "positive", "negative")
  edges$weight <- abs(edges$r)
  
  # 节点表：一个Feature保留其首次出现的层。
  node_names <- unique(c(edges$from, edges$to))
  node_layer <- c(
    stats::setNames(edges$from_layer, edges$from),
    stats::setNames(edges$to_layer, edges$to)
  )
  node_layer <- node_layer[!duplicated(names(node_layer))]
  nodes <- data.frame(
    name = node_names,
    omics = unname(node_layer[node_names]),
    stringsAsFactors = FALSE
  )
  
  graph <- igraph::graph_from_data_frame(
    d = edges[, c("from", "to", "r", "padj", "weight", "direction", "comparison")],
    directed = FALSE,
    vertices = nodes
  )
  nodes$degree <- as.integer(igraph::degree(graph)[nodes$name])
  
  if (verbose) {
    cat(sprintf("  Network: %d nodes, %d edges (%d positive, %d negative).\n",
                nrow(nodes), nrow(edges),
                sum(edges$direction == "positive"),
                sum(edges$direction == "negative")))
  }
  
  list(graph = graph, edges = edges, nodes = nodes)
}


#' 从跨组学网络中提取枢纽节点
#'
#' @description 按度数与中介中心性对节点排序，以筛选出位于关联网络中心、
#'   因而可作为风味形成驱动因子的类群或化合物。
#'
#' @param network \code{build_cross_omics_network()} 的结果，或原始 igraph 对象。
#' @param top_n 返回的枢纽节点数。默认：20。
#' @param by 排序依据，"degree" 或 "betweenness"。默认："degree"。
#' @param verbose 逻辑值，是否打印进度。默认：TRUE。
#'
#' @return 数据框，含 name、omics、degree、betweenness、closeness 以及
#'   关联边的平均绝对相关Coefficient。
#'
#' @examples
#' \dontrun{
#' hubs <- get_network_hubs(net, top_n = 20)
#' }
#'
#' @export
get_network_hubs <- function(network, top_n = 20, by = "degree",
                             verbose = TRUE) {
  if (!requireNamespace("igraph", quietly = TRUE)) {
    stop("Package 'igraph' is required. Install it with install.packages('igraph').")
  }
  by <- match.arg(by, c("degree", "betweenness"))
  
  graph <- if (inherits(network, "igraph")) network else network$graph
  if (is.null(graph) || igraph::vcount(graph) == 0) {
    stop("The network contains no node.")
  }
  
  deg <- igraph::degree(graph)
  btw <- igraph::betweenness(graph, normalized = TRUE)
  clo <- suppressWarnings(igraph::closeness(graph, normalized = TRUE))
  
  vnames <- igraph::V(graph)$name
  omics <- if (!is.null(igraph::V(graph)$omics)) {
    igraph::V(graph)$omics
  } else {
    rep(NA_character_, length(vnames))
  }
  
  # 每个节点关联边上的平均绝对相关Coefficient。
  ew <- igraph::E(graph)$weight
  mean_r <- vapply(seq_along(vnames), function(i) {
    inc <- igraph::incident(graph, v = i, mode = "all")
    if (length(inc) == 0) return(NA_real_)
    mean(ew[as.integer(inc)], na.rm = TRUE)
  }, numeric(1))
  
  hubs <- data.frame(
    name = vnames,
    omics = omics,
    degree = as.integer(deg),
    betweenness = as.numeric(btw),
    closeness = as.numeric(clo),
    mean_abs_r = mean_r,
    stringsAsFactors = FALSE
  )
  
  ord <- if (by == "degree") {
    order(-hubs$degree, -hubs$betweenness)
  } else {
    order(-hubs$betweenness, -hubs$degree)
  }
  hubs <- hubs[ord, , drop = FALSE]
  rownames(hubs) <- NULL
  if (top_n < nrow(hubs)) hubs <- hubs[seq_len(top_n), , drop = FALSE]
  
  if (verbose) {
    cat(sprintf("  Top hub: %s (%s), degree = %d.\n",
                hubs$name[1], hubs$omics[1], hubs$degree[1]))
  }
  hubs
}
