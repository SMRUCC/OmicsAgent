# =============================================================================
# OmicsFlow: Spearman + MIC Association Network
# -----------------------------------------------------------------------------
# 为跨组学（不同层之间）与组学内（同层内部）的 feature 构建
# Spearman（单调线性关联）+ MIC（最大信息系数，任意非线性关联）双指标关联网络。
#
# 设计要点：
#   1. 矩阵约定：features x samples（行=特征，列=样本），与 cross_correlation.R 一致。
#   2. 两阶段计算：先用向量化 Spearman 全量计算（毫秒级），按 |rho| 取 Top K
#      候选对，再仅对候选对调用 minerva::mine() 计算 MIC —— 把 MIC 的网格搜索
#      成本从 "全部配对" 降到 "候选集"，是本模块的核心性能决策。
#   3. MIC 显著性：采用"共享零分布"置换检验（minerva 的 mine() 本身不返回 p 值）。
#      在同样本量下，无关联特征对的 MIC 零分布仅依赖于 n，故对所有候选对
#      共用 n_perm 个随机打乱对的 MIC 经验分布求经验 p 值，成本为常数 n_perm，
#      而非 n_pairs x R。该近似在 mic_pvalue_method = "permutation" 时启用；
#      设为 "none" 则跳过（MIC-pvalue 列返回 NA），进一步提速。
#   4. score / pvalue：score 支持两种口径；pvalue 统一用 Fisher 合并法整合
#      Spearman 与 MIC 两个 p 值。详见各参数说明。
#   5. 降级策略：minerva 缺失时不报错，MIC 与 MIC-pvalue 列置 NA，Spearman 部分
#      仍正常运行（与现有 build_cross_omics_network / plot_cross_correlation_heatmap
#      对可选依赖的处理方式一致）。
# =============================================================================

# 复用现有工具（这些函数在 source_all_scripts.R 加载后可用）
#   drop_zero_variance()  : 移除零方差特征（multiomics_data.R）
#   get_omics_matrix()    : 从 MultiOmicsData 取表达矩阵
#   get_feature_info()    : 从 MultiOmicsData 取特征注释
#   export_table()        : 表格导出（utils/）

# -----------------------------------------------------------------------------
# 内部工具：按方差（信号强度）选择 Top N 特征
# -----------------------------------------------------------------------------
#' Select top variable features from a matrix
#'
#' @param mat Numeric matrix (features x samples).
#' @param top_n Integer. Number of features to keep by descending row variance.
#'   If NULL or larger than nrow(mat), all features are kept.
#' @param label Character, name used in progress messages.
#' @param verbose Logical, print progress.
#' @return A numeric matrix with at most \code{top_n} rows.
#' @noRd
select_top_features <- function(mat, top_n = NULL, label = "matrix",
                                verbose = TRUE) {
  if (!is.matrix(mat)) mat <- as.matrix(mat)
  if (is.null(top_n) || top_n >= nrow(mat)) {
    if (isTRUE(verbose)) {
      cat(sprintf("[assoc] %s: keeping all %d features (no selection).\n",
                  label, nrow(mat)))
    }
    return(mat)
  }
  v <- apply(mat, 1, stats::var, na.rm = TRUE)
  ord <- order(v, decreasing = TRUE)
  keep <- ord[seq_len(min(top_n, length(ord)))]
  if (isTRUE(verbose)) {
    cat(sprintf("[assoc] %s: selected top %d / %d features by variance.\n",
                label, length(keep), nrow(mat)))
  }
  return(mat[keep, , drop = FALSE])
}


# -----------------------------------------------------------------------------
# 内部工具：向量化 Spearman（对行取 rank 后做标准化矩阵叉积）
# 返回 rho 矩阵与解析 p 值矩阵，复用 cross_correlation.R 的 .row_standardise 思路
# -----------------------------------------------------------------------------
#' Vectorised Spearman correlation matrix (rank transform + standardised cross-product)
#'
#' @param mat_x Numeric matrix (features_x x samples).
#' @param mat_y Numeric matrix (features_y x samples). Must share the same
#'   column order / sample set as \code{mat_x}.
#' @return A list with \code{rho} (features_x x features_y) and
#'   \code{pval} (features_x x features_y) matrices.
#' @noRd
.spearman_matrix <- function(mat_x, mat_y) {
  # 同一组学层内部配对时 mat_x == mat_y，仍使用通用路径（上三角在调用方裁剪）
  if (ncol(mat_x) != ncol(mat_y)) {
    stop("[assoc] mat_x and mat_y must share the same number of samples.")
  }
  rx <- t(apply(mat_x, 1, rank))
  ry <- if (identical(mat_x, mat_y)) rx else t(apply(mat_y, 1, rank))

  .row_standardise <- function(m) {
    mu <- rowMeans(m, na.rm = TRUE)
    s  <- sqrt(rowSums((m - mu)^2, na.rm = TRUE))
    s[s == 0] <- 1
    (m - mu) / s
  }
  sx <- .row_standardise(rx)
  sy <- .row_standardise(ry)
  rho <- tcrossprod(sx, sy)          # 等价于 Pearson(rank) = Spearman
  rho[rho > 1]  <- 1
  rho[rho < -1] <- -1

  n  <- ncol(mat_x)
  df <- n - 2
  # t 统计量：t = r * sqrt(df) / sqrt(1 - r^2)
  tstat <- rho * sqrt(df) / sqrt(pmax(1 - rho^2, 0))
  pval  <- 2 * stats::pt(abs(tstat), df = df, lower.tail = FALSE)
  pval[is.na(pval)] <- 1

  list(rho = rho, pval = pval)
}


# -----------------------------------------------------------------------------
# 内部工具：共享零分布置换 —— 返回 n_perm 个随机打乱对的 MIC 经验分布
# -----------------------------------------------------------------------------
#' Shared null distribution of MIC by permutation
#'
#' @param mat Reference matrix (features x samples) used to draw random feature
#'   pairs for permutation.
#' @param n_perm Integer, number of random permutations.
#' @param n_sample Integer, number of samples actually used (after intersect).
#' @param verbose Logical.
#' @return A numeric vector of length \code{n_perm} with MIC values of random
#'   (null) feature pairs. Returns \code{NULL} on any failure.
#' @noRd
.mic_null_distribution <- function(mat, n_perm = 200, n_sample = NULL,
                                   verbose = TRUE) {
  if (!requireNamespace("minerva", quietly = TRUE)) return(NULL)
  if (is.null(n_sample)) n_sample <- ncol(mat)
  pf <- nrow(mat)
  if (pf < 2) return(NULL)
  out <- numeric(n_perm)
  for (i in seq_len(n_perm)) {
    a <- mat[sample.int(pf, 1), ]
    b <- mat[sample.int(pf, 1), ]
    # 随机打乱 b 的样本顺序，构造无关联对
    b_perm <- sample(b)
    res <- tryCatch(minerva::mine(a, b_perm)$MIC, error = function(e) NA_real_)
    out[i] <- if (is.na(res)) 0 else res
  }
  if (isTRUE(verbose)) {
    cat(sprintf("[assoc] MIC null distribution built from %d permutations (max=%.3f).\n",
                n_perm, max(out, na.rm = TRUE)))
  }
  out
}


# -----------------------------------------------------------------------------
# 内部工具：对候选对批量计算 MIC（调用 minerva::mine）
# -----------------------------------------------------------------------------
#' Compute MIC for a list of feature pairs
#'
#' @param mat_x Numeric matrix.
#' @param mat_y Numeric matrix.
#' @param pairs A 2-column integer matrix of (row_in_x, row_in_y) indices.
#' @param verbose Logical.
#' @return Numeric vector of MIC values aligned with \code{pairs} (NA if
#'   minerva unavailable or a pair fails).
#' @noRd
.compute_mic_for_pairs <- function(mat_x, mat_y, pairs, verbose = TRUE) {
  if (!requireNamespace("minerva", quietly = TRUE)) {
    if (isTRUE(verbose)) {
      cat("[assoc] minerva not available -> MIC set to NA. ",
          "Run install.packages('minerva') for MIC support.\n")
    }
    return(rep(NA_real_, nrow(pairs)))
  }
  mic <- numeric(nrow(pairs))
  for (k in seq_len(nrow(pairs))) {
    xa <- mat_x[pairs[k, 1], ]
    yb <- mat_y[pairs[k, 2], ]
    res <- tryCatch(minerva::mine(xa, yb)$MIC, error = function(e) NA_real_)
    mic[k] <- if (is.na(res)) NA_real_ else res
  }
  mic
}


# -----------------------------------------------------------------------------
# 内部工具：组装标准 9 列边表
# -----------------------------------------------------------------------------
#' Assemble the canonical 9-column association edge table
#'
#' @param src Character vector of source feature names.
#' @param tgt Character vector of target feature names.
#' @param rho Numeric vector, Spearman rho.
#' @param rho_p Numeric vector, Spearman p-value.
#' @param mic Numeric vector, MIC (NA allowed).
#' @param mic_p Numeric vector, MIC p-value (NA allowed).
#' @param score_method Character, \code{"combined"} or \code{"nonlinear"}.
#' @param score_weight Numeric, weight on |rho| for combined score.
#' @param p_adjust Character, method passed to \code{p.adjust} for the merged p.
#' @param p_threshold Numeric, significance cutoff on adjusted merged p.
#' @param rho_linear_min Numeric, |rho| above which an association is treated
#'   as linear (vs nonlinear).
#' @return A data.frame with exactly 9 columns:
#'   source, target, spearman-rho, spearman-pval, MIC, MIC-pvalue,
#'   score, pvalue, association. Column names are set with check.names = FALSE
#'   so that the hyphenated names survive export unchanged.
#' @noRd
.assemble_edge_table <- function(src, tgt, rho, rho_p, mic, mic_p,
                                 score_method = "combined",
                                 score_weight = 0.5,
                                 p_adjust = "BH",
                                 p_threshold = 0.05,
                                 rho_linear_min = 0.3) {
  stopifnot(length(src) == length(tgt), length(src) == length(rho),
            length(src) == length(rho_p))
  n <- length(src)

  # ---- score（综合关联强度）----
  # combined  : score = w*|rho| + (1-w)*MIC   （两者皆强时最高，直觉清晰）
  # nonlinear : score = MIC - rho^2           （经典 MIC-R^2，突出非线性关联）
  if (score_method == "nonlinear") {
    score <- mic - rho^2
  } else {
    w <- score_weight
    mic_safe <- if (is.null(mic) || all(is.na(mic))) rep(0, n) else mic
    score <- w * abs(rho) + (1 - w) * mic_safe
  }

  # ---- pvalue（Fisher 合并 Spearman 与 MIC 两个 p 值）----
  # X^2 = -2 * (ln p_rho + ln p_MIC) ~ chi-square(df=4)
  #   MIC p 缺失时退化为 Spearman p 值。
  p_rho <- pmax(rho_p, 1e-300)
  if (!is.null(mic_p) && !all(is.na(mic_p))) {
    p_mic <- pmax(mic_p, 1e-300)
    chisq <- -2 * (log(p_rho) + log(p_mic))
  } else {
    chisq <- -2 * log(p_rho)
  }
  merged_p <- stats::pchisq(chisq, df = 4, lower.tail = FALSE)
  merged_p[is.na(merged_p)] <- 1

  # BH 校正
  padj <- stats::p.adjust(merged_p, method = p_adjust)

  # ---- association 分类 ----
  sig <- padj < p_threshold
  assoc <- rep("not_significant", n)
  assoc[sig & rho >= 0]  <- "positive"
  assoc[sig & rho < 0]   <- "negative"
  assoc[sig & abs(rho) < rho_linear_min] <- "nonlinear"

  df <- data.frame(
    source        = src,
    target        = tgt,
    `spearman-rho` = rho,
    `spearman-pval` = rho_p,
    MIC            = if (is.null(mic)) rep(NA_real_, n) else mic,
    `MIC-pvalue`   = if (is.null(mic_p)) rep(NA_real_, n) else mic_p,
    score          = score,
    pvalue         = merged_p,
    association    = assoc,
    check.names = FALSE
  )
  attr(df, "padj") <- padj   # 供调用方按需使用（不导出到 CSV）
  df
}


# -----------------------------------------------------------------------------
# 核心函数一：跨组学关联（两个不同层之间）
# -----------------------------------------------------------------------------
#' Cross-omics Spearman + MIC association network
#'
#' Computes the association between every feature pair across two omics layers
#' using Spearman correlation (vectorised) and MIC (maximal information
#' coefficient). To keep MIC affordable, only the Top-K feature pairs ranked by
#' |Spearman rho| are sent to \code{minerva::mine()}.
#'
#' @param mat_x Numeric matrix (features x samples) of the first layer.
#' @param mat_y Numeric matrix (features x samples) of the second layer.
#' @param name_x Character, label for the first layer (used in source names).
#' @param name_y Character, label for the second layer.
#' @param top_n Integer, pre-filter each layer to the top-N features by
#'   variance before pairing. NULL keeps all features.
#' @param max_pairs_for_mic Integer, maximum number of feature pairs sent to MIC
#'   (selected by descending |rho|). The single most important cost knob.
#' @param mic_pvalue_method Character, \code{"permutation"} (shared-null
#'   distribution) or \code{"none"} (skip, MIC-pvalue = NA).
#' @param n_perm Integer, number of permutations for the shared MIC null.
#' @param score_method Character, \code{"combined"} (default:
#'   \code{w*|rho| + (1-w)*MIC}) or \code{"nonlinear"} (\code{MIC - rho^2}).
#' @param score_weight Numeric in [0,1], weight of |rho| in combined score.
#' @param p_adjust Character, method for \code{p.adjust} on the merged p.
#' @param p_threshold Numeric, significance cutoff on adjusted merged p.
#' @param rho_linear_min Numeric, |rho| above which a significant pair is
#'   classified as linear (positive/negative) vs \code{nonlinear}.
#' @param verbose Logical, print progress.
#'
#' @return A list:
#'   \item{edges}{data.frame with 9 columns: source, target, spearman-rho,
#'     spearman-pval, MIC, MIC-pvalue, score, pvalue, association.}
#'   \item{nodes}{data.frame: name, omics, degree.}
#'   \item{params}{list of run parameters and counts.}
#'
#' @examples
#' \dontrun{
#'   mo <- create_multiomics_data(...)
#'   mx <- get_omics_matrix(mo, "microbiome")
#'   mv <- get_omics_matrix(mo, "volatilome")
#'   res <- run_cross_omics_association(mx, mv, "microbiome", "volatilome",
#'                                      top_n = 60, max_pairs_for_mic = 2000)
#'   head(res$edges)
#' }
#'
#' @export
run_cross_omics_association <- function(mat_x, mat_y,
                                        name_x = "x", name_y = "y",
                                        top_n = NULL,
                                        max_pairs_for_mic = 2000,
                                        mic_pvalue_method = c("permutation", "none"),
                                        n_perm = 200,
                                        score_method = c("combined", "nonlinear"),
                                        score_weight = 0.5,
                                        p_adjust = "BH",
                                        p_threshold = 0.05,
                                        rho_linear_min = 0.3,
                                        verbose = TRUE) {
  mic_pvalue_method <- match.arg(mic_pvalue_method)
  score_method      <- match.arg(score_method)

  if (!is.matrix(mat_x)) mat_x <- as.matrix(mat_x)
  if (!is.matrix(mat_y)) mat_y <- as.matrix(mat_y)
  if (verbose) cat(sprintf("\n[assoc] === Cross-omics: %s x %s ===\n", name_x, name_y))

  common <- intersect(colnames(mat_x), colnames(mat_y))
  if (length(common) < 8) {
    stop("At least 8 shared samples are required for association analysis.")
  }
  mat_x <- mat_x[, common, drop = FALSE]
  mat_y <- mat_y[, common, drop = FALSE]

  mat_x <- drop_zero_variance(mat_x, label = name_x, verbose = verbose)
  mat_y <- drop_zero_variance(mat_y, label = name_y, verbose = verbose)
  mat_x <- select_top_features(mat_x, top_n, label = name_x, verbose = verbose)
  mat_y <- select_top_features(mat_y, top_n, label = name_y, verbose = verbose)

  fx <- rownames(mat_x); if (is.null(fx)) fx <- sprintf("%s.f%d", name_x, seq_len(nrow(mat_x)))
  fy <- rownames(mat_y); if (is.null(fy)) fy <- sprintf("%s.f%d", name_y, seq_len(nrow(mat_y)))

  sp <- .spearman_matrix(mat_x, mat_y)
  rho  <- as.vector(sp$rho)
  rp   <- as.vector(sp$pval)
  src_x <- rep(fx, times = nrow(mat_y))
  src_y <- rep(fy, each  = nrow(mat_x))
  n_pairs <- length(rho)
  if (verbose) cat(sprintf("[assoc] Spearman computed for %d feature pairs.\n", n_pairs))

  # 候选对：按 |rho| 取 Top K
  ord <- order(abs(rho), decreasing = TRUE)
  k <- min(max_pairs_for_mic, n_pairs)
  cand <- ord[seq_len(k)]
  if (verbose) cat(sprintf("[assoc] Selected %d candidate pairs for MIC.\n", k))

  pairs_idx <- cbind(match(src_x[cand], fx), match(src_y[cand], fy))
  mic  <- rep(NA_real_, n_pairs)
  mic_p <- rep(NA_real_, n_pairs)

  mic_calc <- .compute_mic_for_pairs(mat_x, mat_y, pairs_idx, verbose = FALSE)
  mic[cand]  <- mic_calc
  if (verbose) cat(sprintf("[assoc] MIC computed for %d candidate pairs (minerva).\n", k))

  # MIC p 值：共享零分布
  if (mic_pvalue_method == "permutation" && any(!is.na(mic))) {
    null_dist <- .mic_null_distribution(mat_x, n_perm = n_perm,
                                        n_sample = ncol(mat_x), verbose = verbose)
    if (!is.null(null_dist) && length(null_dist) > 0) {
      thr <- stats::quantile(null_dist, probs = 0.95, na.rm = TRUE)
      mic_p[cand] <- sapply(mic[cand], function(m) {
        if (is.na(m)) return(NA_real_)
        mean(null_dist >= m, na.rm = TRUE)
      })
      if (verbose) {
        cat(sprintf("[assoc] MIC empirical p (95%% null threshold = %.3f).\n", thr))
      }
    }
  }

  edges <- .assemble_edge_table(
    src = src_x, tgt = src_y, rho = rho, rho_p = rp,
    mic = mic, mic_p = mic_p,
    score_method = score_method, score_weight = score_weight,
    p_adjust = p_adjust, p_threshold = p_threshold,
    rho_linear_min = rho_linear_min
  )

  nodes <- .build_node_table(c(src_x, src_y),
                             c(rep(name_x, length(fx)), rep(name_y, length(fy))),
                             edges)

  list(
    edges  = edges,
    nodes  = nodes,
    params = list(
      type = "cross",
      name_x = name_x, name_y = name_y,
      n_features_x = nrow(mat_x), n_features_y = nrow(mat_y),
      n_pairs = n_pairs, n_mic = k,
      mic_pvalue_method = mic_pvalue_method, n_perm = n_perm,
      score_method = score_method, score_weight = score_weight,
      p_adjust = p_adjust, p_threshold = p_threshold,
      n_significant = sum(edges$association != "not_significant"),
      n_nonlinear = sum(edges$association == "nonlinear")
    )
  )
}


# -----------------------------------------------------------------------------
# 核心函数二：组学内关联（同一层内部，上三角）
# -----------------------------------------------------------------------------
#' Intra-omics Spearman + MIC association network
#'
#' Computes associations among features \emph{within} a single omics layer.
#' Only the strict upper triangle of the feature self-correlation is evaluated
#' (no self-pairs, no duplicates). See \code{run_cross_omics_association} for
#' the score / p-value / MIC methodology.
#'
#' @param mat Numeric matrix (features x samples).
#' @param name Character, label for the layer.
#' @param top_n Integer, pre-filter to the top-N features by variance.
#' @param max_pairs_for_mic Integer, max pairs sent to MIC.
#' @param mic_pvalue_method Character, \code{"permutation"} or \code{"none"}.
#' @param n_perm Integer, permutations for shared MIC null.
#' @param score_method Character, \code{"combined"} or \code{"nonlinear"}.
#' @param score_weight Numeric, weight of |rho| in combined score.
#' @param p_adjust Character, p.adjust method on merged p.
#' @param p_threshold Numeric, significance cutoff on adjusted merged p.
#' @param rho_linear_min Numeric, |rho| cutoff for linear vs nonlinear label.
#' @param verbose Logical, print progress.
#'
#' @return A list with \code{edges} (9 columns), \code{nodes}, \code{params}
#'   (see \code{run_cross_omics_association}).
#'
#' @examples
#' \dontrun{
#'   mo <- create_multiomics_data(...)
#'   mm <- get_omics_matrix(mo, "metabolome")
#'   res <- run_intra_omics_association(mm, "metabolome", top_n = 80)
#'   head(res$edges)
#' }
#'
#' @export
run_intra_omics_association <- function(mat, name = "omics",
                                        top_n = NULL,
                                        max_pairs_for_mic = 2000,
                                        mic_pvalue_method = c("permutation", "none"),
                                        n_perm = 200,
                                        score_method = c("combined", "nonlinear"),
                                        score_weight = 0.5,
                                        p_adjust = "BH",
                                        p_threshold = 0.05,
                                        rho_linear_min = 0.3,
                                        verbose = TRUE) {
  mic_pvalue_method <- match.arg(mic_pvalue_method)
  score_method      <- match.arg(score_method)

  if (!is.matrix(mat)) mat <- as.matrix(mat)
  if (verbose) cat(sprintf("\n[assoc] === Intra-omics: %s ===\n", name))

  if (ncol(mat) < 8) stop("At least 8 samples are required for association analysis.")
  mat <- drop_zero_variance(mat, label = name, verbose = verbose)
  mat <- select_top_features(mat, top_n, label = name, verbose = verbose)

  f <- rownames(mat); if (is.null(f)) f <- sprintf("%s.f%d", name, seq_len(nrow(mat)))

  sp <- .spearman_matrix(mat, mat)
  p <- nrow(mat)
  ut <- which(upper.tri(sp$rho), arr.ind = TRUE)   # 严格上三角，避免自配对与重复
  rho  <- sp$rho[ut]
  rp   <- sp$pval[ut]
  src <- f[ut[, 1]]
  tgt <- f[ut[, 2]]
  n_pairs <- length(rho)
  if (verbose) cat(sprintf("[assoc] Spearman computed for %d intra-layer pairs.\n", n_pairs))

  ord <- order(abs(rho), decreasing = TRUE)
  k <- min(max_pairs_for_mic, n_pairs)
  cand <- ord[seq_len(k)]
  if (verbose) cat(sprintf("[assoc] Selected %d candidate pairs for MIC.\n", k))

  pairs_idx <- ut[cand, , drop = FALSE]
  mic  <- rep(NA_real_, n_pairs)
  mic_p <- rep(NA_real_, n_pairs)

  mic_calc <- .compute_mic_for_pairs(mat, mat, pairs_idx, verbose = FALSE)
  mic[cand] <- mic_calc
  if (verbose) cat(sprintf("[assoc] MIC computed for %d candidate pairs (minerva).\n", k))

  if (mic_pvalue_method == "permutation" && any(!is.na(mic))) {
    null_dist <- .mic_null_distribution(mat, n_perm = n_perm,
                                        n_sample = ncol(mat), verbose = verbose)
    if (!is.null(null_dist) && length(null_dist) > 0) {
      thr <- stats::quantile(null_dist, probs = 0.95, na.rm = TRUE)
      mic_p[cand] <- sapply(mic[cand], function(m) {
        if (is.na(m)) return(NA_real_)
        mean(null_dist >= m, na.rm = TRUE)
      })
      if (verbose) {
        cat(sprintf("[assoc] MIC empirical p (95%% null threshold = %.3f).\n", thr))
      }
    }
  }

  edges <- .assemble_edge_table(
    src = src, tgt = tgt, rho = rho, rho_p = rp,
    mic = mic, mic_p = mic_p,
    score_method = score_method, score_weight = score_weight,
    p_adjust = p_adjust, p_threshold = p_threshold,
    rho_linear_min = rho_linear_min
  )

  nodes <- .build_node_table(c(src, tgt), rep(name, 2 * n_pairs), edges)

  list(
    edges  = edges,
    nodes  = nodes,
    params = list(
      type = "intra",
      name = name,
      n_features = nrow(mat),
      n_pairs = n_pairs, n_mic = k,
      mic_pvalue_method = mic_pvalue_method, n_perm = n_perm,
      score_method = score_method, score_weight = score_weight,
      p_adjust = p_adjust, p_threshold = p_threshold,
      n_significant = sum(edges$association != "not_significant"),
      n_nonlinear = sum(edges$association == "nonlinear")
    )
  )
}


# -----------------------------------------------------------------------------
# 内部工具：由边表构建节点表（含 degree）
# -----------------------------------------------------------------------------
#' Build node table (name, omics, degree) from an edge table
#' @noRd
.build_node_table <- function(names_vec, omics_vec, edges) {
  deg <- structure(rep(0L, length(names_vec)),
                   names = names_vec)
  for (i in seq_len(nrow(edges))) {
    s <- edges$source[i]; t <- edges$target[i]
    if (!is.na(deg[s])) deg[s] <- deg[s] + 1L
    if (!is.na(deg[t])) deg[t] <- deg[t] + 1L
  }
  # 去重（source/target 中同一节点会出现多次）
  uniq <- !duplicated(names_vec)
  data.frame(
    name  = names_vec[uniq],
    omics = omics_vec[uniq],
    degree = as.integer(deg[names_vec[uniq]]),
    stringsAsFactors = FALSE
  )
}


# -----------------------------------------------------------------------------
# 便捷封装：遍历 MultiOmicsData 全部跨层组合 + 层内组合
# -----------------------------------------------------------------------------
#' Run all cross-omics and intra-omics associations on a MultiOmicsData object
#'
#' @param mo A MultiOmicsData object.
#' @param layers Character vector of layer names to include. NULL = all layers.
#' @param top_n Integer, per-layer feature pre-filter by variance.
#' @param max_pairs_for_mic Integer, max pairs sent to MIC per call.
#' @param mic_pvalue_method Character, \code{"permutation"} or \code{"none"}.
#' @param n_perm Integer, permutations for shared MIC null.
#' @param score_method Character, \code{"combined"} or \code{"nonlinear"}.
#' @param score_weight Numeric, weight of |rho| in combined score.
#' @param p_adjust Character, p.adjust method.
#' @param p_threshold Numeric, significance cutoff.
#' @param rho_linear_min Numeric, |rho| cutoff for linear vs nonlinear.
#' @param verbose Logical.
#'
#' @return A list with:
#'   \item{cross}{named list of \code{run_cross_omics_association} results}
#'   \item{intra}{named list of \code{run_intra_omics_association} results}
#'   \item{summary}{data.frame of pair counts / significant counts per combo}
#'
#' @examples
#' \dontrun{
#'   mo <- preprocess_multiomics(create_multiomics_data(...))
#'   all <- run_all_omics_associations(mo, top_n = 60)
#' }
#'
#' @export
run_all_omics_associations <- function(mo,
                                       layers = NULL,
                                       top_n = NULL,
                                       max_pairs_for_mic = 2000,
                                       mic_pvalue_method = c("permutation", "none"),
                                       n_perm = 200,
                                       score_method = c("combined", "nonlinear"),
                                       score_weight = 0.5,
                                       p_adjust = "BH",
                                       p_threshold = 0.05,
                                       rho_linear_min = 0.3,
                                       verbose = TRUE) {
  mic_pvalue_method <- match.arg(mic_pvalue_method)
  score_method      <- match.arg(score_method)
  if (!inherits(mo, "MultiOmicsData")) stop("mo must be a MultiOmicsData object.")
  if (is.null(layers)) layers <- names(mo$omics)
  missing <- setdiff(layers, names(mo$omics))
  if (length(missing) > 0) stop(sprintf("Unknown layer(s): %s", paste(missing, collapse = ", ")))

  mats <- lapply(layers, function(nm) get_omics_matrix(mo, nm))
  names(mats) <- layers

  # 跨层两两组合
  cross <- list(); intra <- list(); summ <- list()
  for (i in seq_along(layers)) {
    for (j in seq_along(layers)) {
      if (i < j) {
        key <- sprintf("%s__%s", layers[i], layers[j])
        res <- run_cross_omics_association(
          mats[[i]], mats[[j]], name_x = layers[i], name_y = layers[j],
          top_n = top_n, max_pairs_for_mic = max_pairs_for_mic,
          mic_pvalue_method = mic_pvalue_method, n_perm = n_perm,
          score_method = score_method, score_weight = score_weight,
          p_adjust = p_adjust, p_threshold = p_threshold,
          rho_linear_min = rho_linear_min, verbose = verbose)
        cross[[key]] <- res
        summ[[key]] <- data.frame(
          combo = key, type = "cross",
          n_pairs = res$params$n_pairs, n_significant = res$params$n_significant,
          n_nonlinear = res$params$n_nonlinear,
          n_features = res$params$n_features_x + res$params$n_features_y,
          stringsAsFactors = FALSE)
      }
    }
    # 层内
    key <- layers[i]
    res <- run_intra_omics_association(
      mats[[i]], name = layers[i],
      top_n = top_n, max_pairs_for_mic = max_pairs_for_mic,
      mic_pvalue_method = mic_pvalue_method, n_perm = n_perm,
      score_method = score_method, score_weight = score_weight,
      p_adjust = p_adjust, p_threshold = p_threshold,
      rho_linear_min = rho_linear_min, verbose = verbose)
    intra[[key]] <- res
    summ[[key]] <- data.frame(
      combo = key, type = "intra",
      n_pairs = res$params$n_pairs, n_significant = res$params$n_significant,
      n_nonlinear = res$params$n_nonlinear,
      n_features = res$params$n_features,
      stringsAsFactors = FALSE)
  }

  list(
    cross  = cross,
    intra  = intra,
    summary = do.call(rbind, summ)
  )
}
