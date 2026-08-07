# ==============================================================================
# OmicsFlow: GO Enrichment Analysis for Proteome
# ==============================================================================
# Gene Ontology (GO) 术语富集分析，包含三个本体：
#   Biological Process (BP), Molecular Function (MF), Cellular Component (CC)
# 基于 Fisher's exact test 的超代表检验
# ==============================================================================

#' GO 富集分析
#'
#' @description 执行 Gene Ontology (GO) 术语富集分析，支持 BP、MF、CC 三个本体。
#'   Based on Fisher's exact test 检验显著差异蛋白质是否在特定 GO 术语中过度代表。
#'
#' @param significant_proteins 显著差异蛋白质 ID 向量。
#' @param all_proteins 所有蛋白质 ID 向量（背景集）。
#' @param feature_info Feature注释 data.frame，需包含 GO 术语注释列。
#' @param id_col Feature注释中 ID 列名。默认 "ID"。
#' @param go_col GO 术语列名。默认 "go_terms"。
#' @param ontologies 需要分析的 GO 本体类型。默认 c("BP", "MF", "CC")。
#' @param p_adjust 多重检验校正方法。默认 "BH"。
#' @param p_threshold p 值阈值。默认 0.05。
#' @param min_genes GO 术语中最少显著基因数。默认 2。
#'
#' @return 列表：
#'   \itemize{
#'     \item \code{BP}: Biological Process 富集结果。
#'     \item \code{MF}: Molecular Function 富集结果。
#'     \item \code{CC}: Cellular Component 富集结果。
#'     \item \code{combined}: 合并的结果数据框。
#'   }
#'
#' @examples
#' \dontrun{
#' res <- run_go_enrichment(sig_proteins, all_proteins, feature_info)
#' }
#'
#' @export
run_go_enrichment <- function(significant_proteins, all_proteins,
                              feature_info, id_col = "ID",
                              go_col = "go_terms",
                              ontologies = c("BP", "MF", "CC"),
                              p_adjust = "BH",
                              p_threshold = 0.05,
                              min_genes = 2) {
  # 检查 GO 术语注释列
  if (!go_col %in% colnames(feature_info)) {
    stop(sprintf("GO term column '%s' not found in feature_info.", go_col))
  }

  # 筛选有 GO 注释的蛋白
  go_annot <- feature_info[!is.na(feature_info[[go_col]]) &
                            feature_info[[go_col]] != "", , drop = FALSE]

  # 构建 GO 术语到基因的映射
  # GO 术语格式假设为 "BP:0000001;MF:0000002;CC:0000003" 或类似
  go_terms_all <- unlist(strsplit(as.character(go_annot[[go_col]]), ";"))
  go_terms_all <- trimws(go_terms_all)
  go_terms_all <- unique(go_terms_all)

  if (length(go_terms_all) == 0) {
    stop("No GO term annotations found.")
  }

  # 判断 GO 术语格式：是否包含本体前缀
  has_ontology_prefix <- any(grepl("^(BP|MF|CC):", go_terms_all))

  # 解析每个蛋白的 GO 术语
  protein_to_go <- list()
  for (i in seq_len(nrow(go_annot))) {
    pid <- go_annot[i, id_col]
    terms <- unlist(strsplit(as.character(go_annot[i, go_col]), ";"))
    terms <- trimws(terms)
    terms <- terms[terms != ""]

    if (has_ontology_prefix) {
      # 解析本体
      for (term in terms) {
        parts <- strsplit(term, ":")[[1]]
        if (length(parts) >= 2) {
          ont <- parts[1]
          term_id <- paste(parts[-1], collapse = ":")
          if (ont %in% ontologies) {
            key <- paste(ont, term_id, sep = ":")
            protein_to_go[[key]] <- c(protein_to_go[[key]], pid)
          }
        }
      }
    } else {
      # 无本体前缀，分配到所有选中本体
      for (term in terms) {
        for (ont in ontologies) {
          key <- paste(ont, term, sep = ":")
          protein_to_go[[key]] <- c(protein_to_go[[key]], pid)
        }
      }
    }
  }

  # 执行 Fisher's exact test
  results_list <- list()

  for (ont in ontologies) {
    ont_terms <- names(protein_to_go)[grep(paste0("^", ont, ":"), names(protein_to_go))]

    results <- data.frame(
      ontology = character(),
      go_id = character(),
      n_significant = integer(),
      n_background = integer(),
      expected = numeric(),
      fold_enrichment = numeric(),
      p_value = numeric(),
      p_adj = numeric(),
      genes = character(),
      stringsAsFactors = FALSE
    )

    for (term in ont_terms) {
      term_proteins <- protein_to_go[[term]]
      n_sig_in_term <- length(intersect(significant_proteins, term_proteins))
      n_bg_in_term <- length(intersect(all_proteins, term_proteins))

      if (n_sig_in_term < min_genes) next

      n_sig_total <- length(significant_proteins)
      n_bg_total <- length(all_proteins)

      # Fisher's exact test
      m <- matrix(c(
        n_sig_in_term, n_sig_total - n_sig_in_term,
        n_bg_in_term - n_sig_in_term, n_bg_total - n_bg_total
      ), nrow = 2)

      ft <- stats::fisher.test(m, alternative = "greater")

      expected <- (n_sig_total * n_bg_in_term) / n_bg_total
      fold <- if (expected > 0) n_sig_in_term / expected else Inf

      results <- rbind(results, data.frame(
        ontology = ont,
        go_id = term,
        n_significant = n_sig_in_term,
        n_background = n_bg_in_term,
        expected = round(expected, 2),
        fold_enrichment = round(fold, 2),
        p_value = ft$p.value,
        p_adj = NA,
        genes = paste(intersect(significant_proteins, term_proteins),
                      collapse = ";"),
        stringsAsFactors = FALSE
      ))
    }

    if (nrow(results) > 0) {
      results$p_adj <- stats::p.adjust(results$p_value, method = p_adjust)
      results <- results[order(results$p_value), , drop = FALSE]
      results <- results[results$p_adj < p_threshold, , drop = FALSE]
    }

    results_list[[ont]] <- results
    cat(sprintf("[GO-%s] %d terms passed significance threshold (p_adj < %.2f)\n",
                ont, nrow(results), p_threshold))
  }

  # 合并结果
  combined <- do.call(rbind, results_list)
  rownames(combined) <- NULL

  return(list(
    BP = results_list$BP,
    MF = results_list$MF,
    CC = results_list$CC,
    combined = combined,
    params = list(
      ontologies = ontologies,
      p_adjust = p_adjust,
      p_threshold = p_threshold,
      n_significant = length(significant_proteins),
      n_background = length(all_proteins)
    )
  ))
}


#' 绘制 GO 富集条形图
#'
#' @description 绘制 GO 术语富集分析条形图，按 ontology 分面着色。
#'
#' @param go_result \code{run_go_enrichment()} 的返回结果。
#' @param top_n 每个本体展示前 N 个术语。默认 10。
#' @param plot_type 图类型，"bar" 或 "dot"。默认 "bar"。
#'
#' @return ggplot 对象。
#'
#' @examples
#' \dontrun{
#' p <- plot_go_enrichment(go_result, top_n = 10)
#' }
#'
#' @export
plot_go_enrichment <- function(go_result, top_n = 10, plot_type = "bar") {
  combined <- go_result$combined
  if (nrow(combined) == 0) {
    stop("No significant GO terms to plot.")
  }

  # 按 ontology 取 Top N
  plot_df <- do.call(rbind, lapply(split(combined, combined$ontology), function(x) {
    if (nrow(x) > top_n) x <- x[1:top_n, , drop = FALSE]
    x
  }))

  plot_df$go_label <- sprintf("%s (%d)", plot_df$go_id, plot_df$n_significant)
  plot_df$go_label <- factor(plot_df$go_label,
                              levels = plot_df$go_label[order(plot_df$ontology,
                                                               -plot_df$fold_enrichment)])

  ont_colors <- c(
    "BP" = "#e74c3c",
    "MF" = "#4a90d9",
    "CC" = "#2ecc71"
  )

  if (plot_type == "bar") {
    p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = go_label,
                                                 y = fold_enrichment,
                                                 fill = ontology)) +
      ggplot2::geom_bar(stat = "identity") +
      ggplot2::coord_flip() +
      ggplot2::scale_fill_manual(values = ont_colors, name = "Ontology") +
      ggplot2::labs(
        title = "GO Enrichment Analysis",
        x = NULL,
        y = "Fold Enrichment"
      )
  } else {
    p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = fold_enrichment,
                                                 y = go_label,
                                                 size = n_significant,
                                                 color = ontology)) +
      ggplot2::geom_point() +
      ggplot2::scale_color_manual(values = ont_colors, name = "Ontology") +
      ggplot2::labs(
        title = "GO Enrichment Analysis",
        x = "Fold Enrichment",
        y = NULL,
        size = "Gene Count"
      )
  }

  p <- p + ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 14, face = "bold", hjust = 0.5),
      axis.text = ggplot2::element_text(size = 9),
      axis.title = ggplot2::element_text(size = 12),
      legend.position = "right"
    )

  return(p)
}
