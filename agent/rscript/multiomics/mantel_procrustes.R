# ==============================================================================
# OmicsFlow: Matrix-Level Congruence Between Omics Layers
# ==============================================================================
# Mantel tests and Procrustes analysis quantifying how consistently different
# omics layers, and environmental factors, order the same samples.
# ==============================================================================

#' Compute sample distance matrices for a list of omics matrices
#'
#' @description Builds one sample-by-sample distance matrix per omics layer.
#'   Distances are computed in sample space, so the cost is independent of the
#'   number of features and the full feature set can safely be used. The
#'   resulting list is reused by Mantel, Procrustes and ordination functions.
#'
#' @param mat_list Named list of numeric matrices (features x samples).
#' @param method Distance method. "bray" requires vegan and non-negative data;
#'   any method accepted by \code{stats::dist()} is also allowed.
#'   Default: "euclidean".
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A named list of \code{dist} objects, one per omics layer.
#'
#' @examples
#' \dontrun{
#' dists <- compute_omics_distances(get_omics_list(mo), method = "euclidean")
#' }
#'
#' @export
compute_omics_distances <- function(mat_list, method = "euclidean",
                                    verbose = TRUE) {
  if (!is.list(mat_list) || length(mat_list) == 0) {
    stop("mat_list must be a non-empty named list of matrices.")
  }
  if (method == "bray" && !requireNamespace("vegan", quietly = TRUE)) {
    stop("Package 'vegan' is required for Bray-Curtis distances. ",
         "Install it with install.packages('vegan').")
  }

  out <- lapply(names(mat_list), function(nm) {
    mat <- mat_list[[nm]]
    samples_by_features <- t(mat)

    d <- if (method == "bray") {
      m <- samples_by_features
      if (any(m < 0, na.rm = TRUE)) {
        cat(sprintf("[mantel] layer '%s' contains negative values; shifting for Bray-Curtis.\n",
                    nm))
        m <- m - min(m, na.rm = TRUE)
      }
      vegan::vegdist(m, method = "bray")
    } else {
      stats::dist(samples_by_features, method = method)
    }

    if (verbose) {
      cat(sprintf("[mantel] distance matrix for '%s': %d samples (%s)\n",
                  nm, attr(d, "Size"), method))
    }
    d
  })
  names(out) <- names(mat_list)
  return(out)
}


#' Mantel tests between omics layers and environmental factors
#'
#' @description Tests whether pairs of omics layers order the samples in a
#'   congruent way, and whether that ordering matches environmental gradients
#'   such as temperature, humidity or altitude. Works on sample distance
#'   matrices, so runtime does not depend on the number of features.
#'
#' @param mat_list Named list of numeric matrices (features x samples), or a
#'   named list of \code{dist} objects already computed.
#' @param env_data Optional data.frame of numeric environmental variables with
#'   samples as rows. Each variable is turned into a Euclidean distance matrix
#'   and tested against every omics layer. Default: NULL.
#' @param dist_method Distance method for the omics layers. Default:
#'   "euclidean".
#' @param env_dist_method Distance method for the environmental variables.
#'   Default: "euclidean".
#' @param method Mantel correlation method. Default: "pearson".
#' @param permutations Number of permutations. Default: 999.
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{omics_omics}: data.frame with layer_x, layer_y, mantel_r,
#'       p_value, significance.
#'     \item \code{omics_env}: data.frame with layer, variable, mantel_r,
#'       p_value, significance (empty when env_data is NULL).
#'     \item \code{distances}: The distance matrices used.
#'   }
#'
#' @examples
#' \dontrun{
#' env <- mo$sample_info[, c("temperature_C", "humidity_pct", "altitude_m")]
#' res <- run_mantel_test(get_omics_list(mo), env_data = env)
#' }
#'
#' @export
run_mantel_test <- function(mat_list, env_data = NULL,
                            dist_method = "euclidean",
                            env_dist_method = "euclidean",
                            method = "pearson",
                            permutations = 999,
                            verbose = TRUE) {
  if (!requireNamespace("vegan", quietly = TRUE)) {
    stop("Package 'vegan' is required for Mantel tests. ",
         "Install it with install.packages('vegan').")
  }
  if (!is.list(mat_list) || length(mat_list) < 1) {
    stop("mat_list must be a non-empty named list.")
  }

  # Accept either raw matrices or precomputed distances
  is_dist <- vapply(mat_list, function(x) inherits(x, "dist"), logical(1))
  if (all(is_dist)) {
    dists <- mat_list
  } else if (!any(is_dist)) {
    dists <- compute_omics_distances(mat_list, method = dist_method,
                                     verbose = verbose)
  } else {
    stop("mat_list must contain either only matrices or only dist objects.")
  }

  layer_names <- names(dists)

  # --- omics vs omics --------------------------------------------------------
  omics_omics <- data.frame(
    layer_x = character(0), layer_y = character(0),
    mantel_r = numeric(0), p_value = numeric(0),
    stringsAsFactors = FALSE
  )

  if (length(layer_names) >= 2) {
    combos <- utils::combn(layer_names, 2, simplify = FALSE)
    for (cb in combos) {
      res <- tryCatch({
        vegan::mantel(dists[[cb[1]]], dists[[cb[2]]],
                      method = method, permutations = permutations)
      }, error = function(e) {
        cat(sprintf("[mantel] %s vs %s failed: %s\n",
                    cb[1], cb[2], conditionMessage(e)))
        NULL
      })
      if (is.null(res)) next

      omics_omics <- rbind(omics_omics, data.frame(
        layer_x = cb[1], layer_y = cb[2],
        mantel_r = as.numeric(res$statistic),
        p_value = as.numeric(res$signif),
        stringsAsFactors = FALSE
      ))
      if (verbose) {
        cat(sprintf("[mantel] %-14s vs %-14s r = %6.3f, p = %.3f\n",
                    cb[1], cb[2], res$statistic, res$signif))
      }
    }
  }

  # --- omics vs environment --------------------------------------------------
  omics_env <- data.frame(
    layer = character(0), variable = character(0),
    mantel_r = numeric(0), p_value = numeric(0),
    stringsAsFactors = FALSE
  )

  if (!is.null(env_data)) {
    env_data <- as.data.frame(env_data)
    numeric_cols <- names(env_data)[vapply(env_data, is.numeric, logical(1))]
    if (length(numeric_cols) == 0) {
      cat("[mantel] env_data contains no numeric column; skipping env tests.\n")
    }

    ref_labels <- labels(dists[[1]])

    for (vr in numeric_cols) {
      vals <- env_data[[vr]]
      names(vals) <- rownames(env_data)
      vals <- vals[ref_labels]

      if (all(is.na(vals)) || stats::var(vals, na.rm = TRUE) == 0) {
        cat(sprintf("[mantel] variable '%s' is constant or missing; skipped.\n", vr))
        next
      }

      env_dist <- stats::dist(matrix(vals, ncol = 1,
                                     dimnames = list(ref_labels, vr)),
                              method = env_dist_method)

      for (nm in layer_names) {
        res <- tryCatch({
          vegan::mantel(dists[[nm]], env_dist,
                        method = method, permutations = permutations)
        }, error = function(e) {
          cat(sprintf("[mantel] %s vs %s failed: %s\n",
                      nm, vr, conditionMessage(e)))
          NULL
        })
        if (is.null(res)) next

        omics_env <- rbind(omics_env, data.frame(
          layer = nm, variable = vr,
          mantel_r = as.numeric(res$statistic),
          p_value = as.numeric(res$signif),
          stringsAsFactors = FALSE
        ))
        if (verbose) {
          cat(sprintf("[mantel] %-14s vs %-14s r = %6.3f, p = %.3f\n",
                      nm, vr, res$statistic, res$signif))
        }
      }
    }
  }

  if (nrow(omics_omics) > 0) {
    omics_omics$significance <- .significance_stars(omics_omics$p_value)
  }
  if (nrow(omics_env) > 0) {
    omics_env$significance <- .significance_stars(omics_env$p_value)
  }

  return(list(
    omics_omics = omics_omics,
    omics_env = omics_env,
    distances = dists
  ))
}


#' Significance star helper
#'
#' @param p Numeric vector of p-values.
#'
#' @return A character vector of significance codes.
#'
#' @keywords internal
.significance_stars <- function(p) {
  out <- rep("ns", length(p))
  out[!is.na(p) & p <= 0.05] <- "*"
  out[!is.na(p) & p <= 0.01] <- "**"
  out[!is.na(p) & p <= 0.001] <- "***"
  out
}


#' Procrustes analysis between two omics layers
#'
#' @description Rotates the ordination of one omics layer onto another and
#'   tests the significance of their congruence with PROTEST. Returns the
#'   superimposed coordinates so that per-sample residuals can be plotted.
#'
#' @param mat_x Numeric matrix of the first layer (features x samples), or a
#'   \code{dist} object.
#' @param mat_y Numeric matrix of the second layer (features x samples), or a
#'   \code{dist} object.
#' @param dist_method Distance method used when matrices are supplied.
#'   Default: "euclidean".
#' @param ncomp Number of ordination axes retained. Default: 2.
#' @param permutations Number of permutations for PROTEST. Default: 999.
#' @param name_x Label of the first layer. Default: "x".
#' @param name_y Label of the second layer. Default: "y".
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{procrustes}: The vegan procrustes object.
#'     \item \code{protest}: The PROTEST result.
#'     \item \code{ss}: Procrustes sum of squares.
#'     \item \code{correlation}: Procrustes correlation.
#'     \item \code{p_value}: Permutation p-value.
#'     \item \code{coordinates}: data.frame with sample, x1, y1, x2, y2 and
#'       residual, ready for plotting.
#'   }
#'
#' @examples
#' \dontrun{
#' proc <- run_procrustes(get_omics_matrix(mo, "microbiome"),
#'                        get_omics_matrix(mo, "metabolome"))
#' }
#'
#' @export
run_procrustes <- function(mat_x, mat_y,
                           dist_method = "euclidean",
                           ncomp = 2,
                           permutations = 999,
                           name_x = "x",
                           name_y = "y",
                           verbose = TRUE) {
  if (!requireNamespace("vegan", quietly = TRUE)) {
    stop("Package 'vegan' is required for Procrustes analysis. ",
         "Install it with install.packages('vegan').")
  }

  dx <- if (inherits(mat_x, "dist")) mat_x else
    stats::dist(t(as.matrix(mat_x)), method = dist_method)
  dy <- if (inherits(mat_y, "dist")) mat_y else
    stats::dist(t(as.matrix(mat_y)), method = dist_method)

  common <- intersect(labels(dx), labels(dy))
  if (length(common) < 3) {
    stop("At least 3 shared samples are required for Procrustes analysis.")
  }

  pcoa_x <- stats::cmdscale(dx, k = ncomp)
  pcoa_y <- stats::cmdscale(dy, k = ncomp)
  pcoa_x <- pcoa_x[common, , drop = FALSE]
  pcoa_y <- pcoa_y[common, , drop = FALSE]

  proc <- vegan::procrustes(pcoa_x, pcoa_y, symmetric = TRUE)
  prot <- vegan::protest(pcoa_x, pcoa_y, permutations = permutations)

  # residuals() is an S3 method registered by vegan, not an exported object,
  # so it has to be dispatched through the generic in stats.
  resid <- stats::residuals(proc)

  coords <- data.frame(
    sample = common,
    x1 = proc$X[, 1],
    y1 = if (ncomp >= 2) proc$X[, 2] else 0,
    x2 = proc$Yrot[, 1],
    y2 = if (ncomp >= 2) proc$Yrot[, 2] else 0,
    residual = as.numeric(resid),
    stringsAsFactors = FALSE
  )
  rownames(coords) <- NULL

  if (verbose) {
    cat(sprintf("[procrustes] %s vs %s: SS = %.4f, corr = %.3f, p = %.3f\n",
                name_x, name_y, proc$ss, prot$scale, prot$signif))
  }

  return(list(
    procrustes = proc,
    protest = prot,
    ss = as.numeric(proc$ss),
    correlation = as.numeric(prot$t0),
    p_value = as.numeric(prot$signif),
    coordinates = coords,
    params = list(name_x = name_x, name_y = name_y, ncomp = ncomp)
  ))
}


#' Run Procrustes analysis for several layer pairs
#'
#' @param mo A MultiOmicsData object.
#' @param layer_pairs List of length-2 character vectors naming layers.
#' @param dist_method Distance method. Default: "euclidean".
#' @param permutations Number of permutations. Default: 999.
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A list with \code{results} (named list of \code{run_procrustes()}
#'   outputs) and \code{summary} (data.frame with layer_x, layer_y, ss,
#'   correlation, p_value, significance).
#'
#' @examples
#' \dontrun{
#' pr <- run_all_procrustes(mo, list(c("microbiome", "metabolome")))
#' }
#'
#' @export
run_all_procrustes <- function(mo, layer_pairs,
                               dist_method = "euclidean",
                               permutations = 999,
                               verbose = TRUE) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }

  results <- list()
  summary_df <- data.frame(
    layer_x = character(0), layer_y = character(0),
    ss = numeric(0), correlation = numeric(0), p_value = numeric(0),
    stringsAsFactors = FALSE
  )

  for (lp in layer_pairs) {
    if (length(lp) != 2) next
    key <- paste(lp[1], lp[2], sep = "__")

    res <- tryCatch({
      run_procrustes(
        mat_x = get_omics_matrix(mo, lp[1]),
        mat_y = get_omics_matrix(mo, lp[2]),
        dist_method = dist_method,
        permutations = permutations,
        name_x = lp[1], name_y = lp[2],
        verbose = verbose
      )
    }, error = function(e) {
      cat(sprintf("[procrustes] pair %s failed: %s\n", key, conditionMessage(e)))
      NULL
    })

    if (is.null(res)) next
    results[[key]] <- res
    summary_df <- rbind(summary_df, data.frame(
      layer_x = lp[1], layer_y = lp[2],
      ss = res$ss, correlation = res$correlation, p_value = res$p_value,
      stringsAsFactors = FALSE
    ))
  }

  if (nrow(summary_df) > 0) {
    summary_df$significance <- .significance_stars(summary_df$p_value)
  }

  return(list(results = results, summary = summary_df))
}
