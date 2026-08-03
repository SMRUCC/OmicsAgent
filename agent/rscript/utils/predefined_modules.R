# ==============================================================================
# OmicsFlow: Predefined Module Eigengenes
# ==============================================================================
# Calculate module eigengenes for predefined feature groups (KEGG pathways,
# super_class categories, etc.) and correlate with biological traits
# ==============================================================================

#' Calculate module eigengenes for predefined feature groups
#'
#' @description Groups features by a category column (e.g., KEGG pathway,
#'   super_class) and calculates module eigengenes (first principal component)
#'   for each group. Returns a result compatible with \code{wgcna_module_trait()}
#'   for trait association analysis.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param feature_info Data.frame with feature annotations.
#' @param feature_id_col Column name for feature IDs. Default: "name".
#' @param category_col Column name for category (e.g., "kegg", "super_class").
#' @param min_size Minimum features per module. Default: 2.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{MEs}: Module eigengenes (samples x modules).
#'     \item \code{colors}: Named vector of module assignments per feature.
#'     \item \code{module_sizes}: Table of module sizes.
#'     \item \code{modules}: List of feature IDs per module.
#'     \item \code{n_modules}: Number of modules.
#'   }
#'
#' @examples
#' \dontrun{
#' # KEGG-based modules
#' kegg_mods <- predefined_module_eigengenes(expr_mat, feat_info,
#'                                           category_col = "kegg")
#'
#' # Super class-based modules
#' sc_mods <- predefined_module_eigengenes(expr_mat, feat_info,
#'                                          category_col = "super_class")
#' }
#'
#' @export
predefined_module_eigengenes <- function(expr_matrix, feature_info,
                                          feature_id_col = "name",
                                          category_col = "kegg",
                                          min_size = 2) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }

  # Match features
  feat_ids <- intersect(rownames(expr_matrix),
                        feature_info[[feature_id_col]])
  expr_sub <- expr_matrix[feat_ids, , drop = FALSE]

  # Get category for each feature
  cat_map <- feature_info[[category_col]][match(feat_ids,
                                                  feature_info[[feature_id_col]])]

  # Remove features with NA or empty category
  valid_idx <- !is.na(cat_map) & cat_map != "" & cat_map != "NULL" &
               cat_map != "NA"
  expr_sub <- expr_sub[valid_idx, , drop = FALSE]
  cat_map <- cat_map[valid_idx]

  if (length(cat_map) == 0) {
    warning("No valid category assignments found in column: ", category_col)
    return(NULL)
  }

  # Group features by category
  modules <- split(rownames(expr_sub), as.character(cat_map))

  # Filter by minimum size
  modules <- modules[sapply(modules, length) >= min_size]

  if (length(modules) == 0) {
    warning("No modules with size >= ", min_size, " found.")
    return(NULL)
  }

  # Calculate module eigengenes (first PC) for each module
  me_list <- list()
  colors <- character(nrow(expr_sub))
  names(colors) <- rownames(expr_sub)

  for (mod_name in names(modules)) {
    mod_features <- modules[[mod_name]]
    mod_expr <- expr_sub[mod_features, , drop = FALSE]

    # Calculate eigengene (first PC via prcomp or svd)
    if (length(mod_features) == 1) {
      # Single feature: use the feature itself as eigengene
      me <- as.numeric(mod_expr[1, ])
    } else {
      # Multi-feature: use first PC
      data_t <- t(mod_expr)
      # Remove zero-variance features
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

    # Assign module colors
    colors[mod_features] <- mod_name
  }

  # Features not in any module get "grey"
  unassigned <- names(colors)[colors == ""]
  colors[unassigned] <- "grey"

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
    category_col = category_col
  ))
}
