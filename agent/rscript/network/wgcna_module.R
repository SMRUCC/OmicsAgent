# ==============================================================================
# OmicsFlow: WGCNA 共表达模块构建
# ==============================================================================
# 加权基因共表达网络分析（Weighted Gene Co-expression Network Analysis）—— 模块构建
# ==============================================================================

#' 构建 WGCNA 共表达模块
#'
#' @description 使用 WGCNA 包构建加权基因共表达网络，并识别共表达Feature的模块。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param soft_power 数值型，软阈值幂。若为 NULL 则自动选择。默认：NULL。
#' @param min_module_size 最小模块规模。默认：10。
#' @param merge_cut_height 模块合并的高度阈值。默认：0.25。
#' @param network_type 网络类型："unsigned"、"signed" 或 "signed hybrid"。
#'   默认："signed"。
#' @param cor_fn 相关函数："pearson" 或 "bicor"。默认："bicor"。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{module_colors}：每个Feature的模块颜色命名向量。
#'     \item \code{module_labels}：模块标签命名向量。
#'     \item \code{MEs}：模块Feature基因（样本 x 模块）。
#'     \item \code{soft_power}：所选的软阈值幂。
#'     \item \code{gene_tree}：层次聚类树。
#'     \item \code{diss_TOM}：相异度矩阵（可选，若包含 TOM）。
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

  # 启用 WGCNA 多线程
  WGCNA::enableWGCNAThreads()

  # 转置：WGCNA 要求样本在行
  datExpr <- t(as.matrix(expr_matrix))
  datExpr <- datExpr[, apply(datExpr, 2, stats::var, na.rm = TRUE) > 0]

  # 选择软阈值幂
  cor_fn_name <- cor_fn  # 以字符串形式保存
  if (is.null(soft_power)) {
    powers <- 1:20
    sft <- WGCNA::pickSoftThreshold(datExpr, powerVector = powers,
                                     networkType = network_type,
                                     corFnc = cor_fn_name, verbose = 0)
    soft_power <- sft$power
    # 当没有任何被试幂达到无标度拓扑拟合标准时，pickSoftThreshold 返回 NA；
    # 此时回退到固定的默认值。
    if (is.null(soft_power) || is.na(soft_power) || soft_power == 0) soft_power <- 6
  }

  # 计算邻接矩阵
  adjacency <- WGCNA::adjacency(datExpr, power = soft_power,
                                type = network_type, corFnc = cor_fn_name)

  # 计算 TOM（拓扑重叠矩阵）
  TOM <- WGCNA::TOMsimilarity(adjacency, TOMType = network_type)
  diss_TOM <- 1 - TOM

  # 层次聚类
  gene_tree <- stats::hclust(stats::as.dist(diss_TOM), method = "average")

  # 识别模块
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

  # 转换为颜色
  module_colors <- WGCNA::labels2colors(modules)
  names(module_colors) <- colnames(datExpr)

  # 计算模块Feature基因
  MEs <- WGCNA::moduleEigengenes(datExpr, module_colors)$eigengenes
  rownames(MEs) <- rownames(datExpr)

  # 合并相近的模块
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


#' 绘制 WGCNA 模块树状图
#'
#' @description 创建按模块分配着色的Feature树状图。
#'
#' @param wgcna_result 来自 \code{build_wgcna_modules()} 的结果。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_wgcna_dendrogram(wgcna_result)
#' print(p)
#' }
#'
#' @export
plot_wgcna_dendrogram <- function(wgcna_result) {
  # 使用基础 R 绘图函数绘制树状图
  grDevices::pdf(NULL)  # 抑制图形设备

  old_par <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old_par))

  graphics::plot(wgcna_result$gene_tree, xlab = "", sub = "",
                 main = "WGCNA Module Dendrogram",
                 labels = FALSE)
  WGCNA::plotColorUnderDendro(wgcna_result$gene_tree,
                               wgcna_result$module_colors)

  invisible(NULL)
}


#' 绘制软阈值幂选择图
#'
#' @description 绘制无标度拓扑拟合与平均连通性随幂变化的曲线。
#'
#' @param expr_matrix 数值矩阵（Feature x 样本）。
#' @param powers 幂的范围。默认：1:20。
#' @param network_type 网络类型。默认："signed"。
#'
#' @return 一个 ggplot 对象。
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

  # 无标度拓扑拟合
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
