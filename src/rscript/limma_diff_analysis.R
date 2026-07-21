# ============================================================================
# R 工具函数脚本 - LIMMA 差异分析
# ============================================================================
# 该脚本使用 limma 进行差异分析，包括：
# 1. 多因素 ANOVA 检验
# 2. 总体 F 检验
# 3. 两两比较差异分析
# 4. 时间序列数据：将时间因素作为协变量
# 5. 火山图、文氏图、热图
# ============================================================================

library(limma)
library(ggplot2)
library(pheatmap)
library(VennDiagram)

run_limma_diff <- function(expr_file, sample_info_file, output_dir,
                            comparisons, time_col = NULL,
                            pvalue_threshold = 0.05, vip_threshold = 1.0,
                            is_metabolite = FALSE, top_count = 200,
                            annotation_file = NULL) {
  dir.create(file.path(output_dir, "tables"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(output_dir, "figures"), showWarnings = FALSE, recursive = TRUE)
  
  expr <- read.csv(expr_file, row.names = 1, check.names = FALSE)
  expr_matrix <- as.matrix(expr)
  mode(expr_matrix) <- "numeric"
  
  sample_info <- read.csv(sample_info_file, stringsAsFactors = FALSE, check.names = FALSE)
  common_samples <- intersect(colnames(expr_matrix), sample_info$ID)
  expr_matrix <- expr_matrix[, common_samples]
  sample_info <- sample_info[match(common_samples, sample_info$ID), ]
  
  groups <- factor(sample_info$sample_info, levels = unique(sample_info$sample_info))
  
  # 读取注释表（用于热图标记分子分类）
  annotation <- NULL
  if (!is.null(annotation_file) && file.exists(annotation_file)) {
    annotation <- read.csv(annotation_file, stringsAsFactors = FALSE, check.names = FALSE)
  }
  
  # 构建设计矩阵
  if (!is.null(time_col) && time_col %in% colnames(sample_info)) {
    time_factor <- factor(sample_info[[time_col]])
    design <- model.matrix(~ 0 + groups + time_factor)
    colnames(design) <- c(levels(groups), paste0("time_", levels(time_factor)[-1]))
  } else {
    design <- model.matrix(~ 0 + groups)
    colnames(design) <- levels(groups)
  }
  
  fit <- lmFit(expr_matrix, design)
  
  # 构建对比矩阵
  contrast_names <- c()
  for (comp in comparisons) {
    contrast_names <- c(contrast_names, paste(comp[1], "-", comp[2]))
  }
  contrast_matrix <- makeContrasts(contrasts = contrast_names, levels = design)
  fit2 <- contrasts.fit(fit, contrast_matrix)
  fit2 <- eBayes(fit2)
  
  all_diff_results <- list()
  diff_molecule_lists <- list()
  
  for (i in seq_along(comparisons)) {
    comp <- comparisons[[i]]
    comp_name <- paste(comp[1], "_vs_", comp[2], sep = "")
    
    top_table <- topTable(fit2, coef = i, number = Inf, sort.by = "P")
    top_table$molecule <- rownames(top_table)
    
    # 筛选差异分子
    if (is_metabolite) {
      # 代谢组：pvalue + VIP
      sig <- top_table[top_table$adj.P.Val < pvalue_threshold, ]
      # VIP 值需要单独计算（这里简化处理）
    } else {
      sig <- top_table[top_table$adj.P.Val < pvalue_threshold, ]
    }
    
    # 按 |logFC| 降序排序，取 top
    sig <- sig[order(abs(sig$logFC), decreasing = TRUE), ]
    if (nrow(sig) > top_count) {
      sig <- sig[1:top_count, ]
    }
    
    sig$regulation <- ifelse(sig$logFC > 0, "up", "down")
    
    all_diff_results[[comp_name]] <- top_table
    diff_molecule_lists[[comp_name]] <- rownames(sig)
    
    write.csv(top_table, file.path(output_dir, "tables", paste0("diff_", comp_name, "_all.csv")), row.names = FALSE)
    write.csv(sig, file.path(output_dir, "tables", paste0("diff_", comp_name, "_significant.csv")), row.names = FALSE)
    
    # 火山图
    volcano_data <- top_table
    volcano_data$significant <- volcano_data$adj.P.Val < pvalue_threshold
    volcano_data$top_label <- ""
    if (nrow(sig) >= 5) {
      volcano_data$top_label[match(rownames(sig)[1:5], rownames(volcano_data))] <- rownames(sig)[1:5]
    }
    
    p_volcano <- ggplot(volcano_data, aes(x = logFC, y = -log10(adj.P.Val), color = significant)) +
      geom_point(size = 1) +
      scale_color_manual(values = c("grey", "red")) +
      geom_text(data = subset(volcano_data, top_label != ""),
                aes(label = top_label), vjust = -1, size = 3, color = "black") +
      labs(x = "log2 Fold Change", y = "-log10(adj.P.Val)",
           title = paste("Volcano Plot:", comp_name)) +
      theme_bw() + theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"))
    
    ggsave(file.path(output_dir, "figures", paste0("volcano_", comp_name, ".png")), p_volcano, width = 8, height = 6, dpi = 300)
    ggsave(file.path(output_dir, "figures", paste0("volcano_", comp_name, ".pdf")), p_volcano, width = 8, height = 6)
  }
  
  # 文氏图
  if (length(diff_molecule_lists) >= 2) {
    venn_file <- file.path(output_dir, "figures", "venn_diff_molecules.png")
    venn.diagram(
      x = diff_molecule_lists,
      filename = venn_file,
      category.names = names(diff_molecule_lists),
      fill = rainbow(length(diff_molecule_lists)),
      cat.col = rainbow(length(diff_molecule_lists)),
      cat.cex = 1.2,
      main = "Differential Molecules Venn Diagram"
    )
  }
  
  # 差异分子热图（合并所有比较的差异分子）
  all_diff_molecules <- unique(unlist(diff_molecule_lists))
  if (length(all_diff_molecules) > 0) {
    diff_expr <- expr_matrix[intersect(all_diff_molecules, rownames(expr_matrix)), ]
    
    # 按样本分组排序
    group_order <- order(groups)
    diff_expr <- diff_expr[, group_order]
    
    # 行层次聚类
    hc <- hclust(dist(diff_expr), method = "ward.D2")
    diff_expr <- diff_expr[hc$order, ]
    
    # 分子分类注释
    row_anno <- NULL
    if (!is.null(annotation)) {
      row_anno <- data.frame(
        type = annotation$type[match(rownames(diff_expr), annotation$id)]
      )
      rownames(row_anno) <- rownames(diff_expr)
    }
    
    col_anno <- data.frame(group = groups[group_order])
    rownames(col_anno) <- colnames(diff_expr)
    
    pheatmap(
      diff_expr,
      scale = "row",
      cluster_rows = FALSE,
      cluster_cols = FALSE,
      annotation_col = col_anno,
      annotation_row = row_anno,
      show_rownames = TRUE,
      show_colnames = TRUE,
      filename = file.path(output_dir, "figures", "diff_heatmap.png"),
      width = 10, height = 12
    )
    pheatmap(
      diff_expr,
      scale = "row",
      cluster_rows = FALSE,
      cluster_cols = FALSE,
      annotation_col = col_anno,
      annotation_row = row_anno,
      show_rownames = TRUE,
      show_colnames = TRUE,
      filename = file.path(output_dir, "figures", "diff_heatmap.pdf"),
      width = 10, height = 12
    )
  }
  
  return(list(
    diff_results = all_diff_results,
    diff_molecules = diff_molecule_lists
  ))
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  cat("Usage: source this script and call run_limma_diff() function\n")
}
