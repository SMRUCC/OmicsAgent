# ==============================================================================
# OmicsFlow：基于注释的通路桥接
# ==============================================================================
# 将共享同一生物学注释（KEGG 通路、化合物超类、分类学家族）的不同组学层特征
# 聚合为模块特征值，再跨层连接这些模块，以追踪从基因到蛋白到代谢物再到香气
# 化合物的路径。
# ==============================================================================

#' 按来源生物拆分特征注释表
#'
#' @description 利用转录组与蛋白质组注释中的 \code{organism} 列，将宿主特征与
#'   微生物特征分开，以便分别建模宿主与微生物的通路。
#'
#' @param feature_info 特征注释 data.frame。
#' @param organism_col 保存生物标签的列。默认："organism"。
#' @param host_pattern 用于识别宿主特征的正则表达式。默认："Nicotiana"。
#'
#' @return 一个列表，含 \code{host} 与 \code{microbe} 两个 data.frame。当该列
#'   缺失时，所有特征都作为 \code{host} 返回，并发出警告。
#'
#' @examples
#' \dontrun{
#' parts <- split_by_organism(feature_info)
#' }
#'
#' @export
split_by_organism <- function(feature_info,
                              organism_col = "organism",
                              host_pattern = "Nicotiana") {
  if (!is.data.frame(feature_info)) {
    stop("feature_info must be a data.frame.")
  }
  if (!organism_col %in% colnames(feature_info)) {
    warning(sprintf("Column '%s' not found; treating all features as host.",
                    organism_col))
    return(list(host = feature_info, microbe = feature_info[0, , drop = FALSE]))
  }
  org <- as.character(feature_info[[organism_col]])
  is_host <- grepl(host_pattern, org, ignore.case = TRUE)
  is_host[is.na(is_host)] <- FALSE
  list(
    host = feature_info[is_host, , drop = FALSE],
    microbe = feature_info[!is_host, , drop = FALSE]
  )
}


#' Build cross-omics modules from a shared annotation column
#'
#' @description For every omics layer, groups features sharing an annotation
#'   value and summarises each group by its module eigenvalue (first principal
#'   component), following the aggregation idea already used by
#'   \code{build_latent_def_from_annotation()} in the network module. Layers
#'   lacking the annotation column are skipped with a message rather than
#'   aborting, because the 16S annotation for instance carries no super class.
#'
#' @param mo A MultiOmicsData object.
#' @param category_col Annotation column used for grouping, for example
#'   "super_class", "family" or "kegg". Default: "super_class".
#' @param layers Optional character vector of layers. Default: NULL (all).
#' @param min_size Minimum number of features per module. Default: 3.
#' @param organism_col Optional column used to restrict features to one
#'   organism class. Default: NULL.
#' @param organism_keep One of "all", "host" or "microbe". Only applied when
#'   \code{organism_col} exists in a layer. Default: "all".
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{eigengenes}: Named list of module x sample matrices, one per
#'       layer.
#'     \item \code{definitions}: data.frame of layer, module, n_features.
#'     \item \code{category_col}: The annotation column used.
#'   }
#'
#' @examples
#' \dontrun{
#' mods <- build_cross_omics_modules(mo, category_col = "super_class")
#' }
#'
#' @export
build_cross_omics_modules <- function(mo,
                                      category_col = "super_class",
                                      layers = NULL,
                                      min_size = 3,
                                      organism_col = NULL,
                                      organism_keep = "all",
                                      verbose = TRUE) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  organism_keep <- match.arg(organism_keep, c("all", "host", "microbe"))
  if (is.null(layers)) layers <- mo$metadata$omics_names
  layers <- intersect(layers, mo$metadata$omics_names)
  if (length(layers) == 0) stop("No valid layers selected.")

  eigengenes <- list()
  defs <- list()

  for (nm in layers) {
    od <- mo$omics[[nm]]
    finfo <- od$feature_info
    expr <- od$expression

    if (is.null(finfo) || !category_col %in% colnames(finfo)) {
      if (verbose) {
        cat(sprintf("  [%s] no '%s' annotation, skipped.\n", nm, category_col))
      }
      next
    }

    # Optional restriction to host or microbial features.
    if (!is.null(organism_col) && organism_keep != "all" &&
        organism_col %in% colnames(finfo)) {
      parts <- split_by_organism(finfo, organism_col = organism_col)
      finfo <- if (organism_keep == "host") parts$host else parts$microbe
      if (nrow(finfo) == 0) {
        if (verbose) {
          cat(sprintf("  [%s] no %s features, skipped.\n", nm, organism_keep))
        }
        next
      }
    }

    # The layer was matched on match_col, so feature_info rownames carry the
    # identifiers used as rownames of the expression matrix. Expose them as an
    # explicit column so predefined_module_eigengenes() can match on it.
    finfo <- finfo[rownames(finfo) %in% rownames(expr), , drop = FALSE]
    if (nrow(finfo) == 0) {
      if (verbose) cat(sprintf("  [%s] no feature matches expression, skipped.\n", nm))
      next
    }
    finfo[[".feature_key"]] <- rownames(finfo)

    eg <- tryCatch(
      predefined_module_eigengenes(
        expr_matrix = expr,
        feature_info = finfo,
        feature_id_col = ".feature_key",
        category_col = category_col,
        min_size = min_size
      ),
      error = function(e) {
        cat(sprintf("  [%s] eigengene computation failed: %s\n",
                    nm, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(eg) || is.null(eg$MEs) || eg$n_modules == 0) {
      if (verbose) {
        cat(sprintf("  [%s] no module reaches min_size=%d, skipped.\n",
                    nm, min_size))
      }
      next
    }

    # MEs is samples x modules; transpose to modules x samples.
    mat <- t(as.matrix(eg$MEs))

    eigengenes[[nm]] <- mat
    defs[[nm]] <- data.frame(
      omics = nm,
      module = names(eg$module_sizes),
      n_features = as.integer(eg$module_sizes),
      stringsAsFactors = FALSE
    )
    if (verbose) {
      cat(sprintf("  [%s] %d modules from %d annotated features.\n",
                  nm, eg$n_modules, nrow(finfo)))
    }
  }

  definitions <- if (length(defs) > 0) {
    out <- do.call(rbind, defs)
    rownames(out) <- NULL
    out
  } else {
    data.frame()
  }

  list(
    eigengenes = eigengenes,
    definitions = definitions,
    category_col = category_col
  )
}


#' Link shared modules across consecutive omics layers
#'
#' @description Correlates module eigenvalues carrying the same annotation
#'   label between successive layers of the central dogma, producing the
#'   gene to protein to metabolite to aroma chain for every shared category.
#'
#' @param modules Result of \code{build_cross_omics_modules()}.
#' @param layer_order Character vector giving the biological ordering of the
#'   layers. Default: c("transcriptome", "proteome", "metabolome", "volatilome").
#' @param method Correlation method. Default: "pearson".
#' @param p_adjust Multiple testing adjustment. Default: "BH".
#' @param verbose Logical, print progress. Default: TRUE.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{links}: data.frame of module, from_layer, to_layer, r, p,
#'       padj and the module sizes.
#'     \item \code{chains}: data.frame summarising, per module, how many
#'       consecutive links are significant.
#'   }
#'
#' @examples
#' \dontrun{
#' bridge <- run_pathway_bridge(mods)
#' }
#'
#' @export
run_pathway_bridge <- function(modules,
                               layer_order = c("transcriptome", "proteome",
                                               "metabolome", "volatilome"),
                               method = "pearson",
                               p_adjust = "BH",
                               verbose = TRUE) {
  if (is.null(modules$eigengenes) || length(modules$eigengenes) == 0) {
    stop("No module eigengenes available; run build_cross_omics_modules() first.")
  }
  eg <- modules$eigengenes
  present <- intersect(layer_order, names(eg))
  if (length(present) < 2) {
    stop("At least two annotated layers are required for pathway bridging.")
  }

  rows <- list()
  for (i in seq_len(length(present) - 1L)) {
    a <- present[i]
    b <- present[i + 1L]
    ma <- eg[[a]]
    mb <- eg[[b]]
    shared_samples <- intersect(colnames(ma), colnames(mb))
    shared_modules <- intersect(rownames(ma), rownames(mb))
    if (length(shared_samples) < 4 || length(shared_modules) == 0) {
      if (verbose) {
        cat(sprintf("  %s -> %s: no shared module or too few samples.\n", a, b))
      }
      next
    }
    for (mod in shared_modules) {
      x <- as.numeric(ma[mod, shared_samples])
      y <- as.numeric(mb[mod, shared_samples])
      if (stats::var(x, na.rm = TRUE) == 0 || stats::var(y, na.rm = TRUE) == 0) next
      ct <- tryCatch(stats::cor.test(x, y, method = method),
                     error = function(e) NULL)
      if (is.null(ct)) next
      rows[[length(rows) + 1L]] <- data.frame(
        module = mod,
        from_layer = a,
        to_layer = b,
        r = unname(ct$estimate),
        p = ct$p.value,
        n_samples = length(shared_samples),
        stringsAsFactors = FALSE
      )
    }
    if (verbose) {
      cat(sprintf("  %s -> %s: %d shared modules tested.\n",
                  a, b, length(shared_modules)))
    }
  }

  if (length(rows) == 0) {
    return(list(links = data.frame(), chains = data.frame()))
  }
  links <- do.call(rbind, rows)
  links$padj <- stats::p.adjust(links$p, method = p_adjust)
  links <- links[order(links$padj, -abs(links$r)), , drop = FALSE]
  rownames(links) <- NULL

  # Per-module summary of how much of the chain is significant.
  chain_list <- lapply(split(links, links$module), function(sub) {
    data.frame(
      module = sub$module[1],
      n_links = nrow(sub),
      n_significant = sum(sub$padj < 0.05, na.rm = TRUE),
      mean_abs_r = mean(abs(sub$r), na.rm = TRUE),
      path = paste(paste0(sub$from_layer, "->", sub$to_layer,
                          sprintf("(r=%.2f)", sub$r)), collapse = " | "),
      stringsAsFactors = FALSE
    )
  })
  chains <- do.call(rbind, chain_list)
  chains <- chains[order(-chains$n_significant, -chains$mean_abs_r), , drop = FALSE]
  rownames(chains) <- NULL

  if (verbose) {
    cat(sprintf("  Pathway bridging: %d links, %d significant (padj < 0.05).\n",
                nrow(links), sum(links$padj < 0.05, na.rm = TRUE)))
  }

  list(links = links, chains = chains)
}
