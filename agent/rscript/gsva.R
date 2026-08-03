# ==============================================================================
# OmicsFlow: GSVA (Gene Set Variation Analysis)
# ==============================================================================
# Pathway-level analysis per sample
# ==============================================================================

#' Run GSVA analysis
#'
#' @description Performs Gene Set Variation Analysis (GSVA) to compute
#'   pathway-level scores per sample. Supports metabolism-related gene sets.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param feature_info Data.frame with feature annotations.
#' @param feature_id_col Column name for feature IDs. Default: "ID".
#' @param pathway_col Column name for pathway/category. Default: "kegg".
#' @param method GSVA method: "gsva", "ssgsea", "zscore", or "plage".
#'   Default: "gsva".
#' @param min_size Minimum pathway size. Default: 5.
#' @param max_size Maximum pathway size. Default: 500.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{gsva_matrix}: Numeric matrix (pathways x samples).
#'     \item \code{pathways}: List of pathway feature sets.
#'     \item \code{n_pathways}: Number of pathways.
#'   }
#'
#' @examples
#' \dontrun{
#' gsva_result <- run_gsva(expr_matrix, metabolites_info, pathway_col = "kegg")
#' print(gsva_result$gsva_matrix[1:5, 1:5])
#' }
#'
#' @export
run_gsva <- function(expr_matrix, feature_info, feature_id_col = "ID",
                     pathway_col = "kegg", method = "gsva",
                     min_size = 5, max_size = 500) {
  # Build pathway sets
  if (feature_id_col %in% colnames(feature_info)) {
    rownames(feature_info) <- feature_info[[feature_id_col]]
  }

  # Get common features
  common_features <- intersect(rownames(expr_matrix), rownames(feature_info))
  feature_info_subset <- feature_info[common_features, , drop = FALSE]

  # Build gene sets
  pathways <- split(rownames(feature_info_subset),
                    feature_info_subset[[pathway_col]])
  pathways <- pathways[names(pathways) != "" & !is.na(names(pathways))]

  # Filter by size
  pathway_sizes <- sapply(pathways, length)
  pathways <- pathways[pathway_sizes >= min_size & pathway_sizes <= max_size]

  if (length(pathways) == 0) {
    warning("No pathways meet the size criteria. Try adjusting min_size/max_size.")
    return(list(gsva_matrix = NULL, pathways = list(), n_pathways = 0))
  }

  # Run GSVA
  if (requireNamespace("GSVA", quietly = TRUE)) {
    gsva_result <- GSVA::gsva(
      as.matrix(expr_matrix),
      pathways,
      method = method,
      min.sz = min_size,
      max.sz = max_size,
      verbose = FALSE
    )
    gsva_matrix <- gsva_result
  } else {
    # Fallback: simple mean z-score per pathway
    warning("Package 'GSVA' not available. Using simple mean z-score.")
    gsva_matrix <- sapply(names(pathways), function(pw) {
      pw_features <- intersect(pathways[[pw]], rownames(expr_matrix))
      if (length(pw_features) == 0) return(rep(NA, ncol(expr_matrix)))
      sub_mat <- expr_matrix[pw_features, , drop = FALSE]
      colMeans(sub_mat, na.rm = TRUE)
    })
    gsva_matrix <- t(gsva_matrix)
  }

  return(list(
    gsva_matrix = gsva_matrix,
    pathways = pathways,
    n_pathways = length(pathways)
  ))
}


#' Plot GSVA heatmap
#'
#' @description Creates a heatmap of GSVA pathway scores.
#'
#' @param gsva_result Result from \code{run_gsva()}.
#' @param sample_info Sample metadata.
#' @param group_col Column for group labels. Default: "sample_info".
#'
#' @return A heatmap object.
#'
#' @examples
#' \dontrun{
#' gsva <- run_gsva(expr_matrix, metabolites_info)
#' hm <- plot_gsva_heatmap(gsva, sample_info)
#' }
#'
#' @export
plot_gsva_heatmap <- function(gsva_result, sample_info,
                              group_col = "sample_info") {
  gsva_matrix <- gsva_result$gsva_matrix
  if (is.null(gsva_matrix)) stop("No GSVA matrix to plot.")

  # Use the plot_heatmap function
  hm <- plot_heatmap(gsva_matrix, sample_info, feature_info = NULL,
                     group_col = group_col, scale = "row",
                     n_features = nrow(gsva_matrix))
  return(hm)
}
