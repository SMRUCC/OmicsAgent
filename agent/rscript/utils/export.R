# ==============================================================================
# OmicsFlow: 导出工具
# ==============================================================================
# 将图形与数据导出为 PDF/PNG
# ==============================================================================

#' 将 ggplot 图形导出为 PDF 与 PNG
#'
#' @description 以发表级质量设置将 ggplot 对象同时保存为 PDF 与 PNG 文件。
#'
#' @param plot 一个 ggplot 对象。
#' @param output_dir 输出文件所在目录。
#' @param filename 基础文件名（不含扩展名）。
#' @param width 宽度（英寸）。默认：8。
#' @param height 高度（英寸）。默认：6。
#' @param dpi PNG 的 DPI。默认：300。
#'
#' @return 文件路径的不可见列表。
#'
#' @examples
#' \dontrun{
#' export_plot(pca_plot, "results/figures", "pca_score", width = 8, height = 6)
#' }
#'
#' 打开 PDF 图形设备（内部辅助）
#'
#' @description 优先使用 `cairo_pdf`，因为标准 `grDevices::pdf()` 使用单字节编码，
#'   遇到 Unicode 字符（如希腊字母 γ、中文标签）时会抛出
#'   "conversion failure ... in 'mbcsToSbcs'" 警告并丢失字符。
#'   若当前 R 未编译 cairo 支持，则回退到 `pdf()` 并显式指定 UTF-8 编码。
#'
#' @param file 输出文件路径。
#' @param width,height 尺寸（英寸）。
#'
#' @return 不可见 NULL，副作用为打开图形设备。
#'
#' @keywords internal
.open_pdf_device <- function(file, width, height) {
  if (capabilities("cairo")) {
    grDevices::cairo_pdf(file, width = width, height = height,
                         onefile = TRUE)
  } else {
    grDevices::pdf(file, width = width, height = height,
                   encoding = "UTF-8", useDingbats = FALSE)
  }
  invisible(NULL)
}


#' 打开 PNG 图形设备（内部辅助）
#'
#' @description 优先使用 cairo 后端（支持 Unicode 与抗锯齿）；不可用时回退到
#'   系统默认后端，避免在无 cairo 的环境中直接报错。
#'
#' @param file 输出文件路径。
#' @param width,height 尺寸（英寸）。
#' @param dpi 分辨率。
#'
#' @return 不可见 NULL，副作用为打开图形设备。
#'
#' @keywords internal
.open_png_device <- function(file, width, height, dpi = 300) {
  px_w <- width * dpi
  px_h <- height * dpi
  if (capabilities("cairo")) {
    grDevices::png(file, width = px_w, height = px_h, res = dpi,
                   type = "cairo")
  } else {
    grDevices::png(file, width = px_w, height = px_h, res = dpi)
  }
  invisible(NULL)
}


#' 在图形设备中安全渲染（内部辅助）
#'
#' @description 用 `on.exit` 保证无论渲染是否抛错都会调用 `dev.off()`，
#'   避免设备泄漏导致后续绘图全部写入错误的文件。
#'
#' @param open_fn 无参函数，负责打开设备。
#' @param draw_fn 无参函数，负责绘图。
#'
#' @return 不可见 NULL。
#'
#' @keywords internal
.with_device <- function(open_fn, draw_fn) {
  open_fn()
  on.exit({
    if (grDevices::dev.cur() > 1L) grDevices::dev.off()
  }, add = TRUE)
  draw_fn()
  invisible(NULL)
}


#' @export
export_plot <- function(plot, output_dir = ".", filename = "plot",
                        width = 8, height = 6, dpi = 300) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  pdf_file <- file.path(output_dir, paste0(filename, ".pdf"))
  png_file <- file.path(output_dir, paste0(filename, ".png"))

  draw_fn <- function() print(plot)

  # 保存 PDF
  .with_device(function() .open_pdf_device(pdf_file, width, height), draw_fn)

  # 保存 PNG
  .with_device(function() .open_png_device(png_file, width, height, dpi),
               draw_fn)

  invisible(list(pdf = pdf_file, png = png_file))
}


#' 将热图（ComplexHeatmap 或 pheatmap）导出为 PDF 与 PNG
#'
#' @param heatmap 一个热图对象。
#' @param output_dir 输出文件所在目录。
#' @param filename 基础文件名。
#' @param width 宽度（英寸）。默认：10。
#' @param height 高度（英寸）。默认：8。
#'
#' @return 文件路径的不可见列表。
#'
#' @export
export_heatmap <- function(heatmap, output_dir = ".", filename = "heatmap",
                           width = 10, height = 8) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  pdf_file <- file.path(output_dir, paste0(filename, ".pdf"))
  png_file <- file.path(output_dir, paste0(filename, ".png"))

  draw_fn <- function() {
    if (inherits(heatmap, "Heatmap") || inherits(heatmap, "HeatmapList")) {
      ComplexHeatmap::draw(heatmap)
    } else if (inherits(heatmap, "pheatmap")) {
      grid::grid.newpage()
      grid::grid.draw(heatmap$gtable)
    } else if (inherits(heatmap, "gtable")) {
      grid::grid.newpage()
      grid::grid.draw(heatmap)
    } else if (is.function(heatmap)) {
      # 支持 base R 副作用绘图：传入一个无参绘图函数
      heatmap()
    } else {
      print(heatmap)
    }
  }

  # 保存 PDF
  .with_device(function() .open_pdf_device(pdf_file, width, height), draw_fn)

  # 保存 PNG
  .with_device(function() .open_png_device(png_file, width, height, 300),
               draw_fn)

  invisible(list(pdf = pdf_file, png = png_file))
}


#' 将数据框导出为 CSV
#'
#' @description 将数据框导出为 CSV 文件。当 \code{use_rownames = TRUE}
#'   （默认）时，行名会作为第一列写出，这对于以Feature ID 作为行名的
#'   分子层面分析结果非常有用。
#'
#' @param data 待导出的数据框。
#' @param output_dir 输出所在目录。
#' @param filename 文件名（可带或不带 .csv 扩展名）。
#' @param use_rownames 逻辑值，是否将行名作为第一列写出。默认：TRUE。
#' @param id_col_name 字符型，行名列的列名。默认："feature_id"。
#'
#' @return 导出文件的可视（invisible）路径。
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
    # 行名有意义（不只是 1、2、3……），作为第一列写出
    data <- cbind(row.names(data), data, deparse.level = 0)
    colnames(data)[1] <- id_col_name
    utils::write.csv(data, file_path, row.names = FALSE)
  } else {
    utils::write.csv(data, file_path, row.names = FALSE)
  }
  invisible(file_path)
}
