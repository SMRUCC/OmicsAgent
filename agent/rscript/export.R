# ==============================================================================
# OmicsFlow: Export Utilities
# ==============================================================================
# Export plots and data to PDF/PNG
# ==============================================================================

#' Export a ggplot to PDF and PNG
#'
#' @description Saves a ggplot object to both PDF and PNG files with
#'   publication-quality settings.
#'
#' @param plot A ggplot object.
#' @param output_dir Directory for output files.
#' @param filename Base filename (without extension).
#' @param width Width in inches. Default: 8.
#' @param height Height in inches. Default: 6.
#' @param dpi DPI for PNG. Default: 300.
#'
#' @return Invisible list of file paths.
#'
#' @examples
#' \dontrun{
#' export_plot(pca_plot, "results/figures", "pca_score", width = 8, height = 6)
#' }
#'
#' @export
export_plot <- function(plot, output_dir = ".", filename = "plot",
                        width = 8, height = 6, dpi = 300) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  pdf_file <- file.path(output_dir, paste0(filename, ".pdf"))
  png_file <- file.path(output_dir, paste0(filename, ".png"))

  # PDF
  grDevices::pdf(pdf_file, width = width, height = height)
  print(plot)
  grDevices::dev.off()

  # PNG
  grDevices::png(png_file, width = width * dpi, height = height * dpi,
                 res = dpi, type = "cairo")
  print(plot)
  grDevices::dev.off()

  invisible(list(pdf = pdf_file, png = png_file))
}


#' Export a heatmap (ComplexHeatmap or pheatmap) to PDF and PNG
#'
#' @param heatmap A heatmap object.
#' @param output_dir Directory for output files.
#' @param filename Base filename.
#' @param width Width in inches. Default: 10.
#' @param height Height in inches. Default: 8.
#'
#' @return Invisible list of file paths.
#'
#' @export
export_heatmap <- function(heatmap, output_dir = ".", filename = "heatmap",
                           width = 10, height = 8) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  pdf_file <- file.path(output_dir, paste0(filename, ".pdf"))
  png_file <- file.path(output_dir, paste0(filename, ".png"))

  # PDF
  grDevices::pdf(pdf_file, width = width, height = height)
  if (inherits(heatmap, "Heatmap") || inherits(heatmap, "HeatmapList")) {
    ComplexHeatmap::draw(heatmap)
  } else if (inherits(heatmap, "pheatmap")) {
    grid::grid.newpage()
    grid::grid.draw(heatmap$gtable)
  } else {
    print(heatmap)
  }
  grDevices::dev.off()

  # PNG
  grDevices::png(png_file, width = width * 300, height = height * 300,
                 res = 300, type = "cairo")
  if (inherits(heatmap, "Heatmap") || inherits(heatmap, "HeatmapList")) {
    ComplexHeatmap::draw(heatmap)
  } else if (inherits(heatmap, "pheatmap")) {
    grid::grid.newpage()
    grid::grid.draw(heatmap$gtable)
  } else {
    print(heatmap)
  }
  grDevices::dev.off()

  invisible(list(pdf = pdf_file, png = png_file))
}


#' Export data frame to CSV
#'
#' @description Exports a data frame to a CSV file. When \code{use_rownames = TRUE}
#'   (default), row names are written as the first column, which is useful for
#'   molecular-level analysis results where the feature ID serves as the row name.
#'
#' @param data Data frame to export.
#' @param output_dir Directory for output.
#' @param filename Filename (with or without .csv extension).
#' @param use_rownames Logical, whether to write row names as the first column.
#'   Default: TRUE.
#' @param id_col_name Character, name for the row names column. Default: "feature_id".
#'
#' @return Invisible path to exported file.
#'
#' @examples
#' \dontrun{
#' df <- data.frame(logFC = c(1.2, -0.8), p_value = c(0.01, 0.04))
#' rownames(df) <- c("metabolite_A", "metabolite_B")
#' export_table(df, "results", "de_results")
#' }
#'
#' @export
export_table <- function(data, output_dir = ".", filename = "table.csv",
                         use_rownames = TRUE, id_col_name = "feature_id") {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  if (!grepl("\\.csv$", filename)) filename <- paste0(filename, ".csv")
  file_path <- file.path(output_dir, filename)

  if (use_rownames && !is.null(rownames(data)) &&
      !all(rownames(data) == as.character(seq_len(nrow(data))))) {
    # Row names are meaningful (not just 1, 2, 3...), write as first column
    data <- cbind(row.names(data), data, deparse.level = 0)
    colnames(data)[1] <- id_col_name
    utils::write.csv(data, file_path, row.names = FALSE)
  } else {
    utils::write.csv(data, file_path, row.names = FALSE)
  }
  invisible(file_path)
}
