# ==============================================================================
# OmicsFlow: UpSet Plot
# ==============================================================================
# Visualize intersections of multiple feature sets
# ==============================================================================

#' Plot UpSet diagram
#'
#' @description Creates an UpSet plot for visualizing intersections among
#'   multiple sets of features. Handles more than 4 sets where Venn diagrams
#'   become impractical.
#'
#' @param sets Named list of character vectors (feature IDs).
#' @param n_intersections Number of intersections to display. Default: 30.
#' @param order_by Character, ordering of intersections: "degree" or "size".
#'   Default: "size".
#' @param fill_color Bar fill color. Default: "#4a90d9".
#'
#' @return A ggplot-compatible object from UpSetR.
#'
#' @examples
#' \dontrun{
#' sets <- list(
#'   CD_vs_Control = c("feature1", "feature2", "feature3"),
#'   FE_vs_Control = c("feature2", "feature3", "feature4"),
#'   QC = c("feature1", "feature5")
#' )
#' p <- plot_upset(sets)
#' print(p)
#' }
#'
#' @export
plot_upset <- function(sets, n_intersections = 30, order_by = "size",
                      fill_color = "#4a90d9") {
  if (!requireNamespace("UpSetR", quietly = TRUE)) {
    stop("Package 'UpSetR' is required. Please install it.")
  }

  # Convert list of sets to binary matrix
  all_features <- unique(unlist(sets))
  binary_mat <- data.frame(
    feature_id = all_features,
    stringsAsFactors = FALSE
  )

  for (set_name in names(sets)) {
    binary_mat[[set_name]] <- as.integer(all_features %in% sets[[set_name]])
  }

  rownames(binary_mat) <- binary_mat$feature_id
  binary_mat$feature_id <- NULL

  # Create UpSet plot
  p <- UpSetR::upset(
    as.data.frame(binary_mat),
    nsets = ncol(binary_mat),
    nintersects = n_intersections,
    order.by = order_by,
    sets.bar.color = fill_color,
    main.bar.color = fill_color,
    point.size = 2,
    line.size = 0.5,
    text.scale = 1.1
  )

  return(p)
}
