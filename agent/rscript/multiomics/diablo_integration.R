# ==============================================================================
# OmicsFlow: Multi-Block Discriminant Integration (DIABLO)
# ==============================================================================
# Supervised integration of several omics layers to discriminate sample groups
# such as geographic origin or fermentation phase.
# ==============================================================================

#' Multi-block sparse PLS-DA integration of omics layers
#'
#' @description Wraps \code{mixOmics::block.splsda()} (DIABLO) to build a
#'   supervised model across all omics layers of a MultiOmicsData object. All
#'   features enter the model; the sparsity parameter \code{keepX} performs the
#'   built-in variable selection per component, which is the standard DIABLO
#'   usage and avoids arbitrary pre-filtering.
#'
#' @param mo A MultiOmicsData object.
#' @param group_col Column in sample_info holding the class labels.
#'   Default: "sample_info".
#' @param layers Optional character vector restricting the layers used.
#'   Default: NULL (all layers).
#' @param ncomp Number of components. Default: 2.
#' @param keepX Number of features selected per component. Either a single
#'   integer applied to every layer, or a named list with one numeric vector of
#'   length \code{ncomp} per layer. When NULL an adaptive value is derived from
#'   the layer size. Default: NULL.
#' @param design Off-diagonal value of the DIABLO design matrix, controlling
#'   the trade-off between discrimination and cross-layer correlation.
#'   Default: 0.1.
#' @param exclude_groups Group labels removed before modelling. Default: NULL.
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A list (NULL when the model cannot be fitted) with:
#'   \itemize{
#'     \item \code{model}: The fitted block.splsda object.
#'     \item \code{scores}: Named list of per-layer score data.frames including
#'       the group label.
#'     \item \code{loadings}: Named list of per-layer loading data.frames.
#'     \item \code{selected_features}: data.frame of selected features with
#'       layer, component, feature and loading.
#'     \item \code{groups}: The class levels used.
#'     \item \code{design}: The design matrix.
#'   }
#'
#' @examples
#' \dontrun{
#' res <- run_diablo(mo, group_col = "location", ncomp = 2)
#' }
#'
#' @export
run_diablo <- function(mo, group_col = "sample_info",
                       layers = NULL,
                       ncomp = 2,
                       keepX = NULL,
                       design = 0.1,
                       exclude_groups = NULL,
                       verbose = TRUE) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (!requireNamespace("mixOmics", quietly = TRUE)) {
    stop("Package 'mixOmics' is required for DIABLO. Install it with ",
         "BiocManager::install('mixOmics').")
  }
  if (!group_col %in% colnames(mo$sample_info)) {
    stop(sprintf("Column '%s' not found in sample_info.", group_col))
  }

  if (is.null(layers)) layers <- names(mo$omics)

  sinfo <- mo$sample_info
  y_raw <- as.character(sinfo[[group_col]])
  keep_samples <- !is.na(y_raw)
  if (!is.null(exclude_groups)) {
    keep_samples <- keep_samples & !(y_raw %in% exclude_groups)
  }
  if (sum(keep_samples) < 6) {
    stop("Not enough samples remain for DIABLO after filtering.")
  }

  sample_ids <- rownames(sinfo)[keep_samples]
  y <- factor(y_raw[keep_samples])

  if (nlevels(y) < 2) {
    stop(sprintf("Column '%s' must contain at least two classes.", group_col))
  }

  # Blocks: samples x features, mixOmics convention
  X <- lapply(layers, function(nm) {
    mat <- get_omics_matrix(mo, nm)[, sample_ids, drop = FALSE]
    mat <- drop_zero_variance(mat, label = nm, verbose = FALSE)
    t(mat)
  })
  names(X) <- layers

  # Adaptive keepX ------------------------------------------------------------
  if (is.null(keepX)) {
    keepX <- lapply(X, function(blk) {
      n_feat <- ncol(blk)
      k <- max(5, min(25, floor(n_feat / 20)))
      rep(k, ncomp)
    })
  } else if (is.numeric(keepX) && length(keepX) == 1) {
    keepX <- lapply(X, function(blk) rep(min(keepX, ncol(blk)), ncomp))
  }
  names(keepX) <- names(X)

  # Design matrix -------------------------------------------------------------
  n_blocks <- length(X)
  design_mat <- matrix(design, nrow = n_blocks, ncol = n_blocks,
                       dimnames = list(names(X), names(X)))
  diag(design_mat) <- 0

  if (verbose) {
    cat(sprintf("[diablo] %d blocks, %d samples, %d classes (%s), ncomp = %d\n",
                n_blocks, length(sample_ids), nlevels(y),
                paste(levels(y), collapse = ", "), ncomp))
    for (nm in names(X)) {
      cat(sprintf("[diablo]   block '%s': %d features, keepX = %s\n",
                  nm, ncol(X[[nm]]), paste(keepX[[nm]], collapse = "/")))
    }
  }

  model <- tryCatch({
    mixOmics::block.splsda(X = X, Y = y, ncomp = ncomp,
                           keepX = keepX, design = design_mat)
  }, error = function(e) {
    cat(sprintf("[diablo] model fitting failed: %s\n", conditionMessage(e)))
    NULL
  })

  if (is.null(model)) return(NULL)

  # Scores --------------------------------------------------------------------
  scores <- list()
  for (nm in names(model$variates)) {
    if (identical(nm, "Y")) next
    v <- as.data.frame(model$variates[[nm]])
    colnames(v) <- paste0("comp", seq_len(ncol(v)))
    v$sample <- rownames(v)
    v$group <- as.character(y)[match(rownames(v), sample_ids)]
    scores[[nm]] <- v
  }

  # Loadings and selected features -------------------------------------------
  loadings <- list()
  selected <- NULL
  for (nm in names(model$loadings)) {
    if (identical(nm, "Y")) next
    ld <- as.data.frame(model$loadings[[nm]])
    colnames(ld) <- paste0("comp", seq_len(ncol(ld)))
    ld$feature <- rownames(ld)
    loadings[[nm]] <- ld

    for (ci in seq_len(ncol(ld) - 1)) {
      cname <- paste0("comp", ci)
      nz <- ld[ld[[cname]] != 0, c("feature", cname), drop = FALSE]
      if (nrow(nz) == 0) next
      nz <- nz[order(-abs(nz[[cname]])), , drop = FALSE]
      selected <- rbind(selected, data.frame(
        layer = nm,
        component = ci,
        feature = nz$feature,
        loading = nz[[cname]],
        stringsAsFactors = FALSE
      ))
    }
  }

  if (is.null(selected)) {
    selected <- data.frame(layer = character(0), component = integer(0),
                           feature = character(0), loading = numeric(0),
                           stringsAsFactors = FALSE)
  }
  rownames(selected) <- NULL

  if (verbose) {
    cat(sprintf("[diablo] %d selected feature entries across blocks\n",
                nrow(selected)))
  }

  return(list(
    model = model,
    scores = scores,
    loadings = loadings,
    selected_features = selected,
    groups = levels(y),
    design = design_mat,
    sample_ids = sample_ids
  ))
}


#' Cross-block correlation of DIABLO components
#'
#' @description Correlates the sample scores of the different blocks on each
#'   component, quantifying how strongly the layers agree in the supervised
#'   space. This is the numeric counterpart of the DIABLO circle plot.
#'
#' @param diablo_result Result of \code{run_diablo()}.
#' @param comp Component index. Default: 1.
#'
#' @return A data.frame with layer_x, layer_y, component and correlation.
#'
#' @examples
#' \dontrun{
#' diablo_block_correlation(res, comp = 1)
#' }
#'
#' @export
diablo_block_correlation <- function(diablo_result, comp = 1) {
  if (is.null(diablo_result) || is.null(diablo_result$scores)) {
    stop("diablo_result must be the output of run_diablo().")
  }
  layers <- names(diablo_result$scores)
  if (length(layers) < 2) {
    stop("At least two blocks are required.")
  }
  cname <- paste0("comp", comp)

  out <- NULL
  combos <- utils::combn(layers, 2, simplify = FALSE)
  for (cb in combos) {
    a <- diablo_result$scores[[cb[1]]]
    b <- diablo_result$scores[[cb[2]]]
    if (!cname %in% colnames(a) || !cname %in% colnames(b)) next
    common <- intersect(a$sample, b$sample)
    r <- stats::cor(a[[cname]][match(common, a$sample)],
                    b[[cname]][match(common, b$sample)])
    out <- rbind(out, data.frame(
      layer_x = cb[1], layer_y = cb[2], component = comp,
      correlation = r, stringsAsFactors = FALSE
    ))
  }

  if (is.null(out)) {
    out <- data.frame(layer_x = character(0), layer_y = character(0),
                      component = integer(0), correlation = numeric(0),
                      stringsAsFactors = FALSE)
  }
  rownames(out) <- NULL
  return(out)
}


#' Fallback per-layer PLS-DA when DIABLO is unavailable
#'
#' @description Runs \code{run_plsda()} independently on every omics layer.
#'   Used by demo pipelines as a graceful degradation path when the multi-block
#'   model cannot be fitted, and useful on its own as a per-layer overview.
#'
#' @param mo A MultiOmicsData object.
#' @param group_col Grouping column in sample_info. Default: "sample_info".
#' @param layers Optional character vector of layers. Default: NULL (all).
#' @param ncomp Number of components. Default: 2.
#' @param exclude_groups Groups removed before modelling. Default: NULL.
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A named list of \code{run_plsda()} results (NULL entries dropped).
#'
#' @examples
#' \dontrun{
#' per_layer <- run_layerwise_plsda(mo, group_col = "location")
#' }
#'
#' @export
run_layerwise_plsda <- function(mo, group_col = "sample_info",
                                layers = NULL, ncomp = 2,
                                exclude_groups = NULL, verbose = TRUE) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (is.null(layers)) layers <- names(mo$omics)

  out <- list()
  for (nm in layers) {
    res <- tryCatch({
      run_plsda(expr_matrix = get_omics_matrix(mo, nm),
                sample_info = mo$sample_info,
                group_col = group_col,
                ncomp = ncomp,
                exclude_groups = exclude_groups)
    }, error = function(e) {
      cat(sprintf("[plsda] layer '%s' failed: %s\n", nm, conditionMessage(e)))
      NULL
    })
    if (!is.null(res)) {
      out[[nm]] <- res
      if (verbose) cat(sprintf("[plsda] layer '%s' done\n", nm))
    }
  }
  return(out)
}
