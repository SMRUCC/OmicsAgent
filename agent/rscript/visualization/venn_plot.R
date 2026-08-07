# ==============================================================================
# OmicsFlow: Venn Diagram
# ==============================================================================
# 可视化Feature集合之间的重叠
# ==============================================================================

#' 绘制韦恩图
#'
#' @description 创建韦恩图，展示最多 4 个Feature集合之间的重叠。适用于比较不同条件下
#'   的差异Feature。
#'
#' @param sets 字符向量（Feature ID）的有名列表。名称将用作集合标签。
#' @param fill_colors 可选的填充色有名向量。默认：使用 RColorBrewer。
#' @param font_size 数值，标签字号。默认：0.8。
#'
#' @return 一个 VennDiagram grob。
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
  
  # 默认颜色
  if (is.null(fill_colors)) {
    colors <- make_group_colors(names(sets), palette_name = "Set2")
    colors <- adjustcolor(colors, alpha.f = 0.5)
  } else {
    colors <- fill_colors
  }
  
  # 创建韦恩图
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


#' 将韦恩图导出为 PDF 与 PNG
#'
#' @description 将 \code{plot_venn()} 返回的 VennDiagram grob 同时
#'   保存为 PDF 和 PNG 文件。
#'
#' @param venn 来自 \code{plot_venn()} 的 VennDiagram grob。
#' @param output_dir 输出文件所在目录。
#' @param filename 基础文件名（不含扩展名）。
#'
#' @return 不可见的文件路径列表。
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
