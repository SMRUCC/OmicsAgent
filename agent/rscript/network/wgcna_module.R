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

  if (ncol(datExpr) < 3) {
    stop(sprintf(
      "build_wgcna_modules needs at least 3 non-constant features, got %d.",
      ncol(datExpr)))
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
    # 不显式传 cutHeight：原实现固定为 2，而 diss_TOM 取值域为 [0,1]，
    # 该值远超树高上限，等价于"永不剪枝"，会让 deepSplit 失效并倾向于
    # 把绝大多数特征塞进单一模块。交由 cutreeDynamic 依据树高自适应确定。
    modules <- cutree_fn(
      dendro = gene_tree,
      distM = diss_TOM,
      minClusterSize = min_module_size,
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

  # module_labels 应为数值标签而非颜色字符串（原实现与 module_colors 完全重复）
  module_labels_merged <- WGCNA::matchLabels(
    as.numeric(as.factor(module_colors_merged)) - 1L,
    modules
  )
  module_labels_merged <- as.vector(module_labels_merged)
  names(module_labels_merged) <- colnames(datExpr)

  return(list(
    module_colors = module_colors_merged,
    module_labels = module_labels_merged,
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
#' @details 本函数使用 base R 图形（副作用绘图），会直接绘制到**当前**图形设备上。
#'   因此它返回的是一个无参绘图函数（closure），而非 ggplot 对象，
#'   可直接传给 \code{export_heatmap()} 完成落盘：
#'   \code{export_heatmap(plot_wgcna_dendrogram(res), dir, "dendro")}。
#'
#'   历史实现曾调用 \code{grDevices::pdf(NULL)} 试图"抑制设备"，但该调用
#'   既未配对 \code{dev.off()}（造成设备泄漏），又会把图形画进这个空设备里，
#'   导致调用方打开的设备始终得到空白页。此处不再自行打开任何设备。
#'
#' @return 一个无参函数，调用时在当前图形设备上绘制树状图。
#'
#' @examples
#' \dontrun{
#' draw <- plot_wgcna_dendrogram(wgcna_result)
#' export_heatmap(draw, "figures", "wgcna_dendrogram")
#' }
#'
#' @export
plot_wgcna_dendrogram <- function(wgcna_result) {
  if (!requireNamespace("WGCNA", quietly = TRUE)) {
    stop("Package 'WGCNA' is required.")
  }
  gene_tree <- wgcna_result$gene_tree
  module_colors <- wgcna_result$module_colors
  if (is.null(gene_tree)) {
    stop("wgcna_result$gene_tree is NULL; cannot plot dendrogram.")
  }

  function() {
    old_par <- graphics::par(no.readonly = TRUE)
    on.exit(graphics::par(old_par), add = TRUE)

    WGCNA::plotDendroAndColors(
      dendro = gene_tree,
      colors = module_colors,
      groupLabels = "Module",
      main = "WGCNA Module Dendrogram",
      dendroLabels = FALSE,
      hang = 0.03,
      addGuide = TRUE,
      guideHang = 0.05
    )
    invisible(NULL)
  }
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
  # 零方差列会使相关系数为 NaN，须与 build_wgcna_modules 保持一致地剔除
  keep <- apply(datExpr, 2, stats::var, na.rm = TRUE) > 0
  keep[is.na(keep)] <- FALSE
  datExpr <- datExpr[, keep, drop = FALSE]

  sft <- WGCNA::pickSoftThreshold(datExpr, powerVector = powers,
                                   networkType = network_type, verbose = 0)

  # 无标度拓扑拟合
  # 标准 WGCNA 指标为 -sign(slope) * SFT.R.sq：用回归斜率的符号来区分
  # "真正的无标度拓扑"（slope 为负）与伪拟合。原实现误用 -sign(SFT.R.sq)，
  # 由于 R^2 恒非负，结果恒为负值，曲线与 0.85 参考线完全失去意义。
  fi <- sft$fitIndices
  fit_data <- data.frame(
    power = fi$Power,
    fit = -sign(fi$slope) * fi$SFT.R.sq,
    mean_k = fi$mean.k.
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
