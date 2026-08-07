# ==============================================================================
# OmicsFlow: UpSet Plot
# ==============================================================================
# Visualize intersections of multiple feature sets
# ==============================================================================

#' 绘制 UpSet 图
#'
#' @description 创建 UpSet 图以可视化多个特征集合之间的交集。可处理超过 4 个的集合，
#'   而此时韦恩图已不再适用。
#'
#' @param sets 字符向量（特征 ID）的有名列表。
#' @param n_intersections 显示的交集数量。默认：30。
#' @param order_by 字符，交集的排序方式："degree" 或 "size"。默认："size"。
#' @param fill_color 柱子填充色。默认："#4a90d9"。
#'
#' @return 来自 UpSetR 的、与 ggplot 兼容的对象。
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

  # 将集合列表转换为二值矩阵
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

  # 创建 UpSet 图
  # 注意：当数据框集合很少而元素很多时，order_by = "size" 会在 UpSetR 中崩溃
  # （Counter 选择了不存在的列）。此时回退到 "degree"。
  p <- NULL
  orders <- unique(c(order_by, "size", "degree"))
  for (ord in orders) {
    p <- tryCatch(
      UpSetR::upset(
        as.data.frame(binary_mat),
        nsets = ncol(binary_mat),
        nintersects = n_intersections,
        order.by = ord,
        sets.bar.color = fill_color,
        main.bar.color = fill_color,
        point.size = 2,
        line.size = 0.5,
        text.scale = 1.1
      ),
      error = function(e) NULL
    )
    if (!is.null(p)) break
  }
  if (is.null(p)) {
    stop("Failed to create UpSet plot with order_by = '", order_by, "'.")
  }

  return(p)
}
