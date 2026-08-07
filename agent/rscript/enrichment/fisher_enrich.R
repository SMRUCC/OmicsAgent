# ==============================================================================
# OmicsFlow: Fisher 富集检验
# ==============================================================================
# 用于过表达分析的 Fisher 精确检验
# ==============================================================================

#' Fisher 精确富集检验
#'
#' @description 使用 Fisher 精确检验评估显著Feature中各类别（如 KEGG 通路、
#'   家族、类别）相对全部测量Feature的过表达（over-representation）情况。
#'
#' @param significant_features 显著Feature ID 的字符向量。
#' @param all_features 全部Feature ID（背景集）的字符向量。
#' @param feature_info 含有Feature注释的数据框。
#' @param feature_id_col feature_info 中Feature ID 的列名。默认："ID"。
#' @param category_col 类别所在的列名（如 "kegg"、"family"、"class"）。
#' @param p_adj_method P 值校正方法。默认："BH"。
#' @param min_size 类别最小规模。默认：2。
#'
#' @return 一个数据框，包含：
#'   \itemize{
#'     \item \code{category}：类别名称。
#'     \item \code{sig_count}：显著集中的计数。
#'     \item \code{sig_total}：显著Feature总数。
#'     \item \code{bg_count}：背景集中的计数。
#'     \item \code{bg_total}：背景Feature总数。
#'     \item \code{p_value}：原始 p 值。
#'     \item \code{p_adj}：校正后的 p 值。
#'     \item \code{fold_enrichment}：富集倍数。
#'   }
#'
#' @examples
#' \dontrun{
#' # 检验 KEGG 通路富集
#' enrich <- run_fisher_enrich(
#'   significant_features = c("feature1", "feature2", "feature3"),
#'   all_features = rownames(expr_matrix),
#'   feature_info = metabolites_info,
#'   category_col = "kegg"
#' )
#' head(enrich)
#' }
#'
#' @export
run_fisher_enrich <- function(significant_features, all_features,
                              feature_info, feature_id_col = "ID",
                              category_col = "kegg",
                              p_adj_method = "BH", min_size = 2) {
  # 确保 feature_info 的行名匹配
  if (feature_id_col %in% colnames(feature_info)) {
    rownames(feature_info) <- feature_info[[feature_id_col]]
  }
  
  # 获取显著Feature与背景Feature的类别
  sig_categories <- feature_info[intersect(significant_features,
                                           rownames(feature_info)), category_col]
  bg_categories <- feature_info[intersect(all_features,
                                          rownames(feature_info)), category_col]
  
  # 移除 NA 与空字符串
  sig_categories <- sig_categories[!is.na(sig_categories) & sig_categories != ""]
  bg_categories <- bg_categories[!is.na(bg_categories) & bg_categories != ""]
  
  # 统计类别数量
  sig_counts <- table(sig_categories)
  bg_counts <- table(bg_categories)
  
  # 获取所有唯一类别
  all_categories <- unique(c(names(sig_counts), names(bg_counts)))
  
  # 为每个类别构建列联表
  n_sig <- length(sig_categories)
  n_bg <- length(bg_categories)
  
  results <- data.frame(
    category = character(),
    sig_count = integer(),
    sig_total = integer(),
    bg_count = integer(),
    bg_total = integer(),
    p_value = numeric(),
    fold_enrichment = numeric(),
    stringsAsFactors = FALSE
  )
  
  for (cat in all_categories) {
    cat_sig <- as.numeric(sig_counts[cat])
    if (is.na(cat_sig)) cat_sig <- 0
    cat_bg <- as.numeric(bg_counts[cat])
    if (is.na(cat_bg)) cat_bg <- 0
    
    # 规模过小则跳过
    if (cat_sig < min_size) next
    
    not_cat_sig <- n_sig - cat_sig
    not_cat_bg <- n_bg - cat_bg
    
    # Fisher 精确检验
    contingency <- matrix(c(cat_sig, not_cat_sig, cat_bg, not_cat_bg), nrow = 2)
    ft <- stats::fisher.test(contingency, alternative = "greater")
    
    # 富集倍数
    expected <- (cat_sig + cat_bg) * n_sig / (n_sig + n_bg)
    fold <- if (expected > 0) cat_sig / expected else 0
    
    results <- rbind(results, data.frame(
      category = cat,
      sig_count = cat_sig,
      sig_total = n_sig,
      bg_count = cat_bg,
      bg_total = n_bg,
      p_value = ft$p.value,
      fold_enrichment = fold,
      stringsAsFactors = FALSE
    ))
  }
  
  # 校正 p 值
  # 注意：results 可能为 0 行（没有任何类别的显著计数达到 min_size）。
  # 对 0 行数据框直接赋值 p.adjust(numeric(0)) 会破坏列结构，
  # 因此空结果时显式构造 numeric(0) 列并提前返回，保证列名契约稳定。
  if (nrow(results) == 0) {
    results$p_adj <- numeric(0)
    results$category <- NULL
    warning(sprintf(
      "No category reached min_size = %d in the significant set; returning empty result.",
      min_size))
    return(results)
  }
  
  results$p_adj <- stats::p.adjust(results$p_value, method = p_adj_method)
  
  # 按 p 值排序
  results <- results[order(results$p_value), ]
  rownames(results) <- make.unique(as.character(results$category))
  results$category <- NULL
  
  return(results)
}


#' 绘制富集结果
#'
#' @description 创建富集结果的条形图，展示富集倍数与显著性。
#'
#' @param enrich_result 来自 \code{run_fisher_enrich()} 的结果。
#' @param top_n 展示的前 N 个类别数量。默认：20。
#' @param p_threshold 显著性 p 值阈值。默认：0.05。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' enrich <- run_fisher_enrich(...)
#' p <- plot_enrichment(enrich, top_n = 15)
#' print(p)
#' }
#'
#' @export
plot_enrichment <- function(enrich_result, top_n = 20, p_threshold = 0.05) {
  if (is.null(enrich_result) || nrow(enrich_result) == 0) {
    # 空结果时返回一张带提示文字的占位图，避免调用方因绘图报错中断整个流程
    return(
      ggplot2::ggplot() +
        ggplot2::annotate("text", x = 0, y = 0,
                          label = "No enriched category", size = 5) +
        ggplot2::theme_void() +
        ggplot2::labs(title = "Enrichment Analysis")
    )
  }
  
  top_df <- head(enrich_result, top_n)
  top_df$category <- factor(rownames(top_df), levels = rownames(top_df))
  
  # 显式构造两水平因子并同时指定 values 与 labels 的命名向量。
  # 原实现用位置型 labels = c("Not Sig", ...)，当数据中显著性全为 TRUE 或
  # 全为 FALSE 时只有一个水平，labels 数量与水平数不匹配会直接报错。
  sig_lab_false <- "Not Sig"
  sig_lab_true <- paste0("p_adj < ", p_threshold)
  top_df$sig_flag <- factor(
    ifelse(!is.na(top_df$p_adj) & top_df$p_adj < p_threshold,
           "TRUE", "FALSE"),
    levels = c("FALSE", "TRUE")
  )
  
  p <- ggplot2::ggplot(top_df, ggplot2::aes(x = category, y = fold_enrichment,
                                            fill = sig_flag)) +
    ggplot2::geom_bar(stat = "identity") +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = c("FALSE" = "grey70", "TRUE" = "#e74c3c"),
                               name = "Significant",
                               labels = c("FALSE" = sig_lab_false,
                                          "TRUE" = sig_lab_true),
                               drop = FALSE) +
    ggplot2::labs(
      title = "Enrichment Analysis",
      x = "Category",
      y = "Fold Enrichment"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 9),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right"
    )
  
  return(p)
}
