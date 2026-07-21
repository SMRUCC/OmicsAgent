# ============================================================================
# R 工具函数脚本 - CMeans 模糊聚类
# ============================================================================
# 该脚本实现：
# 1. CMeans 模糊聚类对分子表达矩阵数据做聚类分析
# 2. 对聚类簇中的分子做 KEGG 富集分析
# 3. 将聚类簇的结果与 WGCNA 的共表达模块做关联分析
# ============================================================================

library(e1071)
library(ggplot2)
library(clusterProfiler)
library(pheatmap)

run_cmeans_clustering <- function(expr_file, output_dir,
                                   cluster_num = 6, fuzzifier = 2,
                                   annotation_file = NULL,
                                   wgcna_modules_file = NULL) {
  dir.create(file.path(output_dir, "tables"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(output_dir, "figures"), showWarnings = FALSE, recursive = TRUE)
  
  expr <- read.csv(expr_file, row.names = 1, check.names = FALSE)
  expr_matrix <- as.matrix(expr)
  mode(expr_matrix) <- "numeric"
  
  # CMeans 聚类
  cmeans_result <- cmeans(expr_matrix, centers = cluster_num, m = fuzzifier)
  
  # 保存聚类结果
  cluster_df <- data.frame(
    molecule = rownames(expr_matrix),
    cluster = paste0("Cluster", cmeans_result$cluster),
    membership = apply(cmeans_result$membership, 1, max)
  )
  write.csv(cluster_df, file.path(output_dir, "tables", "cmeans_clusters.csv"), row.names = FALSE)
  
  # 聚类中心
  centers_df <- as.data.frame(cmeans_result$centers)
  centers_df$cluster <- paste0("Cluster", 1:cluster_num)
  write.csv(centers_df, file.path(output_dir, "tables", "cmeans_centers.csv"), row.names = FALSE)
  
  # 聚类大小
  cluster_sizes <- as.data.frame(table(cluster_df$cluster))
  colnames(cluster_sizes) <- c("cluster", "size")
  write.csv(cluster_sizes, file.path(output_dir, "tables", "cluster_sizes.csv"), row.names = FALSE)
  
  # 绘制聚类中心表达模式
  centers_long <- reshape2::melt(centers_df, id.vars = "cluster")
  colnames(centers_long) <- c("cluster", "sample", "expression")
  
  p_centers <- ggplot(centers_long, aes(x = sample, y = expression, color = cluster, group = cluster)) +
    geom_line(size = 1) +
    geom_point(size = 2) +
    labs(x = "Sample", y = "Expression", title = "CMeans Cluster Centers") +
    theme_bw() + theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
                        axis.text.x = element_text(angle = 45, hjust = 1))
  
  ggsave(file.path(output_dir, "figures", "cmeans_centers.png"), p_centers, width = 10, height = 6, dpi = 300)
  ggsave(file.path(output_dir, "figures", "cmeans_centers.pdf"), p_centers, width = 10, height = 6)
  
  # KEGG 富集分析
  if (!is.null(annotation_file) && file.exists(annotation_file)) {
    annotation <- read.csv(annotation_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    enrich_results <- list()
    for (cl in unique(cluster_df$cluster)) {
      cl_molecules <- cluster_df$molecule[cluster_df$cluster == cl]
      cl_kegg <- annotation$kegg[match(cl_molecules, annotation$id)]
      cl_kegg <- cl_kegg[!is.na(cl_kegg)]
      
      if (length(cl_kegg) >= 5) {
        tryCatch({
          enrich <- enrichKEGG(gene = cl_kegg, organism = "ko", pvalueCutoff = 0.05)
          if (!is.null(enrich) && nrow(enrich@result) > 0) {
            enrich_results[[cl]] <- as.data.frame(enrich@result)
          }
        }, error = function(e) NULL)
      }
    }
    
    if (length(enrich_results) > 0) {
      all_enrich <- do.call(rbind, lapply(names(enrich_results), function(k) {
        df <- enrich_results[[k]]
        df$cluster <- k
        df
      }))
      write.csv(all_enrich, file.path(output_dir, "tables", "cluster_kegg_enrichment.csv"), row.names = FALSE)
    }
  }
  
  # 与 WGCNA 模块关联分析
  if (!is.null(wgcna_modules_file) && file.exists(wgcna_modules_file)) {
    wgcna_modules <- read.csv(wgcna_modules_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # 构建关联表
    merged <- merge(cluster_df, wgcna_modules, by.x = "molecule", by.y = "molecule", all = FALSE)
    
    # 列联表
    contingency <- table(merged$cluster, merged$module)
    write.csv(as.data.frame(contingency), file.path(output_dir, "tables", "cmeans_wgcna_contingency.csv"))
    
    # 卡方检验
    chi_test <- chisq.test(contingency)
    chi_result <- data.frame(
      statistic = chi_test$statistic,
      p_value = chi_test$p.value,
      df = chi_test$parameter
    )
    write.csv(chi_result, file.path(output_dir, "tables", "cmeans_wgcna_chi_test.csv"), row.names = FALSE)
    
    # 关联热图
    pheatmap(
      as.matrix(contingency),
      scale = "row",
      cluster_rows = TRUE,
      cluster_cols = TRUE,
      show_rownames = TRUE,
      show_colnames = TRUE,
      filename = file.path(output_dir, "figures", "cmeans_wgcna_heatmap.png"),
      width = 10, height = 8
    )
    pheatmap(
      as.matrix(contingency),
      scale = "row",
      cluster_rows = TRUE,
      cluster_cols = TRUE,
      show_rownames = TRUE,
      show_colnames = TRUE,
      filename = file.path(output_dir, "figures", "cmeans_wgcna_heatmap.pdf"),
      width = 10, height = 8
    )
  }
  
  return(list(
    n_clusters = cluster_num,
    cluster_sizes = cluster_sizes
  ))
}

if (sys.nframe() == 0) {
  cat("Usage: source this script and call run_cmeans_clustering() function\n")
}
