# ============================================================================
# R 工具函数脚本 - WGCNA 共表达模块与生物学性状关联分析
# ============================================================================
# 该脚本实现：
# 1. 按 MAD 值降序排序取 top 20000 个分子
# 2. WGCNA 共表达网络构建
# 3. 模块与生物学性状关联分析
# 4. 共表达模块与生物学性状值的线性回归分析
# 5. 共表达模块分子的 KEGG 功能富集分析
# ============================================================================

library(WGCNA)
library(ggplot2)
library(clusterProfiler)

run_wgcna_analysis <- function(expr_file, sample_info_file, output_dir,
                                trait_data = NULL, top_mad = 20000,
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
  
  # 按 MAD 取 top
  mad_values <- apply(expr_matrix, 1, mad, na.rm = TRUE)
  top_indices <- order(mad_values, decreasing = TRUE)[1:min(top_mad, nrow(expr_matrix))]
  expr_matrix <- expr_matrix[top_indices, ]
  
  # 转置（WGCNA 要求样本为行）
  datExpr <- t(expr_matrix)
  
  # 选择 soft threshold
  powers <- c(1:10, seq(12, 20, by = 2))
  sft <- pickSoftThreshold(datExpr, powerVector = powers, verbose = 5)
  
  power <- sft$powerEstimate
  if (is.na(power)) power <- 6
  
  # 构建网络
  net <- blockwiseModules(datExpr, power = power,
                          TOMType = "unsigned", minModuleSize = 30,
                          reassignThreshold = 0, mergeCutHeight = 0.25,
                          numericLabels = TRUE, saveTOMs = TRUE,
                          saveTOMFileBase = file.path(output_dir, "tables", "TOM"),
                          verbose = 3)
  
  moduleColors <- labels2colors(net$colors)
  
  # 保存模块信息
  module_info <- data.frame(
    molecule = colnames(datExpr),
    module = moduleColors,
    module_label = net$colors
  )
  write.csv(module_info, file.path(output_dir, "tables", "wgcna_modules.csv"), row.names = FALSE)
  
  # 模块大小分布
  module_sizes <- as.data.frame(table(moduleColors))
  colnames(module_sizes) <- c("module", "size")
  write.csv(module_sizes, file.path(output_dir, "tables", "module_sizes.csv"), row.names = FALSE)
  
  # 绘制模块树状图
  pdf(file.path(output_dir, "figures", "wgcna_dendrogram.pdf"), width = 12, height = 8)
  plotDendroAndColors(net$dendrograms[[1]], moduleColors[net$blockGenes[[1]]],
                      "Module colors", dendroLabels = FALSE,
                      addGuide = TRUE, main = "WGCNA Dendrogram")
  dev.off()
  png(file.path(output_dir, "figures", "wgcna_dendrogram.png"), width = 2400, height = 1600, res = 300)
  plotDendroAndColors(net$dendrograms[[1]], moduleColors[net$blockGenes[[1]]],
                      "Module colors", dendroLabels = FALSE,
                      addGuide = TRUE, main = "WGCNA Dendrogram")
  dev.off()
  
  # 构建性状数据
  trait <- NULL
  if (!is.null(trait_data)) {
    trait <- trait_data
  } else {
    # 使用样本元数据作为性状
    numeric_cols <- sapply(sample_info, is.numeric)
    if (sum(numeric_cols) > 0) {
      trait <- sample_info[, numeric_cols, drop = FALSE]
      rownames(trait) <- sample_info$ID
      trait <- trait[common_samples, , drop = FALSE]
    }
  }
  
  # 模块与性状关联分析
  if (!is.null(trait) && ncol(trait) > 0) {
    MEs <- moduleEigengenes(datExpr, moduleColors)$eigengenes
    MEs <- orderMEs(MEs)
    
    moduleTraitCor <- cor(MEs, trait, use = "p")
    moduleTraitPvalue <- corPvalueStudent(moduleTraitCor, nrow(datExpr))
    
    # 保存关联结果
    module_trait_df <- as.data.frame(moduleTraitCor)
    module_trait_df$module <- rownames(module_trait_df)
    write.csv(module_trait_df, file.path(output_dir, "tables", "module_trait_correlation.csv"), row.names = FALSE)
    
    # 热图
    textMatrix <- paste(signif(moduleTraitCor, 2), "\n(", signif(moduleTraitPvalue, 1), ")", sep = "")
    dim(textMatrix) <- dim(moduleTraitCor)
    
    pdf(file.path(output_dir, "figures", "module_trait_heatmap.pdf"), width = 10, height = 8)
    par(mar = c(6, 8, 3, 3))
    labeledHeatmap(Matrix = moduleTraitCor,
                   xLabels = colnames(trait),
                   yLabels = names(MEs),
                   colorLabels = FALSE,
                   textMatrix = textMatrix,
                   textColors = "black",
                   setStdMargins = FALSE,
                   cex.text = 0.5,
                   zlim = c(-1, 1),
                   main = "Module-Trait Relationships")
    dev.off()
    
    png(file.path(output_dir, "figures", "module_trait_heatmap.png"), width = 2400, height = 2000, res = 300)
    par(mar = c(6, 8, 3, 3))
    labeledHeatmap(Matrix = moduleTraitCor,
                   xLabels = colnames(trait),
                   yLabels = names(MEs),
                   colorLabels = FALSE,
                   textMatrix = textMatrix,
                   textColors = "black",
                   setStdMargins = FALSE,
                   cex.text = 0.5,
                   zlim = c(-1, 1),
                   main = "Module-Trait Relationships")
    dev.off()
    
    # 线性回归分析
    regression_results <- list()
    for (me in colnames(MEs)) {
      for (tr in colnames(trait)) {
        fit <- lm(MEs[[me]] ~ trait[[tr]])
        summary_fit <- summary(fit)
        regression_results[[paste(me, tr, sep = "_vs_")]] <- list(
          r_squared = summary_fit$r.squared,
          p_value = summary_fit$coefficients[2, 4]
        )
      }
    }
    
    reg_df <- do.call(rbind, lapply(names(regression_results), function(k) {
      data.frame(
        comparison = k,
        r_squared = regression_results[[k]]$r_squared,
        p_value = regression_results[[k]]$p_value
      )
    }))
    write.csv(reg_df, file.path(output_dir, "tables", "module_trait_regression.csv"), row.names = FALSE)
  }
  
  # 模块 KEGG 富集分析
  if (!is.null(annotation_file) && file.exists(annotation_file)) {
    annotation <- read.csv(annotation_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    enrich_results <- list()
    for (mod in unique(moduleColors)) {
      mod_molecules <- colnames(datExpr)[moduleColors == mod]
      mod_kegg <- annotation$kegg[match(mod_molecules, annotation$id)]
      mod_kegg <- mod_kegg[!is.na(mod_kegg)]
      
      if (length(mod_kegg) >= 5) {
        tryCatch({
          enrich <- enrichKEGG(gene = mod_kegg, organism = "ko", pvalueCutoff = 0.05)
          if (!is.null(enrich) && nrow(enrich@result) > 0) {
            enrich_results[[mod]] <- as.data.frame(enrich@result)
          }
        }, error = function(e) NULL)
      }
    }
    
    if (length(enrich_results) > 0) {
      all_enrich <- do.call(rbind, lapply(names(enrich_results), function(k) {
        df <- enrich_results[[k]]
        df$module <- k
        df
      }))
      write.csv(all_enrich, file.path(output_dir, "tables", "module_kegg_enrichment.csv"), row.names = FALSE)
    }
  }
  
  return(list(
    power = power,
    n_modules = length(unique(moduleColors)),
    module_sizes = module_sizes
  ))
}

if (sys.nframe() == 0) {
  cat("Usage: source this script and call run_wgcna_analysis() function\n")
}
