# ==============================================================================
# OmicsFlow: WGCNA Co-expression Module Construction
# ==============================================================================
# Weighted Gene Co-expression Network Analysis - module building
# ==============================================================================

#' Build WGCNA co-expression modules
#'
#' @description Constructs a weighted gene co-expression network and identifies
#'   modules of co-expressed features using the WGCNA package.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param soft_power Numeric, soft-thresholding power. If NULL, automatically
#'   selected. Default: NULL.
#' @param min_module_size Minimum module size. Default: 10.
#' @param merge_cut_height Height cut for module merging. Default: 0.25.
#' @param network_type Network type: "unsigned", "signed", or "signed hybrid".
#'   Default: "signed".
#' @param cor_fn Correlation function: "pearson" or "bicor". Default: "bicor".
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{module_colors}: Named vector of module colors per feature.
#'     \item \code{module_labels}: Named vector of module labels.
#'     \item \code{MEs}: Module eigengenes (samples x modules).
#'     \item \code{soft_power}: Selected soft-thresholding power.
#'     \item \code{gene_tree}: Hierarchical clustering tree.
#'     \item \code{diss_TOM}: Dissimilarity matrix (optional, if TOM included).
#'   }
#'
#' @examples
#' \dontrun{
#' wgcna <- build_wgcna_modules(expr_matrix, min_module_size = 10)
#' print(table(wgcna$module_colors))
#' }
#'
#' @export
build_wgcna_modules <- function(expr_matrix, soft_power = NULL,
                                min_module_size = 10, merge_cut_height = 0.25,
                                network_type = "signed",
                                cor_fn = "cor") {
  if (!requireNamespace("WGCNA", quietly = TRUE)) {
    stop("Package 'WGCNA' is required. Please install it.")
  }

  # Enable WGCNA threads
  WGCNA::enableWGCNAThreads()

  # Transpose: WGCNA expects samples in rows
  datExpr <- t(as.matrix(expr_matrix))
  datExpr <- datExpr[, apply(datExpr, 2, stats::var, na.rm = TRUE) > 0]

  # Select soft-thresholding power
  cor_fn_name <- cor_fn  # Store as string
  if (is.null(soft_power)) {
    powers <- 1:20
    sft <- WGCNA::pickSoftThreshold(datExpr, powerVector = powers,
                                     networkType = network_type,
                                     corFnc = cor_fn_name, verbose = 0)
    soft_power <- sft$power
    # pickSoftThreshold returns NA when no tested power reaches the scale-free
    # topology fit criterion; fall back to a fixed default in that case.
    if (is.null(soft_power) || is.na(soft_power) || soft_power == 0) soft_power <- 6
  }

  # Calculate adjacency
  adjacency <- WGCNA::adjacency(datExpr, power = soft_power,
                                type = network_type, corFnc = cor_fn_name)

  # Calculate TOM
  TOM <- WGCNA::TOMsimilarity(adjacency, TOMType = network_type)
  diss_TOM <- 1 - TOM

  # Hierarchical clustering
  gene_tree <- stats::hclust(stats::as.dist(diss_TOM), method = "average")

  # Identify modules
    cutree_fn <- if (requireNamespace("dynamicTreeCut", quietly = TRUE)) {
      dynamicTreeCut::cutreeDynamic
    } else {
      WGCNA::cutreeDynamic
    }
    modules <- cutree_fn(
      dendro = gene_tree,
      distM = diss_TOM,
      minClusterSize = min_module_size,
      cutHeight = 2,
      deepSplit = 2,
      pamRespectsDendro = FALSE
    )

  # Convert to colors
  module_colors <- WGCNA::labels2colors(modules)
  names(module_colors) <- colnames(datExpr)

  # Calculate module eigengenes
  MEs <- WGCNA::moduleEigengenes(datExpr, module_colors)$eigengenes
  rownames(MEs) <- rownames(datExpr)

  # Merge close modules
  merge_result <- WGCNA::mergeCloseModules(datExpr, module_colors,
                                           cutHeight = merge_cut_height)
  module_colors_merged <- merge_result$colors
  names(module_colors_merged) <- colnames(datExpr)
  MEs_merged <- merge_result$newMEs
  rownames(MEs_merged) <- rownames(datExpr)

  return(list(
    module_colors = module_colors_merged,
    module_labels = merge_result$colors,
    MEs = MEs_merged,
    soft_power = soft_power,
    gene_tree = gene_tree,
    diss_TOM = diss_TOM
  ))
}


#' Plot WGCNA module dendrogram
#'
#' @description Creates a dendrogram of features colored by module assignment.
#'
#' @param wgcna_result Result from \code{build_wgcna_modules()}.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' p <- plot_wgcna_dendrogram(wgcna_result)
#' print(p)
#' }
#'
#' @export
plot_wgcna_dendrogram <- function(wgcna_result) {
  # Use base R plot for dendrogram
  grDevices::pdf(NULL)  # Suppress device

  old_par <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old_par))

  graphics::plot(wgcna_result$gene_tree, xlab = "", sub = "",
                 main = "WGCNA Module Dendrogram",
                 labels = FALSE)
  WGCNA::plotColorUnderDendro(wgcna_result$gene_tree,
                               wgcna_result$module_colors)

  invisible(NULL)
}


#' Plot soft-thresholding power selection
#'
#' @description Plots scale-free topology fit and mean connectivity vs power.
#'
#' @param expr_matrix A numeric matrix (features x samples).
#' @param powers Power range. Default: 1:20.
#' @param network_type Network type. Default: "signed".
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' p <- plot_soft_threshold(expr_matrix)
#' print(p)
#' }
#'
#' @export
plot_soft_threshold <- function(expr_matrix, powers = 1:20,
                                 network_type = "signed") {
  if (!requireNamespace("WGCNA", quietly = TRUE)) {
    stop("Package 'WGCNA' is required.")
  }

  datExpr <- t(as.matrix(expr_matrix))
  sft <- WGCNA::pickSoftThreshold(datExpr, powerVector = powers,
                                   networkType = network_type, verbose = 0)

  # Scale-free topology fit
  fit_data <- data.frame(
    power = powers,
    fit = -sign(sft$fitIndices$SFT.R.sq) * sft$fitIndices$SFT.R.sq,
    mean_k = sft$fitIndices$mean.k.
  )

  p1 <- ggplot2::ggplot(fit_data, ggplot2::aes(x = power, y = fit)) +
    ggplot2::geom_line(color = "#4a90d9", linewidth = 0.8) +
    ggplot2::geom_point(size = 2) +
    ggplot2::geom_hline(yintercept = 0.85, color = "#e74c3c",
                        linetype = "dashed") +
    ggplot2::labs(title = "Scale-Independent Topology",
                  x = "Soft Power", y = expression(R^2)) +
    ggplot2::theme_bw() +
    ggplot2::theme(plot.title = ggplot2::element_text(size = 12, face = "bold"))

  return(p1)
}
