# ==============================================================================
# OmicsFlow: Virtual Perturbation Analysis on Bayesian Networks
# ==============================================================================
# In-silico interventions on a learned (dynamic) Bayesian network to rank the
# regulatory importance of nodes. Three complementary layers of evidence are
# combined, from cheap to expensive:
#
#   1. Structural layer  - igraph reachability: which nodes are downstream of
#                          the perturbed node (O(V+E), always available).
#   2. Intervention layer- bnlearn::mutilated() implements Pearl's do-operator
#                          by cutting the incoming arcs of the target node and
#                          fixing it to a chosen state.
#   3. Inference layer   - bnlearn::cpdist() sampling compares the downstream
#                          state distributions before and after the
#                          intervention (total variation distance).
#
# The gRain package is intentionally not required; all inference is performed
# with bnlearn's built-in approximate methods.
# ==============================================================================


# ------------------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------------------

#' Build an igraph object from a DBN result
#'
#' @param dbn_result Result of \code{run_dbn_layer()} / \code{run_dbn_multiomics()}.
#'
#' @return An igraph directed graph, or NULL when igraph is unavailable.
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


#' Total variation distance between two discrete distributions
#'
#' @param p,q Named numeric vectors of probabilities.
#'
#' @return Numeric scalar in [0, 1].
#'
#' @keywords internal
.perturb_tvd <- function(p, q) {
  lv <- union(names(p), names(q))
  pv <- as.numeric(p[lv]); pv[is.na(pv)] <- 0
  qv <- as.numeric(q[lv]); qv[is.na(qv)] <- 0
  0.5 * sum(abs(pv - qv))
}


#' Probability of the highest state of a discrete distribution
#'
#' @param p Named numeric vector of probabilities.
#' @param high_level Name of the "high" level.
#'
#' @return Numeric probability, 0 when the level is absent.
#'
#' @keywords internal
.perturb_high_prob <- function(p, high_level) {
  v <- p[high_level]
  if (length(v) == 0 || is.na(v)) return(0)
  as.numeric(v)
}


#' Empirical marginal distribution of a factor column
#'
#' @param x A factor vector.
#'
#' @return Named numeric vector of proportions.
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

#' Find all nodes reachable downstream of a node
#'
#' @description Returns the descendants of \code{node} in the directed network,
#'   together with their shortest-path distance. This is the cheap structural
#'   evidence layer of the perturbation analysis and is always available.
#'
#' @param dbn_result A DBN result object.
#' @param node Name of the node to start from.
#' @param max_distance Maximum path length to follow. Default: Inf.
#'
#' @return A data.frame with \code{node} and \code{distance}, empty when the
#'   node has no descendants.
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


#' Simulate node knockout by removing nodes and their outgoing influence
#'
#' @description Deletes each candidate node from the network and measures the
#'   structural damage: how many descendants lose their regulator, how many
#'   arcs disappear and how fragmented the remaining network becomes.
#'
#' @param dbn_result A DBN result object.
#' @param nodes Nodes to knock out. Default: all nodes with at least one
#'   outgoing arc.
#' @param top_n Keep only the \code{top_n} nodes with the largest out-degree.
#'   Default: NULL (all).
#'
#' @return A data.frame with one row per knocked-out node, containing
#'   \code{n_descendants}, \code{n_arcs_lost}, \code{n_components_after} and
#'   \code{n_orphaned} (descendants left without any parent).
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

#' Sample the downstream distribution under an intervention
#'
#' @param fitted A \code{bn.fit} object.
#' @param node Intervened node.
#' @param state State the node is fixed to.
#' @param targets Downstream nodes to observe.
#' @param n_sim Number of samples.
#'
#' @return Named list of marginal distributions, or NULL on failure.
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


#' Run virtual perturbation analysis on a Bayesian network
#'
#' @description Performs in-silico interventions on the nodes of a learned
#'   network and quantifies how strongly each perturbation propagates to the
#'   downstream nodes.
#'
#'   Three modes are supported:
#'   \itemize{
#'     \item \code{"knockout"}: the node is removed, downstream impact is
#'       measured structurally (lost regulation, orphaned descendants).
#'     \item \code{"overexpress"}: the node is clamped to its highest state.
#'     \item \code{"inhibit"}: the node is clamped to its lowest state.
#'   }
#'
#'   To keep the runtime bounded a two-stage strategy is used: all nodes are
#'   first screened with the cheap structural layer, and only the \code{top_n}
#'   most connected candidates are pushed through the sampling-based inference
#'   layer. Leaf nodes are skipped because they have no downstream effect.
#'
#' @param dbn_result A DBN result object with a fitted \code{bn.fit} model.
#' @param nodes Candidate nodes. Default: all nodes with outgoing arcs.
#' @param mode One of "knockout", "overexpress", "inhibit".
#' @param n_sim Number of Monte-Carlo samples per intervention. Default: 5000.
#' @param top_n Number of candidates sent to the inference layer. Default: 15.
#' @param seed Random seed. Default: 42.
#' @param verbose Print progress. Default: TRUE.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{node_summary}: one row per perturbed node.
#'     \item \code{pair_details}: one row per (perturbed node, downstream node).
#'     \item \code{params}: the settings used.
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

  # attach readable labels and omics annotation ------------------------------
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
# Regulatory importance scoring
# ------------------------------------------------------------------------------

#' Rank nodes by their regulatory importance
#'
#' @description Combines the structural reach of a perturbation (number of
#'   descendants), the strength of its probabilistic effect (mean total
#'   variation distance) and the topological centrality of the node
#'   (betweenness) into a single normalised score in [0, 1].
#'
#' @param perturb_result Output of \code{run_virtual_perturbation()}.
#' @param weights Named numeric vector with the weights of the three
#'   components. Default: c(descendants = 0.4, tvd = 0.4, betweenness = 0.2).
#'
#' @return A data.frame ordered by \code{impact_score}, with a \code{rank}
#'   column added.
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
