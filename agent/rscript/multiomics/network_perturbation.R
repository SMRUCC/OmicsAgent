# ==============================================================================
# OmicsFlow：贝叶斯网络上的虚拟扰动分析
# ==============================================================================
# 对已学习（动态）贝叶斯网络进行计算机干预，以对各节点的调控重要性排序。
# 将三层互补的证据由廉价到昂贵地结合起来：
#
#   1. 结构层  - igraph 可达性：哪些节点位于被扰动节点的下游
#                          （O(V+E)，始终可用）。
#   2. 干预层  - bnlearn::mutilated() 通过切断目标节点的入弧并将其
#                          固定到选定状态，实现 Pearl 的 do-算子。
#   3. 推断层  - bnlearn::cpdist() 采样比较干预前后下游状态分布的
#                          差异（总变差距离）。
#
# 有意不依赖 gRain 包；所有推断均使用 bnlearn 内置的近似方法完成。
# ==============================================================================


# ------------------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------------------

#' 从 DBN 结果构建 igraph 对象
#'
#' @param dbn_result \code{run_dbn_layer()} / \code{run_dbn_multiomics()} 的结果。
#'
#' @return 一个 igraph 有向图；igraph 不可用时返回 NULL。
#'
#' @keywords internal
.perturb_graph <- function(dbn_result) {
  if (!requireNamespace("igraph", quietly = TRUE)) return(NULL)
  arcs <- dbn_result$arcs
  nodes <- dbn_result$nodes
  edges <- if (!is.null(arcs) && nrow(arcs) > 0) {
    arcs[, c("from", "to"), drop = FALSE]
  } else {
    data.frame(from = character(0), to = character(0), stringsAsFactors = FALSE)
  }
  igraph::graph_from_data_frame(edges, directed = TRUE,
                                vertices = data.frame(name = nodes,
                                                      stringsAsFactors = FALSE))
}


#' 两个离散分布之间的总变差距离
#'
#' @param p,q 具名的数值概率向量。
#'
#' @return 取值 [0, 1] 的数值标量。
#'
#' @keywords internal
.perturb_tvd <- function(p, q) {
  lv <- union(names(p), names(q))
  pv <- as.numeric(p[lv]); pv[is.na(pv)] <- 0
  qv <- as.numeric(q[lv]); qv[is.na(qv)] <- 0
  0.5 * sum(abs(pv - qv))
}


#' 离散分布中最高状态的概率
#'
#' @param p 具名的数值概率向量。
#' @param high_level "high" 水平的名称。
#'
#' @return 数值概率；该水平不存在时为 0。
#'
#' @keywords internal
.perturb_high_prob <- function(p, high_level) {
  v <- p[high_level]
  if (length(v) == 0 || is.na(v)) return(0)
  as.numeric(v)
}


#' 因子列的经验边际分布
#'
#' @param x 一个因子向量。
#'
#' @return 具名的比例数值向量。
#'
#' @keywords internal
.perturb_marginal <- function(x) {
  tb <- table(x)
  if (sum(tb) == 0) return(stats::setNames(numeric(0), character(0)))
  tb / sum(tb)
}


# ------------------------------------------------------------------------------
# Structural layer
# ------------------------------------------------------------------------------

#' 查找节点下游可达的所有节点
#'
#' @description 返回有向网络中 \code{node} 的所有后代节点及其最短路径距离。这是
#'   扰动分析中最廉价的结构证据层，始终可用。
#'
#' @param dbn_result 一个 DBN 结果对象。
#' @param node 起始节点的名称。
#' @param max_distance 跟随的最大路径长度。默认：Inf。
#'
#' @return 含 \code{node} 与 \code{distance} 的数据框；节点无后代时为空。
#'
#' @examples
#' \dontrun{
#' get_downstream_nodes(dbn, "TRA_hexanal_reductase_t0")
#' }
#'
#' @export
get_downstream_nodes <- function(dbn_result, node, max_distance = Inf) {
  empty <- data.frame(node = character(0), distance = numeric(0),
                      stringsAsFactors = FALSE)
  g <- .perturb_graph(dbn_result)
  if (is.null(g) || !node %in% igraph::V(g)$name) return(empty)

  d <- igraph::distances(g, v = node, mode = "out")[1, ]
  d <- d[is.finite(d) & d > 0 & d <= max_distance]
  if (length(d) == 0) return(empty)

  out <- data.frame(node = names(d), distance = as.numeric(d),
                    stringsAsFactors = FALSE)
  out[order(out$distance), , drop = FALSE]
}


#' 通过移除节点及其出向影响来模拟节点敲除
#'
#' @description 从网络中删除每个候选节点，并量化结构损伤：多少后代失去了调控因子、
#'   多少弧消失，以及剩余网络的碎片化程度。
#'
#' @param dbn_result 一个 DBN 结果对象。
#' @param nodes 要敲除的节点。默认：所有至少有一条出弧的节点。
#' @param top_n 仅保留出度最大的 \code{top_n} 个节点。默认：NULL（全部）。
#'
#' @return 每个被敲除节点一行数据框，含 \code{n_descendants}、\code{n_arcs_lost}、
#'   \code{n_components_after} 与 \code{n_orphaned}（失去任何父节点的后代）。
#'
#' @examples
#' \dontrun{
#' ko <- run_node_knockout(dbn, top_n = 10)
#' }
#'
#' @export
run_node_knockout <- function(dbn_result, nodes = NULL, top_n = NULL) {
  g <- .perturb_graph(dbn_result)
  if (is.null(g)) stop("Package 'igraph' is required for knockout analysis.")

  nd <- dbn_result$nodes_df
  if (is.null(nodes)) {
    nodes <- nd$node[nd$out_degree > 0]
  }
  nodes <- intersect(nodes, igraph::V(g)$name)
  if (length(nodes) == 0) {
    return(data.frame(node = character(0), stringsAsFactors = FALSE))
  }
  if (!is.null(top_n)) {
    od <- nd$out_degree[match(nodes, nd$node)]
    nodes <- nodes[order(-od)][seq_len(min(top_n, length(nodes)))]
  }

  base_comp <- igraph::components(g, mode = "weak")$no

  rows <- lapply(nodes, function(n) {
    desc <- get_downstream_nodes(dbn_result, n)
    g2 <- igraph::delete_vertices(g, n)
    lost <- igraph::gsize(g) - igraph::gsize(g2)
    comp <- igraph::components(g2, mode = "weak")$no
    orphaned <- 0L
    if (nrow(desc) > 0) {
      indeg <- igraph::degree(g2, v = intersect(desc$node, igraph::V(g2)$name),
                              mode = "in")
      orphaned <- sum(indeg == 0)
    }
    data.frame(node = n,
               n_descendants = nrow(desc),
               n_arcs_lost = as.integer(lost),
               n_components_before = as.integer(base_comp),
               n_components_after = as.integer(comp),
               n_orphaned = as.integer(orphaned),
               stringsAsFactors = FALSE)
  })

  out <- do.call(rbind, rows)
  out <- out[order(-out$n_descendants, -out$n_arcs_lost), , drop = FALSE]
  rownames(out) <- NULL
  out
}


# ------------------------------------------------------------------------------
# Intervention + inference layers
# ------------------------------------------------------------------------------

#' 在干预下对下游分布进行采样
#'
#' @param fitted 一个 \code{bn.fit} 对象。
#' @param node 被干预的节点。
#' @param state 节点被固定到的状态。
#' @param targets 要观测的下游节点。
#' @param n_sim 采样数量。
#'
#' @return 边际分布的有名列表；失败时返回 NULL。
#'
#' @keywords internal
.perturb_sample_intervention <- function(fitted, node, state, targets, n_sim) {
  tryCatch({
    mut <- bnlearn::mutilated(fitted, evidence = stats::setNames(list(state),
                                                                 node))
    sim <- bnlearn::rbn(mut, n = n_sim)
    lapply(stats::setNames(targets, targets),
           function(tg) .perturb_marginal(sim[[tg]]))
  }, error = function(e) NULL)
}


#' 在贝叶斯网络上运行虚拟扰动分析
#'
#' @description 对一个学习得到的网络的节点执行计算机干预，并量化每个扰动向下游
#'   节点的传播强度。
#'
#'   支持三种模式：
#'   \itemize{
#'     \item \code{"knockout"}: 移除该节点，从结构上衡量下游影响
#'       （失去调控、后代成为孤儿）。
#'     \item \code{"overexpress"}: 将节点固定到其最高状态。
#'     \item \code{"inhibit"}: 将节点固定到其最低状态。
#'   }
#'
#'   为控制运行时间，采用两阶段策略：先用廉价的结构层对所有节点做筛选，
#'   仅将连接度最高的 \code{top_n} 个候选送入基于采样的推断层。叶节点由于没有
#'   下游效应而被跳过。
#'
#' @param dbn_result 一个带有拟合 \code{bn.fit} 模型的 DBN 结果对象。
#' @param nodes 候选节点。默认：所有有出弧的节点。
#' @param mode "knockout"、"overexpress"、"inhibit" 之一。
#' @param n_sim 每次干预的蒙特卡洛采样数。默认：5000。
#' @param top_n 送入推断层的候选数量。默认：15。
#' @param seed 随机种子。默认：42。
#' @param verbose 是否打印进度。默认：TRUE。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{node_summary}: 每个被扰动节点一行。
#'     \item \code{pair_details}: 每个（被扰动节点, 下游节点）一行。
#'     \item \code{params}: 所使用的设置。
#'   }
#'
#' @examples
#' \dontrun{
#' pert <- run_virtual_perturbation(dbn, mode = "overexpress", n_sim = 2000)
#' }
#'
#' @export
run_virtual_perturbation <- function(dbn_result,
                                     nodes = NULL,
                                     mode = c("knockout", "overexpress",
                                              "inhibit"),
                                     n_sim = 5000, top_n = 15, seed = 42,
                                     verbose = TRUE) {
  mode <- match.arg(mode)
  if (is.null(dbn_result) || is.null(dbn_result$nodes_df)) {
    stop("dbn_result must be a DBN result object.")
  }
  set.seed(seed)

  nd <- dbn_result$nodes_df
  g <- .perturb_graph(dbn_result)
  if (is.null(g)) stop("Package 'igraph' is required for perturbation analysis.")

  # --- stage 1: cheap structural screening ---------------------------------
  if (is.null(nodes)) nodes <- nd$node[nd$out_degree > 0]
  nodes <- intersect(nodes, nd$node)
  if (length(nodes) == 0) {
    if (verbose) cat("[perturb] no node has downstream targets; nothing to do.\n")
    return(list(node_summary = data.frame(), pair_details = data.frame(),
                params = list(mode = mode, n_sim = n_sim, top_n = top_n)))
  }
  od <- nd$out_degree[match(nodes, nd$node)]
  nodes <- nodes[order(-od)]
  if (!is.null(top_n)) nodes <- nodes[seq_len(min(top_n, length(nodes)))]

  betw <- tryCatch(igraph::betweenness(g, directed = TRUE),
                   error = function(e) stats::setNames(rep(0, length(nd$node)),
                                                       nd$node))

  fitted <- dbn_result$fitted
  disc <- dbn_result$data
  can_infer <- mode != "knockout" && !is.null(fitted) && !is.null(disc)

  node_rows <- list()
  pair_rows <- list()

  for (n in nodes) {
    desc <- get_downstream_nodes(dbn_result, n)
    n_desc <- nrow(desc)

    tvds <- rep(NA_real_, n_desc)
    shifts <- rep(NA_real_, n_desc)
    inferred <- FALSE

    if (can_infer && n_desc > 0) {
      lv <- levels(disc[[n]])
      state <- if (mode == "overexpress") lv[length(lv)] else lv[1]
      post <- .perturb_sample_intervention(fitted, n, state, desc$node, n_sim)
      if (!is.null(post)) {
        inferred <- TRUE
        high_lv <- lv[length(lv)]
        for (i in seq_len(n_desc)) {
          tg <- desc$node[i]
          base <- .perturb_marginal(disc[[tg]])
          tvds[i] <- .perturb_tvd(base, post[[tg]])
          shifts[i] <- .perturb_high_prob(post[[tg]], high_lv) -
            .perturb_high_prob(base, high_lv)
        }
      }
    }

    if (n_desc > 0) {
      pair_rows[[length(pair_rows) + 1]] <- data.frame(
        perturbed_node = n,
        downstream_node = desc$node,
        distance = desc$distance,
        tvd = tvds,
        prob_shift = shifts,
        mode = mode,
        stringsAsFactors = FALSE
      )
    }

    g2 <- igraph::delete_vertices(g, n)
    node_rows[[length(node_rows) + 1]] <- data.frame(
      node = n,
      mode = mode,
      n_descendants = n_desc,
      max_distance = if (n_desc > 0) max(desc$distance) else 0,
      mean_tvd = if (any(!is.na(tvds))) mean(tvds, na.rm = TRUE) else NA_real_,
      max_tvd = if (any(!is.na(tvds))) max(tvds, na.rm = TRUE) else NA_real_,
      mean_prob_shift = if (any(!is.na(shifts))) mean(shifts, na.rm = TRUE) else NA_real_,
      n_arcs_lost = as.integer(igraph::gsize(g) - igraph::gsize(g2)),
      betweenness = as.numeric(betw[n]),
      inference_used = inferred,
      stringsAsFactors = FALSE
    )
  }

  node_summary <- do.call(rbind, node_rows)
  pair_details <- if (length(pair_rows) > 0) do.call(rbind, pair_rows) else
    data.frame(perturbed_node = character(0), downstream_node = character(0),
               distance = numeric(0), tvd = numeric(0),
               prob_shift = numeric(0), mode = character(0),
               stringsAsFactors = FALSE)

  # 附加可读标签与组学注释 ------------------------------
  lab <- stats::setNames(nd$label, nd$node)
  node_summary$label <- unname(lab[node_summary$node])
  if ("omics" %in% colnames(nd)) {
    om <- stats::setNames(nd$omics, nd$node)
    node_summary$omics <- unname(om[node_summary$node])
    if (nrow(pair_details) > 0) {
      pair_details$perturbed_omics <- unname(om[pair_details$perturbed_node])
      pair_details$downstream_omics <- unname(om[pair_details$downstream_node])
    }
  }
  if (nrow(pair_details) > 0) {
    pair_details$perturbed_label <- unname(lab[pair_details$perturbed_node])
    pair_details$downstream_label <- unname(lab[pair_details$downstream_node])
    pair_details <- pair_details[order(pair_details$perturbed_node,
                                       -ifelse(is.na(pair_details$tvd), 0,
                                               pair_details$tvd)), ,
                                 drop = FALSE]
    rownames(pair_details) <- NULL
  }

  node_summary <- node_summary[order(-node_summary$n_descendants), ,
                               drop = FALSE]
  rownames(node_summary) <- NULL

  if (verbose) {
    cat(sprintf("[perturb] mode=%s: %d node(s) perturbed, %d downstream pair(s), inference=%s\n",
                mode, nrow(node_summary), nrow(pair_details),
                if (any(node_summary$inference_used)) "yes" else "structural-only"))
  }

  list(node_summary = node_summary, pair_details = pair_details,
       params = list(mode = mode, n_sim = n_sim, top_n = top_n, seed = seed))
}


# ------------------------------------------------------------------------------
# 调控重要性评分
# ------------------------------------------------------------------------------

#' 按调控重要性对节点排序
#'
#' @description 将扰动的结构波及范围（后代数量）、其概率效应的强度（平均总变差
#'   距离）以及节点的拓扑中心性（betweenness）合并为一个归一化到 [0, 1] 的评分。
#'
#' @param perturb_result \code{run_virtual_perturbation()} 的输出。
#' @param weights 含有三个分量权重的有名数值向量。默认：c(descendants = 0.4,
#'   tvd = 0.4, betweenness = 0.2)。
#'
#' @return 按 \code{impact_score} 排序的数据框，新增一列 \code{rank}。
#'
#' @examples
#' \dontrun{
#' imp <- score_regulatory_importance(pert)
#' }
#'
#' @export
score_regulatory_importance <- function(perturb_result,
                                        weights = c(descendants = 0.4,
                                                    tvd = 0.4,
                                                    betweenness = 0.2)) {
  ns <- perturb_result$node_summary
  if (is.null(ns) || nrow(ns) == 0) return(ns)

  norm01 <- function(x) {
    x[is.na(x)] <- 0
    rng <- range(x, finite = TRUE)
    if (!is.finite(rng[1]) || diff(rng) == 0) return(rep(0, length(x)))
    (x - rng[1]) / diff(rng)
  }

  s_desc <- norm01(ns$n_descendants)
  s_tvd <- norm01(ns$mean_tvd)
  s_bet <- norm01(ns$betweenness)

  w <- weights / sum(weights)
  ns$score_descendants <- round(s_desc, 4)
  ns$score_tvd <- round(s_tvd, 4)
  ns$score_betweenness <- round(s_bet, 4)
  ns$impact_score <- round(w[["descendants"]] * s_desc +
                             w[["tvd"]] * s_tvd +
                             w[["betweenness"]] * s_bet, 4)

  ns <- ns[order(-ns$impact_score), , drop = FALSE]
  ns$rank <- seq_len(nrow(ns))
  rownames(ns) <- NULL
  ns
}


#' Run all perturbation modes and combine the rankings
#'
#' @description Convenience wrapper that executes knockout, overexpression and
#'   inhibition on the same network and stacks the scored results, so the modes
#'   can be compared side by side.
#'
#' @param dbn_result A DBN result object.
#' @param modes Modes to run. Default: all three.
#' @param n_sim Monte-Carlo samples per intervention. Default: 3000.
#' @param top_n Candidates per mode. Default: 15.
#' @param seed Random seed. Default: 42.
#' @param verbose Print progress. Default: TRUE.
#'
#' @return A list with \code{importance} (stacked scored summaries),
#'   \code{pair_details} (stacked pair tables) and \code{by_mode} (the raw
#'   per-mode results).
#'
#' @examples
#' \dontrun{
#' all_p <- run_perturbation_panel(dbn, n_sim = 2000, top_n = 10)
#' }
#'
#' @export
run_perturbation_panel <- function(dbn_result,
                                   modes = c("knockout", "overexpress",
                                             "inhibit"),
                                   n_sim = 3000, top_n = 15, seed = 42,
                                   verbose = TRUE) {
  by_mode <- list()
  imp_list <- list()
  pair_list <- list()

  for (m in modes) {
    res <- tryCatch(
      run_virtual_perturbation(dbn_result, mode = m, n_sim = n_sim,
                               top_n = top_n, seed = seed, verbose = verbose),
      error = function(e) {
        cat(sprintf("[perturb] mode '%s' failed: %s\n", m, conditionMessage(e)))
        NULL
      })
    if (is.null(res) || nrow(res$node_summary) == 0) next
    by_mode[[m]] <- res
    imp_list[[m]] <- score_regulatory_importance(res)
    if (nrow(res$pair_details) > 0) pair_list[[m]] <- res$pair_details
  }

  importance <- if (length(imp_list) > 0) do.call(rbind, imp_list) else
    data.frame()
  pair_details <- if (length(pair_list) > 0) do.call(rbind, pair_list) else
    data.frame()
  if (nrow(importance) > 0) rownames(importance) <- NULL
  if (nrow(pair_details) > 0) rownames(pair_details) <- NULL

  list(importance = importance, pair_details = pair_details, by_mode = by_mode)
}
