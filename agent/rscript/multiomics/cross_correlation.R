# ==============================================================================
# OmicsFlow：跨组学特征相关性分析
# ==============================================================================
# 两个组学层之间特征级别的相关性（向量化计算），用于
# 微生物-代谢物、以及微生物-挥发物驱动的关联分析。
# ==============================================================================

#' 两个矩阵之间的跨组学特征相关性
#'
#' @description 计算在相同样本上测得的、两个组学层各特征之间的完整相关矩阵。
#'   计算全程向量化（标准化矩阵叉积），因此诸如 2000 x 1000 这样的大规模
#'   特征块可在数秒内完成，而无需运行数百万次 \code{cor.test()} 调用。
#'   p 值由 t 分布解析得出，并针对多重检验进行校正；只有通过阈值的特征对
#'   才会以稀疏 \code{pairs} 表的形式返回。
#'
#' @param mat_x 第一层的数值矩阵（特征 x 样本）。
#' @param mat_y 第二层的数值矩阵（特征 x 样本）。
#' @param method 相关方法，"pearson" 或 "spearman"。spearman 为对各行先排序
#'   再套用同样的向量化路径得到。默认："pearson"。
#' @param p_adjust 传给 \code{p.adjust()} 的多重检验校正方法。默认："BH"。
#' @param r_threshold 报告某对特征所需的最小绝对相关系数。默认：0.6。
#' @param p_threshold 报告某对特征所需的最大校正后 p 值。默认：0.05。
#' @param max_pairs 稀疏表中保留的最大特征对数；超出上限时保留关联最强者。
#'   默认：100000。
#' @param name_x 存储在 pairs 表中的第一层标签。默认："x"。
#' @param name_y 存储在 pairs 表中的第二层标签。默认："y"。
#' @param verbose 逻辑值，是否打印进度信息。默认：TRUE。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{cor_matrix}: 相关矩阵（features_x x features_y）。
#'     \item \code{p_matrix}: 原始 p 值矩阵。
#'     \item \code{padj_matrix}: 校正后的 p 值矩阵。
#'     \item \code{pairs}: 显著特征对的数据框，列包括
#'       feature_x、feature_y、omics_x、omics_y、r、p、padj。
#'     \item \code{params}: 所使用设置的列表。
#'   }
#'
#' @examples
#' \dontrun{
#' res <- run_cross_correlation(microbiome_mat, metabolome_mat,
#'                              r_threshold = 0.6, name_x = "microbiome",
#'                              name_y = "metabolome")
#' head(res$pairs)
#' }
#'
#' @export
run_cross_correlation <- function(mat_x, mat_y,
                                  method = "pearson",
                                  p_adjust = "BH",
                                  r_threshold = 0.6,
                                  p_threshold = 0.05,
                                  max_pairs = 100000,
                                  name_x = "x",
                                  name_y = "y",
                                  verbose = TRUE) {
  method <- match.arg(method, c("pearson", "spearman"))

  if (!is.matrix(mat_x)) mat_x <- as.matrix(mat_x)
  if (!is.matrix(mat_y)) mat_y <- as.matrix(mat_y)

  common <- intersect(colnames(mat_x), colnames(mat_y))
  if (length(common) < 4) {
    stop("At least 4 shared samples are required for correlation analysis.")
  }
  mat_x <- mat_x[, common, drop = FALSE]
  mat_y <- mat_y[, common, drop = FALSE]

  mat_x <- drop_zero_variance(mat_x, label = name_x, verbose = verbose)
  mat_y <- drop_zero_variance(mat_y, label = name_y, verbose = verbose)

  if (nrow(mat_x) == 0 || nrow(mat_y) == 0) {
    stop("No informative features left after removing zero-variance rows.")
  }

  # Spearman 即秩上的 Pearson
  if (method == "spearman") {
    mat_x <- t(apply(mat_x, 1, rank))
    mat_y <- t(apply(mat_y, 1, rank))
    mat_x <- drop_zero_variance(mat_x, label = paste0(name_x, " (ranked)"),
                                verbose = FALSE)
    mat_y <- drop_zero_variance(mat_y, label = paste0(name_y, " (ranked)"),
                                verbose = FALSE)
  }

  n <- length(common)

  if (verbose) {
    cat(sprintf("[cross-cor] %s (%d features) vs %s (%d features), n = %d samples, method = %s\n",
                name_x, nrow(mat_x), name_y, nrow(mat_y), n, method))
  }

  # 按行标准化 -> 相关系数即为简单的叉积 ---------
  zx <- .row_standardise(mat_x)
  zy <- .row_standardise(mat_y)

  cor_matrix <- (zx %*% t(zy)) / (n - 1)
  cor_matrix[cor_matrix > 1] <- 1
  cor_matrix[cor_matrix < -1] <- -1

  # 由 t 分布解析得到 p 值 ---------------------------------
  df <- n - 2
  denom <- 1 - cor_matrix^2
  denom[denom <= .Machine$double.eps] <- .Machine$double.eps
  t_stat <- cor_matrix * sqrt(df / denom)
  p_matrix <- 2 * stats::pt(-abs(t_stat), df = df)
  dimnames(p_matrix) <- dimnames(cor_matrix)

  padj_vec <- stats::p.adjust(as.vector(p_matrix), method = p_adjust)
  padj_matrix <- matrix(padj_vec, nrow = nrow(p_matrix),
                        dimnames = dimnames(p_matrix))

  # 显著特征对的稀疏表 -----------------------------------------
  sel <- which(abs(cor_matrix) >= r_threshold & padj_matrix <= p_threshold,
               arr.ind = TRUE)

  if (nrow(sel) == 0) {
    if (verbose) {
      cat(sprintf("[cross-cor] no pair passed |r| >= %.2f and padj <= %.3f\n",
                  r_threshold, p_threshold))
    }
    pairs <- data.frame(
      feature_x = character(0), feature_y = character(0),
      omics_x = character(0), omics_y = character(0),
      r = numeric(0), p = numeric(0), padj = numeric(0),
      stringsAsFactors = FALSE
    )
  } else {
    pairs <- data.frame(
      feature_x = rownames(cor_matrix)[sel[, 1]],
      feature_y = colnames(cor_matrix)[sel[, 2]],
      omics_x = name_x,
      omics_y = name_y,
      r = cor_matrix[sel],
      p = p_matrix[sel],
      padj = padj_matrix[sel],
      stringsAsFactors = FALSE
    )
    pairs <- pairs[order(-abs(pairs$r)), , drop = FALSE]

    if (nrow(pairs) > max_pairs) {
      if (verbose) {
        cat(sprintf("[cross-cor] %d significant pairs truncated to the top %d by |r|\n",
                    nrow(pairs), max_pairs))
      }
      pairs <- pairs[seq_len(max_pairs), , drop = FALSE]
    }
    rownames(pairs) <- NULL

    if (verbose) {
      cat(sprintf("[cross-cor] %d significant pair(s) retained (%d positive, %d negative)\n",
                  nrow(pairs), sum(pairs$r > 0), sum(pairs$r < 0)))
    }
  }

  return(list(
    cor_matrix = cor_matrix,
    p_matrix = p_matrix,
    padj_matrix = padj_matrix,
    pairs = pairs,
    params = list(method = method, n_samples = n,
                  r_threshold = r_threshold, p_threshold = p_threshold,
                  p_adjust = p_adjust, name_x = name_x, name_y = name_y)
  ))
}


#' 按行标准化辅助函数
#'
#' @param mat 数值矩阵（特征 x 样本）。
#'
#' @return 每一行均中心化并缩放为单位标准差的矩阵。
#'
#' @keywords internal
.row_standardise <- function(mat) {
  rm_ <- rowMeans(mat, na.rm = TRUE)
  centred <- mat - rm_
  sd_ <- sqrt(rowSums(centred^2, na.rm = TRUE) / (ncol(mat) - 1))
  sd_[sd_ <= .Machine$double.eps] <- .Machine$double.eps
  centred / sd_
}


#' 针对多个层对运行跨组学相关性分析
#'
#' @description 便利封装，针对 MultiOmicsData 对象中若干组学层对的列表，
#'   循环调用 \code{run_cross_correlation()}。
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param layer_pairs 长度为 2 的字符向量组成的列表，用于指定要相关的层，
#'   例如 \code{list(c("microbiome", "metabolome"))}。
#' @param method 相关方法。默认："spearman"。
#' @param r_threshold 最小绝对相关系数。默认：0.6。
#' @param p_threshold 最大校正后 p 值。默认：0.05。
#' @param max_pairs 每次比较保留的最大特征对数。默认：100000。
#' @param verbose 逻辑值，是否打印进度。默认：TRUE。
#'
#' @return \code{run_cross_correlation()} 结果的有名列表，名称为
#'   "layerA__layerB"。额外元素 \code{all_pairs} 拼接了所有比较的稀疏对表。
#'
#' @examples
#' \dontrun{
#' res <- run_all_pairwise_correlation(
#'   mo, list(c("microbiome", "metabolome"), c("microbiome", "volatilome")))
#' }
#'
#' @export
run_all_pairwise_correlation <- function(mo, layer_pairs,
                                         method = "spearman",
                                         r_threshold = 0.6,
                                         p_threshold = 0.05,
                                         max_pairs = 100000,
                                         verbose = TRUE) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (!is.list(layer_pairs) || length(layer_pairs) == 0) {
    stop("layer_pairs must be a non-empty list of length-2 character vectors.")
  }

  results <- list()
  all_pairs <- NULL

  for (lp in layer_pairs) {
    if (length(lp) != 2) {
      warning("Each element of layer_pairs must have exactly two layer names.")
      next
    }
    key <- paste(lp[1], lp[2], sep = "__")

    res <- tryCatch({
      run_cross_correlation(
        mat_x = get_omics_matrix(mo, lp[1]),
        mat_y = get_omics_matrix(mo, lp[2]),
        method = method,
        r_threshold = r_threshold,
        p_threshold = p_threshold,
        max_pairs = max_pairs,
        name_x = lp[1],
        name_y = lp[2],
        verbose = verbose
      )
    }, error = function(e) {
      cat(sprintf("[cross-cor] pair %s failed: %s\n", key, conditionMessage(e)))
      NULL
    })

    if (!is.null(res)) {
      results[[key]] <- res
      if (nrow(res$pairs) > 0) {
        all_pairs <- rbind(all_pairs, res$pairs)
      }
    }
  }

  if (is.null(all_pairs)) {
    all_pairs <- data.frame(
      feature_x = character(0), feature_y = character(0),
      omics_x = character(0), omics_y = character(0),
      r = numeric(0), p = numeric(0), padj = numeric(0),
      stringsAsFactors = FALSE
    )
  }

  results$all_pairs <- all_pairs
  return(results)
}


#' 对每个特征汇总跨组学相关性结果
#'
#' @description 将稀疏特征对表聚合为每个特征的汇总（显著伙伴数、平均与最大
#'   绝对相关系数），可用于筛选驱动类群或核心枢纽代谢物。
#'
#' @param pairs 数据框，格式同 \code{run_cross_correlation()} 返回的
#'   \code{pairs} 元素。
#' @param side 汇总哪一侧，"x"、"y" 或 "both"。默认："both"。
#' @param top_n 返回的行数，按伙伴数量排序。默认：50。
#'
#' @return 数据框，列包括 feature、omics、n_partners、n_positive、
#'   n_negative、mean_abs_r 与 max_abs_r。
#'
#' @examples
#' \dontrun{
#' drivers <- summarise_correlation_partners(res$pairs, side = "x", top_n = 20)
#' }
#'
#' @export
summarise_correlation_partners <- function(pairs, side = "both", top_n = 50) {
  side <- match.arg(side, c("both", "x", "y"))

  if (is.null(pairs) || nrow(pairs) == 0) {
    return(data.frame(feature = character(0), omics = character(0),
                      n_partners = integer(0), n_positive = integer(0),
                      n_negative = integer(0), mean_abs_r = numeric(0),
                      max_abs_r = numeric(0), stringsAsFactors = FALSE))
  }

  parts <- list()
  if (side %in% c("both", "x")) {
    parts[[length(parts) + 1]] <- data.frame(
      feature = pairs$feature_x, omics = pairs$omics_x,
      r = pairs$r, stringsAsFactors = FALSE)
  }
  if (side %in% c("both", "y")) {
    parts[[length(parts) + 1]] <- data.frame(
      feature = pairs$feature_y, omics = pairs$omics_y,
      r = pairs$r, stringsAsFactors = FALSE)
  }
  long <- do.call(rbind, parts)

  key <- paste(long$omics, long$feature, sep = "\r")
  split_r <- split(long$r, key)

  out <- data.frame(
    feature = vapply(strsplit(names(split_r), "\r", fixed = TRUE),
                     function(x) x[2], character(1)),
    omics = vapply(strsplit(names(split_r), "\r", fixed = TRUE),
                   function(x) x[1], character(1)),
    n_partners = vapply(split_r, length, integer(1)),
    n_positive = vapply(split_r, function(x) sum(x > 0), integer(1)),
    n_negative = vapply(split_r, function(x) sum(x < 0), integer(1)),
    mean_abs_r = vapply(split_r, function(x) mean(abs(x)), numeric(1)),
    max_abs_r = vapply(split_r, function(x) max(abs(x)), numeric(1)),
    stringsAsFactors = FALSE
  )
  rownames(out) <- NULL
  out <- out[order(-out$n_partners, -out$max_abs_r), , drop = FALSE]

  if (nrow(out) > top_n) out <- out[seq_len(top_n), , drop = FALSE]
  rownames(out) <- NULL
  return(out)
}
