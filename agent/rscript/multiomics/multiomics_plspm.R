# ==============================================================================
# OmicsFlow: Hierarchical Multi-Omics PLS Path Modelling (PLS-PM)
# ==============================================================================
# Builds latent variables from biological annotation (EC numbers, KEGG pathway
# mappings, compound classes, microbial taxonomy) and connects them across the
# omics hierarchy with a PLS path model solved by the plspm package.
#
# Typical workflow:
#   1. build_multiomics_latent_def()     annotation -> latent variable blocks
#   2. build_hierarchical_inner_model()  layer ordering -> lower-triangular
#                                        path matrix
#   3. run_multiomics_plspm()            solve and flatten the results
#   4. summarise_plspm_paths()           per-layer path summary
#
# Unlike the simplified run_plspm() in network/plspm_net.R (PCA scores plus
# pairwise lm), this module calls plspm::plspm() so weights, loadings and path
# coefficients are estimated jointly.
# ==============================================================================


# ------------------------------------------------------------------------------
# Annotation helpers
# ------------------------------------------------------------------------------

#' Normalise and truncate EC numbers to a given hierarchy level
#'
#' @description Enzyme Commission numbers in the annotation tables are stored
#'   with a textual prefix (e.g. \code{"EC 1.13.11.71"}). Full EC numbers are
#'   far too granular to form usable latent blocks, so the identifier is
#'   cleaned and truncated to the first \code{level} components, which groups
#'   enzymes into meaningful functional classes.
#'
#' @param x Character vector of raw EC annotations.
#' @param level Number of EC components to keep. Default: 2 (e.g. "1.13").
#'
#' @return Character vector of truncated EC classes, \code{NA} where the input
#'   carries no usable EC number.
#'
#' @examples
#' \dontrun{
#' clean_ec_number(c("EC 1.13.11.71", "EC 2.7.1.1"), level = 2)
#' # -> c("1.13", "2.7")
#' }
#'
#' @export
clean_ec_number <- function(x, level = 2) {
  x <- as.character(x)
  x <- trimws(gsub("^\\s*EC[:\\s]*", "", x, ignore.case = TRUE, perl = TRUE))
  x[is.na(x) | x == "" | tolower(x) %in% c("na", "-", "none")] <- NA_character_

  keep <- !is.na(x)
  if (any(keep)) {
    parts <- strsplit(x[keep], ".", fixed = TRUE)
    x[keep] <- vapply(parts, function(p) {
      p <- p[p != "" & p != "-"]
      if (length(p) == 0) return(NA_character_)
      paste(p[seq_len(min(level, length(p)))], collapse = ".")
    }, character(1))
  }
  x
}


#' Resolve the grouping vector of one omics layer
#'
#' @param finfo Feature annotation data.frame (row names = matrix row names).
#' @param features Feature IDs present in the expression matrix.
#' @param source Name of the annotation column, or "ec_number" / "kegg".
#' @param ec_level EC truncation level.
#'
#' @return Character vector aligned with \code{features}, NA where unusable.
#'
#' @keywords internal
.plspm_group_vector <- function(finfo, features, source, ec_level = 2) {
  if (is.null(finfo) || !source %in% colnames(finfo)) return(NULL)
  vals <- as.character(finfo[[source]])[match(features, rownames(finfo))]
  if (identical(source, "ec_number")) {
    vals <- clean_ec_number(vals, level = ec_level)
  }
  vals[is.na(vals) | vals == "" |
         tolower(vals) %in% c("na", "unknown", "-", "none")] <- NA_character_
  vals
}


#' Coverage of a candidate annotation column
#'
#' @param v Character vector returned by \code{.plspm_group_vector()}.
#'
#' @return Fraction of non-missing entries in [0, 1].
#'
#' @keywords internal
.plspm_coverage <- function(v) {
  if (is.null(v) || length(v) == 0) return(0)
  sum(!is.na(v)) / length(v)
}


# ------------------------------------------------------------------------------
# Latent variable construction
# ------------------------------------------------------------------------------

#' Build multi-omics latent variable definitions from annotation
#'
#' @description Groups the features of every omics layer into latent variables
#'   using biological annotation. Each layer may use a different grouping
#'   source, which is required because the layers carry different metadata:
#'   transcriptome and proteome have EC numbers and KEGG orthologs, metabolome
#'   and volatilome have compound classes, and the 16S layer only has taxonomy.
#'
#'   When the requested source has poor coverage the function automatically
#'   falls back to the next usable column instead of failing, so a layer is
#'   only skipped when no annotation at all can be used.
#'
#' @param mo A MultiOmicsData object.
#' @param layer_sources Named list mapping layer name to the annotation column
#'   to group by, e.g. \code{list(transcriptome = "ec_number",
#'   metabolome = "super_class", microbiome = "taxonomy_phylum")}.
#' @param min_size Minimum number of features per latent variable. Default: 3.
#' @param max_latent_per_layer Cap on the number of latent variables kept per
#'   layer, selected by total variance. Default: NULL (no cap).
#' @param max_features_per_latent Cap on the manifest variables per latent
#'   variable, selected by variance. Default: 15.
#' @param ec_level EC truncation level. Default: 2.
#' @param fallback_sources Columns tried when the requested source has
#'   insufficient coverage.
#' @param min_coverage Minimum fraction of annotated features required to
#'   accept a source. Default: 0.2.
#' @param verbose Print progress. Default: TRUE.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{latent_def}: named list latent -> feature IDs.
#'     \item \code{definitions}: data.frame with \code{latent}, \code{layer},
#'       \code{source}, \code{group}, \code{n_features}.
#'     \item \code{layer_sources_used}: the source actually used per layer.
#'   }
#'
#' @examples
#' \dontrun{
#' lat <- build_multiomics_latent_def(
#'   mo, list(transcriptome = "ec_number", metabolome = "super_class"))
#' }
#'
#' @export
build_multiomics_latent_def <- function(mo, layer_sources, min_size = 3,
                                        max_latent_per_layer = NULL,
                                        max_features_per_latent = 15,
                                        ec_level = 2,
                                        fallback_sources = c("super_class",
                                                             "class", "family",
                                                             "taxonomy_phylum",
                                                             "kegg"),
                                        min_coverage = 0.2, verbose = TRUE) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }

  latent_def <- list()
  def_rows <- list()
  used_sources <- character(0)

  for (nm in names(layer_sources)) {
    if (!nm %in% names(mo$omics)) {
      if (verbose) cat(sprintf("  [plspm] layer '%s' not found, skipped.\n", nm))
      next
    }
    mat <- get_omics_matrix(mo, nm)
    finfo <- get_feature_info(mo, nm)
    feats <- rownames(mat)

    # pick the first source with acceptable coverage --------------------------
    candidates <- unique(c(layer_sources[[nm]], fallback_sources))
    chosen <- NULL
    grp <- NULL
    for (src in candidates) {
      v <- .plspm_group_vector(finfo, feats, src, ec_level = ec_level)
      if (.plspm_coverage(v) >= min_coverage) {
        chosen <- src
        grp <- v
        break
      }
    }
    if (is.null(chosen)) {
      if (verbose) {
        cat(sprintf("  [plspm] layer '%-14s' skipped: no annotation column with >=%.0f%% coverage.\n",
                    nm, 100 * min_coverage))
      }
      next
    }
    if (verbose && !identical(chosen, layer_sources[[nm]])) {
      cat(sprintf("  [plspm] layer '%-14s' fell back from '%s' to '%s'.\n",
                  nm, layer_sources[[nm]], chosen))
    }
    used_sources[nm] <- chosen

    vars <- apply(mat, 1, stats::var, na.rm = TRUE)
    vars[is.na(vars)] <- 0

    groups <- split(feats, grp)
    groups <- groups[vapply(groups, length, integer(1)) >= min_size]
    if (length(groups) == 0) {
      if (verbose) {
        cat(sprintf("  [plspm] layer '%-14s' skipped: no group reaches min_size=%d.\n",
                    nm, min_size))
      }
      next
    }

    # keep the most variable blocks, and the most variable members per block --
    if (!is.null(max_latent_per_layer) &&
        length(groups) > max_latent_per_layer) {
      gv <- vapply(groups, function(f) sum(vars[f], na.rm = TRUE), numeric(1))
      groups <- groups[order(gv, decreasing = TRUE)[
        seq_len(max_latent_per_layer)]]
    }
    groups <- lapply(groups, function(f) {
      if (length(f) <= max_features_per_latent) return(f)
      f[order(vars[f], decreasing = TRUE)[seq_len(max_features_per_latent)]]
    })

    tag <- toupper(substr(nm, 1, 3))
    for (g in names(groups)) {
      lname <- make.names(paste(tag, g, sep = "_"))
      lname <- gsub("\\.+", "_", lname)
      lname <- make.unique(c(names(latent_def), lname))[length(latent_def) + 1]
      latent_def[[lname]] <- groups[[g]]
      def_rows[[length(def_rows) + 1]] <- data.frame(
        latent = lname, layer = nm, source = chosen, group = g,
        n_features = length(groups[[g]]), stringsAsFactors = FALSE)
    }
    if (verbose) {
      cat(sprintf("  [plspm] layer '%-14s' -> %2d latent variable(s) from '%s'\n",
                  nm, length(groups), chosen))
    }
  }

  if (length(latent_def) == 0) {
    stop("No latent variable could be constructed; relax min_size or min_coverage.")
  }

  definitions <- do.call(rbind, def_rows)
  rownames(definitions) <- NULL

  list(latent_def = latent_def, definitions = definitions,
       layer_sources_used = used_sources)
}


# ------------------------------------------------------------------------------
# Hierarchical inner model
# ------------------------------------------------------------------------------

#' Build the lower-triangular inner model matrix for a layered PLS path model
#'
#' @description Orders the latent variables by the biological hierarchy of
#'   their omics layer and connects every latent variable to all latent
#'   variables of downstream layers. plspm requires a lower-triangular path
#'   matrix, which this ordering guarantees.
#'
#' @param definitions The \code{definitions} data.frame produced by
#'   \code{build_multiomics_latent_def()}.
#' @param layer_order Character vector of layers, most upstream first.
#' @param allow_within_layer Whether latent variables of the same layer may be
#'   connected. Default: FALSE.
#' @param adjacent_only Connect each layer only to the next layer in
#'   \code{layer_order} rather than to all downstream layers. Default: FALSE.
#'
#' @return A list with \code{path_matrix} (lower-triangular 0/1 matrix) and
#'   \code{definitions} reordered to match its row order.
#'
#' @examples
#' \dontrun{
#' im <- build_hierarchical_inner_model(
#'   lat$definitions,
#'   c("microbiome", "transcriptome", "proteome", "metabolome", "volatilome"))
#' }
#'
#' @export
build_hierarchical_inner_model <- function(definitions, layer_order,
                                           allow_within_layer = FALSE,
                                           adjacent_only = FALSE) {
  if (is.null(definitions) || nrow(definitions) == 0) {
    stop("definitions must be a non-empty data.frame.")
  }
  layer_order <- layer_order[layer_order %in% unique(definitions$layer)]
  extra <- setdiff(unique(definitions$layer), layer_order)
  layer_order <- c(layer_order, extra)
  if (length(layer_order) == 0) stop("No layer in definitions matches layer_order.")

  rank_of <- stats::setNames(seq_along(layer_order), layer_order)
  definitions$layer_rank <- rank_of[definitions$layer]
  definitions <- definitions[order(definitions$layer_rank, definitions$latent), ,
                             drop = FALSE]
  rownames(definitions) <- NULL

  lv <- definitions$latent
  k <- length(lv)
  if (k < 2) stop("At least 2 latent variables are required for a path model.")

  pm <- matrix(0L, nrow = k, ncol = k, dimnames = list(lv, lv))
  lr <- definitions$layer_rank

  for (j in seq_len(k)) {       # predictor (upstream)
    for (i in seq_len(k)) {     # outcome (downstream)
      if (i <= j) next          # keep strictly lower triangular
      same <- lr[i] == lr[j]
      if (same && !allow_within_layer) next
      if (!same && adjacent_only && (lr[i] - lr[j]) != 1) next
      pm[i, j] <- 1L
    }
  }

  list(path_matrix = pm, definitions = definitions)
}


# ------------------------------------------------------------------------------
# Solving the path model
# ------------------------------------------------------------------------------

#' Fit a hierarchical multi-omics PLS path model
#'
#' @description Assembles a wide sample-by-manifest-variable table from all
#'   omics layers, maps every latent variable to its column indices and solves
#'   the path model with \code{plspm::plspm()}. Zero-variance and duplicated
#'   manifest variables are removed beforehand because they make the PLS
#'   algorithm unstable.
#'
#' @param mo A MultiOmicsData object.
#' @param latent_def Named list latent -> feature IDs.
#' @param definitions Definitions data.frame, already ordered to match
#'   \code{path_matrix} (as returned by
#'   \code{build_hierarchical_inner_model()}).
#' @param path_matrix Lower-triangular 0/1 inner model matrix.
#' @param scale Standardise manifest variables. Default: TRUE.
#' @param boot_val Run bootstrap validation. Default: FALSE.
#' @param br Bootstrap resamples when \code{boot_val} is TRUE. Default: 100.
#' @param min_block_size Minimum manifest variables per block after cleaning.
#'   Default: 2.
#' @param verbose Print progress. Default: TRUE.
#'
#' @return A list with \code{model}, \code{inner_paths}, \code{outer_loadings},
#'   \code{scores}, \code{fit_summary}, \code{effects}, \code{gof} and
#'   \code{definitions}.
#'
#' @examples
#' \dontrun{
#' res <- run_multiomics_plspm(mo, lat$latent_def, im$definitions,
#'                             im$path_matrix)
#' }
#'
#' @export
run_multiomics_plspm <- function(mo, latent_def, definitions, path_matrix,
                                 scale = TRUE, boot_val = FALSE, br = 100,
                                 min_block_size = 2, verbose = TRUE) {
  if (!requireNamespace("plspm", quietly = TRUE)) {
    stop("Package 'plspm' is required for PLS path modelling.")
  }
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }

  lv <- rownames(path_matrix)
  definitions <- definitions[match(lv, definitions$latent), , drop = FALSE]

  # --- collect the manifest variables of every latent block -----------------
  samples <- mo$common_samples
  cols <- list()
  blocks <- list()
  block_layer <- character(0)
  col_counter <- 0L
  keep_lv <- character(0)

  for (i in seq_along(lv)) {
    l <- lv[i]
    layer <- definitions$layer[i]
    feats <- latent_def[[l]]
    if (is.null(feats) || length(feats) == 0) next

    mat <- tryCatch(get_omics_matrix(mo, layer), error = function(e) NULL)
    if (is.null(mat)) next
    feats <- intersect(feats, rownames(mat))
    if (length(feats) < min_block_size) next

    sub <- t(mat[feats, samples, drop = FALSE])   # samples x features
    v <- apply(sub, 2, stats::var, na.rm = TRUE)
    sub <- sub[, !is.na(v) & v > 0, drop = FALSE]
    if (ncol(sub) < min_block_size) next

    colnames(sub) <- paste(l, seq_len(ncol(sub)), sep = "__")
    idx <- col_counter + seq_len(ncol(sub))
    col_counter <- col_counter + ncol(sub)

    cols[[l]] <- sub
    blocks[[l]] <- idx
    block_layer[l] <- layer
    keep_lv <- c(keep_lv, l)
  }

  if (length(keep_lv) < 2) {
    stop("Fewer than 2 usable latent blocks remain after cleaning.")
  }

  # --- restrict the path matrix to the surviving latent variables -----------
  pm <- path_matrix[keep_lv, keep_lv, drop = FALSE]
  # drop latent variables that ended up isolated
  connected <- (rowSums(pm) + colSums(pm)) > 0
  if (sum(connected) < 2) {
    stop("The inner model has fewer than 2 connected latent variables.")
  }
  if (any(!connected)) {
    keep_lv <- keep_lv[connected]
    pm <- pm[keep_lv, keep_lv, drop = FALSE]
  }

  # --- assemble the wide table and the block column indices ----------------
  offset <- 0L
  reindexed <- list()
  for (l in keep_lv) {
    n <- ncol(cols[[l]])
    reindexed[[l]] <- offset + seq_len(n)
    offset <- offset + n
  }
  wide <- as.data.frame(do.call(cbind, cols[keep_lv]), stringsAsFactors = FALSE)
  colnames(wide) <- make.unique(make.names(colnames(wide)))

  definitions <- definitions[match(keep_lv, definitions$latent), , drop = FALSE]
  rownames(definitions) <- NULL

  if (verbose) {
    cat(sprintf("  [plspm] fitting model: %d latent variable(s), %d manifest variable(s), %d sample(s)\n",
                length(keep_lv), ncol(wide), nrow(wide)))
  }

  model <- plspm::plspm(Data = wide, path_matrix = pm,
                        blocks = unname(reindexed[keep_lv]),
                        modes = rep("A", length(keep_lv)),
                        scaled = scale, boot.val = boot_val, br = br)

  layer_of <- stats::setNames(definitions$layer, definitions$latent)

  # --- flatten the inner model ---------------------------------------------
  inner_rows <- list()
  im <- model$inner_model
  for (target in names(im)) {
    tb <- as.data.frame(im[[target]], stringsAsFactors = FALSE)
    tb$from <- rownames(tb)
    tb <- tb[tb$from != "Intercept", , drop = FALSE]
    if (nrow(tb) == 0) next
    inner_rows[[target]] <- data.frame(
      from = tb$from,
      to = target,
      from_layer = unname(layer_of[tb$from]),
      to_layer = unname(layer_of[target]),
      path_coeff = as.numeric(tb[["Estimate"]]),
      std_error = as.numeric(tb[["Std. Error"]]),
      t_value = as.numeric(tb[["t value"]]),
      p_value = as.numeric(tb[["Pr(>|t|)"]]),
      stringsAsFactors = FALSE)
  }
  inner_paths <- if (length(inner_rows) > 0) do.call(rbind, inner_rows) else
    data.frame(from = character(0), to = character(0),
               from_layer = character(0), to_layer = character(0),
               path_coeff = numeric(0), std_error = numeric(0),
               t_value = numeric(0), p_value = numeric(0),
               stringsAsFactors = FALSE)
  if (nrow(inner_paths) > 0) {
    inner_paths$significant <- inner_paths$p_value < 0.05
    inner_paths$edge_type <- ifelse(
      inner_paths$from_layer == inner_paths$to_layer,
      "within_layer", "cross_layer")
    inner_paths <- inner_paths[order(-abs(inner_paths$path_coeff)), ,
                               drop = FALSE]
    rownames(inner_paths) <- NULL
  }

  # --- outer model ----------------------------------------------------------
  outer <- as.data.frame(model$outer_model, stringsAsFactors = FALSE)
  outer$latent <- as.character(outer$block)
  outer$layer <- unname(layer_of[outer$latent])
  rownames(outer) <- NULL

  # --- fit summary ----------------------------------------------------------
  isum <- as.data.frame(model$inner_summary, stringsAsFactors = FALSE)
  isum$latent <- rownames(isum)
  isum$layer <- unname(layer_of[isum$latent])
  uni <- as.data.frame(model$unidim, stringsAsFactors = FALSE)
  if (!is.null(uni) && nrow(uni) > 0) {
    isum$n_manifest <- uni[["MVs"]][match(isum$latent, rownames(uni))]
    isum$cronbach_alpha <- round(uni[["C.alpha"]][match(isum$latent,
                                                        rownames(uni))], 4)
    isum$dillon_goldstein_rho <- round(uni[["DG.rho"]][match(isum$latent,
                                                             rownames(uni))], 4)
  }
  isum$gof <- round(as.numeric(model$gof), 4)
  rownames(isum) <- NULL

  scores <- as.data.frame(model$scores, stringsAsFactors = FALSE)
  rownames(scores) <- rownames(wide)

  effects <- tryCatch(as.data.frame(model$effects, stringsAsFactors = FALSE),
                      error = function(e) NULL)

  if (verbose) {
    n_sig <- sum(inner_paths$significant, na.rm = TRUE)
    cat(sprintf("  [plspm] %d path(s), %d significant (p<0.05), GoF = %.4f\n",
                nrow(inner_paths), n_sig, as.numeric(model$gof)))
  }

  list(model = model, inner_paths = inner_paths, outer_loadings = outer,
       scores = scores, fit_summary = isum, effects = effects,
       gof = as.numeric(model$gof), path_matrix = pm,
       definitions = definitions)
}


#' Summarise PLS path model results per layer transition
#'
#' @param plspm_result Output of \code{run_multiomics_plspm()}.
#' @param p_threshold Significance threshold. Default: 0.05.
#'
#' @return A data.frame with one row per (from_layer, to_layer) transition.
#'
#' @examples
#' \dontrun{
#' summarise_plspm_paths(res)
#' }
#'
#' @export
summarise_plspm_paths <- function(plspm_result, p_threshold = 0.05) {
  ip <- plspm_result$inner_paths
  if (is.null(ip) || nrow(ip) == 0) return(NULL)

  key <- paste(ip$from_layer, ip$to_layer, sep = " -> ")
  rows <- lapply(split(seq_len(nrow(ip)), key), function(idx) {
    s <- ip[idx, , drop = FALSE]
    data.frame(
      transition = paste(s$from_layer[1], s$to_layer[1], sep = " -> "),
      from_layer = s$from_layer[1],
      to_layer = s$to_layer[1],
      n_paths = nrow(s),
      n_significant = sum(s$p_value < p_threshold, na.rm = TRUE),
      mean_path_coeff = round(mean(s$path_coeff, na.rm = TRUE), 4),
      mean_abs_path_coeff = round(mean(abs(s$path_coeff), na.rm = TRUE), 4),
      max_abs_path_coeff = round(max(abs(s$path_coeff), na.rm = TRUE), 4),
      n_positive = sum(s$path_coeff > 0, na.rm = TRUE),
      n_negative = sum(s$path_coeff < 0, na.rm = TRUE),
      stringsAsFactors = FALSE)
  })

  out <- do.call(rbind, rows)
  out <- out[order(-out$n_significant, -out$mean_abs_path_coeff), ,
             drop = FALSE]
  rownames(out) <- NULL
  out
}
