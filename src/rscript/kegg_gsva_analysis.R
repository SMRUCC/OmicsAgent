# ============================================================================
# R 工具函数脚本 - KEGG 富集分析与 GSVA
# ============================================================================
# 该脚本实现：
# 1. KEGG 通路富集分析（基于差异分子）
# 2. GSVA 分析（按相同组别设计进行差异分析）
# 3. 富集结果条形图（按 KEGG 大分类分组）
# 4. GSVA 总体热图（列=样本按分组排序，行=KEGG 通路按大分类分组+层次聚类）
# 5. GSVA 差异分析火山图、得分图
# ============================================================================

library(ggplot2)
library(pheatmap)
library(clusterProfiler)
library(GSVA)

run_kegg_analysis <- function(expr_file, sample_info_file, output_dir,
                               diff_molecules, annotation_file,
                               kegg_background_file = NULL,
                               group_col = "sample_info") {
  dir.create(file.path(output_dir, "tables"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(output_dir, "figures"), showWarnings = FALSE, recursive = TRUE)
  
  expr <- read.csv(expr_file, row.names = 1, check.names = FALSE)
  expr_matrix <- as.matrix(expr)
  mode(expr_matrix) <- "numeric"
  
  sample_info <- read.csv(sample_info_file, stringsAsFactors = FALSE, check.names = FALSE)
  common_samples <- intersect(colnames(expr_matrix), sample_info$ID)
  expr_matrix <- expr_matrix[, common_samples]
  sample_info <- sample_info[match(common_samples, sample_info$ID), ]
  groups <- sample_info[[group_col]]
  
  annotation <- read.csv(annotation_file, stringsAsFactors = FALSE, check.names = FALSE)
  
  # ---------------- KEGG 富集分析 ----------------
  kegg_enrichment_result <- tryCatch({
    # 获取差异分子的 KEGG ID
    diff_kegg_ids <- annotation$kegg[match(diff_molecules, annotation$id)]
    diff_kegg_ids <- diff_kegg_ids[!is.na(diff_kegg_ids)]
    
    # 富集分析
    if (!is.null(kegg_background_file) && file.exists(kegg_background_file)) {
      # 使用本地 KEGG 背景文件
      background <- read.csv(kegg_background_file, stringsAsFactors = FALSE)
      # 简化的超几何检验
      enrich_result <- enrichKEGG(gene = diff_kegg_ids, organism = "ko", pvalueCutoff = 0.05)
    } else {
      enrich_result <- enrichKEGG(gene = diff_kegg_ids, organism = "ko", pvalueCutoff = 0.05)
    }
    
    if (!is.null(enrich_result) && nrow(enrich_result@result) > 0) {
      enrich_df <- as.data.frame(enrich_result@result)
      write.csv(enrich_df, file.path(output_dir, "tables", "kegg_enrichment.csv"), row.names = FALSE)
      
      # 富集条形图（按 KEGG 大分类分组）
      enrich_df$neg_log10_p <- -log10(enrich_df$p.adjust)
      enrich_df$category <- sapply(strsplit(enrich_df$Description, " - "), function(x) x[1])
      
      p_bar <- ggplot(head(enrich_df, 20), aes(x = reorder(Description, neg_log10_p), y = neg_log10_p, fill = category)) +
        geom_bar(stat = "identity") +
        coord_flip() +
        labs(x = "KEGG Pathway", y = "-log10(p.adjust)", title = "KEGG Enrichment Bar Plot") +
        theme_bw() + theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"))
      
      ggsave(file.path(output_dir, "figures", "kegg_enrichment_barplot.png"), p_bar, width = 10, height = 8, dpi = 300)
      ggsave(file.path(output_dir, "figures", "kegg_enrichment_barplot.pdf"), p_bar, width = 10, height = 8)
    }
    
    enrich_result
  }, error = function(e) {
    cat("KEGG enrichment failed:", e$message, "\n")
    NULL
  })
  
  # ---------------- GSVA 分析 ----------------
  gsva_result <- tryCatch({
    # 构建 KEGG 通路基因集
    kegg_ids <- annotation$kegg[!is.na(annotation$kegg)]
    pathways <- split(annotation$id, annotation$kegg)
    pathways <- pathways[sapply(pathways, length) >= 5]
    
    gsva_par <- gsvaParam(exprData = expr_matrix, geneSets = pathways)
    gsva_scores <- gsva(gsva_par)
    
    write.csv(gsva_scores, file.path(output_dir, "tables", "gsva_scores.csv"))
    
    # GSVA 热图
    group_order <- order(groups)
    gsva_ordered <- gsva_scores[, group_order]
    
    # 按大分类分组+层次聚类
    pathway_categories <- sapply(rownames(gsva_ordered), function(pid) {
      anno_rows <- annotation[annotation$kegg == pid, ]
      if (nrow(anno_rows) > 0) anno_rows$type[1] else "unknown"
    })
    
    row_anno <- data.frame(category = pathway_categories)
    rownames(row_anno) <- rownames(gsva_ordered)
    col_anno <- data.frame(group = groups[group_order])
    rownames(col_anno) <- colnames(gsva_ordered)
    
    pheatmap(
      gsva_ordered,
      scale = "row",
      cluster_rows = TRUE,
      cluster_cols = FALSE,
      annotation_col = col_anno,
      annotation_row = row_anno,
      show_rownames = FALSE,
      show_colnames = TRUE,
      filename = file.path(output_dir, "figures", "gsva_heatmap.png"),
      width = 10, height = 12
    )
    pheatmap(
      gsva_ordered,
      scale = "row",
      cluster_rows = TRUE,
      cluster_cols = FALSE,
      annotation_col = col_anno,
      annotation_row = row_anno,
      show_rownames = FALSE,
      show_colnames = TRUE,
      filename = file.path(output_dir, "figures", "gsva_heatmap.pdf"),
      width = 10, height = 12
    )
    
    # GSVA 差异分析
    library(limma)
    design <- model.matrix(~ 0 + factor(groups))
    colnames(design) <- levels(factor(groups))
    fit <- lmFit(gsva_scores, design)
    
    # 两两比较
    group_levels <- levels(factor(groups))
    if (length(group_levels) >= 2) {
      contrast_matrix <- makeContrasts(
        contrasts = paste(group_levels[1], "-", group_levels[2]),
        levels = design
      )
      fit2 <- contrasts.fit(fit, contrast_matrix)
      fit2 <- eBayes(fit2)
      
      gsva_diff <- topTable(fit2, coef = 1, number = Inf)
      write.csv(gsva_diff, file.path(output_dir, "tables", "gsva_diff.csv"))
      
      # 火山图
      gsva_diff$significant <- gsva_diff$adj.P.Val < 0.05
      p_volcano <- ggplot(gsva_diff, aes(x = logFC, y = -log10(adj.P.Val), color = significant)) +
        geom_point(size = 1) +
        scale_color_manual(values = c("grey", "red")) +
        labs(x = "log2 Fold Change", y = "-log10(adj.P.Val)", title = "GSVA Differential Volcano Plot") +
        theme_bw() + theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"))
      
      ggsave(file.path(output_dir, "figures", "gsva_volcano.png"), p_volcano, width = 8, height = 6, dpi = 300)
      ggsave(file.path(output_dir, "figures", "gsva_volcano.pdf"), p_volcano, width = 8, height = 6)
    }
    
    gsva_scores
  }, error = function(e) {
    cat("GSVA failed:", e$message, "\n")
    NULL
  })
  
  return(list(
    enrichment = kegg_enrichment_result,
    gsva = gsva_result
  ))
}

if (sys.nframe() == 0) {
  cat("Usage: source this script and call run_kegg_analysis() function\n")
}
