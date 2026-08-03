# ==============================================================================
# OmicsFlow: Plot Utility Functions
# ==============================================================================
# Helper functions for creating publication-quality plots
# ==============================================================================

#' Create a default color palette for groups
#'
#' @description Generates a named color palette for sample groups.
#'
#' @param groups Character vector of group names.
#' @param palette_name Name of RColorBrewer palette. Default: "Set2".
#' @param custom_colors Optional named vector of custom colors.
#'
#' @return Named character vector of colors.
#'
#' @examples
#' groups <- c("Control", "Treatment", "QC")
#' colors <- make_group_colors(groups)
#'
#' @export
make_group_colors <- function(groups, palette_name = "Set2", custom_colors = NULL) {
  groups <- unique(groups)
  n <- length(groups)

  if (!is.null(custom_colors)) {
    colors <- custom_colors[groups]
    colors[is.na(colors)] <- grDevices::rainbow(sum(is.na(colors)))
    return(colors)
  }

  if (n <= 9) {
    pal <- RColorBrewer::brewer.pal(max(3, n), palette_name)[1:n]
  } else {
    pal <- grDevices::rainbow(n)
  }

  names(pal) <- groups
  return(pal)
}


#' Save a ggplot to PDF and PNG
#'
#' @description Saves a ggplot object to both PDF and PNG files with
#'   publication-quality settings.
#'
#' @param plot A ggplot object.
#' @param filename Output filename (without extension). Default: "plot".
#' @param output_dir Output directory. Default: ".".
#' @param width Plot width in inches. Default: 8.
#' @param height Plot height in inches. Default: 6.
#' @param dpi DPI for PNG output. Default: 300.
#'
#' @return Invisible list of file paths.
#'
#' @examples
#' \dontrun{
#' p <- ggplot(mtcars, aes(mpg, wt)) + geom_point()
#' save_plot(p, "scatter", "results/figures")
#' }
#'
#' @export
save_plot <- function(plot, filename = "plot", output_dir = ".",
                      width = 8, height = 6, dpi = 300) {
  # Create output directory if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # PDF output
  pdf_file <- file.path(output_dir, paste0(filename, ".pdf"))
  grDevices::pdf(pdf_file, width = width, height = height)
  print(plot)
  grDevices::dev.off()

  # PNG output
  png_file <- file.path(output_dir, paste0(filename, ".png"))
  ggplot2::ggsave(png_file, plot = plot, width = width, height = height,
                  dpi = dpi, units = "in")

  invisible(list(pdf = pdf_file, png = png_file))
}


#' Extract metadata for plotting from sample info
#'
#' @description Extracts specified columns from sample metadata for use in
#'   ggplot aesthetics (color, shape, size).
#'
#' @param sample_info A data.frame with sample metadata.
#' @param color_col Column name to use for color grouping. Default: "sample_info".
#' @param shape_col Column name to use for shape grouping. Default: NULL.
#' @param size_col Column name to use for size mapping. Default: NULL.
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{color_values}: Named vector of colors.
#'     \item \code{shape_values}: Named vector of shapes.
#'     \item \code{size_values}: Named vector of sizes.
#'     \item \code{meta}: Subset metadata with selected columns.
#'   }
#'
#' @examples
#' \dontrun{
#' aes_info <- extract_plot_meta(sample_info, color_col = "sample_info")
#' }
#'
#' @export
extract_plot_meta <- function(sample_info, color_col = "sample_info",
                               shape_col = NULL, size_col = NULL) {
  meta <- data.frame(row.names = rownames(sample_info))

  # Color
  if (!is.null(color_col) && color_col %in% colnames(sample_info)) {
    meta$color <- sample_info[[color_col]]
    color_values <- make_group_colors(meta$color)
  } else {
    color_values <- NULL
  }

  # Shape
  if (!is.null(shape_col) && shape_col %in% colnames(sample_info)) {
    meta$shape <- sample_info[[shape_col]]
    n_shapes <- length(unique(meta$shape))
    shape_values <- setNames(0:(n_shapes - 1) %% 25 + 1, unique(meta$shape))
    if (n_shapes > 25) warning("More than 25 shape groups. Shapes will repeat.")
  } else {
    shape_values <- NULL
  }

  # Size
  if (!is.null(size_col) && size_col %in% colnames(sample_info)) {
    meta$size <- as.numeric(sample_info[[size_col]])
    size_values <- NULL  # Continuous mapping
  } else {
    size_values <- NULL
  }

  return(list(
    color_values = color_values,
    shape_values = shape_values,
    size_values = size_values,
    meta = meta
  ))
}
