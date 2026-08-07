# ==============================================================================
# OmicsFlow: WGCNA Module - Downstream Trait Association
# ==============================================================================
# Builds WGCNA co-expression modules on one omics layer, then treats the
# molecular features of a downstream omics layer as biological traits and tests
# the association between every module eigengene and every downstream feature.
# This answers "which co-expressed module of layer A tracks which molecule of
# layer B" and supports the trait-driven view of cross-omics integration.
# ==============================================================================

#' 在多组学层上构建 WGCNA 模块
#'
#' @description 对共享的 \code{build_wgcna_modules()} 的轻量封装，保证稳定的样本顺序，
#'   并保留下游性状关联所需的模块成员表。表达矩阵取自 MultiOmicsData 容器，
#'   从而保留容器继承而来的样本对齐。
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param layer 用于构建模块的组学层名称。
#' @param soft_power 数值型软阈值幂。默认：NULL（自动）。
#' @param min_module_size 最小模块大小。默认：10。
#' @param merge_cut_height 模块合并截断高度。默认：0.25。
#' @param network_type 传给 WGCNA 的网络类型。默认："signed"。
#' @param cor_fn 相关函数字符串。默认："cor"。
#'
#' @return 一个列表，含 \code{module_colors}（每特征的有名向量）、
#'   \code{MEs}（样本 x 模块）、\code{soft_power}、\code{membership}
#'   （含 feature、module_color、module_label 的数据框）以及原始层名。
#'
#' @examples
#' \dontrun{
#' wgcna <- build_wgcna_modules_layer(mo, "transcriptome")
#' }
#'
#' @export
build_wgcna_modules_layer <- function(mo, layer,
                                      soft_power = NULL,
                                      min_module_size = 10,
                                      merge_cut_height = 0.25,
                                      network_type = "signed",
                                      cor_fn = "cor") {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (!layer %in% names(mo$omics)) {
    stop(sprintf("Omics layer '%s' not found. Available: %s",
                 layer, paste(names(mo$omics), collapse = ", ")))
  }

  mat <- mo$omics[[layer]]$expression
  n_samp <- ncol(mat)
  n_feat <- nrow(mat)
  if (n_feat < min_module_size * 3) {
    stop(sprintf("Layer '%s' has only %d features; too few for WGCNA with min_module_size=%d.",
                 layer, n_feat, min_module_size))
  }
  cat(sprintf("  [WGCNA] building modules on '%s' (%d features x %d samples)\n",
              layer, n_feat, n_samp))

  wgcna <- build_wgcna_modules(
    expr_matrix = mat,
    soft_power = soft_power,
    min_module_size = min_module_size,
    merge_cut_height = merge_cut_height,
    network_type = network_type,
    cor_fn = cor_fn
  )

  membership <- data.frame(
    feature = names(wgcna$module_colors),
    module_color = unname(wgcna$module_colors),
    stringsAsFactors = FALSE
  )
  rownames(membership) <- membership$feature

  n_modules <- length(setdiff(unique(wgcna$module_colors), "grey"))
  cat(sprintf("  [WGCNA] '%s': soft power = %s, %d non-grey module(s)\n",
              layer, wgcna$soft_power, n_modules))

  list(
    module_colors = wgcna$module_colors,
    module_labels = wgcna$module_labels,
    MEs = wgcna$MEs,
    soft_power = wgcna$soft_power,
    membership = membership,
    gene_tree = wgcna$gene_tree,
    diss_TOM = wgcna$diss_TOM,
    layer = layer
  )
}


#' 将下游组学特征提取为性状矩阵
#'
#' @description 将下游组学层的表达矩阵转换为性状关联所需的 样本 x 性状 矩阵，
#'   并将样本对齐到参考样本顺序。可选地只保留特征子集（例如已显示为差异的
#'   特征，或出现在某特征签名列表中的特征）。
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param layer 下游组学层的名称。
#' @param reference_samples 要对齐到的样本 ID 字符向量。
#' @param features 可选字符向量，用于限定性状。默认：NULL（全部特征）。
#' @param log_transform 逻辑值，是否对每个性状应用 log2(x+1)。默认：FALSE。
#'
#' @return 数值矩阵（样本 x 性状），样本顺序与 \code{reference_samples} 一致。
#'
#' @examples
#' \dontrun{
#' traits <- wgcna_traits_from_layer(mo, "metabolome", reference_samples = samples)
#' }
#'
#' @export
wgcna_traits_from_layer <- function(mo, layer, reference_samples,
                                    features = NULL,
                                    log_transform = FALSE) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }
  if (!layer %in% names(mo$omics)) {
    stop(sprintf("Omics layer '%s' not found.", layer))
  }
  mat <- mo$omics[[layer]]$expression
  if (!is.null(features)) {
    keep <- intersect(features, rownames(mat))
    if (length(keep) == 0) {
      stop("None of the requested features are present in the downstream layer.")
    }
    mat <- mat[keep, , drop = FALSE]
  }
  common <- intersect(reference_samples, colnames(mat))
  if (length(common) < 3) {
    stop(sprintf("Too few shared samples between reference and layer '%s'.", layer))
  }
  traits <- t(as.matrix(mat[, common, drop = FALSE]))
  if (isTRUE(log_transform)) traits <- log2(traits + 1)

  # 确保性状为数值型，并丢弃所有零方差列。
  mode(traits) <- "numeric"
  v <- apply(traits, 2, function(x) stats::var(x, na.rm = TRUE))
  keep_col <- !is.na(v) & v > 0
  if (sum(keep_col) < ncol(traits)) {
    cat(sprintf("  [WGCNA] trait layer '%s': %d zero-variance feature(s) dropped.\n",
                layer, sum(!keep_col)))
  }
  traits <- traits[, keep_col, drop = FALSE]

  # 按参考顺序返回（行为样本）。
  traits <- traits[reference_samples[reference_samples %in% rownames(traits)], , drop = FALSE]
  return(traits)
}


#' WGCNA 模块特征基因 与 下游性状的关联分析
#'
#' @description 将模块层的每个模块特征基因与下游组学层的每个分子特征（性状）做相关，
#'   并为每对 模块-性状 额外拟合一个单变量线性模型。p 值在所有被测的
#'   模块-性状 对上进行调整，使结果可直接用于全局显著性过滤。
#'
#' @param wgcna 来自 \code{build_wgcna_modules_layer()} 的 WGCNA 结果。
#' @param traits 来自 \code{wgcna_traits_from_layer()} 的数值矩阵（样本 x 性状）。
#' @param trait_layer 下游层的名称（用于标签）。
#' @param cor_method 相关方法。默认："pearson"。
#' @param p_adjust 多重检验校正方法。默认："BH"。
#' @param verbose 逻辑值，是否打印简短摘要。默认：TRUE。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{module_trait}: 含 module、trait、r、p、padj、
#'       以及 lm 的 slope、intercept、r_squared 的数据框。
#'     \item \code{module_summary}: 每个模块的显著性状命中汇总。
#'     \item \code{trait_summary}: 每个性状的显著模块命中汇总。
#'     \item \code{used_traits}: 含性状 id 与层的数据框。
#'   }
#'
#' @examples
#' \dontrun{
#' assoc <- run_wgcna_trait_association(wgcna, traits, trait_layer = "metabolome")
#' }
#'
#' @export
run_wgcna_trait_association <- function(wgcna, traits,
                                        trait_layer,
                                        cor_method = "pearson",
                                        p_adjust = "BH",
                                        verbose = TRUE) {
  MEs <- wgcna$MEs
  common <- intersect(rownames(MEs), rownames(traits))
  if (length(common) < 4) {
    stop("Need at least 4 shared samples between module eigengenes and traits.")
  }
  MEs <- MEs[common, , drop = FALSE]
  traits <- traits[common, , drop = FALSE]

  modules <- colnames(MEs)
  trait_ids <- colnames(traits)
  modules <- modules[modules != "MEgrey"]  # unassigned genes are not a module

  if (length(modules) == 0) {
    stop("No non-grey module is available for trait association.")
  }

  rows <- list()
  for (mod in modules) {
    x <- as.numeric(MEs[, mod])
    if (stats::var(x, na.rm = TRUE) == 0) next
    for (tr in trait_ids) {
      y <- as.numeric(traits[, tr])
      if (stats::var(y, na.rm = TRUE) == 0) next
      ct <- tryCatch(stats::cor.test(x, y, method = cor_method),
                     error = function(e) NULL)
      if (is.null(ct)) next
      fit <- tryCatch(stats::lm(y ~ x), error = function(e) NULL)
      if (is.null(fit)) next
      s <- summary(fit)
      co <- stats::coef(s)
      rows[[length(rows) + 1L]] <- data.frame(
        module = mod,
        trait = tr,
        r = unname(ct$estimate),
        p = ct$p.value,
        lm_slope = unname(co[2, 1]),
        lm_se = unname(co[2, 2]),
        lm_t = unname(co[2, 3]),
        lm_p = unname(co[2, 4]),
        lm_r_squared = unname(s$r.squared),
        n_samples = length(common),
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) {
    return(list(module_trait = data.frame(),
                module_summary = data.frame(),
                trait_summary = data.frame(),
                used_traits = data.frame(trait = trait_ids, layer = trait_layer)))
  }
  out <- do.call(rbind, rows)
  out$padj <- stats::p.adjust(out$p, method = p_adjust)
  out$significant <- out$padj < 0.05
  out <- out[order(out$padj, -abs(out$r)), , drop = FALSE]
  rownames(out) <- NULL

  module_summary <- do.call(rbind, lapply(split(out, out$module), function(sub) {
    data.frame(
      module = sub$module[1],
      n_traits_tested = nrow(sub),
      n_significant = sum(sub$significant),
      mean_abs_r = mean(abs(sub$r)),
      best_trait = sub$trait[1],
      best_r = sub$r[1],
      best_padj = sub$padj[1],
      stringsAsFactors = FALSE
    )
  }))
  module_summary <- module_summary[order(-module_summary$n_significant,
                                         -module_summary$mean_abs_r), , drop = FALSE]
  rownames(module_summary) <- NULL

  trait_summary <- do.call(rbind, lapply(split(out, out$trait), function(sub) {
    data.frame(
      trait = sub$trait[1],
      n_modules_tested = nrow(sub),
      n_significant = sum(sub$significant),
      best_module = sub$module[1],
      best_r = sub$r[1],
      best_padj = sub$padj[1],
      stringsAsFactors = FALSE
    )
  }))
  trait_summary <- trait_summary[order(-trait_summary$n_significant,
                                       -abs(trait_summary$best_r)), , drop = FALSE]
  rownames(trait_summary) <- NULL

  if (verbose) {
    cat(sprintf("  [WGCNA] %d module-trait pairs tested, %d significant (padj<0.05)\n",
                nrow(out), sum(out$significant)))
  }

  list(
    module_trait = out,
    module_summary = module_summary,
    trait_summary = trait_summary,
    used_traits = data.frame(trait = trait_ids, layer = trait_layer)
  )
}


#' 将模块成员映射回特征名称
#'
#' @description 将可读的特征标识符（来自特征注释）附加到模块-性状结果上，
#'   使显著对能够以生物学含义解读，而非依赖内部特征 id。
#'
#' @param assoc \code{run_wgcna_trait_association()} 的结果。
#' @param module_feature_info 模块层的特征注释。
#' @param module_layer 模块层的名称。
#' @param trait_feature_info 性状层的特征注释。
#' @param trait_layer 性状层的名称。
#'
#' @return 与 \code{assoc$module_trait} 相同的数据框，另加 module 与 trait 的
#'   显示名称列。
#'
#' @export
annotate_wgcna_trait_result <- function(assoc, module_feature_info = NULL,
                                        module_layer = "module",
                                        trait_feature_info = NULL,
                                        trait_layer = "trait") {
  res <- assoc$module_trait
  if (is.null(res) || nrow(res) == 0) return(res)
  res$module_layer <- module_layer
  res$trait_layer <- trait_layer
  res$module_name <- res$module
  if (!is.null(trait_feature_info) && nrow(trait_feature_info) > 0 &&
      "name" %in% colnames(trait_feature_info)) {
    name_map <- stats::setNames(as.character(trait_feature_info$name),
                                rownames(trait_feature_info))
    res$trait_name <- unname(name_map[res$trait])
    res$trait_name[is.na(res$trait_name)] <- res$trait[is.na(res$trait_name)]
  } else {
    res$trait_name <- res$trait
  }
  return(res)
}


#' 模块-性状相关矩阵的热力图
#'
#' @description 以瓦片热力图展示模块特征基因与下游性状的相关，并标注显著性星号。
#'   当性状数量很大时，仅显示按显著性排序的 top 性状，其余在返回值中汇总。
#'
#' @param assoc \code{run_wgcna_trait_association()} 的结果。
#' @param top_n_traits 显示的最大性状数。默认：40。
#' @param title 可选图标题。
#'
#' @return 一个 ggplot 对象（当性状数超过 \code{top_n_traits} 时，完整矩阵的数据
#'   会以列表形式（invisibly）一并返回）。
#'
#' @examples
#' \dontrun{
#' p <- plot_wgcna_trait_heatmap(assoc, top_n_traits = 30)
#' }
#'
#' @export
plot_wgcna_trait_heatmap <- function(assoc, top_n_traits = 40, title = NULL) {
  res <- assoc$module_trait
  if (is.null(res) || nrow(res) == 0) {
    stop("No module-trait pairs to plot.")
  }
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' is required.")
  }

  # 按最小校正 p 值选取 top 性状。
  trait_rank <- aggregate(padj ~ trait, res, FUN = min)
  trait_rank <- trait_rank[order(trait_rank$padj), , drop = FALSE]
  top_traits <- head(trait_rank$trait, top_n_traits)
  sub <- res[res$trait %in% top_traits, , drop = FALSE]

  sub$module <- factor(sub$module, levels = rev(sort(unique(sub$module))))
  sub$trait <- factor(sub$trait, levels = rev(unique(sub$trait)))
  sub$star <- ifelse(sub$padj < 0.001, "***",
                     ifelse(sub$padj < 0.01, "**",
                            ifelse(sub$padj < 0.05, "*", "")))

  p <- ggplot2::ggplot(sub, ggplot2::aes(x = trait, y = module, fill = r)) +
    ggplot2::geom_tile(color = "grey90") +
    ggplot2::geom_text(ggplot2::aes(label = star), size = 2.6, nudge_y = 0.22) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", r)), size = 2.4,
                       nudge_y = -0.22) +
    ggplot2::scale_fill_gradient2(low = "#2c7bb6", mid = "white",
                                  high = "#d7191c", midpoint = 0,
                                  name = "Correlation") +
    ggplot2::labs(
      title = if (is.null(title)) "Module eigengene vs downstream trait" else title,
      x = "Downstream trait", y = "WGCNA module") +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold", hjust = 0.5),
      axis.text.x = ggplot2::element_text(angle = 90, hjust = 1, vjust = 0.5,
                                          size = 7),
      axis.text.y = ggplot2::element_text(size = 9)
    )
  return(p)
}
