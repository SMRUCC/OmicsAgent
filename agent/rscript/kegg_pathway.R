# ==============================================================================
# OmicsFlow: KEGG Pathway Mapping and Analysis
# ==============================================================================
# Map KEGG compound IDs to KEGG pathways, then perform pathway-level
# enrichment analysis and GSVA. This corrects the scientific error of treating
# compound IDs as pathway IDs.
# ==============================================================================

#' Map KEGG compound IDs to KEGG pathways
#'
#' @description Queries the KEGG REST API to map compound IDs (e.g., C02845)
#'   to their associated metabolic pathways (e.g., map00010). A compound can
#'   be associated with multiple pathways. Returns a data.frame with
#'   compound-pathway pairs.
#'
#' @param kegg_ids Character vector of KEGG compound IDs (e.g., "C02845").
#' @param cache_file Optional path to cache file for storing/retrieving
#'   the mapping. Default: NULL.
#' @param batch_size Number of compounds per API request (max 10). Default: 10.
#' @param delay Seconds between API calls. Default: 0.3.
#'
#' @return A data.frame with columns:
#'   \itemize{
#'     \item \code{compound_id}: KEGG compound ID.
#'     \item \code{pathway_id}: KEGG pathway ID (e.g., "map00010").
#'     \item \code{pathway_name}: Pathway name (e.g., "Glycolysis / Gluconeogenesis").
#'   }
#'
#' @examples
#' \dontrun{
#' mapping <- map_kegg_compound_to_pathway(c("C00022", "C00135"))
#' head(mapping)
#' }
#'
#' @export
map_kegg_compound_to_pathway <- function(kegg_ids, cache_dir = NULL,
                                          batch_size = 10, delay = 0.3) {
  # Clean input
  kegg_ids <- unique(kegg_ids[!is.na(kegg_ids) & kegg_ids != "" &
                                kegg_ids != "NULL" & kegg_ids != "NA"])
  if (length(kegg_ids) == 0) {
    warning("No valid KEGG compound IDs provided.")
    return(data.frame(
      compound_id = character(),
      pathway_id = character(),
      pathway_name = character(),
      stringsAsFactors = FALSE
    ))
  }

  # Check cache
  cache_file <- if (!is.null(cache_dir)) file.path(cache_dir, "kegg_pathway_mapping.csv") else NULL
  if (!is.null(cache_file) && file.exists(cache_file)) {
    cached <- utils::read.csv(cache_file, stringsAsFactors = FALSE)
    cached_ids <- unique(cached$compound_id)
    new_ids <- setdiff(kegg_ids, cached_ids)
    if (length(new_ids) == 0) {
      cat("  Using cached KEGG pathway mapping\n")
      return(cached[cached$compound_id %in% kegg_ids, ])
    }
    kegg_ids <- new_ids
    cached_data <- cached
  } else {
    cached_data <- NULL
  }

  # Ensure "cpd:" prefix
  query_ids <- paste0("cpd:", kegg_ids)

  # Query KEGG API in batches
  all_links <- character()
  n_batches <- ceiling(length(query_ids) / batch_size)

  for (b in seq_len(n_batches)) {
    start_idx <- (b - 1) * batch_size + 1
    end_idx <- min(b * batch_size, length(query_ids))
    batch <- query_ids[start_idx:end_idx]

    url <- paste0("https://rest.kegg.jp/link/pathway/", paste(batch, collapse = "+"))

    tryCatch({
      tmp <- tempfile()
      system2("curl", args = c("-s", url), stdout = tmp, stderr = NULL)
      lines <- readLines(tmp, warn = FALSE)
      unlink(tmp)
      if (length(lines) > 0 && any(nchar(lines) > 0)) {
        all_links <- c(all_links, lines[nchar(lines) > 0])
      }
    }, error = function(e) {
      warning("Failed to query KEGG API for batch ", b)
    })

    if (b %% 10 == 0) cat("  KEGG API: batch", b, "/", n_batches, "\n")
    if (delay > 0) Sys.sleep(delay)
  }

  if (length(all_links) == 0) {
    warning("No pathway associations found for any compound.")
    return(data.frame(
      compound_id = character(),
      pathway_id = character(),
      pathway_name = character(),
      stringsAsFactors = FALSE
    ))
  }

  # Parse links
  links <- strsplit(all_links, "\t")
  compound_ids <- gsub("cpd:", "", sapply(links, `[`, 1))
  pathway_ids <- sapply(links, `[`, 2)

  # Get pathway names
  unique_pathways <- unique(pathway_ids)
  cat("  Found", length(unique_pathways), "unique pathways for",
      length(unique(compound_ids)), "compounds\n")

  pathway_names <- character(length(unique_pathways))
  names(pathway_names) <- unique_pathways

  for (i in seq_along(unique_pathways)) {
    pw <- unique_pathways[i]
    tryCatch({
      tmp <- tempfile()
      system2("curl", args = c("-s", paste0("https://rest.kegg.jp/get/", pw)),
              stdout = tmp, stderr = NULL)
      lines <- readLines(tmp, warn = FALSE)
      unlink(tmp)
      name_line <- grep("^NAME", lines, value = TRUE)[1]
      if (!is.na(name_line)) {
        pathway_names[pw] <- gsub("^NAME\\s+", "", name_line)
      } else {
        pathway_names[pw] <- pw
      }
    }, error = function(e) {
      pathway_names[pw] <- pw
    })
    if (i %% 20 == 0) cat("  Pathway names:", i, "/", length(unique_pathways), "\n")
    if (delay > 0) Sys.sleep(delay)
  }

  result <- data.frame(
    compound_id = compound_ids,
    pathway_id = pathway_ids,
    pathway_name = pathway_names[pathway_ids],
    stringsAsFactors = FALSE
  )

  # Cache
  if (!is.null(cache_file)) {
    if (!is.null(cached_data)) {
      result <- rbind(cached_data, result)
    }
    utils::write.csv(result, cache_file, row.names = FALSE)
    cat("  KEGG mapping cached to:", cache_file, "\n")
  } else if (!is.null(cached_data)) {
    result <- rbind(cached_data, result)
  }

  return(result)
}


#' KEGG pathway Fisher enrichment analysis
#'
#' @description Performs Fisher's exact test for KEGG pathway over-representation
#'   among significant compounds. Unlike compound-level enrichment, this
#'   properly maps compounds to pathways first, then tests each pathway.
#'
#' @param significant_compounds Character vector of significant compound IDs
#'   (KEGG compound IDs, e.g., "C02845").
#' @param all_compounds Character vector of all compound IDs (background).
#' @param kegg_mapping Data.frame from \code{map_kegg_compound_to_pathway()}
#'   with columns: compound_id, pathway_id, pathway_name.
#' @param p_adj_method P-value adjustment method. Default: "BH".
#' @param min_size Minimum number of compounds per pathway. Default: 2.
#'
#' @return A data.frame with pathway enrichment results (pathway_name as row names).
#'
#' @examples
#' \dontrun{
#' mapping <- map_kegg_compound_to_pathway(kegg_ids)
#' enrich <- run_kegg_pathway_enrich(sig_compounds, all_compounds, mapping)
#' }
#'
#' @export
run_kegg_pathway_enrich <- function(significant_compounds, all_compounds,
                                     kegg_mapping, p_adj_method = "BH",
                                     min_size = 2) {
  if (is.null(kegg_mapping) || nrow(kegg_mapping) == 0) {
    warning("No KEGG pathway mapping provided.")
    return(data.frame())
  }

  # Filter mapping to compounds in all_compounds
  mapping <- kegg_mapping[kegg_mapping$compound_id %in% all_compounds, ]

  # Get unique compounds with pathway annotations (background)
  bg_compounds <- unique(mapping$compound_id)
  n_bg <- length(bg_compounds)

  # Significant compounds with pathway annotations
  sig_compounds <- unique(significant_compounds[significant_compounds %in% bg_compounds])
  n_sig <- length(sig_compounds)

  cat("  KEGG pathway enrichment:\n")
  cat("    Background compounds (with pathway):", n_bg, "\n")
  cat("    Significant compounds (with pathway):", n_sig, "\n")

  if (n_sig == 0 || n_bg == 0) {
    warning("No compounds with KEGG pathway annotations found.")
    return(data.frame())
  }

  # Get pathway list
  pathways <- unique(mapping$pathway_id)

  results <- data.frame(
    pathway_id = character(),
    pathway_name = character(),
    sig_count = integer(),
    sig_total = integer(),
    bg_count = integer(),
    bg_total = integer(),
    p_value = numeric(),
    fold_enrichment = numeric(),
    stringsAsFactors = FALSE
  )

  for (pw in pathways) {
    pw_compounds <- unique(mapping$compound_id[mapping$pathway_id == pw])

    if (length(pw_compounds) < min_size) next

    cat_bg <- length(pw_compounds)
    cat_sig <- sum(sig_compounds %in% pw_compounds)
    not_cat_bg <- n_bg - cat_bg
    not_cat_sig <- n_sig - cat_sig

    # Fisher's exact test (one-sided, greater)
    contingency <- matrix(c(cat_sig, not_cat_sig, cat_bg, not_cat_bg), nrow = 2)
    ft <- stats::fisher.test(contingency, alternative = "greater")

    # Fold enrichment
    expected <- (cat_sig + cat_bg) * n_sig / (n_sig + n_bg)
    fold <- if (expected > 0) cat_sig / expected else 0

    pw_name <- mapping$pathway_name[mapping$pathway_id == pw][1]

    results <- rbind(results, data.frame(
      pathway_id = pw,
      pathway_name = pw_name,
      sig_count = cat_sig,
      sig_total = n_sig,
      bg_count = cat_bg,
      bg_total = n_bg,
      p_value = ft$p.value,
      fold_enrichment = fold,
      stringsAsFactors = FALSE
    ))
  }

  if (nrow(results) == 0) {
    warning("No pathways with sufficient compounds found.")
    return(data.frame())
  }

  # Adjust p-values
  results$p_adj <- stats::p.adjust(results$p_value, method = p_adj_method)
  results$significant <- results$p_adj < 0.05

  # Sort by p-value
  results <- results[order(results$p_value), ]

  # Set pathway_id as row names (unique), keep pathway_name as column
  rownames(results) <- make.unique(as.character(results$pathway_id))
  results$pathway_id <- NULL

  return(results)
}


#' KEGG pathway GSVA analysis
#'
#' @description Performs GSVA (Gene Set Variation Analysis) at the KEGG pathway
#'   level. Compounds are grouped by their KEGG pathway membership, and pathway-
#'   level activity scores are computed per sample. A compound can contribute
#'   to multiple pathways.
#'
#' @param expr_matrix A numeric matrix (features x samples). Row names must
#'   match compound names in \code{kegg_mapping$compound_id}.
#' @param kegg_mapping Data.frame from \code{map_kegg_compound_to_pathway()}
#'   with columns: compound_id, pathway_id, pathway_name.
#' @param method Method for score computation: "gsva", "ssgsea", "zscore", or
#'   "mean". Default: "mean" (uses mean z-score when GSVA package unavailable).
#' @param min_size Minimum pathway size. Default: 2.
#' @param max_size Maximum pathway size. Default: 500.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{gsva_matrix}: Numeric matrix (pathways x samples).
#'     \item \code{pathways}: Named list of compound vectors per pathway.
#'     \item \code{n_pathways}: Number of pathways.
#'   }
#'
#' @examples
#' \dontrun{
#' mapping <- map_kegg_compound_to_pathway(kegg_ids)
#' gsva_res <- run_kegg_pathway_gsva(expr_matrix, mapping)
#' }
#'
#' @export
run_kegg_pathway_gsva <- function(expr_matrix, kegg_mapping,
                                   feature_info = NULL, feature_id_col = "name",
                                   kegg_col = "kegg",
                                   method = "mean", min_size = 2,
                                   max_size = 500) {
  if (is.null(kegg_mapping) || nrow(kegg_mapping) == 0) {
    warning("No KEGG pathway mapping provided.")
    return(NULL)
  }

  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # If feature_info provided, map KEGG compound IDs to feature row names
  if (!is.null(feature_info)) {
    # Create mapping: KEGG ID -> feature name in expression matrix
    valid <- !is.na(feature_info[[kegg_col]]) & feature_info[[kegg_col]] != ""
    kegg_to_feature <- setNames(feature_info[[feature_id_col]][valid],
                                feature_info[[kegg_col]][valid])
    # Add feature_name column to mapping
    mapping <- kegg_mapping
    mapping$feature_name <- kegg_to_feature[mapping$compound_id]
    mapping <- mapping[!is.na(mapping$feature_name), ]

    # Match to expression matrix
    common_features <- intersect(mapping$feature_name, rownames(expr_matrix))
  } else {
    # Direct match: compound IDs are row names in expr_matrix
    mapping <- kegg_mapping
    mapping$feature_name <- mapping$compound_id
    common_features <- intersect(mapping$compound_id, rownames(expr_matrix))
  }

  if (nrow(mapping) == 0 || length(common_features) == 0) {
    warning("No matching compounds between expression matrix and KEGG mapping.")
    return(NULL)
  }

  # Group compounds by pathway
  pathways <- list()
  pathway_names <- character()

  for (pw in unique(mapping$pathway_id)) {
    pw_mapping <- mapping[mapping$pathway_id == pw, ]
    pw_features <- unique(pw_mapping$feature_name)
    pw_features <- intersect(pw_features, rownames(expr_matrix))

    if (length(pw_features) >= min_size && length(pw_features) <= max_size) {
      pw_name <- mapping$pathway_name[mapping$pathway_id == pw][1]
      if (is.na(pw_name) || pw_name == "") pw_name <- pw
      pathways[[pw_name]] <- pw_features
    }
  }

  if (length(pathways) == 0) {
    warning("No KEGG pathways with sufficient compounds found.")
    return(NULL)
  }

  cat("  KEGG pathway GSVA:", length(pathways), "pathways\n")

  # Check if GSVA package is available
  use_gsva <- requireNamespace("GSVA", quietly = TRUE) && method %in% c("gsva", "ssgsea")

  if (use_gsva) {
    # Use GSVA package
    gene_sets <- lapply(pathways, function(x) x)
    gsva_mat <- GSVA::gsva(expr_matrix, gene_sets, method = method,
                           min.sz = min_size, max.sz = max_size,
                           verbose = FALSE)
    gsva_matrix <- as.matrix(gsva_mat)
    rownames(gsva_matrix) <- names(pathways)
  } else {
    # Fallback: mean z-score per pathway
    if (!use_gsva) {
      warning("Package 'GSVA' not available. Using mean z-score per pathway.")
    }

    gsva_matrix <- matrix(NA, nrow = length(pathways), ncol = ncol(expr_matrix))
    rownames(gsva_matrix) <- names(pathways)
    colnames(gsva_matrix) <- colnames(expr_matrix)

    for (i in seq_along(pathways)) {
      pw_compounds <- pathways[[i]]
      pw_expr <- expr_matrix[pw_compounds, , drop = FALSE]

      # Z-score per compound, then mean across compounds per sample
      pw_t <- t(as.matrix(pw_expr))  # samples x compounds
      scaled_expr <- scale(pw_t)  # scale each column (compound)
      # rowMeans gives mean across compounds per sample
      gsva_matrix[i, ] <- rowMeans(scaled_expr, na.rm = TRUE)
    }
  }

  return(list(
    gsva_matrix = gsva_matrix,
    pathways = pathways,
    n_pathways = length(pathways)
  ))
}


#' KEGG pathway-level WGCNA module eigengenes
#'
#' @description Groups features by their KEGG pathway membership (via
#'   compound-to-pathway mapping) and calculates module eigengenes (first
#'   principal component) for each pathway. Returns a result compatible with
#'   \code{wgcna_module_trait()} for trait association analysis. This corrects
#'   the scientific error of treating compound IDs as module definitions.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param kegg_mapping Data.frame from \code{map_kegg_compound_to_pathway()}
#'   with columns: compound_id, pathway_id, pathway_name.
#' @param feature_info Data.frame with feature annotations. Must have a column
#'   matching \code{feature_id_col} (feature names in expression matrix) and
#'   \code{kegg_col} (KEGG compound IDs).
#' @param feature_id_col Column name for feature IDs in feature_info. Default: "name".
#' @param kegg_col Column name for KEGG compound IDs in feature_info. Default: "kegg".
#' @param min_size Minimum pathway size. Default: 2.
#' @param max_size Maximum pathway size. Default: 500.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{MEs}: Data.frame of module eigengenes (samples x pathways).
#'     \item \code{colors}: Named character vector of pathway assignment per feature.
#'     \item \code{module_sizes}: Named integer vector of pathway sizes.
#'     \item \code{modules}: Named list of feature vectors per pathway.
#'     \item \code{n_modules}: Number of pathways.
#'     \item \code{category_col}: "kegg_pathway".
#'   }
#'
#' @examples
#' \dontrun{
#' mapping <- map_kegg_compound_to_pathway(kegg_ids)
#' modules <- run_kegg_pathway_wgcna(expr_matrix, mapping, feature_info)
#' trait_assoc <- wgcna_module_trait(modules, traits)
#' }
#'
#' @export
run_kegg_pathway_wgcna <- function(expr_matrix, kegg_mapping, feature_info,
                                    feature_id_col = "name", kegg_col = "kegg",
                                    min_size = 2, max_size = 500) {
  if (is.null(kegg_mapping) || nrow(kegg_mapping) == 0) {
    warning("No KEGG pathway mapping provided.")
    return(NULL)
  }

  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # Map KEGG compound IDs to feature names in expression matrix
  valid <- !is.na(feature_info[[kegg_col]]) & feature_info[[kegg_col]] != ""
  kegg_to_feature <- setNames(feature_info[[feature_id_col]][valid],
                              feature_info[[kegg_col]][valid])

  # Build expanded mapping: feature_name -> pathway
  mapping <- kegg_mapping
  mapping$feature_name <- kegg_to_feature[mapping$compound_id]
  mapping <- mapping[!is.na(mapping$feature_name), ]
  mapping <- mapping[mapping$feature_name %in% rownames(expr_matrix), ]

  if (nrow(mapping) == 0) {
    warning("No matching features between expression matrix and KEGG mapping.")
    return(NULL)
  }

  # Group features by pathway
  modules <- list()
  for (pw in unique(mapping$pathway_id)) {
    pw_mapping <- mapping[mapping$pathway_id == pw, ]
    pw_features <- unique(pw_mapping$feature_name)
    pw_features <- intersect(pw_features, rownames(expr_matrix))

    if (length(pw_features) >= min_size && length(pw_features) <= max_size) {
      pw_name <- mapping$pathway_name[mapping$pathway_id == pw][1]
      if (is.na(pw_name) || pw_name == "") pw_name <- pw
      modules[[pw_name]] <- pw_features
    }
  }

  if (length(modules) == 0) {
    warning("No KEGG pathways with sufficient features found.")
    return(NULL)
  }

  cat("  KEGG pathway modules:", length(modules), "pathways\n")

  # Calculate module eigengenes (first PC) per pathway
  me_list <- list()
  colors <- setNames(rep("grey", nrow(expr_matrix)), rownames(expr_matrix))

  for (mod_name in names(modules)) {
    mod_features <- modules[[mod_name]]
    mod_expr <- expr_matrix[mod_features, , drop = FALSE]

    if (nrow(mod_expr) == 1) {
      me <- as.numeric(mod_expr[1, ])
    } else {
      data_t <- t(mod_expr)
      feat_var <- apply(data_t, 2, stats::var, na.rm = TRUE)
      if (any(feat_var == 0)) {
        data_t <- data_t[, feat_var > 0, drop = FALSE]
      }
      if (ncol(data_t) >= 1) {
        pca <- stats::prcomp(data_t, scale. = FALSE, center = TRUE)
        me <- pca$x[, 1]
      } else {
        me <- as.numeric(mod_expr[1, ])
      }
    }
    me_list[[mod_name]] <- me
    colors[mod_features] <- mod_name
  }

  # Combine eigengenes
  MEs <- as.data.frame(do.call(cbind, me_list))
  rownames(MEs) <- colnames(expr_matrix)

  # Module sizes
  module_sizes <- sapply(modules, length)

  return(list(
    MEs = MEs,
    colors = colors,
    module_sizes = module_sizes,
    modules = modules,
    n_modules = length(modules),
    category_col = "kegg_pathway"
  ))
}
