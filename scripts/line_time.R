# ==============================================================================
# 1. 环境设置与数据加载
# ==============================================================================

# 清空环境变量
rm(list = ls())
gc()

# 检查并加载所需的包
required_packages <- c("limma", "ggplot2", "ggrepel", "pheatmap", "RColorBrewer", "dplyr", "tidyr")

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    if (pkg %in% c("limma", "pheatmap")) {
      if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
      BiocManager::install(pkg)
    } else {
      install.packages(pkg)
    }
  }
  library(pkg, character.only = TRUE)
}

# 创建结果保存目录
dir.create("results", showWarnings = FALSE)

# -----------------------------------------------------------------------------
# 1.1 读取样本信息
# -----------------------------------------------------------------------------
# 读取样本信息文件
sample_info <- read.csv("rnaseqs_samples.csv", header = TRUE, stringsAsFactors = FALSE, fileEncoding = "UTF-8")

# 数据清洗：去除可能存在的BOM头或空格
names(sample_info) <- trimws(names(sample_info))
sample_info$ID <- trimws(sample_info$ID)
sample_info$line <- trimws(sample_info$line)
# 清洗days列，去除字符'd'，转换为数值型协变量
sample_info$days <- as.numeric(gsub("d", "", sample_info$days))

# 确保line为因子
sample_info$line <- as.factor(sample_info$line)

print("样本信息概览：")
print(head(sample_info))

# -----------------------------------------------------------------------------
# 1.2 读取表达矩阵
# -----------------------------------------------------------------------------
# 假设rnaseqs.csv第一列为基因ID，其余列为样本表达量
expr_data <- read.csv("rnaseqs.csv", header = TRUE, row.names = 1, check.names = FALSE)

# 确保表达矩阵列名与样本信息ID对应
# 仅保留样本信息中存在的样本
common_samples <- intersect(colnames(expr_data), sample_info$ID)

if (length(common_samples) == 0) {
  stop("错误：表达矩阵的列名与样本信息表中的ID不匹配，请检查文件。")
}

expr_data <- expr_data[, common_samples]
sample_info <- sample_info[match(common_samples, sample_info$ID), ]

# 过滤低表达基因 (保留至少在部分样本中有表达的基因)
keep_genes <- rowSums(expr_data > 0) >= ncol(expr_data) * 0.1 # 至少在10%的样本中大于0
expr_data <- expr_data[keep_genes, ]

# 转换为矩阵
expr_matrix <- as.matrix(expr_data)

print("表达矩阵维度：")
print(dim(expr_matrix))


# ==============================================================================
# 2. PCA 分析与可视化
# ==============================================================================
# 对数据进行转置(样本为行，基因为列)进行PCA
pca_data <- t(expr_matrix)
# 缩放数据
pca_res <- prcomp(pca_data, scale. = TRUE, center = TRUE)

# 提取PCA结果
pca_df <- data.frame(
  Sample = rownames(pca_res$x),
  PC1 = pca_res$x[, 1],
  PC2 = pca_res$x[, 2]
)
# 合并样本信息
pca_df <- merge(pca_df, sample_info, by.x = "Sample", by.y = "ID")

# 定义颜色和形状
color_palette <- brewer.pal(length(unique(pca_df$days)), "Set1")
shapes <- c(16, 17, 15, 18, 8, 11)[1:length(unique(pca_df$line))]

# 绘制PCA散点图
p_plot <- ggplot(pca_df, aes(x = PC1, y = PC2, color = factor(days), shape = line)) +
  geom_point(size = 4, alpha = 0.8) +
  scale_color_manual(values = color_palette, name = "Days") +
  scale_shape_manual(values = shapes, name = "Line") +
  stat_ellipse(aes(group = line, color = factor(days)), 
               geom = "polygon", alpha = 0.1, level = 0.95, show.legend = FALSE) +
  # 注意：要求相同line为一组画椭圆，但颜色是days。通常椭圆按分组画。
  # 这里为了视觉效果，按line分组画椭圆，填充色与days颜色映射一致但较淡
  labs(title = "PCA Plot of Samples", 
       x = paste0("PC1 (", round(summary(pca_res)$importance[2,1]*100, 1), "%)"),
       y = paste0("PC2 (", round(summary(pca_res)$importance[2,2]*100, 1), "%)")) +
  theme_bw() +
  theme(plot.title = element_text(hjust = 0.5, size = 14, face = "bold"))

# 保存PCA图
ggsave("results/01_PCA_plot.pdf", p_plot, width = 8, height = 6)
ggsave("results/01_PCA_plot.png", p_plot, width = 8, height = 6, dpi = 300)
print("PCA图已保存。")


# ==============================================================================
# 3. Limma 差异分析 (以days为协变量)
# ==============================================================================

# 3.1 设计矩阵
# 模型公式: ~ 0 + line + days
# 0 + line: 创建不同品种的分组均值
# days: 作为数值型协变量，调整时间效应
design <- model.matrix(~ 0 + line + days, data = sample_info)
colnames(design) <- c(levels(sample_info$line), "days") # 重命名列以便于识别

# 3.2 拟合模型
fit <- lmFit(expr_matrix, design)
fit <- eBayes(fit)

# ==============================================================================
# 4. 两两比较分析
# ==============================================================================

# 获取所有品种
lines <- levels(sample_info$line)
line_pairs <- combn(lines, 2, simplify = FALSE)

# 用于存储结果列表
pairwise_results <- list()

# 循环进行两两比较
for (pair in line_pairs) {
  group1 <- pair[1]
  group2 <- pair[2]
  
  # 构建对比矩阵: group2 vs group1
  contrast_formula <- paste0(group2, " - ", group1)
  contrast_matrix <- makeContrasts(contrasts = contrast_formula, levels = design)
  
  # 拟合对比
  fit_contrast <- contrasts.fit(fit, contrast_matrix)
  fit_contrast <- eBayes(fit_contrast)
  
  # 提取结果
  res <- topTable(fit_contrast, adjust = "fdr", number = Inf)
  res$GeneID <- rownames(res)
  
  # 保存结果
  file_name <- paste0("results/02_DEG_", group2, "_vs_", group1, ".csv")
  write.csv(res, file_name, row.names = FALSE)
  
  pairwise_results[[paste(group2, "vs", group1, sep = "_")]] <- res
  
  # -------------------------------------------------------------------------
  # 绘制火山图
  # -------------------------------------------------------------------------
  volcanodata <- res
  # 定义显著基因标准: |logFC| > 1 & FDR < 0.05
  volcanodata$Significant <- "No"
  volcanodata$Significant[volcanodata$logFC > 1 & volcanodata$adj.P.Val < 0.05] <- "Up"
  volcanodata$Significant[volcanodata$logFC < -1 & volcanodata$adj.P.Val < 0.05] <- "Down"
  volcanodata$Significant <- factor(volcanodata$Significant, levels = c("Down", "No", "Up"))
  
  # 筛选需要标注的基因: Top 10 显著上调和下调
  top_up <- head(volcanodata[volcanodata$Significant == "Up" & order(volcanodata$adj.P.Val), ], 5)
  top_down <- head(volcanodata[volcanodata$Significant == "Down" & order(volcanodata$adj.P.Val), ], 5)
  label_genes <- rbind(top_up, top_down)
  
  p_volcano <- ggplot(volcanodata, aes(x = logFC, y = -log10(adj.P.Val), color = Significant)) +
    geom_point(alpha = 0.6, size = 1.2) +
    scale_color_manual(values = c("blue", "grey", "red")) +
    geom_vline(xintercept = c(-1, 1), linetype = "dashed", color = "grey30") +
    geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "grey30") +
    geom_text_repel(data = label_genes, aes(label = GeneID), 
                    color = "black", size = 3, max.overlaps = 20) +
    labs(title = paste("Volcano Plot:", group2, "vs", group1),
         x = "log2 Fold Change", y = "-log10(Adjusted P-value)") +
    theme_bw() +
    theme(plot.title = element_text(hjust = 0.5, face = "bold"),
          legend.position = "right")
  
  ggsave(paste0("results/03_Volcano_", group2, "_vs_", group1, ".pdf"), p_volcano, width = 8, height = 6)
  ggsave(paste0("results/03_Volcano_", group2, "_vs_", group1, ".png"), p_volcano, width = 8, height = 6, dpi = 300)
}
print("两两比较分析及火山图绘制完成。")


# ==============================================================================
# 5. F检验 (ANOVA-like F-test) 分析
# ==============================================================================

# F检验：检验所有品种之间是否存在表达差异 (排除days影响)
# 在设计矩阵中，品种列是否不全为0。
# 使用 topTable 指定多个系数进行F检验
line_cols <- colnames(design)[grepl("^line", colnames(design))] # 获取所有品种列名

# 这里的F检验是针对所有line系数是否等于0（即品种间无差异）
# 注意：design矩阵包含days，所以这是调整了days后的F检验
fit_F <- eBayes(fit)
res_F <- topTable(fit_F, coef = line_cols, number = Inf, sort.by = "F", adjust.method = "fdr")
res_F$GeneID <- rownames(res_F)

# 保存F检验结果
write.csv(res_F, "results/04_F_test_All_Lines.csv", row.names = FALSE)

# 获取 Top 10 基因
top10_genes <- res_F$GeneID[1:10]

# -------------------------------------------------------------------------
# 绘制 Top 10 基因的表达分布图 (条形图、盒须图、小提琴图)
# -------------------------------------------------------------------------

# 准备绘图数据: 提取Top 10 基因的表达量，并转换为长格式
plot_data <- expr_matrix[top10_genes, , drop = FALSE]
plot_data <- as.data.frame(t(plot_data))
plot_data <- cbind(Sample = rownames(plot_data), plot_data)
plot_data <- merge(sample_info, plot_data, by.x = "ID", by.y = "Sample")
plot_data_long <- pivot_longer(plot_data, cols = all_of(top10_genes), names_to = "Gene", values_to = "Expression")

# 循环绘制每个基因的图
for (gene in top10_genes) {
  gene_data <- subset(plot_data_long, Gene == gene)
  
  # 1. 条形图 - 展示均值
  p_bar <- ggplot(gene_data, aes(x = line, y = Expression, fill = line)) +
    stat_summary(fun = "mean", geom = "bar", color = "black") +
    stat_summary(fun.data = mean_se, geom = "errorbar", width = 0.2) +
    labs(title = paste("Barplot of", gene), subtitle = "Mean Expression +/- SE") +
    theme_bw() + theme(legend.position = "none", axis.text.x = element_text(angle = 45, hjust = 1))
  
  # 2. 盒须图
  p_box <- ggplot(gene_data, aes(x = line, y = Expression, fill = line)) +
    geom_boxplot() +
    labs(title = paste("Boxplot of", gene)) +
    theme_bw() + theme(legend.position = "none", axis.text.x = element_text(angle = 45, hjust = 1))
  
  # 3. 小提琴图
  p_violin <- ggplot(gene_data, aes(x = line, y = Expression, fill = line)) +
    geom_violin(trim = FALSE) +
    geom_boxplot(width = 0.1, fill = "white") +
    labs(title = paste("Violin Plot of", gene)) +
    theme_bw() + theme(legend.position = "none", axis.text.x = element_text(angle = 45, hjust = 1))
  
  # 组合图形 (patchwork包未默认加载，使用gridExtra或分别保存)
  ggsave(paste0("results/05_Top10_", gene, "_plots.pdf"), 
         plot = p_bar + p_box + p_violin + plot_layout(ncol = 3), 
         width = 15, height = 5)
  ggsave(paste0("results/05_Top10_", gene, "_plots.png"), 
         plot = p_bar + p_box + p_violin + plot_layout(ncol = 3), 
         width = 15, height = 5, dpi = 300)
}
print("F检验及Top 10基因表达图绘制完成。")


# ==============================================================================
# 6. 差异基因热图
# ==============================================================================

# 选择F检验显著的基因 (adj.P.Val < 0.05)
sig_genes_F <- rownames(subset(res_F, adj.P.Val < 0.05))

if (length(sig_genes_F) > 0) {
  # 为了绘图美观，如果显著基因过多，只取Top 50 或 Top 100
  if (length(sig_genes_F) > 100) {
    heatmap_genes <- sig_genes_F[1:100]
  } else {
    heatmap_genes <- sig_genes_F
  }
  
  # 准备热图数据
  heatmap_matrix <- expr_matrix[heatmap_genes, , drop = FALSE]
  
  # 样本排序：先按line，再按days
  sample_order <- sample_info[order(sample_info$line, sample_info$days), ]
  heatmap_matrix <- heatmap_matrix[, sample_order$ID]
  
  # 标注信息
  annotation_col <- data.frame(
    Line = sample_order$line,
    Days = factor(sample_order$days)
  )
  rownames(annotation_col) <- sample_order$ID
  
  # 定义颜色
  ann_colors <- list(
    Line = brewer.pal(length(unique(sample_order$line)), "Paired"),
    Days = brewer.pal(length(unique(sample_order$days)), "Set2")
  )
  names(ann_colors$Line) <- levels(sample_order$line)
  names(ann_colors$Days) <- levels(factor(sample_order$days))
  
  # 绘制热图
  pdf("results/06_Heatmap_DEG.pdf", width = 10, height = 12)
  pheatmap(heatmap_matrix,
           scale = "row", # 按行归一化
           cluster_rows = TRUE, # 基因聚类
           cluster_cols = FALSE, # 样本不聚类，按排序展示
           show_rownames = FALSE, # 基因过多不显示名字
           show_colnames = FALSE,
           annotation_col = annotation_col,
           annotation_colors = ann_colors,
           main = "Heatmap of Differentially Expressed Genes (F-test)",
           color = colorRampPalette(c("navy", "white", "firebrick3"))(100))
  dev.off()
  
  png("results/06_Heatmap_DEG.png", width = 10, height = 12, units = "in", res = 300)
  pheatmap(heatmap_matrix,
           scale = "row",
           cluster_rows = TRUE,
           cluster_cols = FALSE,
           show_rownames = FALSE,
           show_colnames = FALSE,
           annotation_col = annotation_col,
           annotation_colors = ann_colors,
           main = "Heatmap of Differentially Expressed Genes (F-test)",
           color = colorRampPalette(c("navy", "white", "firebrick3"))(100))
  dev.off()
  
  print("热图绘制完成。")
} else {
  print("未找到显著差异基因，跳过热图绘制。")
}

print("所有分析已完成，结果保存在 'results' 文件夹中。")
