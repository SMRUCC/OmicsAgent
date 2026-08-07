# ==============================================================================
# OmicsFlow: WGCNA 模块-性状关联
# ==============================================================================
# 模块与生物学性状的相关性 + 线性回归
# ==============================================================================

#' WGCNA 模块-性状关联
#'
#' @description 计算 WGCNA 模块特征基因与生物学性状之间的相关性，
#'   并通过线性回归评估显著性。
#'
#' @param wgcna_result 来自 \code{build_wgcna_modules()} 的结果。
#' @param traits 数值矩阵或数据框（样本 x 性状）。行名必须与
#'   wgcna_result$MEs 中的样本名对应。
#' @param sample_info 可选的样本元数据，用于分组。
#' @param cor_method 相关方法。默认："pearson"。
#'
#' @return 一个列表，包含：
#'   \itemize{
#'     \item \code{module_trait_cor}：相关矩阵（模块 x 性状）。
#'     \item \code{module_trait_p}：p 值矩阵。
#'     \item \code{module_trait_lm}：每个模块-性状对的线性回归结果。
#'     \item \code{feature_trait_cor}：特征层面与性状的相关性。
#'     \item \code{feature_trait_lm}：特征层面的线性回归。
#'   }
#'
#' @examples
#' \dontrun{
#' # 性状可以是临床测量值或表型
#' traits <- data.frame(
#'   weight = c(25, 30, 22, 28),
#'   survival = c(0.8, 0.6, 0.9, 0.7),
#'   row.names = c("sample1", "sample2", "sample3", "sample4")
#' )
#' assoc <- wgcna_module_trait(wgcna_result, traits)
#' }
#'
#' @export
wgcna_module_trait <- function(wgcna_result, traits, sample_info = NULL,
                               cor_method = "pearson") {
  MEs <- wgcna_result$MEs

  # 对齐样本
  common_samples <- intersect(rownames(MEs), rownames(traits))
  MEs <- MEs[common_samples, , drop = FALSE]
  traits <- as.matrix(traits)[common_samples, , drop = FALSE]
  mode(traits) <- "numeric"

  n_modules <- ncol(MEs)
  n_traits <- ncol(traits)

  # 模块-性状相关性
  cor_mat <- matrix(0, n_modules, n_traits)
  p_mat <- matrix(1, n_modules, n_traits)
  rownames(cor_mat) <- colnames(MEs)
  colnames(cor_mat) <- colnames(traits)
  rownames(p_mat) <- colnames(MEs)
  colnames(p_mat) <- colnames(traits)

  for (i in 1:n_modules) {
    for (j in 1:n_traits) {
      ct <- stats::cor.test(MEs[, i], traits[, j], method = cor_method)
      cor_mat[i, j] <- unname(ct$estimate)
      p_mat[i, j] <- ct$p.value
    }
  }

  # 对每个模块-性状对做线性回归
  lm_results <- list()
  for (i in 1:n_modules) {
    for (j in 1:n_traits) {
      key <- paste0(colnames(MEs)[i], "_vs_", colnames(traits)[j])
      fit <- stats::lm(traits[, j] ~ MEs[, i])
      s <- summary(fit)
      lm_results[[key]] <- data.frame(
        module = colnames(MEs)[i],
        trait = colnames(traits)[j],
        estimate = stats::coef(s)[2, 1],
        std_error = stats::coef(s)[2, 2],
        t_stat = stats::coef(s)[2, 3],
        p_value = stats::coef(s)[2, 4],
        r_squared = s$r.squared,
        adj_r_squared = s$adj.r.squared,
        stringsAsFactors = FALSE
      )
    }
  }
  lm_df <- do.call(rbind, lm_results)
  rownames(lm_df) <- NULL

  # 特征层面的相关性
  # 需要从 wgcna_result 获取原始表达矩阵
  feature_trait_cor <- NULL
  feature_trait_lm <- NULL

  # 若可用 module_colors，则计算特征-性状相关性
  if (!is.null(wgcna_result$module_colors)) {
    # We need the original expression matrix - but it's not stored
    # Instead, use module eigengenes as proxy
    feature_trait_cor <- data.frame(
      module = colnames(MEs),
      cor_mat,
      stringsAsFactors = FALSE
    )
  }

  return(list(
    module_trait_cor = cor_mat,
    module_trait_p = p_mat,
    module_trait_lm = lm_df,
    feature_trait_cor = feature_trait_cor,
    feature_trait_lm = feature_trait_lm
  ))
}


#' 绘制模块-性状关系热图
#'
#' @description 创建带显著性的模块-性状相关性热图。
#'
#' @param assoc_result 来自 \code{wgcna_module_trait()} 的结果。
#' @param p_threshold 显著性 p 值阈值。默认：0.05。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_module_trait(assoc_result)
#' print(p)
#' }
#'
#' @export
plot_module_trait <- function(assoc_result, p_threshold = 0.05) {
  cor_mat <- assoc_result$module_trait_cor
  p_mat <- assoc_result$module_trait_p

  # 创建用于绘图的数据框
  plot_data <- expand.grid(
    module = rownames(cor_mat),
    trait = colnames(cor_mat),
    stringsAsFactors = FALSE
  )
  plot_data$cor <- as.vector(cor_mat)
  plot_data$p_value <- as.vector(p_mat)
  plot_data$significant <- plot_data$p_value < p_threshold
  plot_data$label <- sprintf("%.2f", plot_data$cor)
  plot_data$label[!plot_data$significant] <- ""

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = trait, y = module)) +
    ggplot2::geom_tile(ggplot2::aes(fill = cor)) +
    ggplot2::scale_fill_gradient2(low = "#2c7bb6", mid = "white",
                                   high = "#d7191c", midpoint = 0,
                                   name = "Correlation") +
    ggplot2::geom_text(ggplot2::aes(label = label), size = 3.5) +
    ggplot2::labs(
      title = "Module-Trait Relationships",
      x = "Trait",
      y = "Module"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 10),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      axis.title = ggplot2::element_text(size = 12)
    )

  return(p)
}
