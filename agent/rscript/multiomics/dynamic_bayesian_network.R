# ==============================================================================
# OmicsFlow：面向多组学时间序列数据的动态贝叶斯网络
# ==============================================================================
# 使用 bnlearn 构建带时间滞后的（动态）贝叶斯网络。与静态贝叶斯网络不同，
# DBN 将每个特征展开为两个时间切片（t0 与 t1），并通过黑名单约束结构学习，
# 使所有学习到的弧均从 t0 指向 t1，即编码时间先后关系。
#
# 典型流程：
#   1. aggregate_time_series()       按时间点合并生物学重复
#   2. build_transition_pairs()      将相邻时间点展开为 t0/t1
#   3. discretize_transition_data()  对 t0/t1 做共享分箱离散化
#   4. run_dbn_layer()               单组学 DBN
#   5. run_dbn_multiomics()           合并的全组学 DBN
# ==============================================================================


# ------------------------------------------------------------------------------
# 内部辅助函数
# ------------------------------------------------------------------------------

#' 用于标记动态贝叶斯网络两个时间切片的后缀
#' @keywords internal
.dbn_suffix <- list(t0 = "_t0", t1 = "_t1")


#' 清洗特征名称以生成合法且唯一的 bnlearn 节点标签
#'
#' @param x 原始特征名称的字符向量。
#'
#' @return 语法合法且唯一的名称字符向量。
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


#' 选择矩阵中变异最大的特征
#'
#' @param mat 数值矩阵（特征 x 样本）。
#' @param max_nodes 保留的最大特征数。
#'
#' @return 最多包含 \code{max_nodes} 行的一个子集矩阵。
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
# 步骤 1：在每个时间点内聚合重复样本
# ------------------------------------------------------------------------------

#' 在每个时间点与序列内聚合生物学重复
#'
#' @description 通过对共享同一时间点、且属于同一序列定义（如 location x variety）
#'   的重复样本取均值，将其合并。这将为每个 (序列, 时间点) 生成一条干净的观测，
#'   是构建时间转移对的先决条件。
#'
#' @param mat 数值矩阵（特征 x 样本）。
#' @param sample_info 样本元数据 data.frame，行名为样本 ID。
#' @param time_col 数值时间列的名称。默认："day"。
#' @param group_cols 定义独立时间序列的列字符向量。重复样本仅在同一组合内求均值。
#'   默认：c("location", "variety")。不存在的列会被忽略。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{matrix}: 聚合后的矩阵（特征 x 聚合列）。
#'     \item \code{meta}: 每个聚合列一行（\code{column}、\code{series}、
#'       \code{time}、\code{n_replicates}）的数据框。
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
# 步骤 2：将相邻时间点展开为转移对
# ------------------------------------------------------------------------------

#' 由聚合后的时间序列构建时间转移对
#'
#' @description 对每个独立序列，将相邻时间点配对为 (t, t + lag) 观测。每个特征
#'   贡献两列：\code{<feature>_t0}（较早切片）与 \code{<feature>_t1}（较晚切片）。
#'   跨不同序列绝不配对，以避免虚假的时间边。
#'
#' @param agg_mat 来自 \code{aggregate_time_series()} 的聚合数值矩阵。
#' @param time_meta 来自 \code{aggregate_time_series()} 的 \code{meta} 数据框。
#' @param max_lag 两个切片之间的时间点数。默认：1。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{data}: 转移对的数据框（行）x 2 * 特征数。
#'     \item \code{features}: 清洗后特征名称的字符向量。
#'     \item \code{pairs}: 描述每次转移的数据框
#'       （\code{series}、\code{time_from}、\code{time_to}）。
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
# 步骤 3：两个时间切片共享分箱的离散化
# ------------------------------------------------------------------------------

#' 使用两个时间切片共享的分箱对转移对数据离散化
#'
#' @description 每个特征被离散化为 \code{n_bins} 个水平。关键在于分箱断点由该特征
#'   t0 与 t1 的合并值估计，因此同一状态标签在两个切片中表示相同的含义，两个
#'   时间点保持可比。
#'
#' @param df 来自 \code{build_transition_pairs()} 的转移对数据框。
#' @param features 清洗后特征名称的字符向量。
#' @param n_bins 离散水平数。默认：3。
#'
#' @return 一个数据框，其中每一列均为因子，且同一特征的 t0/t1 对具有相同水平。
#'   无法拆分为至少两个水平的特征将被丢弃。
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
    # bnlearn 要求每个节点至少具有两个可观测状态
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
# 步骤 4：带时间黑名单的结构学习
# ------------------------------------------------------------------------------

#' 构建强制动态（时间滞后）结构的黑名单
#'
#' @description 禁止 (a) 任何离开 t1 节点的弧，(b) 任意两个 t0 节点之间的弧，
#'   从而只有从 t0 节点指向 t1 节点的弧是允许的。可选地，还可禁止违反生物学
#'   层顺序的弧。
#'
#' @param nodes 节点名称的字符向量（带 _t0 / _t1 后缀）。
#' @param node_omics 可选的有名字符向量，映射节点 -> 组学层，与 \code{layer_order}
#'   配合使用。
#' @param layer_order 可选的字符向量，给出组学层允许的从上游到下游的顺序。
#'
#' @return 两列数据框（\code{from}、\code{to}），包含被禁止的弧。
#'
#' @keywords internal
.dbn_build_blacklist <- function(nodes, node_omics = NULL, layer_order = NULL) {
  is_t1 <- grepl(paste0(.dbn_suffix$t1, "$"), nodes)
  t0_nodes <- nodes[!is_t1]
  t1_nodes <- nodes[is_t1]

  bl <- list()

  # (a) 任何弧都不得源自未来节点
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
