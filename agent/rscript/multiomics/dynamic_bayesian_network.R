# ==============================================================================
# OmicsFlow: Dynamic Bayesian Networks for Multi-Omics Time-Series Data
# ==============================================================================
# Builds time-lagged (dynamic) Bayesian networks with bnlearn. Unlike a static
# Bayesian network, a DBN unrolls every feature into two time slices (t0 and
# t1) and constrains structure learning with a blacklist so that all learned
# arcs are directed from t0 to t1, i.e. they encode temporal precedence.
#
# Typical workflow:
#   1. aggregate_time_series()      collapse biological replicates per timepoint
#   2. build_transition_pairs()     unroll consecutive timepoints into t0/t1
#   3. discretize_transition_data() shared-bin discretisation of t0/t1
#   4. run_dbn_layer()              single-omics DBN
#   5. run_dbn_multiomics()         merged pan-omics DBN
# ==============================================================================


# ------------------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------------------

#' Suffix used to mark the two time slices of a dynamic Bayesian network
#' @keywords internal
.dbn_suffix <- list(t0 = "_t0", t1 = "_t1")


#' Sanitise feature names so they are valid and unique bnlearn node labels
#'
#' @param x Character vector of raw feature names.
#'
#' @return Character vector of syntactically valid, unique names.
#'
#' @keywords internal
.dbn_clean_names <- function(x) {
  x <- as.character(x)
  x[is.na(x) | x == ""] <- "feature"
  x <- gsub("[^A-Za-z0-9]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  x[x == ""] <- "feature"
  x <- ifelse(grepl("^[0-9]", x), paste0("F_", x), x)
  make.unique(x, sep = "_")
}


#' Select the most variable features of a matrix
#'
#' @param mat Numeric matrix (features x samples).
#' @param max_nodes Maximum number of features to keep.
#'
#' @return Subset matrix with at most \code{max_nodes} rows.
#'
#' @keywords internal
.dbn_select_features <- function(mat, max_nodes) {
  if (nrow(mat) <= max_nodes) return(mat)
  v <- apply(mat, 1, stats::var, na.rm = TRUE)
  v[is.na(v)] <- 0
  keep <- order(v, decreasing = TRUE)[seq_len(max_nodes)]
  mat[sort(keep), , drop = FALSE]
}


# ------------------------------------------------------------------------------
# Step 1: aggregate replicates within each timepoint
# ------------------------------------------------------------------------------

#' Aggregate biological replicates within each timepoint and series
#'
#' @description Collapses replicate samples that share the same timepoint and
#'   the same series definition (e.g. location x variety) by taking the mean.
#'   This produces one clean observation per (series, timepoint) and is the
#'   prerequisite for building temporal transition pairs.
#'
#' @param mat Numeric matrix (features x samples).
#' @param sample_info Sample metadata data.frame, row names are sample IDs.
#' @param time_col Name of the numeric time column. Default: "day".
#' @param group_cols Character vector of columns that define independent time
#'   series. Replicates are only averaged within the same combination.
#'   Default: c("location", "variety"). Columns that do not exist are ignored.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{matrix}: aggregated matrix (features x aggregated columns).
#'     \item \code{meta}: data.frame with one row per aggregated column
#'       (\code{column}, \code{series}, \code{time}, \code{n_replicates}).
#'   }
#'
#' @examples
#' \dontrun{
#' agg <- aggregate_time_series(mat, mo$sample_info, time_col = "day")
#' }
#'
#' @export
aggregate_time_series <- function(mat, sample_info, time_col = "day",
                                  group_cols = c("location", "variety")) {
  if (!is.matrix(mat)) mat <- as.matrix(mat)
  if (is.null(colnames(mat))) {
    stop("Expression matrix must have column (sample) names.")
  }
  if (!time_col %in% colnames(sample_info)) {
    stop(sprintf("Time column '%s' not found in sample_info.", time_col))
  }

  common <- intersect(colnames(mat), rownames(sample_info))
  if (length(common) < 2) {
    stop("Fewer than 2 samples shared between matrix and sample_info.")
  }
  mat <- mat[, common, drop = FALSE]
  si <- sample_info[common, , drop = FALSE]

  group_cols <- group_cols[group_cols %in% colnames(si)]

  time_vals <- suppressWarnings(as.numeric(as.character(si[[time_col]])))
  if (all(is.na(time_vals))) {
    stop(sprintf("Time column '%s' could not be coerced to numeric.", time_col))
  }

  if (length(group_cols) > 0) {
    series <- apply(si[, group_cols, drop = FALSE], 1,
                    function(r) paste(as.character(r), collapse = "|"))
  } else {
    series <- rep("all", nrow(si))
  }
  series <- as.character(series)

  key <- paste(series, time_vals, sep = "@")
  keep <- !is.na(time_vals)
  if (!any(keep)) stop("No samples with a valid numeric timepoint.")

  mat <- mat[, keep, drop = FALSE]
  key <- key[keep]
  series <- series[keep]
  time_vals <- time_vals[keep]

  uk <- unique(key)
  agg <- vapply(uk, function(k) rowMeans(mat[, key == k, drop = FALSE],
                                         na.rm = TRUE),
                numeric(nrow(mat)))
  if (is.null(dim(agg))) agg <- matrix(agg, nrow = nrow(mat))
  rownames(agg) <- rownames(mat)
  colnames(agg) <- uk

  idx <- match(uk, key)
  meta <- data.frame(
    column = uk,
    series = series[idx],
    time = time_vals[idx],
    n_replicates = as.integer(table(key)[uk]),
    stringsAsFactors = FALSE
  )

  ord <- order(meta$series, meta$time)
  meta <- meta[ord, , drop = FALSE]
  agg <- agg[, meta$column, drop = FALSE]
  rownames(meta) <- NULL

  list(matrix = agg, meta = meta)
}


# ------------------------------------------------------------------------------
# Step 2: unroll consecutive timepoints into transition pairs
# ------------------------------------------------------------------------------

#' Build temporal transition pairs from an aggregated time series
#'
#' @description For every independent series, consecutive timepoints are paired
#'   into (t, t + lag) observations. Each feature contributes two columns,
#'   \code{<feature>_t0} (the earlier slice) and \code{<feature>_t1} (the later
#'   slice). Pairs are never formed across different series, which prevents
#'   spurious temporal edges.
#'
#' @param agg_mat Aggregated numeric matrix from \code{aggregate_time_series()}.
#' @param time_meta The \code{meta} data.frame from
#'   \code{aggregate_time_series()}.
#' @param max_lag Number of timepoints between the two slices. Default: 1.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{data}: data.frame of transition pairs (rows) x 2 * features.
#'     \item \code{features}: character vector of the clean feature names.
#'     \item \code{pairs}: data.frame describing each transition
#'       (\code{series}, \code{time_from}, \code{time_to}).
#'   }
#'
#' @examples
#' \dontrun{
#' tp <- build_transition_pairs(agg$matrix, agg$meta)
#' }
#'
#' @export
build_transition_pairs <- function(agg_mat, time_meta, max_lag = 1) {
  if (!is.matrix(agg_mat)) agg_mat <- as.matrix(agg_mat)
  if (nrow(agg_mat) == 0) stop("Aggregated matrix has no features.")
  max_lag <- max(1L, as.integer(max_lag))

  from_idx <- integer(0)
  to_idx <- integer(0)
  pair_series <- character(0)
  pair_from_t <- numeric(0)
  pair_to_t <- numeric(0)

  for (s in unique(time_meta$series)) {
    rows <- which(time_meta$series == s)
    rows <- rows[order(time_meta$time[rows])]
    if (length(rows) < max_lag + 1) next
    for (i in seq_len(length(rows) - max_lag)) {
      a <- rows[i]
      b <- rows[i + max_lag]
      from_idx <- c(from_idx, a)
      to_idx <- c(to_idx, b)
      pair_series <- c(pair_series, s)
      pair_from_t <- c(pair_from_t, time_meta$time[a])
      pair_to_t <- c(pair_to_t, time_meta$time[b])
    }
  }

  if (length(from_idx) == 0) {
    stop("No temporal transition pairs could be formed; too few timepoints.")
  }

  feats <- .dbn_clean_names(rownames(agg_mat))

  t0 <- t(agg_mat[, from_idx, drop = FALSE])
  t1 <- t(agg_mat[, to_idx, drop = FALSE])
  colnames(t0) <- paste0(feats, .dbn_suffix$t0)
  colnames(t1) <- paste0(feats, .dbn_suffix$t1)

  df <- as.data.frame(cbind(t0, t1), stringsAsFactors = FALSE)
  rownames(df) <- NULL

  pairs <- data.frame(
    series = pair_series,
    time_from = pair_from_t,
    time_to = pair_to_t,
    stringsAsFactors = FALSE
  )

  list(data = df, features = feats, pairs = pairs)
}


# ------------------------------------------------------------------------------
# Step 3: discretisation with shared bins across the two time slices
# ------------------------------------------------------------------------------

#' Discretise transition-pair data using bins shared by both time slices
#'
#' @description Each feature is discretised into \code{n_bins} levels. Crucially
#'   the bin breaks are estimated from the pooled t0 and t1 values of that
#'   feature, so a given state label means the same thing in both slices and the
#'   two time points remain comparable.
#'
#' @param df Data.frame of transition pairs from \code{build_transition_pairs()}.
#' @param features Character vector of clean feature names.
#' @param n_bins Number of discrete levels. Default: 3.
#'
#' @return A data.frame where every column is a factor with identical levels
#'   for the t0/t1 pair of the same feature. Features that cannot be split into
#'   at least two levels are dropped.
#'
#' @examples
#' \dontrun{
#' disc <- discretize_transition_data(tp$data, tp$features, n_bins = 3)
#' }
#'
#' @export
discretize_transition_data <- function(df, features, n_bins = 3) {
  n_bins <- max(2L, as.integer(n_bins))
  labels <- if (n_bins == 3) c("low", "mid", "high") else paste0("L", seq_len(n_bins))

  out <- list()
  for (f in features) {
    c0 <- paste0(f, .dbn_suffix$t0)
    c1 <- paste0(f, .dbn_suffix$t1)
    if (!all(c(c0, c1) %in% colnames(df))) next

    pooled <- c(df[[c0]], df[[c1]])
    pooled <- pooled[is.finite(pooled)]
    if (length(pooled) < n_bins) next

    probs <- seq(0, 1, length.out = n_bins + 1)
    breaks <- unique(stats::quantile(pooled, probs = probs, na.rm = TRUE))
    if (length(breaks) < 3) next
    breaks[1] <- -Inf
    breaks[length(breaks)] <- Inf
    lab <- labels[seq_len(length(breaks) - 1)]

    f0 <- cut(df[[c0]], breaks = breaks, labels = lab, include.lowest = TRUE)
    f1 <- cut(df[[c1]], breaks = breaks, labels = lab, include.lowest = TRUE)
    if (anyNA(f0) || anyNA(f1)) next
    # bnlearn requires every node to have at least two observed states
    if (nlevels(droplevels(f0)) < 2 && nlevels(droplevels(f1)) < 2) next

    f0 <- factor(as.character(f0), levels = lab)
    f1 <- factor(as.character(f1), levels = lab)
    out[[c0]] <- f0
    out[[c1]] <- f1
  }

  if (length(out) == 0) {
    stop("Discretisation removed all features; check the input matrix.")
  }
  as.data.frame(out, stringsAsFactors = FALSE)
}


# ------------------------------------------------------------------------------
# Step 4: structure learning with a temporal blacklist
# ------------------------------------------------------------------------------

#' Build the blacklist that enforces the dynamic (time-lagged) structure
#'
#' @description Forbids (a) any arc leaving a t1 node, (b) any arc between two
#'   t0 nodes, so that the only admissible arcs go from a t0 node to a t1 node.
#'   Optionally also forbids arcs that violate a biological layer ordering.
#'
#' @param nodes Character vector of node names (with _t0 / _t1 suffixes).
#' @param node_omics Optional named character vector mapping node -> omics
#'   layer, used together with \code{layer_order}.
#' @param layer_order Optional character vector giving the allowed upstream to
#'   downstream ordering of omics layers.
#'
#' @return A two-column data.frame (\code{from}, \code{to}) of forbidden arcs.
#'
#' @keywords internal
.dbn_build_blacklist <- function(nodes, node_omics = NULL, layer_order = NULL) {
  is_t1 <- grepl(paste0(.dbn_suffix$t1, "$"), nodes)
  t0_nodes <- nodes[!is_t1]
  t1_nodes <- nodes[is_t1]

  bl <- list()

  # (a) nothing may originate from a future node
  if (length(t1_nodes) > 0 && length(nodes) > 1) {
    bl[[length(bl) + 1]] <- expand.grid(from = t1_nodes, to = nodes,
                                        stringsAsFactors = FALSE)
  }
  # (b) no contemporaneous arcs inside the past slice
  if (length(t0_nodes) > 1) {
    bl[[length(bl) + 1]] <- expand.grid(from = t0_nodes, to = t0_nodes,
                                        stringsAsFactors = FALSE)
  }

  bl <- do.call(rbind, bl)
  if (is.null(bl)) {
    return(data.frame(from = character(0), to = character(0),
                      stringsAsFactors = FALSE))
  }
  bl <- bl[bl$from != bl$to, , drop = FALSE]

  # (c) optional biological layer ordering constraint
  if (!is.null(node_omics) && !is.null(layer_order) && length(layer_order) > 1) {
    rank_of <- stats::setNames(seq_along(layer_order), layer_order)
    from_rank <- rank_of[node_omics[t0_nodes]]
    to_rank <- rank_of[node_omics[t1_nodes]]
    if (!all(is.na(from_rank)) && !all(is.na(to_rank))) {
      grid <- expand.grid(from = t0_nodes, to = t1_nodes,
                          stringsAsFactors = FALSE)
      fr <- rank_of[node_omics[grid$from]]
      tr <- rank_of[node_omics[grid$to]]
      bad <- !is.na(fr) & !is.na(tr) & fr > tr
      if (any(bad)) bl <- rbind(bl, grid[bad, , drop = FALSE])
    }
  }

  bl <- unique(bl)
  rownames(bl) <- NULL
  bl
}


#' Assemble the standard DBN result object from a learned bnlearn network
#'
#' @param bn A learned bnlearn object.
#' @param disc_df The discretised transition data.frame used for learning.
#' @param strength_df Optional \code{bnlearn::boot.strength()} output.
#' @param strength_threshold Minimum arc strength to retain.
#' @param feature_map Optional named character vector clean_name -> label.
#' @param node_omics Optional named character vector node -> omics layer.
#'
#' @return The standard DBN result list.
#'
#' @keywords internal
.dbn_assemble_result <- function(bn, disc_df, strength_df = NULL,
                                 strength_threshold = 0,
                                 feature_map = NULL, node_omics = NULL) {
  arcs <- as.data.frame(bnlearn::arcs(bn), stringsAsFactors = FALSE)

  if (nrow(arcs) > 0) {
    arcs$strength <- NA_real_
    arcs$direction <- NA_real_
    if (!is.null(strength_df) && nrow(strength_df) > 0) {
      key <- paste(arcs$from, arcs$to, sep = "->")
      skey <- paste(strength_df$from, strength_df$to, sep = "->")
      m <- match(key, skey)
      arcs$strength <- strength_df$strength[m]
      arcs$direction <- strength_df$direction[m]
      keep <- is.na(arcs$strength) | arcs$strength >= strength_threshold
      arcs <- arcs[keep, , drop = FALSE]
    }
  }

  strip <- function(x) sub("_t[01]$", "", x)
  slice_of <- function(x) ifelse(grepl("_t1$", x), "t1", "t0")

  if (nrow(arcs) > 0) {
    arcs$from_feature <- strip(arcs$from)
    arcs$to_feature <- strip(arcs$to)
    if (!is.null(feature_map)) {
      lf <- feature_map[arcs$from_feature]
      lt <- feature_map[arcs$to_feature]
      arcs$from_label <- ifelse(is.na(lf), arcs$from_feature, lf)
      arcs$to_label <- ifelse(is.na(lt), arcs$to_feature, lt)
    } else {
      arcs$from_label <- arcs$from_feature
      arcs$to_label <- arcs$to_feature
    }
    arcs$lag <- 1L
    arcs$self_loop <- arcs$from_feature == arcs$to_feature

    if (!is.null(node_omics)) {
      arcs$from_omics <- unname(node_omics[arcs$from])
      arcs$to_omics <- unname(node_omics[arcs$to])
      arcs$edge_type <- ifelse(
        is.na(arcs$from_omics) | is.na(arcs$to_omics), NA_character_,
        ifelse(arcs$from_omics == arcs$to_omics, "intra_omics", "inter_omics")
      )
    }
    arcs <- arcs[order(-ifelse(is.na(arcs$strength), 0, arcs$strength)), ,
                 drop = FALSE]
    rownames(arcs) <- NULL
  } else {
    arcs <- data.frame(from = character(0), to = character(0),
                       strength = numeric(0), direction = numeric(0),
                       from_feature = character(0), to_feature = character(0),
                       from_label = character(0), to_label = character(0),
                       lag = integer(0), self_loop = logical(0),
                       stringsAsFactors = FALSE)
    if (!is.null(node_omics)) {
      arcs$from_omics <- character(0)
      arcs$to_omics <- character(0)
      arcs$edge_type <- character(0)
    }
  }

  nodes <- bnlearn::nodes(bn)
  out_deg <- vapply(nodes, function(n) sum(arcs$from == n), integer(1))
  in_deg <- vapply(nodes, function(n) sum(arcs$to == n), integer(1))

  nodes_df <- data.frame(
    node = nodes,
    feature = strip(nodes),
    time_slice = slice_of(nodes),
    in_degree = as.integer(in_deg),
    out_degree = as.integer(out_deg),
    degree = as.integer(in_deg + out_deg),
    stringsAsFactors = FALSE
  )
  if (!is.null(feature_map)) {
    lb <- feature_map[nodes_df$feature]
    nodes_df$label <- ifelse(is.na(lb), nodes_df$feature, lb)
  } else {
    nodes_df$label <- nodes_df$feature
  }
  if (!is.null(node_omics)) {
    nodes_df$omics <- unname(node_omics[nodes_df$node])
  }
  nodes_df <- nodes_df[order(-nodes_df$degree), , drop = FALSE]
  rownames(nodes_df) <- NULL

  adjacency <- matrix(0L, nrow = length(nodes), ncol = length(nodes),
                      dimnames = list(nodes, nodes))
  if (nrow(arcs) > 0) {
    adjacency[cbind(arcs$from, arcs$to)] <- 1L
  }

  fitted <- tryCatch(bnlearn::bn.fit(bn, disc_df), error = function(e) NULL)

  list(
    network = bn,
    fitted = fitted,
    arcs = arcs,
    edges_df = arcs,
    nodes = nodes,
    nodes_df = nodes_df,
    adjacency = adjacency,
    data = disc_df,
    node_omics = node_omics
  )
}


#' Learn a dynamic Bayesian network for a single omics layer
#'
#' @description Aggregates replicates, unrolls consecutive timepoints into
#'   transition pairs, discretises them with shared bins and learns a
#'   time-lagged Bayesian network whose arcs are forced to run from t0 to t1.
#'   Arc reliability is assessed with non-parametric bootstrap.
#'
#' @param expr_matrix Numeric matrix (features x samples).
#' @param sample_info Sample metadata with row names equal to sample IDs.
#' @param feature_info Optional annotation data.frame whose row names match the
#'   matrix row names; \code{name_col} supplies readable node labels.
#' @param time_col Numeric time column in \code{sample_info}. Default: "day".
#' @param group_cols Columns defining independent time series.
#'   Default: c("location", "variety").
#' @param max_nodes Maximum number of features (by variance). Default: 25.
#' @param algorithm Structure-learning algorithm: "hc" or "tabu". Default: "hc".
#' @param score Network score, e.g. "bic" or "aic". Default: "bic".
#' @param boot_R Bootstrap replicates for arc strength; 0 disables. Default: 100.
#' @param strength_threshold Minimum bootstrap arc strength to keep. Default: 0.5.
#' @param n_bins Number of discretisation levels. Default: 3.
#' @param name_col Annotation column used for labels. Default: "name".
#' @param seed Random seed. Default: 42.
#'
#' @return A list with \code{network}, \code{fitted}, \code{arcs},
#'   \code{edges_df}, \code{nodes}, \code{nodes_df}, \code{adjacency},
#'   \code{data} and \code{stats}.
#'
#' @examples
#' \dontrun{
#' dbn <- run_dbn_layer(get_omics_matrix(mo, "metabolome"), mo$sample_info,
#'                      get_feature_info(mo, "metabolome"))
#' }
#'
#' @export
run_dbn_layer <- function(expr_matrix, sample_info, feature_info = NULL,
                          time_col = "day",
                          group_cols = c("location", "variety"),
                          max_nodes = 25, algorithm = "hc", score = "bic",
                          boot_R = 100, strength_threshold = 0.5,
                          n_bins = 3, name_col = "name", seed = 42) {
  if (!requireNamespace("bnlearn", quietly = TRUE)) {
    stop("Package 'bnlearn' is required for dynamic Bayesian networks.")
  }
  set.seed(seed)

  mat <- as.matrix(expr_matrix)
  mat <- drop_zero_variance(mat, label = "DBN input", verbose = FALSE)
  if (nrow(mat) < 2) stop("At least 2 non-constant features are required.")
  mat <- .dbn_select_features(mat, max_nodes)

  # readable labels keyed by the sanitised feature name
  raw_names <- rownames(mat)
  clean <- .dbn_clean_names(raw_names)
  labels <- raw_names
  if (!is.null(feature_info) && name_col %in% colnames(feature_info)) {
    idx <- match(raw_names, rownames(feature_info))
    cand <- as.character(feature_info[[name_col]])[idx]
    labels <- ifelse(is.na(cand) | cand == "", raw_names, cand)
  }
  feature_map <- stats::setNames(labels, clean)

  agg <- aggregate_time_series(mat, sample_info, time_col = time_col,
                               group_cols = group_cols)
  tp <- build_transition_pairs(agg$matrix, agg$meta, max_lag = 1)
  disc <- discretize_transition_data(tp$data, tp$features, n_bins = n_bins)

  nodes <- colnames(disc)
  blacklist <- .dbn_build_blacklist(nodes)

  learner <- switch(algorithm,
                    hc = bnlearn::hc,
                    tabu = bnlearn::tabu,
                    stop(sprintf("Unsupported algorithm '%s'; use 'hc' or 'tabu'.",
                                 algorithm)))

  bn <- learner(disc, score = score, blacklist = blacklist)

  strength_df <- NULL
  if (isTRUE(boot_R > 0) && nrow(disc) >= 5) {
    strength_df <- tryCatch({
      s <- bnlearn::boot.strength(disc, R = as.integer(boot_R),
                                  algorithm = algorithm,
                                  algorithm.args = list(score = score,
                                                        blacklist = blacklist))
      as.data.frame(s, stringsAsFactors = FALSE)
    }, error = function(e) {
      cat(sprintf("[dbn] boot.strength failed (%s); keeping unscored arcs.\n",
                  conditionMessage(e)))
      NULL
    })
  }

  res <- .dbn_assemble_result(bn, disc, strength_df, strength_threshold,
                              feature_map = feature_map)

  res$stats <- list(
    n_features = nrow(mat),
    n_timepoints = length(unique(agg$meta$time)),
    n_series = length(unique(agg$meta$series)),
    n_transitions = nrow(tp$pairs),
    n_nodes = length(res$nodes),
    n_arcs = nrow(res$arcs),
    algorithm = algorithm,
    score = score,
    boot_R = boot_R,
    strength_threshold = strength_threshold
  )
  res$time_meta <- agg$meta
  res$transitions <- tp$pairs
  res$type <- "dbn_layer"
  class(res) <- c("DBNResult", "list")
  res
}


#' Learn one merged dynamic Bayesian network across all omics layers
#'
#' @description Selects the most variable features from every omics layer,
#'   prefixes node names with a layer tag to avoid collisions, merges them into
#'   a single matrix and learns one time-lagged Bayesian network spanning all
#'   layers. Arcs are annotated as \code{intra_omics} or \code{inter_omics}.
#'
#' @param mo A MultiOmicsData object.
#' @param layers Omics layers to include. Default: all layers of \code{mo}.
#' @param per_layer_nodes Number of features taken from each layer. Default: 8.
#' @param time_col Numeric time column. Default: "day".
#' @param group_cols Columns defining independent time series.
#'   Default: c("location", "variety").
#' @param enforce_layer_order Whether to forbid arcs that run against
#'   \code{layer_order}. Default: FALSE.
#' @param layer_order Biological ordering of the layers, upstream first.
#' @param algorithm Structure-learning algorithm. Default: "hc".
#' @param score Network score. Default: "bic".
#' @param boot_R Bootstrap replicates. Default: 100.
#' @param strength_threshold Minimum bootstrap arc strength. Default: 0.5.
#' @param n_bins Discretisation levels. Default: 3.
#' @param name_col Annotation column for labels. Default: "name".
#' @param seed Random seed. Default: 42.
#'
#' @return The same structure as \code{run_dbn_layer()}, with \code{edges_df}
#'   additionally carrying \code{from_omics}, \code{to_omics} and
#'   \code{edge_type}, and \code{nodes_df} carrying \code{omics}.
#'
#' @examples
#' \dontrun{
#' dbn <- run_dbn_multiomics(mo, per_layer_nodes = 6)
#' }
#'
#' @export
run_dbn_multiomics <- function(mo, layers = NULL, per_layer_nodes = 8,
                               time_col = "day",
                               group_cols = c("location", "variety"),
                               enforce_layer_order = FALSE,
                               layer_order = NULL,
                               algorithm = "hc", score = "bic",
                               boot_R = 100, strength_threshold = 0.5,
                               n_bins = 3, name_col = "name", seed = 42) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (!requireNamespace("bnlearn", quietly = TRUE)) {
    stop("Package 'bnlearn' is required for dynamic Bayesian networks.")
  }
  set.seed(seed)

  if (is.null(layers)) layers <- mo$metadata$omics_names
  layers <- layers[layers %in% names(mo$omics)]
  if (length(layers) < 2) {
    stop("At least 2 omics layers are required for a merged DBN.")
  }
  if (is.null(layer_order)) layer_order <- layers

  merged <- list()
  feature_map <- character(0)
  clean_to_omics <- character(0)

  for (nm in layers) {
    mat <- tryCatch(get_omics_matrix(mo, nm), error = function(e) NULL)
    if (is.null(mat) || nrow(mat) == 0) next
    mat <- drop_zero_variance(as.matrix(mat), label = nm, verbose = FALSE)
    if (nrow(mat) < 1) next
    mat <- .dbn_select_features(mat, per_layer_nodes)

    finfo <- tryCatch(get_feature_info(mo, nm), error = function(e) NULL)
    raw <- rownames(mat)
    labels <- raw
    if (!is.null(finfo) && name_col %in% colnames(finfo)) {
      cand <- as.character(finfo[[name_col]])[match(raw, rownames(finfo))]
      labels <- ifelse(is.na(cand) | cand == "", raw, cand)
    }

    tag <- toupper(substr(nm, 1, 3))
    clean <- .dbn_clean_names(paste(tag, raw, sep = "_"))
    rownames(mat) <- clean
    feature_map <- c(feature_map,
                     stats::setNames(paste0(tag, "|", labels), clean))
    clean_to_omics <- c(clean_to_omics, stats::setNames(rep(nm, length(clean)),
                                                        clean))
    merged[[nm]] <- mat
  }

  if (length(merged) < 2) {
    stop("Fewer than 2 usable omics layers after feature selection.")
  }

  common <- Reduce(intersect, lapply(merged, colnames))
  if (length(common) < 3) {
    stop("Too few samples shared by all omics layers for a merged DBN.")
  }
  big <- do.call(rbind, lapply(merged, function(m) m[, common, drop = FALSE]))

  agg <- aggregate_time_series(big, mo$sample_info, time_col = time_col,
                               group_cols = group_cols)
  tp <- build_transition_pairs(agg$matrix, agg$meta, max_lag = 1)
  disc <- discretize_transition_data(tp$data, tp$features, n_bins = n_bins)

  nodes <- colnames(disc)
  node_omics <- stats::setNames(
    unname(clean_to_omics[sub("_t[01]$", "", nodes)]), nodes)

  blacklist <- .dbn_build_blacklist(
    nodes,
    node_omics = if (isTRUE(enforce_layer_order)) node_omics else NULL,
    layer_order = if (isTRUE(enforce_layer_order)) layer_order else NULL
  )

  learner <- switch(algorithm,
                    hc = bnlearn::hc,
                    tabu = bnlearn::tabu,
                    stop(sprintf("Unsupported algorithm '%s'.", algorithm)))

  bn <- learner(disc, score = score, blacklist = blacklist)

  strength_df <- NULL
  if (isTRUE(boot_R > 0) && nrow(disc) >= 5) {
    strength_df <- tryCatch({
      s <- bnlearn::boot.strength(disc, R = as.integer(boot_R),
                                  algorithm = algorithm,
                                  algorithm.args = list(score = score,
                                                        blacklist = blacklist))
      as.data.frame(s, stringsAsFactors = FALSE)
    }, error = function(e) {
      cat(sprintf("[dbn] boot.strength failed (%s); keeping unscored arcs.\n",
                  conditionMessage(e)))
      NULL
    })
  }

  res <- .dbn_assemble_result(bn, disc, strength_df, strength_threshold,
                              feature_map = feature_map,
                              node_omics = node_omics)

  n_inter <- if (nrow(res$arcs) > 0) sum(res$arcs$edge_type == "inter_omics",
                                         na.rm = TRUE) else 0L
  res$stats <- list(
    n_layers = length(merged),
    n_features = nrow(big),
    n_timepoints = length(unique(agg$meta$time)),
    n_series = length(unique(agg$meta$series)),
    n_transitions = nrow(tp$pairs),
    n_nodes = length(res$nodes),
    n_arcs = nrow(res$arcs),
    n_inter_omics_arcs = as.integer(n_inter),
    n_intra_omics_arcs = as.integer(nrow(res$arcs) - n_inter),
    algorithm = algorithm,
    score = score,
    boot_R = boot_R,
    strength_threshold = strength_threshold,
    enforce_layer_order = enforce_layer_order
  )
  res$layers <- names(merged)
  res$layer_order <- layer_order
  res$time_meta <- agg$meta
  res$transitions <- tp$pairs
  res$type <- "dbn_multiomics"
  class(res) <- c("DBNResult", "list")
  res
}


# ------------------------------------------------------------------------------
# Step 5: summaries
# ------------------------------------------------------------------------------

#' Summarise a dynamic Bayesian network as a one-row data.frame
#'
#' @param dbn_result Result of \code{run_dbn_layer()} or
#'   \code{run_dbn_multiomics()}.
#' @param label Optional label written into the \code{network} column.
#'
#' @return A one-row data.frame of network-level statistics.
#'
#' @examples
#' \dontrun{
#' summarise_dbn_network(dbn, label = "metabolome")
#' }
#'
#' @export
summarise_dbn_network <- function(dbn_result, label = NULL) {
  if (is.null(dbn_result)) return(NULL)
  st <- dbn_result$stats
  arcs <- dbn_result$arcs
  nd <- dbn_result$nodes_df

  mean_strength <- if (nrow(arcs) > 0 && "strength" %in% colnames(arcs)) {
    mean(arcs$strength, na.rm = TRUE)
  } else NA_real_

  df <- data.frame(
    network = if (is.null(label)) as.character(dbn_result$type) else label,
    type = as.character(dbn_result$type),
    n_nodes = as.integer(st$n_nodes %||% length(dbn_result$nodes)),
    n_arcs = as.integer(st$n_arcs %||% nrow(arcs)),
    n_features = as.integer(st$n_features %||% NA_integer_),
    n_timepoints = as.integer(st$n_timepoints %||% NA_integer_),
    n_series = as.integer(st$n_series %||% NA_integer_),
    n_transitions = as.integer(st$n_transitions %||% NA_integer_),
    n_inter_omics_arcs = as.integer(st$n_inter_omics_arcs %||% NA_integer_),
    n_intra_omics_arcs = as.integer(st$n_intra_omics_arcs %||% NA_integer_),
    mean_arc_strength = round(mean_strength, 4),
    mean_degree = round(mean(nd$degree), 3),
    max_out_degree = as.integer(max(c(nd$out_degree, 0L))),
    max_in_degree = as.integer(max(c(nd$in_degree, 0L))),
    algorithm = as.character(st$algorithm %||% NA_character_),
    score = as.character(st$score %||% NA_character_),
    stringsAsFactors = FALSE
  )
  rownames(df) <- NULL
  df
}


#' Null-coalescing helper
#' @keywords internal
#' @noRd
`%||%` <- function(a, b) if (is.null(a)) b else a
