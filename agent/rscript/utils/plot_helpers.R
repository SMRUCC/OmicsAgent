# ==============================================================================
# OmicsFlow: 绘图工具函数
# ==============================================================================
# 用于生成发表级质量图形的辅助函数
# ==============================================================================

#' 为分组创建默认配色板
#'
#' @description 为样本分组生成一个命名配色板。
#'
#' @param groups 分组名称的字符向量。
#' @param palette_name RColorBrewer 调色板名称。默认："Set2"。
#' @param custom_colors 可选的自定义颜色命名向量。
#'
#' @return 命名的颜色字符向量。
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


#' 将 ggplot 保存为 PDF 与 PNG
#'
#' @description 以发表级质量设置将 ggplot 对象同时保存为 PDF 与 PNG 文件。
#'
#' @param plot 一个 ggplot 对象。
#' @param filename 输出文件名（不含扩展名）。默认："plot"。
#' @param output_dir 输出目录。默认："."。
#' @param width 图形宽度（英寸）。默认：8。
#' @param height 图形高度（英寸）。默认：6。
#' @param dpi PNG 输出的 DPI。默认：300。
#'
#' @return 文件路径的不可见列表。
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
  # 若输出目录不存在则创建
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # 统一的绘制动作：ggplot / trellis 需要 print()，base 绘图函数直接调用。
  # print() 对 ggplot 是惰性求值，真正的绘图错误（如 scale_*_manual 的
  # 水平数不匹配）在此刻才抛出，因此设备必须用 on.exit 保护。
  draw <- function() {
    if (is.function(plot)) plot() else print(plot)
  }

  # 输出 PDF
  # 原实现为 pdf() -> print() -> dev.off() 的裸序列：一旦 print() 抛错，
  # dev.off() 永不执行，设备泄漏会导致后续所有绘图被静默写进这个残留
  # PDF。改用 export.R 中已有的 .with_device()（内部 on.exit 保证配对）。
  pdf_file <- file.path(output_dir, paste0(filename, ".pdf"))
  .with_device(
    function() .open_pdf_device(pdf_file, width = width, height = height),
    draw
  )

  # 输出 PNG
  # ggsave() 仅支持 ggplot 对象，对 base 绘图函数或 grid 对象会报错，
  # 故统一走 png 设备 + 同一套 draw()。
  png_file <- file.path(output_dir, paste0(filename, ".png"))
  .with_device(
    function() .open_png_device(png_file, width = width, height = height,
                                dpi = dpi),
    draw
  )

  invisible(list(pdf = pdf_file, png = png_file))
}


#' 从样本信息中提取用于绘图的元数据
#'
#' @description 从样本元数据中提取指定列，供 ggplot 的美学映射
#'   （颜色、形状、大小）使用。
#'
#' @param sample_info 含有样本元数据的数据框。
#' @param color_col 用于颜色分组的列名。默认："sample_info"。
#' @param shape_col 用于形状分组的列名。默认：NULL。
#' @param size_col 用于大小映射的列名。默认：NULL。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{color_values}：命名的颜色向量。
#'     \item \code{shape_values}：命名的形状向量。
#'     \item \code{size_values}：命名的大小向量。
#'     \item \code{meta}：含所选列的子集元数据。
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

  # 颜色
  if (!is.null(color_col) && color_col %in% colnames(sample_info)) {
    meta$color <- sample_info[[color_col]]
    color_values <- make_group_colors(meta$color)
  } else {
    color_values <- NULL
  }

  # 形状
  if (!is.null(shape_col) && shape_col %in% colnames(sample_info)) {
    meta$shape <- sample_info[[shape_col]]
    n_shapes <- length(unique(meta$shape))
    shape_values <- setNames(0:(n_shapes - 1) %% 25 + 1, unique(meta$shape))
    if (n_shapes > 25) warning("More than 25 shape groups. Shapes will repeat.")
  } else {
    shape_values <- NULL
  }

  # 大小
  if (!is.null(size_col) && size_col %in% colnames(sample_info)) {
    meta$size <- as.numeric(sample_info[[size_col]])
    size_values <- NULL  # 连续型映射
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
