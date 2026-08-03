# ==============================================================================
# OmicsFlow: Venn Diagram
# ==============================================================================
# Visualize overlap between feature sets
# ==============================================================================

#' Plot Venn diagram
#'
#' @description Creates a Venn diagram showing overlap between up to 4 sets of
#'   features. Useful for comparing differential features across conditions.
#'
#' @param sets Named list of character vectors (feature IDs). Names will be
#'   used as set labels.
#' @param fill_colors Optional named vector of fill colors. Default: uses
#'   RColorBrewer.
#' @param font_size Numeric, font size for labels. Default: 0.8.
#'
#' @return A VennDiagram grob.
#'
#' @examples
#' \dontrun{
#' sets <- list(
#'   CD_vs_Control = c("feature1", "feature2", "feature3"),
#'   FE_vs_Control = c("feature2", "feature3", "feature4")
#' )
#' venn <- plot_venn(sets)
#' }
#'
#' @export
plot_venn <- function(sets, fill_colors = NULL, font_size = 0.8) {
  if (!requireNamespace("VennDiagram", quietly = TRUE)) {
    stop("Package 'VennDiagram' is required. Please install it.")
  }

  n_sets <- length(sets)
  if (n_sets < 2 || n_sets > 4) {
    stop("Venn diagram supports 2 to 4 sets. Got: ", n_sets)
  }

  # Default colors
  if (is.null(fill_colors)) {
    colors <- make_group_colors(names(sets), palette_name = "Set2")
    colors <- adjustcolor(colors, alpha.f = 0.5)
  } else {
    colors <- fill_colors
  }

  # Create Venn diagram
  if (n_sets == 2) {
    venn <- VennDiagram::draw.pairwise.venn(
      area1 = length(sets[[1]]),
      area2 = length(sets[[2]]),
      cross.area = length(intersect(sets[[1]], sets[[2]])),
      category = names(sets),
      fill = colors,
      cat.fontface = "bold",
      cat.cex = font_size,
      fontface = "plain",
      cex = font_size,
      ext.text = TRUE,
      ext.pos = "outside"
    )
  } else if (n_sets == 3) {
    venn <- VennDiagram::draw.triple.venn(
      area1 = length(sets[[1]]),
      area2 = length(sets[[2]]),
      area3 = length(sets[[3]]),
      n12 = length(intersect(sets[[1]], sets[[2]])),
      n23 = length(intersect(sets[[2]], sets[[3]])),
      n13 = length(intersect(sets[[1]], sets[[3]])),
      n123 = length(Reduce(intersect, sets[1:3])),
      category = names(sets),
      fill = colors,
      cat.fontface = "bold",
      cat.cex = font_size,
      cex = font_size
    )
  } else if (n_sets == 4) {
    venn <- VennDiagram::draw.quad.venn(
      area1 = length(sets[[1]]),
      area2 = length(sets[[2]]),
      area3 = length(sets[[3]]),
      area4 = length(sets[[4]]),
      n12 = length(intersect(sets[[1]], sets[[2]])),
      n13 = length(intersect(sets[[1]], sets[[3]])),
      n14 = length(intersect(sets[[1]], sets[[4]])),
      n23 = length(intersect(sets[[2]], sets[[3]])),
      n24 = length(intersect(sets[[2]], sets[[4]])),
      n34 = length(intersect(sets[[3]], sets[[4]])),
      n123 = length(Reduce(intersect, sets[1:3])),
      n124 = length(intersect(intersect(sets[[1]], sets[[2]]), sets[[4]])),
      n134 = length(intersect(intersect(sets[[1]], sets[[3]]), sets[[4]])),
      n234 = length(Reduce(intersect, sets[2:4])),
      n1234 = length(Reduce(intersect, sets[1:4])),
      category = names(sets),
      fill = colors,
      cat.fontface = "bold",
      cat.cex = font_size,
      cex = font_size
    )
  }

  return(venn)
}


#' Export Venn diagram to PDF and PNG
#'
#' @param venn A VennDiagram grob from \code{plot_venn()}.
#' @param output_dir Directory for output files.
#' @param filename Base filename (without extension).
#'
#' @return Invisible list of file paths.
#'
#' @examples
#' \dontrun{
#' export_venn(venn, output_dir = "results/figures", filename = "venn")
#' }
#'
#' @export
export_venn <- function(venn, output_dir = ".", filename = "venn") {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  pdf_file <- file.path(output_dir, paste0(filename, ".pdf"))
  png_file <- file.path(output_dir, paste0(filename, ".png"))

  grDevices::pdf(pdf_file, width = 6, height = 6)
  grid::grid.draw(venn)
  grDevices::dev.off()

  grDevices::png(png_file, width = 2400, height = 2400, res = 300,
                 type = "cairo")
  grid::grid.draw(venn)
  grDevices::dev.off()

  invisible(list(pdf = pdf_file, png = png_file))
}
