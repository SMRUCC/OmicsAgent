# ==============================================================================
# OmicsFlow：多模块判别整合（DIABLO）
# ==============================================================================
# 对多个组学层进行监督式整合，以区分样本分组，例如地理来源或发酵阶段。
# ==============================================================================

#' 组学层的多模块稀疏 PLS-DA 整合
#'
#' @description 封装 \code{mixOmics::block.splsda()}（DIABLO），针对 MultiOmicsData
#'   对象的所有组学层构建监督模型。所有特征均进入模型；稀疏参数 \code{keepX}
#'   在每个组分上执行内置的变量筛选，这是 DIABLO 的标准用法，可避免任意的
#'   预筛选。
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param group_col sample_info 中保存类别标签的列。默认："sample_info"。
#' @param layers 可选字符向量，限定所使用的层。默认：NULL（所有层）。
#' @param ncomp 组分数。默认：2。
#' @param keepX 每个组分筛选的特征数。可为单个整数（应用于所有层），或为有名列表，
#'   每层含一个长度为 \code{ncomp} 的数值向量。为 NULL 时根据层规模自适应取值。
#'   默认：NULL。
#' @param design DIABLO 设计矩阵的对角线外取值，用于权衡判别与跨层相关性。默认：0.1。
#' @param exclude_groups 建模前移除的分组标签。默认：NULL。
#' @param verbose 逻辑值，是否打印进度。默认：TRUE。
#'
#' @return 一个列表（模型无法拟合时为 NULL），含有：
#'   \itemize{
#'     \item \code{model}: 拟合得到的 block.splsda 对象。
#'     \item \code{scores}: 各层分数数据框的有名列表，包含分组标签。
#'     \item \code{loadings}: 各层载荷数据框的有名列表。
#'     \item \code{selected_features}: 选中特征的数据框，含 layer、component、
#'       feature 与 loading。
#'     \item \code{groups}: 所使用的类别水平。
#'     \item \code{design}: 设计矩阵。
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

  # 数据块：样本 x 特征，遵循 mixOmics 约定
  X <- lapply(layers, function(nm) {
    mat <- get_omics_matrix(mo, nm)[, sample_ids, drop = FALSE]
    mat <- drop_zero_variance(mat, label = nm, verbose = FALSE)
    t(mat)
  })
  names(X) <- layers

  # 自适应 keepX ------------------------------------------------------------
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
