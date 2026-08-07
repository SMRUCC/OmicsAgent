# =============================================================================
# OmicsFlow: Spearman + MIC Association Network
# -----------------------------------------------------------------------------
# 为跨组学（不同层之间）与组学内（同层内部）的 feature 构建
# Spearman（单调线性关联）+ MIC（最大信息Coefficient，任意非线性关联）双指标关联网络。
#
# 设计要点：
#   1. 矩阵约定：features x samples（行=Feature，列=样本），与 cross_correlation.R 一致。
#   2. 两阶段计算：先用向量化 Spearman 全量计算（毫秒级），按 |rho| 取 Top K
#      候选对，再仅对候选对调用 minerva::mine() 计算 MIC —— 把 MIC 的网格搜索
#      成本从 "all pairs" 降到 "candidate set"，是本模块的Core性能决策。
#   3. MIC 显著性：采用"shared null distribution"置换检验（minerva 的 mine() 本身不返回 p 值）。
#      在同样本量下，无关联Feature对的 MIC 零分布仅依赖于 n，故对所有候选对
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
#   drop_zero_variance()  : 移除零方差Feature（multiomics_data.R）
#   get_omics_matrix()    : 从 MultiOmicsData 取表达矩阵
#   get_feature_info()    : 从 MultiOmicsData 取Feature注释
#   export_table()        : 表格导出（utils/）

# -----------------------------------------------------------------------------
# 内部工具：按方差（信号强度）选择 Top N Feature
# -----------------------------------------------------------------------------
#' 从矩阵中选择变异最大的 Top N 个Feature
#'
#' @param mat 数值矩阵（Feature x 样本）。
#' @param top_n 整数，按行方差降序保留的Feature数量。
#'   若为 NULL 或大于 nrow(mat)，则保留全部Feature。
#' @param label 字符，进度提示信息中使用的名称。
#' @param verbose 逻辑值，是否打印进度。
#' @return 最多包含 \code{top_n} 行的一个数值矩阵。
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
#' 向量化 Spearman 相关矩阵（秩变换 + 标准化叉积）
#'
#' @param mat_x 数值矩阵（features_x x 样本）。
#' @param mat_y 数值矩阵（features_y x 样本）。必须与 \code{mat_x} 具有
#'   相同的列顺序 / 样本集合。
#' @return 一个列表，含有 \code{rho}（features_x x features_y）与
#'   \code{pval}（features_x x features_y）两个矩阵。
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
# 内部工具：shared null distribution置换 —— 返回 n_perm 个随机打乱对的 MIC 经验分布
# -----------------------------------------------------------------------------
#' 通过置换计算共享的 MIC 零分布
#'
#' @param mat 参考矩阵（Feature x 样本），用于抽取随机Feature对进行置换。
#' @param n_perm 整数，随机置换次数。
#' @param n_sample 整数，实际使用的样本数（取交集之后）。
#' @param verbose 逻辑值。
#' @return 长度为 \code{n_perm} 的数值向量，包含随机（零）Feature对的 MIC 值。
#'   若发生任何错误则返回 \code{NULL}。
#' @noRd
.mic_null_distribution <- function(mat, n_perm = 200, n_sample = NULL,
                                   verbose = TRUE) {
  if (!requireNamespace("minerva", quietly = TRUE)) return(NULL)
  if (is.null(n_sample)) n_sample <- ncol(mat)
  pf <- nrow(mat)
  if (pf < 2) return(NULL)
  out <- numeric(n_perm)
  for (i in seq_len(n_perm)) {
    # 抽取两个**不同**的Feature。原实现两次独立抽样可能取到同一行，
    # 此时 a 与打乱后的 b 来自同一分布，会系统性抬高零分布，
    # 使经验 p 值偏保守。
    ij <- sample.int(pf, size = min(2L, pf), replace = FALSE)
    a <- mat[ij[1], ]
    b <- mat[if (length(ij) > 1) ij[2] else ij[1], ]
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
#' 对一组Feature对批量计算 MIC
#'
#' @param mat_x 数值矩阵。
#' @param mat_y 数值矩阵。
#' @param pairs 两列整数矩阵，含有 (row_in_x, row_in_y) 的索引。
#' @param verbose 逻辑值。
#' @return 与 \code{pairs} 对齐的 MIC 值数值向量（若 minerva 不可用或某对
#'   计算失败则为 NA）。
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
# 内部工具：选取送入 MIC 计算的候选Feature对
# -----------------------------------------------------------------------------
#' 选择 MIC 候选对
#'
#' @description MIC 的价值在于发现 Spearman 捕捉不到的非线性关联。
#'   原实现一律按 |rho| 降序取 Top-K，导致候选对全是高度线性的边
#'   （实测 top 2000 的 |rho| 落在 [0.951, 0.973]），而
#'   \code{association} 判定 "nonlinear" 要求 |rho| < rho_linear_min
#'   （默认 0.3）——两个条件互斥，nonlinear 永远为 0，MIC 实际上白算了。
#'
#'   此处提供三种策略：
#'   \itemize{
#'     \item \code{"balanced"}（默认）：一半取 |rho| 最高（验证强线性关联），
#'       一半取 |rho| < rho_linear_min 中 MIC 最有可能有发现的低 rho 对，
#'       使非线性关联真正可被检出。
#'     \item \code{"low_rho"}：全部取 |rho| < rho_linear_min 的对，
#'       专注非线性发现。
#'     \item \code{"top_rho"}：保持原行为，按 |rho| 降序取 Top-K。
#'   }
#'
#' @param rho 数值向量，Spearman rho。
#' @param k 整数，候选对数量上限。
#' @param strategy 字符，候选选取策略。
#' @param rho_linear_min 数值，线性/非线性的 |rho| 分界。
#'
#' @return 整数向量，候选对在 rho 中的下标。
#'
#' @keywords internal
#' @noRd
.select_mic_candidates <- function(rho, k,
                                   strategy = "balanced",
                                   rho_linear_min = 0.3) {
  n <- length(rho)
  k <- min(k, n)
  if (k <= 0) return(integer(0))

  arho <- abs(rho)
  ord_desc <- order(arho, decreasing = TRUE)

  if (identical(strategy, "top_rho")) {
    return(ord_desc[seq_len(k)])
  }

  low_idx <- which(arho < rho_linear_min)

  if (identical(strategy, "low_rho")) {
    if (length(low_idx) == 0) return(ord_desc[seq_len(k)])
    # 低 rho 内部按 |rho| 降序：更接近阈值的边信息量通常更高
    low_sorted <- low_idx[order(arho[low_idx], decreasing = TRUE)]
    return(low_sorted[seq_len(min(k, length(low_sorted)))])
  }

  # balanced：高 rho 与低 rho 各占一半，不足的一方由另一方补足
  n_low <- min(length(low_idx), floor(k / 2))
  low_sel <- if (n_low > 0) {
    low_sorted <- low_idx[order(arho[low_idx], decreasing = TRUE)]
    low_sorted[seq_len(n_low)]
  } else {
    integer(0)
  }
  high_sel <- setdiff(ord_desc, low_sel)
  high_sel <- high_sel[seq_len(min(k - length(low_sel), length(high_sel)))]

  sort(unique(c(low_sel, high_sel)))
}


# -----------------------------------------------------------------------------
# 内部工具：组装标准 9 列边表
# -----------------------------------------------------------------------------
#' 组装标准的 9 列关联边表
#'
#' @param src 源Feature名称的字符向量。
#' @param tgt 目标Feature名称的字符向量。
#' @param rho 数值向量，Spearman rho。
#' @param rho_p 数值向量，Spearman p 值。
#' @param mic 数值向量，MIC（允许为 NA）。
#' @param mic_p 数值向量，MIC p 值（允许为 NA）。
#' @param score_method 字符，\code{"combined"} 或 \code{"nonlinear"}。
#' @param score_weight 数值，综合评分中 |rho| 的权重。
#' @param p_adjust 字符，传给 \code{p.adjust} 用于合并 p 值的方法。
#' @param p_threshold 数值，校正后合并 p 值的显著性阈值。
#' @param rho_linear_min 数值，超过该 |rho| 的关联被视为线性（而非非线性）。
#' @return 恰好包含 9 列的数据框：
#'   source、target、spearman-rho、spearman-pval、MIC、MIC-pvalue、
#'   score、pvalue、association。列名使用 check.names = FALSE 设置，
#'   以保持带连字符的列名在导出时不被改变。
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
  # X^2 = -2 * sum(ln p_i) ~ chi-square(df = 2k)，k 为参与合并的 p 值个数。
  #
  # 关键：MIC 只对候选对（按 |rho| 取 Top max_pairs_for_mic）计算，
  # 其余边的 mic_p 恒为 NA。原实现按"整体是否存在非 NA 的 mic_p"来决定
  # 是否走双 p 合并，一旦走双 p 分支，非候选边的 log(NA) 会让 chisq 变成 NA，
  # 随后被统一置为 merged_p = 1，等价于把所有非候选边强制判为不显著，
  # 使显著边数恒等于 max_pairs_for_mic。
  # 正确做法是**逐边**判断：有 MIC p 的用 df=4 合并，没有的仅用 Spearman p
  # 并以 df=2 计算（即退化为 Spearman 自身的 p 值）。
  p_rho <- pmax(rho_p, 1e-300)
  log_rho <- log(p_rho)
  
  if (!is.null(mic_p) && any(!is.na(mic_p))) {
    p_mic <- pmax(mic_p, 1e-300)
    has_mic <- !is.na(p_mic)
    chisq <- ifelse(has_mic, -2 * (log_rho + log(ifelse(has_mic, p_mic, 1))),
                    -2 * log_rho)
    df_vec <- ifelse(has_mic, 4, 2)
  } else {
    chisq <- -2 * log_rho
    df_vec <- rep(2, n)
  }
  merged_p <- stats::pchisq(chisq, df = df_vec, lower.tail = FALSE)
  merged_p[is.na(merged_p)] <- 1
  
  # BH 校正
  padj <- stats::p.adjust(merged_p, method = p_adjust)
  
  # ---- association 分类 ----
  sig <- !is.na(padj) & padj < p_threshold
  assoc <- rep("not_significant", n)
  assoc[sig & rho >= 0]  <- "positive"
  assoc[sig & rho < 0]   <- "negative"
  # 只有在实际算过 MIC 的边上才可能判定为 "nonlinear"：
  # |rho| 低但显著，且 MIC 提供了非线性关联证据。
  # 若 MIC 为 NA（非候选对），缺乏非线性证据，仍按 rho 的符号归类。
  has_mic_val <- if (is.null(mic)) rep(FALSE, n) else !is.na(mic)
  assoc[sig & abs(rho) < rho_linear_min & has_mic_val] <- "nonlinear"
  
  df <- data.frame(
    source        = src,
    target        = tgt,
    `spearman-rho` = rho,
    `spearman-pval` = rho_p,
    MIC            = if (is.null(mic)) rep(NA_real_, n) else mic,
    `MIC-pvalue`   = if (is.null(mic_p)) rep(NA_real_, n) else mic_p,
    score          = score,
    pvalue         = merged_p,
    padj           = padj,
    association    = assoc,
    check.names = FALSE
  )
  # association 列是依据 padj（BH 校正后）判定的。此前 padj 仅作为 attr 附带，
  # 而 attr 会在 data.frame 取子集 / rbind / 写 CSV 时全部丢失，导致下游
  # （如 build_association_network）只能退而用未校正的 pvalue 过滤，
  # 与 association 的判定口径不一致。因此提升为正式列。
  attr(df, "padj") <- padj   # 保留以兼容既有调用方
  df
}


# -----------------------------------------------------------------------------
# Core函数一：跨组学关联（两个不同层之间）
# -----------------------------------------------------------------------------
#' 跨组学 Spearman + MIC 关联网络
#'
#' 使用 Spearman 相关（向量化）与 MIC（最大互信息Coefficient），计算两个组学层之间
#' 每一对Feature的关联。为控制 MIC 的计算开销，仅将按 |Spearman rho| 排序的
#' Top-K Feature对送入 \code{minerva::mine()}。
#'
#' @param mat_x 第一层的数值矩阵（Feature x 样本）。
#' @param mat_y 第二层的数值矩阵（Feature x 样本）。
#' @param name_x 字符，第一层的标签（用于源Feature命名）。
#' @param name_y 字符，第二层的标签。
#' @param top_n 整数，配对前按方差预筛选每层 Top-N 个Feature。NULL 表示保留全部。
#' @param max_pairs_for_mic 整数，送入 MIC 的最大Feature对数量
#'   （按 |rho| 降序选取）。这是最关键的性能控制参数。
#' @param mic_pvalue_method 字符，\code{"permutation"}（shared null distribution）
#'   或 \code{"none"}（跳过，MIC-pvalue = NA）。
#' @param n_perm 整数，共享 MIC 零分布所用的置换次数。
#' @param score_method 字符，\code{"combined"}（默认：
#'   \code{w*|rho| + (1-w)*MIC}）或 \code{"nonlinear"}（\code{MIC - rho^2}）。
#' @param score_weight 数值，取值 [0,1]，综合评分中 |rho| 的权重。
#' @param p_adjust 字符，合并 p 值所用 \code{p.adjust} 的方法。
#' @param p_threshold 数值，校正后合并 p 值的显著性阈值。
#' @param rho_linear_min 数值，超过该 |rho| 的显著对被判定为线性
#'   （positive/negative），否则为 \code{nonlinear}。
#' @param verbose 逻辑值，是否打印进度。
#'
#' @return 一个列表：
#'   \item{edges}{包含 9 列的数据框：source、target、spearman-rho、
#'     spearman-pval、MIC、MIC-pvalue、score、pvalue、association。}
#'   \item{nodes}{数据框：name、omics、degree。}
#'   \item{params}{运行参数与计数的列表。}
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
                                        mic_candidate = c("balanced", "low_rho", "top_rho"),
                                        verbose = TRUE) {
  mic_pvalue_method <- match.arg(mic_pvalue_method)
  score_method      <- match.arg(score_method)
  mic_candidate     <- match.arg(mic_candidate)
  
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
  
  # 候选对选取（见 .select_mic_candidates：按 |rho| 取 Top-K 会让
  # nonlinear 判定永远无法触发）
  k <- min(max_pairs_for_mic, n_pairs)
  cand <- .select_mic_candidates(rho, k, mic_candidate, rho_linear_min)
  k <- length(cand)
  if (verbose) {
    cat(sprintf(paste0("[assoc] Selected %d candidate pairs for MIC ",
                       "(strategy=%s; %d with |rho| < %.2f).\n"),
                k, mic_candidate, sum(abs(rho[cand]) < rho_linear_min),
                rho_linear_min))
  }

  pairs_idx <- cbind(match(src_x[cand], fx), match(src_y[cand], fy))
  mic  <- rep(NA_real_, n_pairs)
  mic_p <- rep(NA_real_, n_pairs)
  
  mic_calc <- .compute_mic_for_pairs(mat_x, mat_y, pairs_idx, verbose = FALSE)
  mic[cand]  <- mic_calc
  if (verbose) cat(sprintf("[assoc] MIC computed for %d candidate pairs (minerva).\n", k))
  
  # MIC p 值：shared null distribution
  if (mic_pvalue_method == "permutation" && any(!is.na(mic))) {
    null_dist <- .mic_null_distribution(mat_x, n_perm = n_perm,
                                        n_sample = ncol(mat_x), verbose = verbose)
    if (!is.null(null_dist) && length(null_dist) > 0) {
      thr <- stats::quantile(null_dist, probs = 0.95, na.rm = TRUE)
      n_null <- sum(!is.na(null_dist))
      mic_p[cand] <- sapply(mic[cand], function(m) {
        if (is.na(m)) return(NA_real_)
        # (b+1)/(R+1) 伪计数：避免经验 p 恰为 0 导致 Fisher 合并 p 值为 0
        (sum(null_dist >= m, na.rm = TRUE) + 1) / (n_null + 1)
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
# Core函数二：组学内关联（同一层内部，上三角）
# -----------------------------------------------------------------------------
#' 组学内 Spearman + MIC 关联网络
#'
#' 计算单个组学层\emph{内部}各Feature之间的关联。仅评估Feature自相关矩阵中严格的上三角
#' （不含自配对、不含重复对）。评分 / p 值 / MIC 的方法学详见
#' \code{run_cross_omics_association}。
#'
#' @param mat 数值矩阵（Feature x 样本）。
#' @param name 字符，该层的标签。
#' @param top_n 整数，按方差预筛选 Top-N 个Feature。
#' @param max_pairs_for_mic 整数，送入 MIC 的最大Feature对数。
#' @param mic_pvalue_method 字符，\code{"permutation"} 或 \code{"none"}。
#' @param n_perm 整数，共享 MIC 零分布所用的置换次数。
#' @param score_method 字符，\code{"combined"} 或 \code{"nonlinear"}。
#' @param score_weight 数值，综合评分中 |rho| 的权重。
#' @param p_adjust 字符，合并 p 值所用 p.adjust 方法。
#' @param p_threshold 数值，校正后合并 p 值的显著性阈值。
#' @param rho_linear_min 数值，线性与线性标签判定的 |rho| 阈值。
#' @param mic_candidate 字符，MIC 候选对选取策略：
#'   \code{"balanced"}（默认，高/低 rho 各半，使非线性关联可被检出）、
#'   \code{"low_rho"}（只取 |rho| < rho_linear_min）或
#'   \code{"top_rho"}（按 |rho| 降序，旧行为）。
#' @param verbose 逻辑值，是否打印进度。
#'
#' @return 一个列表，含有 \code{edges}（9 列）、\code{nodes}、\code{params}
#'   （详见 \code{run_cross_omics_association}）。
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
                                        mic_candidate = c("balanced", "low_rho", "top_rho"),
                                        verbose = TRUE) {
  mic_pvalue_method <- match.arg(mic_pvalue_method)
  score_method      <- match.arg(score_method)
  mic_candidate     <- match.arg(mic_candidate)
  
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
  
  k <- min(max_pairs_for_mic, n_pairs)
  cand <- .select_mic_candidates(rho, k, mic_candidate, rho_linear_min)
  k <- length(cand)
  if (verbose) {
    cat(sprintf(paste0("[assoc] Selected %d candidate pairs for MIC ",
                       "(strategy=%s; %d with |rho| < %.2f).\n"),
                k, mic_candidate, sum(abs(rho[cand]) < rho_linear_min),
                rho_linear_min))
  }

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
      n_null <- sum(!is.na(null_dist))
      mic_p[cand] <- sapply(mic[cand], function(m) {
        if (is.na(m)) return(NA_real_)
        # (b+1)/(R+1) 伪计数：避免经验 p 恰为 0 导致 Fisher 合并 p 值为 0
        (sum(null_dist >= m, na.rm = TRUE) + 1) / (n_null + 1)
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
      mic_candidate = mic_candidate,
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
#'
#' @details degree 只统计**显著**边（association != "not_significant"），
#'   因为不显著边在网络中不会被绘制，把它们计入会让每个节点的度都接近
#'   "参与的总配对数"，从而完全失去区分度。
#'
#'   历史实现用带重复名的 `names_vec` 构造 `deg` 命名向量，再通过
#'   `deg[s] <- deg[s] + 1L` 按名字累加。R 的按名索引只会命中**第一个**同名
#'   元素，导致绝大多数计数被写到重复项上而丢失，degree 统计整体错误；
#'   同时逐边 for 循环在数万条边时非常慢。此处改为对唯一节点建立索引后
#'   用 `tabulate()` 向量化统计。
#'
#' @noRd
.build_node_table <- function(names_vec, omics_vec, edges) {
  # 去重（source/target 中同一节点会出现多次）
  uniq <- !duplicated(names_vec)
  node_names <- names_vec[uniq]
  node_omics <- omics_vec[uniq]
  n_nodes <- length(node_names)

  deg <- integer(n_nodes)
  if (!is.null(edges) && nrow(edges) > 0) {
    keep <- edges$association != "not_significant"
    keep[is.na(keep)] <- FALSE
    if (any(keep)) {
      si <- match(edges$source[keep], node_names)
      ti <- match(edges$target[keep], node_names)
      idx <- c(si, ti)
      idx <- idx[!is.na(idx)]
      deg <- tabulate(idx, nbins = n_nodes)
    }
  }

  data.frame(
    name   = node_names,
    omics  = node_omics,
    degree = as.integer(deg),
    stringsAsFactors = FALSE
  )
}


# -----------------------------------------------------------------------------
# 便捷封装：遍历 MultiOmicsData 全部跨层组合 + 层内组合
# -----------------------------------------------------------------------------
#' 对 MultiOmicsData 对象运行全部跨层与层内关联分析
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param layers 字符向量，指定要包含的层名称。NULL 表示所有层。
#' @param top_n 整数，每层按方差预筛选Feature。
#' @param max_pairs_for_mic 整数，每次调用送入 MIC 的最大Feature对数。
#' @param mic_pvalue_method 字符，\code{"permutation"} 或 \code{"none"}。
#' @param n_perm 整数，共享 MIC 零分布所用的置换次数。
#' @param score_method 字符，\code{"combined"} 或 \code{"nonlinear"}。
#' @param score_weight 数值，综合评分中 |rho| 的权重。
#' @param p_adjust 字符，p.adjust 方法。
#' @param p_threshold 数值，显著性阈值。
#' @param rho_linear_min 数值，线性与非线性的 |rho| 阈值。
#' @param verbose 逻辑值。
#'
#' @return 一个列表：
#'   \item{cross}{\code{run_cross_omics_association} 结果的有名列表}
#'   \item{intra}{\code{run_intra_omics_association} 结果的有名列表}
#'   \item{summary}{每组合的对数与显著数对的数据框}
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
