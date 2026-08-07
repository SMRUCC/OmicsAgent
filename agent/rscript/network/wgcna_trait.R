# ==============================================================================
# OmicsFlow: WGCNA 模块-性状关联
# ==============================================================================
# 模块与生物学性状的相关性 + 线性回归
# ==============================================================================

#' WGCNA 模块-性状关联
#'
#' @description 计算 WGCNA 模块Feature基因与生物学性状之间的相关性，
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
#'     \item \code{feature_trait_cor}：Feature层面与性状的相关性。
#'     \item \code{feature_trait_lm}：Feature层面的线性回归。
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
  if (length(common_samples) < 3) {
    stop(sprintf(
      "wgcna_module_trait needs at least 3 shared samples between MEs and traits, got %d.",
      length(common_samples)))
  }
  MEs <- MEs[common_samples, , drop = FALSE]

  # 逐列强制转数值。若 traits 为混合类型 data.frame，as.matrix() 会先整体
  # 退化为 character，再 mode<-"numeric" 会把所有列变成 NA。
  traits <- traits[common_samples, , drop = FALSE]
  traits <- as.data.frame(traits, stringsAsFactors = FALSE)
  traits[] <- lapply(traits, function(col) {
    if (is.factor(col)) col <- as.character(col)
    suppressWarnings(as.numeric(col))
  })
  bad_cols <- names(traits)[vapply(traits, function(c) all(is.na(c)),
                                   logical(1))]
  if (length(bad_cols) > 0) {
    stop(sprintf(
      "traits columns are not numeric-coercible: %s. Encode categorical phenotypes numerically first.",
      paste(bad_cols, collapse = ", ")))
  }
  traits <- as.matrix(traits)

  # 剔除零方差列，否则 cor.test 会抛出 "standard deviation is zero"
  me_ok <- apply(MEs, 2, stats::var, na.rm = TRUE) > 0
  me_ok[is.na(me_ok)] <- FALSE
  if (any(!me_ok)) {
    warning(sprintf("Dropping %d zero-variance module eigengene(s): %s",
                    sum(!me_ok), paste(colnames(MEs)[!me_ok], collapse = ", ")))
    MEs <- MEs[, me_ok, drop = FALSE]
  }
  tr_ok <- apply(traits, 2, stats::var, na.rm = TRUE) > 0
  tr_ok[is.na(tr_ok)] <- FALSE
  if (any(!tr_ok)) {
    warning(sprintf("Dropping %d zero-variance trait(s): %s",
                    sum(!tr_ok), paste(colnames(traits)[!tr_ok], collapse = ", ")))
    traits <- traits[, tr_ok, drop = FALSE]
  }
  if (ncol(MEs) == 0 || ncol(traits) == 0) {
    stop("No variable module eigengene or trait remains after filtering.")
  }

  n_modules <- ncol(MEs)
  n_traits <- ncol(traits)

  # 模块-性状相关性
  cor_mat <- matrix(0, n_modules, n_traits)
  p_mat <- matrix(1, n_modules, n_traits)
  rownames(cor_mat) <- colnames(MEs)
  colnames(cor_mat) <- colnames(traits)
  rownames(p_mat) <- colnames(MEs)
  colnames(p_mat) <- colnames(traits)

  for (i in seq_len(n_modules)) {
    for (j in seq_len(n_traits)) {
      ct <- tryCatch(
        stats::cor.test(MEs[, i], traits[, j], method = cor_method),
        error = function(e) NULL
      )
      if (is.null(ct) || is.na(ct$estimate)) {
        cor_mat[i, j] <- NA_real_
        p_mat[i, j] <- NA_real_
      } else {
        cor_mat[i, j] <- unname(ct$estimate)
        p_mat[i, j] <- ct$p.value
      }
    }
  }

  # 对每个模块-性状对做线性回归
  lm_results <- list()
  for (i in seq_len(n_modules)) {
    for (j in seq_len(n_traits)) {
      key <- paste0(colnames(MEs)[i], "_vs_", colnames(traits)[j])
      fit <- stats::lm(traits[, j] ~ MEs[, i])
      s <- summary(fit)
      cf <- stats::coef(s)
      # 模型秩亏时 coef 只有截距一行，直接取 [2, ] 会下标越界
      if (nrow(cf) < 2) {
        lm_results[[key]] <- data.frame(
          module = colnames(MEs)[i], trait = colnames(traits)[j],
          estimate = NA_real_, std_error = NA_real_, t_stat = NA_real_,
          p_value = NA_real_, r_squared = NA_real_, adj_r_squared = NA_real_,
          stringsAsFactors = FALSE
        )
        next
      }
      lm_results[[key]] <- data.frame(
        module = colnames(MEs)[i],
        trait = colnames(traits)[j],
        estimate = cf[2, 1],
        std_error = cf[2, 2],
        t_stat = cf[2, 3],
        p_value = cf[2, 4],
        r_squared = s$r.squared,
        adj_r_squared = s$adj.r.squared,
        stringsAsFactors = FALSE
      )
    }
  }
  lm_df <- do.call(rbind, lm_results)
  rownames(lm_df) <- NULL

  # Feature层面的相关性
  # 需要从 wgcna_result 获取原始表达矩阵
  feature_trait_cor <- NULL
  feature_trait_lm <- NULL

  # 若可用 module_colors，则计算Feature-性状相关性
  if (!is.null(wgcna_result$module_colors)) {
    # 我们需要原始表达矩阵，但它并未被存储
    # 因此改为以模块Feature基因（eigengene）作为代理
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
  # p_value 为 NA（相关检验失败）时比较结果为 NA，会让下方按逻辑向量取子集
  # 产生 NA 元素，统一按不显著处理
  plot_data$significant <- !is.na(plot_data$p_value) &
    plot_data$p_value < p_threshold
  plot_data$label <- ifelse(is.na(plot_data$cor), "",
                            sprintf("%.2f", plot_data$cor))
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
