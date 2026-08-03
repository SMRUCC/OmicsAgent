# ==============================================================================
# OmicsFlow: Multi-Omics Data Container
# ==============================================================================
# Container construction, sample alignment and batch preprocessing for
# multi-omics integration analysis.
# ==============================================================================

#' Create a MultiOmicsData container
#'
#' @description Builds a multi-omics container from several expression
#'   matrices sharing a common sample metadata table. Each omics layer is
#'   wrapped with \code{create_omics_data()} and all layers are aligned to the
#'   set of samples present in every layer, so that downstream cross-omics
#'   functions can assume identical sample order across layers.
#'
#' @param expr_list Named list of numeric matrices (features x samples). Names
#'   are used as omics layer names.
#' @param sample_info A data.frame with sample metadata, row names are sample
#'   IDs (as returned by \code{load_sample_info()}).
#' @param feature_info_list Named list of feature annotation data.frames, with
#'   the same names as \code{expr_list}. Layers missing from this list get an
#'   automatically generated minimal annotation.
#' @param match_cols Character vector giving the \code{match_col} passed to
#'   \code{create_omics_data()} for each layer. Either length 1 (recycled) or a
#'   named vector with one entry per layer. Default: "name".
#'
#' @return A MultiOmicsData object (list) with:
#'   \itemize{
#'     \item \code{omics}: Named list of OmicsData objects.
#'     \item \code{sample_info}: Sample metadata restricted to common samples.
#'     \item \code{common_samples}: Character vector of shared sample IDs.
#'     \item \code{metadata}: List with n_omics, omics_names, n_samples and
#'       n_features_per_omics.
#'   }
#'
#' @examples
#' \dontrun{
#' mo <- create_multiomics_data(
#'   expr_list = list(metabolome = m1, microbiome = m2),
#'   sample_info = sample_info,
#'   feature_info_list = list(metabolome = f1, microbiome = f2),
#'   match_cols = c(metabolome = "name", microbiome = "ID")
#' )
#' print(mo)
#' }
#'
#' @export
create_multiomics_data <- function(expr_list, sample_info,
                                   feature_info_list = NULL,
                                   match_cols = "name") {
  if (!is.list(expr_list) || length(expr_list) == 0) {
    stop("expr_list must be a non-empty named list of expression matrices.")
  }
  if (is.null(names(expr_list)) || any(names(expr_list) == "")) {
    stop("expr_list must be a named list; names are used as omics layer names.")
  }
  if (is.null(sample_info) || nrow(sample_info) == 0) {
    stop("sample_info must be a non-empty data.frame.")
  }

  layer_names <- names(expr_list)
  n_layers <- length(layer_names)

  # Resolve per-layer match columns -------------------------------------------
  if (length(match_cols) == 1 && is.null(names(match_cols))) {
    match_cols <- stats::setNames(rep(match_cols, n_layers), layer_names)
  } else if (!is.null(names(match_cols))) {
    missing_match <- setdiff(layer_names, names(match_cols))
    if (length(missing_match) > 0) {
      match_cols <- c(match_cols,
                      stats::setNames(rep("name", length(missing_match)),
                                      missing_match))
    }
    match_cols <- match_cols[layer_names]
  } else if (length(match_cols) == n_layers) {
    match_cols <- stats::setNames(match_cols, layer_names)
  } else {
    stop("match_cols must be length 1, length(expr_list), or a named vector.")
  }

  # Determine the samples shared by every layer and the metadata table --------
  common_samples <- rownames(sample_info)
  for (nm in layer_names) {
    mat <- expr_list[[nm]]
    if (is.null(colnames(mat))) {
      stop(sprintf("Expression matrix '%s' has no column (sample) names.", nm))
    }
    common_samples <- intersect(common_samples, colnames(mat))
  }

  if (length(common_samples) == 0) {
    stop("No samples are shared by all omics layers and the sample metadata.")
  }

  dropped <- nrow(sample_info) - length(common_samples)
  if (dropped > 0) {
    cat(sprintf("[multiomics] %d sample(s) dropped, not present in all layers.\n",
                dropped))
  }

  aligned_info <- sample_info[common_samples, , drop = FALSE]

  # Build one OmicsData per layer on the aligned sample set -------------------
  omics <- vector("list", n_layers)
  names(omics) <- layer_names

  for (nm in layer_names) {
    mat <- expr_list[[nm]][, common_samples, drop = FALSE]

    finfo <- NULL
    if (!is.null(feature_info_list) && nm %in% names(feature_info_list)) {
      finfo <- feature_info_list[[nm]]
    }

    if (is.null(finfo)) {
      finfo <- data.frame(
        ID = rownames(mat),
        name = rownames(mat),
        type = "unknown",
        kegg = NA_character_,
        stringsAsFactors = FALSE
      )
      rownames(finfo) <- rownames(mat)
      this_match <- "name"
    } else {
      this_match <- match_cols[[nm]]
    }

    omics[[nm]] <- create_omics_data(
      expr_matrix = mat,
      sample_info = aligned_info,
      feature_info = finfo,
      match_col = this_match
    )

    kept <- omics[[nm]]$metadata$n_features
    lost <- nrow(mat) - kept
    if (lost > 0) {
      cat(sprintf("[multiomics] layer '%s': %d/%d features matched annotation (%d dropped).\n",
                  nm, kept, nrow(mat), lost))
    }
  }

  n_features <- vapply(omics, function(x) nrow(x$expression), integer(1))

  mo <- list(
    omics = omics,
    sample_info = aligned_info,
    common_samples = common_samples,
    metadata = list(
      n_omics = n_layers,
      omics_names = layer_names,
      n_samples = length(common_samples),
      n_features_per_omics = n_features
    )
  )

  class(mo) <- "MultiOmicsData"
  return(mo)
}


#' Print method for MultiOmicsData object
#'
#' @param x A MultiOmicsData object.
#' @param ... Additional arguments (ignored).
#'
#' @export
print.MultiOmicsData <- function(x, ...) {
  cat("=== OmicsFlow Multi-Omics Dataset ===\n")
  cat("Omics layers:", x$metadata$n_omics, "\n")
  cat("Common samples:", x$metadata$n_samples, "\n")
  cat("Layer details:\n")
  for (nm in x$metadata$omics_names) {
    om <- x$omics[[nm]]
    cat(sprintf("  - %-15s %6d features x %4d samples\n",
                nm, nrow(om$expression), ncol(om$expression)))
  }
  if (!is.null(x$sample_info$sample_info)) {
    cat("Group details:\n")
    group_tab <- table(x$sample_info$sample_info)
    for (g in names(group_tab)) {
      cat("  -", g, ":", group_tab[[g]], "samples\n")
    }
  }
  invisible(x)
}


#' Extract one expression matrix from a MultiOmicsData object
#'
#' @param mo A MultiOmicsData object.
#' @param name Name of the omics layer.
#'
#' @return A numeric matrix (features x samples).
#'
#' @examples
#' \dontrun{
#' mat <- get_omics_matrix(mo, "metabolome")
#' }
#'
#' @export
get_omics_matrix <- function(mo, name) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (!name %in% names(mo$omics)) {
    stop(sprintf("Omics layer '%s' not found. Available: %s",
                 name, paste(names(mo$omics), collapse = ", ")))
  }
  return(mo$omics[[name]]$expression)
}


#' Extract all expression matrices from a MultiOmicsData object
#'
#' @param mo A MultiOmicsData object.
#' @param layers Optional character vector restricting the returned layers.
#'   Default: NULL (all layers).
#'
#' @return A named list of numeric matrices (features x samples).
#'
#' @examples
#' \dontrun{
#' mats <- get_omics_list(mo)
#' }
#'
#' @export
get_omics_list <- function(mo, layers = NULL) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (is.null(layers)) layers <- names(mo$omics)
  missing_layers <- setdiff(layers, names(mo$omics))
  if (length(missing_layers) > 0) {
    stop(sprintf("Unknown omics layer(s): %s",
                 paste(missing_layers, collapse = ", ")))
  }
  out <- lapply(layers, function(nm) mo$omics[[nm]]$expression)
  names(out) <- layers
  return(out)
}


#' Extract feature annotation of one omics layer
#'
#' @param mo A MultiOmicsData object.
#' @param name Name of the omics layer.
#'
#' @return A data.frame with feature annotation.
#'
#' @examples
#' \dontrun{
#' fi <- get_feature_info(mo, "transcriptome")
#' }
#'
#' @export
get_feature_info <- function(mo, name) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (!name %in% names(mo$omics)) {
    stop(sprintf("Omics layer '%s' not found.", name))
  }
  return(mo$omics[[name]]$feature_info)
}


#' Batch preprocessing of all omics layers
#'
#' @description Applies the standard OmicsFlow preprocessing chain
#'   (missing-value filtering, imputation, sample normalization and scaling)
#'   to every layer of a MultiOmicsData object. Each step can be switched off
#'   globally or skipped for specific layers.
#'
#' @param mo A MultiOmicsData object.
#' @param filter Logical, run \code{filter_missing_values()}. Default: TRUE.
#' @param filter_threshold Minimum fraction of valid values required to keep a
#'   feature. Default: 0.5.
#' @param filter_method Filtering strategy, "group" or "overall". Default:
#'   "group".
#' @param group_col Grouping column in sample_info used by group filtering.
#'   Default: "sample_info".
#' @param impute Logical, run \code{impute_min_half()}. Default: TRUE.
#' @param normalize Logical, run \code{normalize_sample_total()}. Default: TRUE.
#' @param scale Logical, run \code{scale_pareto()}. Default: TRUE.
#' @param log_transform Logical, apply \code{log2(x + 1)} before scaling.
#'   Default: FALSE.
#' @param skip_normalize Character vector of layer names for which sample-total
#'   normalization is skipped (e.g. already-normalized layers). Default: NULL.
#'
#' @return A MultiOmicsData object with preprocessed expression matrices. A
#'   \code{preprocessing} element records the steps applied and the number of
#'   features kept per layer.
#'
#' @examples
#' \dontrun{
#' mo_proc <- preprocess_multiomics(mo, filter_threshold = 0.5)
#' }
#'
#' @export
preprocess_multiomics <- function(mo,
                                  filter = TRUE,
                                  filter_threshold = 0.5,
                                  filter_method = "group",
                                  group_col = "sample_info",
                                  impute = TRUE,
                                  normalize = TRUE,
                                  scale = TRUE,
                                  log_transform = FALSE,
                                  skip_normalize = NULL) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }

  report <- data.frame(
    omics = character(0),
    n_features_before = integer(0),
    n_features_after = integer(0),
    stringsAsFactors = FALSE
  )

  for (nm in names(mo$omics)) {
    mat <- mo$omics[[nm]]$expression
    n_before <- nrow(mat)

    if (isTRUE(filter)) {
      flt <- tryCatch({
        filter_missing_values(
          expr_matrix = mat,
          sample_info = mo$sample_info,
          threshold = filter_threshold,
          method = filter_method,
          group_col = group_col
        )
      }, error = function(e) {
        cat(sprintf("[multiomics] layer '%s': filtering skipped (%s)\n",
                    nm, conditionMessage(e)))
        NULL
      })
      if (!is.null(flt)) mat <- flt$filtered_matrix
    }

    if (nrow(mat) == 0) {
      cat(sprintf("[multiomics] layer '%s': all features removed by filtering.\n", nm))
    }

    if (isTRUE(impute) && nrow(mat) > 0) {
      mat <- impute_min_half(mat)
    }

    if (isTRUE(normalize) && nrow(mat) > 0 && !(nm %in% skip_normalize)) {
      mat <- normalize_sample_total(mat)
    }

    if (isTRUE(log_transform) && nrow(mat) > 0) {
      mat <- log2(mat + 1)
    }

    if (isTRUE(scale) && nrow(mat) > 0) {
      mat <- scale_pareto(mat)
    }

    # Keep the feature annotation aligned with the surviving features
    finfo <- mo$omics[[nm]]$feature_info
    keep <- intersect(rownames(mat), rownames(finfo))
    if (length(keep) == nrow(mat)) {
      finfo <- finfo[rownames(mat), , drop = FALSE]
    }

    mo$omics[[nm]]$expression <- mat
    mo$omics[[nm]]$feature_info <- finfo
    mo$omics[[nm]]$metadata$n_features <- nrow(mat)

    report <- rbind(report, data.frame(
      omics = nm,
      n_features_before = n_before,
      n_features_after = nrow(mat),
      stringsAsFactors = FALSE
    ))

    cat(sprintf("[multiomics] layer '%s' preprocessed: %d -> %d features\n",
                nm, n_before, nrow(mat)))
  }

  mo$metadata$n_features_per_omics <-
    vapply(mo$omics, function(x) nrow(x$expression), integer(1))

  mo$preprocessing <- list(
    steps = c(
      if (isTRUE(filter)) "filter_missing_values",
      if (isTRUE(impute)) "impute_min_half",
      if (isTRUE(normalize)) "normalize_sample_total",
      if (isTRUE(log_transform)) "log2",
      if (isTRUE(scale)) "scale_pareto"
    ),
    report = report
  )

  return(mo)
}


#' Subset a MultiOmicsData object by samples
#'
#' @description Restricts every omics layer and the sample metadata to a
#'   subset of samples, e.g. one geographic location or one fermentation phase.
#'
#' @param mo A MultiOmicsData object.
#' @param samples Character vector of sample IDs to keep. Ignored when
#'   \code{subset_col} is supplied.
#' @param subset_col Column name in sample_info used for selection.
#'   Default: NULL.
#' @param subset_values Values of \code{subset_col} to keep. Default: NULL.
#'
#' @return A MultiOmicsData object restricted to the selected samples.
#'
#' @examples
#' \dontrun{
#' mo_yn <- subset_multiomics(mo, subset_col = "location", subset_values = "Yunnan")
#' }
#'
#' @export
subset_multiomics <- function(mo, samples = NULL, subset_col = NULL,
                              subset_values = NULL) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }

  if (!is.null(subset_col)) {
    if (!subset_col %in% colnames(mo$sample_info)) {
      stop(sprintf("Column '%s' not found in sample_info.", subset_col))
    }
    if (is.null(subset_values)) {
      stop("subset_values must be supplied together with subset_col.")
    }
    keep <- rownames(mo$sample_info)[
      as.character(mo$sample_info[[subset_col]]) %in% as.character(subset_values)
    ]
  } else {
    if (is.null(samples)) stop("Either samples or subset_col must be supplied.")
    keep <- intersect(samples, mo$common_samples)
  }

  if (length(keep) == 0) {
    stop("No samples left after subsetting.")
  }

  mo$sample_info <- mo$sample_info[keep, , drop = FALSE]
  mo$common_samples <- keep
  for (nm in names(mo$omics)) {
    mo$omics[[nm]]$expression <- mo$omics[[nm]]$expression[, keep, drop = FALSE]
    mo$omics[[nm]]$sample_info <- mo$sample_info
    mo$omics[[nm]]$metadata$n_samples <- length(keep)
  }
  mo$metadata$n_samples <- length(keep)

  return(mo)
}


#' Remove zero-variance features from a matrix
#'
#' @description Utility used by cross-omics correlation and integration
#'   functions. Features with zero or undefined variance produce NaN
#'   correlations and must be discarded before analysis.
#'
#' @param mat A numeric matrix (features x samples).
#' @param label Optional label used in the reporting message. Default: "matrix".
#' @param verbose Logical, report the number of removed features. Default: TRUE.
#'
#' @return A numeric matrix without zero-variance features.
#'
#' @examples
#' \dontrun{
#' mat <- drop_zero_variance(mat, label = "metabolome")
#' }
#'
#' @export
drop_zero_variance <- function(mat, label = "matrix", verbose = TRUE) {
  if (!is.matrix(mat)) mat <- as.matrix(mat)
  v <- apply(mat, 1, function(x) stats::var(x, na.rm = TRUE))
  keep <- !is.na(v) & v > 0
  n_drop <- sum(!keep)
  if (n_drop > 0 && isTRUE(verbose)) {
    cat(sprintf("[multiomics] %s: %d zero-variance feature(s) removed.\n",
                label, n_drop))
  }
  return(mat[keep, , drop = FALSE])
}
