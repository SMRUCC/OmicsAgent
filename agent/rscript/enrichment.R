# ============================================================
# Required packages
# ============================================================
library(stats)
library(ggplot2)
library(grDevices)
library(GSVA)

#' @title Fisher's Exact Enrichment Test
#'
#' @description
#' 执行Fisher精确检验（Fisher's Exact Test）做富集分析。该函数对每个
#' 类别（如KEGG通路、Pfam结构域、family分类等）检验差异feature是否
#' 显著富集。Fisher检验适用于2×2列联表，特别适用于小样本情况。
#'
#' 富集分析原理：对每个类别，构建2×2列联表：
#' \tabular{lcc}{
#'   \tab 差异feature \tab 非差异feature \cr
#'   属于该类别 \tab a \tab b \cr
#'   不属于该类别 \tab c \tab d \cr
#' }
#' 然后用Fisher检验评估差异feature是否在该类别中富集。
#'
#' @param all_features 字符向量，所有feature ID（背景集）
#' @param sig_features 字符向量，差异feature ID（前景集）
#' @param feature_anno 数据框，feature注释信息
#' @param category_col 字符串，类别列名（如"kegg"、"pfam"、"family"）
#' @param pvalue_threshold 数值，P值阈值，默认0.05
#' @param p_adjust_method 字符串，P值校正方法，默认"BH"
#'
#' @return 返回一个数据框，包含：
#' \itemize{
#'   \item Category: 类别名称
#'   \item Count_in_sig: 差异feature中属于该类别的数量
#'   \item Count_in_bg: 背景feature中属于该类别的数量
#'   \item Sig_size: 差异feature总数
#'   \item Bg_size: 背景feature总数
#'   \item pvalue: Fisher检验P值
#'   \item pvalue_adj: 校正后P值
#'   \item enriched: 是否显著富集
#' }
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' anno <- load_feature_annotation("anno.csv")
#' dea_result <- perform_limma(expr, meta, strategy = "pvalue_logFC")
#'
#' enrichment_result <- perform_fisher_enrichment(
#'   all_features = rownames(expr),
#'   sig_features = dea_result$Feature[dea_result$significant],
#'   feature_anno = anno,
#'   category_col = "kegg"
#' )
#' }
#'
#' @export
perform_fisher_enrichment <- function(all_features, sig_features,
                                       feature_anno, category_col,
                                       pvalue_threshold = 0.05,
                                       p_adjust_method = "BH") {
  if (!category_col %in% colnames(feature_anno)) {
    stop("Category column '", category_col, "' not found in feature_anno.")
  }

  # Get category mapping
  anno_subset <- feature_anno[feature_anno$ID %in% all_features,
                              c("ID", category_col), drop = FALSE]
  anno_subset[[category_col]] <- as.character(anno_subset[[category_col]])

  # Split multi-value fields (e.g., pfam separated by ";")
  categories_split <- strsplit(anno_subset[[category_col]], ";")
  names(categories_split) <- anno_subset$ID

  # Build feature -> categories mapping
  feature_to_cats <- categories_split
  feature_to_cats <- lapply(feature_to_cats, function(x) {
    x <- trimws(x)
    x <- x[x != "" & !is.na(x)]
    x
  })

  # Get all unique categories
  all_cats <- unique(unlist(feature_to_cats))
  all_cats <- all_cats[!is.na(all_cats) & all_cats != ""]

  if (length(all_cats) == 0) {
    warning("No valid categories found in column '", category_col, "'.")
    return(data.frame())
  }

  sig_features <- intersect(sig_features, names(feature_to_cats))
  n_sig <- length(sig_features)
  n_bg <- length(all_features)

  # For each category, build contingency table
  results <- lapply(all_cats, function(cat) {
    features_in_cat <- names(feature_to_cats)[sapply(feature_to_cats,
                                                      function(x) cat %in% x)]
    features_in_cat <- intersect(features_in_cat, all_features)

    a <- length(intersect(features_in_cat, sig_features))
    b <- length(features_in_cat) - a
    c <- n_sig - a
    d <- n_bg - length(features_in_cat) - c

    contingency <- matrix(c(a, b, c, d), nrow = 2)
    fisher_result <- stats::fisher.test(contingency, alternative = "greater")

    data.frame(
      Category = cat,
      Count_in_sig = a,
      Count_in_bg = length(features_in_cat),
      Sig_size = n_sig,
      Bg_size = n_bg,
      pvalue = fisher_result$p.value,
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, results)
  result$pvalue_adj <- stats::p.adjust(result$pvalue, method = p_adjust_method)
  result$enriched <- result$pvalue_adj < pvalue_threshold
  result <- result[order(result$pvalue), ]

  message("Fisher enrichment analysis completed for ", length(all_cats),
          " categories. ", sum(result$enriched), " enriched.")
  return(result)
}


#' @title Plot Enrichment Barplot
#'
#' @description
#' 绘制富集分析结果条形图，展示Top N富集类别。条形图按富集显著性
#' 排序，颜色表示P值大小，条形长度表示差异feature数量。
#'
#' @param enrichment_result 数据框，由perform_fisher_enrichment返回
#' @param top_n 整数，显示的Top类别数，默认20
#' @param output_dir 字符串，输出目录路径
#' @param width 数值，图片宽度（英寸），默认9
#' @param height 数值，图片高度（英寸），默认8
#'
#' @return 不可见地返回ggplot对象
#'
#' @examples
#' \dontrun{
#' plot_enrichment_barplot(enrichment_result, top_n = 20,
#'                         output_dir = "./figures")
#' }
#'
#' @export
plot_enrichment_barplot <- function(enrichment_result, top_n = 20,
                                     output_dir = ".", width = 9, height = 8) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  if (nrow(enrichment_result) == 0) {
    warning("No enrichment results to plot.")
    return(invisible(NULL))
  }

  plot_data <- head(enrichment_result[order(enrichment_result$pvalue), ], top_n)
  plot_data$neg_log10_p <- -log10(plot_data$pvalue_adj)
  plot_data$Category <- factor(plot_data$Category,
                                levels = plot_data$Category[order(plot_data$neg_log10_p)])

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = Category, y = Count_in_sig,
                                                fill = neg_log10_p)) +
    ggplot2::geom_bar(stat = "identity") +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_gradient(low = "lightblue", high = "darkred",
                                  name = expression(-log[10](P[adj]))) +
    ggplot2::labs(
      title = paste0("Top ", top_n, " Enriched Categories"),
      x = "Category",
      y = "Feature Count"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold"),
      axis.text.y = ggplot2::element_text(size = 9)
    )

  pdf_file <- file.path(output_dir, "Enrichment_barplot.pdf")
  png_file <- file.path(output_dir, "Enrichment_barplot.png")

  grDevices::pdf(pdf_file, width = width, height = height)
  print(p)
  grDevices::dev.off()

  grDevices::png(png_file, width = width * 300, height = height * 300, res = 300)
  print(p)
  grDevices::dev.off()

  message("Enrichment barplot saved to:\n  ", pdf_file, "\n  ", png_file)
  invisible(p)
}


#' @title Perform GSVA Analysis
#'
#' @description
#' 执行基因集变异分析（Gene Set Variation Analysis, GSVA）。GSVA是一种
#' 无监督方法，将feature级别的表达矩阵转换为基因集（或通路）级别的
#' 富集分数矩阵。该方法通过估计每个样本中每个基因集的相对富集情况，
#' 实现样本级别的通路活性比较。
#'
#' @param expr_matrix 数值矩阵，表达矩阵
#' @param gene_sets 命名列表，每个元素是一个feature ID向量，代表一个基因集
#' @param method 字符串，GSVA方法，"gsva"、"ssgsea"、"plage"或"zscore"，默认"gsva"
#' @param kcdf 字符串，核密度估计方法，"Gaussian"、"Poisson"或"none"，默认"Gaussian"
#' @param min_sz 整数，基因集最小大小，默认1
#' @param max_sz 整数，基因集最大大小，默认500
#'
#' @return 返回一个矩阵，行为基因集，列为样本，值为富集分数
#'
#' @examples
#' \dontrun{
#' # 构建基因集（基于KEGG通路）
#' gene_sets <- build_gene_sets_from_kegg(feature_anno)
#'
#' # 执行GSVA
#' gsva_scores <- perform_gsva(expr, gene_sets, method = "gsva")
#' }
#'
#' @export
perform_gsva <- function(expr_matrix, gene_sets, method = "gsva",
                         kcdf = "Gaussian", min_sz = 1, max_sz = 500) {
  if (!requireNamespace("GSVA", quietly = TRUE)) {
    stop("Package 'GSVA' is required. Please install it: ",
         "BiocManager::install('GSVA')")
  }

  # Filter gene sets by size
  gene_sets <- lapply(gene_sets, function(x) intersect(x, rownames(expr_matrix)))
  gene_sets <- gene_sets[sapply(gene_sets, length) >= min_sz &
                          sapply(gene_sets, length) <= max_sz]

  if (length(gene_sets) == 0) {
    stop("No valid gene sets after filtering by size.")
  }

  param <- GSVA::gsvaParam(exprData = expr_matrix,
                           geneSets = gene_sets,
                           kcdf = kcdf,
                           minSize = min_sz,
                           maxSize = max_sz)

  gsva_result <- GSVA::gsva(param)

  message("GSVA completed with method '", method, "'. ",
          nrow(gsva_result), " gene sets x ", ncol(gsva_result), " samples.")
  return(gsva_result)
}


#' @title Build Gene Sets from KEGG Annotation
#'
#' @description
#' 从feature注释文件的kegg列构建基因集列表。每个KEGG通路对应一个
#' feature ID向量。该函数用于GSVA和富集分析的输入准备。
#'
#' @param feature_anno 数据框，feature注释信息，必须包含ID和kegg列
#'
#' @return 返回一个命名列表，每个元素是一个feature ID向量
#'
#' @examples
#' \dontrun{
#' anno <- load_feature_annotation("anno.csv")
#' gene_sets <- build_gene_sets_from_kegg(anno)
#' }
#'
#' @export
build_gene_sets_from_kegg <- function(feature_anno) {
  if (!"kegg" %in% colnames(feature_anno)) {
    stop("feature_anno must contain 'kegg' column.")
  }

  kegg_split <- strsplit(as.character(feature_anno$kegg), ";")
  names(kegg_split) <- feature_anno$ID

  gene_sets <- list()
  for (i in seq_along(kegg_split)) {
    pathways <- trimws(kegg_split[[i]])
    pathways <- pathways[pathways != "" & !is.na(pathways)]
    for (pw in pathways) {
      if (is.null(gene_sets[[pw]])) {
        gene_sets[[pw]] <- c()
      }
      gene_sets[[pw]] <- c(gene_sets[[pw]], names(kegg_split)[i])
    }
  }

  message("Built ", length(gene_sets), " KEGG gene sets.")
  return(gene_sets)
}


#' @title Build Gene Sets from Family Annotation
#'
#' @description
#' 从feature注释文件的family列构建基因集列表。每个family类别对应一个
#' feature ID向量。该函数用于GSVA和富集分析的输入准备。
#'
#' @param feature_anno 数据框，feature注释信息，必须包含ID和family列
#'
#' @return 返回一个命名列表，每个元素是一个feature ID向量
#'
#' @examples
#' \dontrun{
#' anno <- load_feature_annotation("anno.csv")
#' family_sets <- build_gene_sets_from_family(anno)
#' }
#'
#' @export
build_gene_sets_from_family <- function(feature_anno) {
  if (!"family" %in% colnames(feature_anno)) {
    stop("feature_anno must contain 'family' column.")
  }

  families <- as.character(feature_anno$family)
  families[is.na(families)] <- "Unknown"

  gene_sets <- split(feature_anno$ID, families)

  message("Built ", length(gene_sets), " family gene sets.")
  return(gene_sets)
}
