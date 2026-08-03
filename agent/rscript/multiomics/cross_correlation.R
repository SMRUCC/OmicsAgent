# ==============================================================================
# OmicsFlow: Cross-Omics Feature Correlation
# ==============================================================================
# Vectorised feature-level correlation between two omics layers, used for
# microbiome-metabolite and microbiome-volatilome driver analysis.
# ==============================================================================

#' Cross-omics feature correlation between two matrices
#'
#' @description Computes the full correlation matrix between the features of
#'   two omics layers measured on the same samples. The computation is fully
#'   vectorised (standardised matrix cross-product) so that large blocks such
#'   as 2000 x 1000 features are evaluated in seconds instead of running
#'   millions of \code{cor.test()} calls. P-values are derived analytically
#'   from the t distribution and adjusted for multiple testing; only pairs
#'   passing the thresholds are returned in the sparse \code{pairs} table.
#'
#' @param mat_x Numeric matrix of the first layer (features x samples).
#' @param mat_y Numeric matrix of the second layer (features x samples).
#' @param method Correlation method, "pearson" or "spearman". Spearman is
#'   obtained by ranking rows before applying the same vectorised path.
#'   Default: "pearson".
#' @param p_adjust Multiple-testing correction passed to \code{p.adjust()}.
#'   Default: "BH".
#' @param r_threshold Minimum absolute correlation for a pair to be reported.
#'   Default: 0.6.
#' @param p_threshold Maximum adjusted p-value for a pair to be reported.
#'   Default: 0.05.
#' @param max_pairs Maximum number of pairs kept in the sparse table; the
#'   strongest associations are retained when the limit is exceeded.
#'   Default: 100000.
#' @param name_x Label of the first layer stored in the pairs table.
#'   Default: "x".
#' @param name_y Label of the second layer stored in the pairs table.
#'   Default: "y".
#' @param verbose Logical, print progress information. Default: TRUE.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{cor_matrix}: Correlation matrix (features_x x features_y).
#'     \item \code{p_matrix}: Raw p-value matrix.
#'     \item \code{padj_matrix}: Adjusted p-value matrix.
#'     \item \code{pairs}: data.frame of significant pairs with columns
#'       feature_x, feature_y, omics_x, omics_y, r, p, padj.
#'     \item \code{params}: List of the settings used.
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

  # Spearman is Pearson on ranks
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

  # Row-wise standardisation -> correlation is a simple cross-product ---------
  zx <- .row_standardise(mat_x)
  zy <- .row_standardise(mat_y)

  cor_matrix <- (zx %*% t(zy)) / (n - 1)
  cor_matrix[cor_matrix > 1] <- 1
  cor_matrix[cor_matrix < -1] <- -1

  # Analytic p-values from the t distribution ---------------------------------
  df <- n - 2
  denom <- 1 - cor_matrix^2
  denom[denom <= .Machine$double.eps] <- .Machine$double.eps
  t_stat <- cor_matrix * sqrt(df / denom)
  p_matrix <- 2 * stats::pt(-abs(t_stat), df = df)
  dimnames(p_matrix) <- dimnames(cor_matrix)

  padj_vec <- stats::p.adjust(as.vector(p_matrix), method = p_adjust)
  padj_matrix <- matrix(padj_vec, nrow = nrow(p_matrix),
                        dimnames = dimnames(p_matrix))

  # Sparse table of significant pairs -----------------------------------------
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


#' Row-wise standardisation helper
#'
#' @param mat A numeric matrix (features x samples).
#'
#' @return A matrix with each row centred and scaled to unit standard deviation.
#'
#' @keywords internal
.row_standardise <- function(mat) {
  rm_ <- rowMeans(mat, na.rm = TRUE)
  centred <- mat - rm_
  sd_ <- sqrt(rowSums(centred^2, na.rm = TRUE) / (ncol(mat) - 1))
  sd_[sd_ <= .Machine$double.eps] <- .Machine$double.eps
  centred / sd_
}


#' Run cross-correlation for several layer pairs
#'
#' @description Convenience wrapper looping \code{run_cross_correlation()} over
#'   a list of omics layer pairs of a MultiOmicsData object.
#'
#' @param mo A MultiOmicsData object.
#' @param layer_pairs List of length-2 character vectors naming the layers to
#'   correlate, e.g. \code{list(c("microbiome", "metabolome"))}.
#' @param method Correlation method. Default: "spearman".
#' @param r_threshold Minimum absolute correlation. Default: 0.6.
#' @param p_threshold Maximum adjusted p-value. Default: 0.05.
#' @param max_pairs Maximum number of pairs per comparison. Default: 100000.
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A named list of \code{run_cross_correlation()} results, names being
#'   "layerA__layerB". An extra element \code{all_pairs} concatenates the
#'   sparse pair tables of all comparisons.
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


#' Summarise cross-correlation results per feature
#'
#' @description Aggregates a sparse pair table into a per-feature summary
#'   (number of significant partners, mean and maximum absolute correlation),
#'   useful to nominate driver taxa or hub metabolites.
#'
#' @param pairs A data.frame as returned in the \code{pairs} element of
#'   \code{run_cross_correlation()}.
#' @param side Which side to summarise, "x", "y" or "both". Default: "both".
#' @param top_n Number of rows returned, ordered by number of partners.
#'   Default: 50.
#'
#' @return A data.frame with columns feature, omics, n_partners, n_positive,
#'   n_negative, mean_abs_r and max_abs_r.
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
