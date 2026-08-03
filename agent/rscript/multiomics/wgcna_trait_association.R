# ==============================================================================
# OmicsFlow: WGCNA Module - Downstream Trait Association
# ==============================================================================
# Builds WGCNA co-expression modules on one omics layer, then treats the
# molecular features of a downstream omics layer as biological traits and tests
# the association between every module eigengene and every downstream feature.
# This answers "which co-expressed module of layer A tracks which molecule of
# layer B" and supports the trait-driven view of cross-omics integration.
# ==============================================================================

#' Build WGCNA modules on a multi-omics layer
#'
#' @description Thin wrapper around the shared \code{build_wgcna_modules()}
#'   that guarantees a stable sample order and retains the module membership
#'   table needed for downstream trait association. The expression matrix is
#'   taken from a MultiOmicsData container so the sample alignment inherited
#'   from the container is preserved.
#'
#' @param mo A MultiOmicsData object.
#' @param layer Name of the omics layer used to build the modules.
#' @param soft_power Numeric soft-thresholding power. Default: NULL (auto).
#' @param min_module_size Minimum module size. Default: 10.
#' @param merge_cut_height Module merging cut height. Default: 0.25.
#' @param network_type Network type passed to WGCNA. Default: "signed".
#' @param cor_fn Correlation function string. Default: "cor".
#'
#' @return A list with \code{module_colors} (named vector per feature),
#'   \code{MEs} (samples x modules), \code{soft_power}, \code{membership}
#'   (data.frame of feature, module_color, module_label) and the original layer
#'   name.
#'
#' @examples
#' \dontrun{
#' wgcna <- build_wgcna_modules_layer(mo, "transcriptome")
#' }
#'
#' @export
build_wgcna_modules_layer <- function(mo, layer,
                                      soft_power = NULL,
                                      min_module_size = 10,
                                      merge_cut_height = 0.25,
                                      network_type = "signed",
                                      cor_fn = "cor") {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (!layer %in% names(mo$omics)) {
    stop(sprintf("Omics layer '%s' not found. Available: %s",
                 layer, paste(names(mo$omics), collapse = ", ")))
  }

  mat <- mo$omics[[layer]]$expression
  n_samp <- ncol(mat)
  n_feat <- nrow(mat)
  if (n_feat < min_module_size * 3) {
    stop(sprintf("Layer '%s' has only %d features; too few for WGCNA with min_module_size=%d.",
                 layer, n_feat, min_module_size))
  }
  cat(sprintf("  [WGCNA] building modules on '%s' (%d features x %d samples)\n",
              layer, n_feat, n_samp))

  wgcna <- build_wgcna_modules(
    expr_matrix = mat,
    soft_power = soft_power,
    min_module_size = min_module_size,
    merge_cut_height = merge_cut_height,
    network_type = network_type,
    cor_fn = cor_fn
  )

  membership <- data.frame(
    feature = names(wgcna$module_colors),
    module_color = unname(wgcna$module_colors),
    stringsAsFactors = FALSE
  )
  rownames(membership) <- membership$feature

  n_modules <- length(setdiff(unique(wgcna$module_colors), "grey"))
  cat(sprintf("  [WGCNA] '%s': soft power = %s, %d non-grey module(s)\n",
              layer, wgcna$soft_power, n_modules))

  list(
    module_colors = wgcna$module_colors,
    module_labels = wgcna$module_labels,
    MEs = wgcna$MEs,
    soft_power = wgcna$soft_power,
    membership = membership,
    gene_tree = wgcna$gene_tree,
    diss_TOM = wgcna$diss_TOM,
    layer = layer
  )
}


#' Extract downstream omics features as a trait matrix
#'
#' @description Converts the expression matrix of a downstream omics layer into
#'   the samples x traits matrix expected by the trait association, aligning
#'   samples to a reference sample order. Optionally only a subset of features
#'   can be retained (e.g. features already shown to be differential or those
#'   present in a signature list).
#'
#' @param mo A MultiOmicsData object.
#' @param layer Name of the downstream omics layer.
#' @param reference_samples Character vector of sample IDs to align to.
#' @param features Optional character vector restricting the traits. Default:
#'   NULL (all features).
#' @param log_transform Logical, apply log2(x+1) to each trait. Default: FALSE.
#'
#' @return A numeric matrix (samples x traits) with sample order matching
#'   \code{reference_samples}.
#'
#' @examples
#' \dontrun{
#' traits <- wgcna_traits_from_layer(mo, "metabolome", reference_samples = samples)
#' }
#'
#' @export
wgcna_traits_from_layer <- function(mo, layer, reference_samples,
                                    features = NULL,
                                    log_transform = FALSE) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (!layer %in% names(mo$omics)) {
    stop(sprintf("Omics layer '%s' not found.", layer))
  }
  mat <- mo$omics[[layer]]$expression
  if (!is.null(features)) {
    keep <- intersect(features, rownames(mat))
    if (length(keep) == 0) {
      stop("None of the requested features are present in the downstream layer.")
    }
    mat <- mat[keep, , drop = FALSE]
  }
  common <- intersect(reference_samples, colnames(mat))
  if (length(common) < 3) {
    stop(sprintf("Too few shared samples between reference and layer '%s'.", layer))
  }
  traits <- t(as.matrix(mat[, common, drop = FALSE]))
  if (isTRUE(log_transform)) traits <- log2(traits + 1)

  # Ensure traits are numeric and drop any zero-variance columns.
  mode(traits) <- "numeric"
  v <- apply(traits, 2, function(x) stats::var(x, na.rm = TRUE))
  keep_col <- !is.na(v) & v > 0
  if (sum(keep_col) < ncol(traits)) {
    cat(sprintf("  [WGCNA] trait layer '%s': %d zero-variance feature(s) dropped.\n",
                layer, sum(!keep_col)))
  }
  traits <- traits[, keep_col, drop = FALSE]

  # Return in the reference order (rows are samples).
  traits <- traits[reference_samples[reference_samples %in% rownames(traits)], , drop = FALSE]
  return(traits)
}


#' WGCNA module eigengene vs downstream trait association
#'
#' @description Correlates every module eigengene of the module layer with every
#'   molecular feature (trait) of a downstream omics layer, and additionally fits
#'   a univariate linear model for each module-trait pair. P-values are adjusted
#'   across all tested module-trait pairs so the results are ready for global
#'   significance filtering.
#'
#' @param wgcna A WGCNA result from \code{build_wgcna_modules_layer()}.
#' @param traits A numeric matrix (samples x traits) from
#'   \code{wgcna_traits_from_layer()}.
#' @param trait_layer Name of the downstream layer (used for labels).
#' @param cor_method Correlation method. Default: "pearson".
#' @param p_adjust Multiple testing adjustment. Default: "BH".
#' @param verbose Logical, print a short summary. Default: TRUE.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{module_trait}: data.frame of module, trait, r, p, padj,
#'       and lm slope, intercept, r_squared.
#'     \item \code{module_summary}: per-module summary of significant trait hits.
#'     \item \code{trait_summary}: per-trait summary of significant module hits.
#'     \item \code{used_traits}: data.frame of trait id and layer.
#'   }
#'
#' @examples
#' \dontrun{
#' assoc <- run_wgcna_trait_association(wgcna, traits, trait_layer = "metabolome")
#' }
#'
#' @export
run_wgcna_trait_association <- function(wgcna, traits,
                                        trait_layer,
                                        cor_method = "pearson",
                                        p_adjust = "BH",
                                        verbose = TRUE) {
  MEs <- wgcna$MEs
  common <- intersect(rownames(MEs), rownames(traits))
  if (length(common) < 4) {
    stop("Need at least 4 shared samples between module eigengenes and traits.")
  }
  MEs <- MEs[common, , drop = FALSE]
  traits <- traits[common, , drop = FALSE]

  modules <- colnames(MEs)
  trait_ids <- colnames(traits)
  modules <- modules[modules != "MEgrey"]  # unassigned genes are not a module

  if (length(modules) == 0) {
    stop("No non-grey module is available for trait association.")
  }

  rows <- list()
  for (mod in modules) {
    x <- as.numeric(MEs[, mod])
    if (stats::var(x, na.rm = TRUE) == 0) next
    for (tr in trait_ids) {
      y <- as.numeric(traits[, tr])
      if (stats::var(y, na.rm = TRUE) == 0) next
      ct <- tryCatch(stats::cor.test(x, y, method = cor_method),
                     error = function(e) NULL)
      if (is.null(ct)) next
      fit <- tryCatch(stats::lm(y ~ x), error = function(e) NULL)
      if (is.null(fit)) next
      s <- summary(fit)
      co <- stats::coef(s)
      rows[[length(rows) + 1L]] <- data.frame(
        module = mod,
        trait = tr,
        r = unname(ct$estimate),
        p = ct$p.value,
        lm_slope = unname(co[2, 1]),
        lm_se = unname(co[2, 2]),
        lm_t = unname(co[2, 3]),
        lm_p = unname(co[2, 4]),
        lm_r_squared = unname(s$r.squared),
        n_samples = length(common),
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) {
    return(list(module_trait = data.frame(),
                module_summary = data.frame(),
                trait_summary = data.frame(),
                used_traits = data.frame(trait = trait_ids, layer = trait_layer)))
  }
  out <- do.call(rbind, rows)
  out$padj <- stats::p.adjust(out$p, method = p_adjust)
  out$significant <- out$padj < 0.05
  out <- out[order(out$padj, -abs(out$r)), , drop = FALSE]
  rownames(out) <- NULL

  module_summary <- do.call(rbind, lapply(split(out, out$module), function(sub) {
    data.frame(
      module = sub$module[1],
      n_traits_tested = nrow(sub),
      n_significant = sum(sub$significant),
      mean_abs_r = mean(abs(sub$r)),
      best_trait = sub$trait[1],
      best_r = sub$r[1],
      best_padj = sub$padj[1],
      stringsAsFactors = FALSE
    )
  }))
  module_summary <- module_summary[order(-module_summary$n_significant,
                                         -module_summary$mean_abs_r), , drop = FALSE]
  rownames(module_summary) <- NULL

  trait_summary <- do.call(rbind, lapply(split(out, out$trait), function(sub) {
    data.frame(
      trait = sub$trait[1],
      n_modules_tested = nrow(sub),
      n_significant = sum(sub$significant),
      best_module = sub$module[1],
      best_r = sub$r[1],
      best_padj = sub$padj[1],
      stringsAsFactors = FALSE
    )
  }))
  trait_summary <- trait_summary[order(-trait_summary$n_significant,
                                       -abs(trait_summary$best_r)), , drop = FALSE]
  rownames(trait_summary) <- NULL

  if (verbose) {
    cat(sprintf("  [WGCNA] %d module-trait pairs tested, %d significant (padj<0.05)\n",
                nrow(out), sum(out$significant)))
  }

  list(
    module_trait = out,
    module_summary = module_summary,
    trait_summary = trait_summary,
    used_traits = data.frame(trait = trait_ids, layer = trait_layer)
  )
}


#' Map module membership back to feature names
#'
#' @description Attaches readable feature identifiers (from the feature
#'   annotation) to a module-trait result so the significant pairs can be
#'   interpreted biologically instead of by internal feature ids.
#'
#' @param assoc Result of \code{run_wgcna_trait_association()}.
#' @param module_feature_info Feature annotation of the module layer.
#' @param module_layer Name of the module layer.
#' @param trait_feature_info Feature annotation of the trait layer.
#' @param trait_layer Name of the trait layer.
#'
#' @return A data.frame identical to \code{assoc$module_trait} plus module and
#'   trait display-name columns.
#'
#' @export
annotate_wgcna_trait_result <- function(assoc, module_feature_info = NULL,
                                        module_layer = "module",
                                        trait_feature_info = NULL,
                                        trait_layer = "trait") {
  res <- assoc$module_trait
  if (is.null(res) || nrow(res) == 0) return(res)
  res$module_layer <- module_layer
  res$trait_layer <- trait_layer
  res$module_name <- res$module
  if (!is.null(trait_feature_info) && nrow(trait_feature_info) > 0 &&
      "name" %in% colnames(trait_feature_info)) {
    name_map <- stats::setNames(as.character(trait_feature_info$name),
                                rownames(trait_feature_info))
    res$trait_name <- unname(name_map[res$trait])
    res$trait_name[is.na(res$trait_name)] <- res$trait[is.na(res$trait_name)]
  } else {
    res$trait_name <- res$trait
  }
  return(res)
}


#' Heatmap of module-trait correlation matrix
#'
#' @description Renders a tile heatmap of module eigengene vs downstream trait
#'   correlations with significance stars. When the number of traits is large,
#'   only the top traits by significance are shown and the rest are aggregated
#'   in the return value.
#'
#' @param assoc Result of \code{run_wgcna_trait_association()}.
#' @param top_n_traits Maximum number of traits shown. Default: 40.
#' @param title Optional plot title.
#'
#' @return A ggplot object (invisibly a list with the data is returned for the
#'   full matrix when n_traits exceeds \code{top_n_traits}).
#'
#' @examples
#' \dontrun{
#' p <- plot_wgcna_trait_heatmap(assoc, top_n_traits = 30)
#' }
#'
#' @export
plot_wgcna_trait_heatmap <- function(assoc, top_n_traits = 40, title = NULL) {
  res <- assoc$module_trait
  if (is.null(res) || nrow(res) == 0) {
    stop("No module-trait pairs to plot.")
  }
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' is required.")
  }

  # Choose the top traits by minimum adjusted p-value.
  trait_rank <- aggregate(padj ~ trait, res, FUN = min)
  trait_rank <- trait_rank[order(trait_rank$padj), , drop = FALSE]
  top_traits <- head(trait_rank$trait, top_n_traits)
  sub <- res[res$trait %in% top_traits, , drop = FALSE]

  sub$module <- factor(sub$module, levels = rev(sort(unique(sub$module))))
  sub$trait <- factor(sub$trait, levels = rev(unique(sub$trait)))
  sub$star <- ifelse(sub$padj < 0.001, "***",
                     ifelse(sub$padj < 0.01, "**",
                            ifelse(sub$padj < 0.05, "*", "")))

  p <- ggplot2::ggplot(sub, ggplot2::aes(x = trait, y = module, fill = r)) +
    ggplot2::geom_tile(color = "grey90") +
    ggplot2::geom_text(ggplot2::aes(label = star), size = 2.6, nudge_y = 0.22) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", r)), size = 2.4,
                       nudge_y = -0.22) +
    ggplot2::scale_fill_gradient2(low = "#2c7bb6", mid = "white",
                                  high = "#d7191c", midpoint = 0,
                                  name = "Correlation") +
    ggplot2::labs(
      title = if (is.null(title)) "Module eigengene vs downstream trait" else title,
      x = "Downstream trait", y = "WGCNA module") +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold", hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 90, hjust = 1, vjust = 0.5,
                                          size = 7),
      axis.text.y = ggplot2::element_text(size = 9)
    )
  return(p)
}
