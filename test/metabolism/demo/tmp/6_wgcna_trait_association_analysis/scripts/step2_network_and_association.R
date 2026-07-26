###############################################################
# WGCNA Step2: Network Construction, Module Identification,
# Module-Trait Association & Hub Network Visualization
###############################################################

base_dir <- "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis"
tables_dir <- file.path(base_dir, "tables")
figures_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/6_wgcna_trait_association_analysis/figures"
scripts_dir <- file.path(base_dir, "scripts")

for (d in c(tables_dir, figures_dir, scripts_dir)) {
 if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

cat("=== WGCNA Step2: Network Construction & Module-Trait Association ===\n")

# ----0. Load required packages ----
library(WGCNA)
library(dynamicTreeCut)
library(igraph)
library(ggplot2)
library(reshape2)
library(grDevices)
library(stats)

allowWGCNAThreads()
cat("WGCNA multi-threading enabled.\n")

# ----1. Load Step1 data ----
rdata_file <- file.path(base_dir, "wgcna_step1_data.RData")
cat("Loading Step1 data from:", rdata_file, "\n")
load(rdata_file)

cat("Data loaded:\n")
cat(" expr_matrix:", nrow(expr_matrix), "x", ncol(expr_matrix), "\n")
cat(" datExpr:", nrow(datExpr), "x", ncol(datExpr), "\n")
cat(" all_traits:", nrow(all_traits), "x", ncol(all_traits), "\n")
cat(" power_estimate:", power_estimate, "\n")

# ----2. Network construction ----
cat("Building WGCNA network with power =", power_estimate, "...\n")

# Build adjacency matrix
adjacency <- WGCNA::adjacency(
 datExpr,
 power = power_estimate,
 type = "signed"
)
cat("Adjacency matrix built. Dimensions:", nrow(adjacency), "x", ncol(adjacency), "\n")

# Build TOM (Topological Overlap Matrix)
cat("Calculating TOM similarity (this may take a moment)...\n")
TOM <- WGCNA::TOMsimilarity(adjacency)
cat("TOM matrix calculated. Dimensions:", nrow(TOM), "x", ncol(TOM), "\n")

# Hierarchical clustering
gene_tree <- stats::hclust(stats::as.dist(1 - TOM), method = "average")
cat("Hierarchical clustering completed.\n")

# Dynamic tree cut (use dynamicTreeCut explicitly)
dynamic_labels <- dynamicTreeCut::cutreeDynamic(
 dendro = gene_tree,
 method = "tree",
 minClusterSize =10,
 distM =1 - TOM
)
cat("Dynamic tree cut completed.\n")

# Convert numeric labels to colors
module_colors <- WGCNA::labels2colors(dynamic_labels)
cat("Number of modules (pre-merge):", length(unique(module_colors)), "\n")
cat("Module colors:", paste(sort(unique(module_colors)), collapse = ", "), "\n")

# Calculate module eigengenes
MEs <- WGCNA::moduleEigengenes(datExpr, module_colors)$eigengenes
MEs <- WGCNA::orderMEs(MEs)
cat("Module eigengenes calculated.\n")

# Merge similar modules
merge_result <- WGCNA::mergeCloseModules(
 datExpr, module_colors,
 cutHeight =0.25,
 verbose =0
)
merged_colors <- merge_result$colors
merged_MEs <- merge_result$newMEs

n_modules <- length(unique(merged_colors))
cat("Number of modules (post-merge):", n_modules, "\n")
cat("Modules:", paste(sort(unique(merged_colors)), collapse = ", "), "\n")

# Module size summary
module_sizes <- table(merged_colors)
cat("Module sizes:\n")
print(module_sizes)

# ----3. Save module assignment ----
module_df <- data.frame(
 Feature = rownames(expr_matrix),
 Module = merged_colors,
 stringsAsFactors = FALSE
)
module_file <- file.path(tables_dir, "wgcna_module_colors.csv")
write.csv(module_df, module_file, row.names = FALSE)
cat("Module assignments saved to:", module_file, "\n")

# ----4. Save module eigengenes ----
me_file <- file.path(tables_dir, "wgcna_module_eigengenes.csv")
write.csv(cbind(Sample = rownames(merged_MEs), merged_MEs), 
 me_file, row.names = FALSE)
cat("Module eigengenes saved to:", me_file, "\n")

# ----5. Calculate module membership (MM) ----
cat("Calculating module membership...\n")
mm_list <- list()
for (me_name in colnames(merged_MEs)) {
 module_short <- gsub("^ME", "", me_name)
 mm_cor <- stats::cor(
 t(expr_matrix),
 merged_MEs[, me_name, drop = FALSE],
 use = "pairwise.complete.obs"
 )
 mm_list[[module_short]] <- as.numeric(mm_cor)
}

module_membership <- data.frame(
 Feature = rownames(expr_matrix),
 Module = merged_colors,
 as.data.frame(mm_list),
 stringsAsFactors = FALSE
)
colnames(module_membership)[-(1:2)] <- paste0("MM_", names(mm_list))

mm_file <- file.path(tables_dir, "wgcna_module_membership.csv")
write.csv(module_membership, mm_file, row.names = FALSE)
cat("Module membership saved to:", mm_file, "\n")

# ----6. Module-Trait Association ----
cat("Computing module-trait associations...\n")

common_samples <- intersect(rownames(merged_MEs), rownames(all_traits))
MEs_aligned <- merged_MEs[common_samples, , drop = FALSE]
traits_aligned <- all_traits[common_samples, , drop = FALSE]

n_mod <- ncol(MEs_aligned)
n_tr <- ncol(traits_aligned)

cor_matrix <- matrix(NA, nrow = n_mod, ncol = n_tr)
pval_matrix <- matrix(NA, nrow = n_mod, ncol = n_tr)
rownames(cor_matrix) <- colnames(MEs_aligned)
colnames(cor_matrix) <- colnames(traits_aligned)
rownames(pval_matrix) <- colnames(MEs_aligned)
colnames(pval_matrix) <- colnames(traits_aligned)

for (i in 1:n_mod) {
 for (j in 1:n_tr) {
 ct <- stats::cor.test(MEs_aligned[, i], traits_aligned[, j], use = "complete.obs")
 cor_matrix[i, j] <- ct$estimate
 pval_matrix[i, j] <- ct$p.value
 }
}

cor_df <- reshape2::melt(cor_matrix, varnames = c("Module", "Trait"), value.name = "Correlation")
pval_df <- reshape2::melt(pval_matrix, varnames = c("Module", "Trait"), value.name = "pvalue")

cor_df$pvalue <- pval_df$pvalue
cor_df$Significance <- ifelse(cor_df$pvalue <0.001, "***",
 ifelse(cor_df$pvalue <0.01, "**",
 ifelse(cor_df$pvalue <0.05, "*", "")))
cor_df$Module <- gsub("^ME", "", cor_df$Module)

cor_file <- file.path(tables_dir, "wgcna_module_trait_correlation.csv")
write.csv(cor_df, cor_file, row.names = FALSE)
cat("Module-trait correlation saved to:", cor_file, "\n")

# ----7. Module-Trait Heatmap ----
cat("Plotting module-trait heatmap...\n")

key_traits <- c("is_NC", "is_CD", "is_FE")
gsva_trait_names <- setdiff(colnames(traits_aligned), key_traits)
gsva_var <- apply(traits_aligned[, gsva_trait_names, drop = FALSE],2, var, na.rm = TRUE)
top_gsva <- names(sort(gsva_var, decreasing = TRUE))
selected_traits <- c(key_traits, head(top_gsva,10))

plot_traits <- intersect(selected_traits, colnames(traits_aligned))
plot_df <- cor_df[cor_df$Trait %in% plot_traits, ]
plot_df$Trait <- factor(plot_df$Trait, levels = rev(plot_traits))
plot_df$Module <- factor(plot_df$Module, levels = sort(unique(plot_df$Module)))

p_heat <- ggplot(plot_df, aes(x = Trait, y = Module, fill = Correlation)) +
 geom_tile(color = "white", linewidth =0.5) +
 geom_text(aes(label = Significance), size =4, color = "black", vjust =0.7) +
 scale_fill_gradient2(low = "blue", mid = "white", high = "red",
 midpoint =0, limits = c(-1,1), name = "Correlation") +
 labs(title = "Module-Trait Relationship", x = "Trait", y = "Module") +
 theme_minimal(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 axis.text.x = element_text(angle =45, hjust =1, size =9),
 axis.text.y = element_text(size =9),
 panel.grid = element_blank(),
 legend.position = "right")

pdf_heat <- file.path(figures_dir, "Module_trait_heatmap.pdf")
pdf(pdf_heat, width =12, height = max(6, n_modules *0.4))
print(p_heat)
dev.off()
cat("Heatmap PDF:", pdf_heat, "\n")

png_heat <- file.path(figures_dir, "Module_trait_heatmap.png")
png(png_heat, width =12 *300, height = max(6, n_modules *0.4) *300, res =300)
print(p_heat)
dev.off()
cat("Heatmap PNG:", png_heat, "\n")

# ----8. Module Eigengene Barplot ----
cat("Plotting module eigengene barplot...\n")

sample_to_group <- setNames(
 ifelse(traits_aligned$is_FE ==1, "FE",
 ifelse(traits_aligned$is_CD ==1, "CD", "NC")),
 rownames(traits_aligned)
)

me_long <- data.frame(
 Sample = rep(rownames(MEs_aligned), each = ncol(MEs_aligned)),
 Module = rep(gsub("^ME", "", colnames(MEs_aligned)), times = nrow(MEs_aligned)),
 ME_value = as.numeric(unlist(MEs_aligned)),
 Group = rep(sample_to_group[rownames(MEs_aligned)], each = ncol(MEs_aligned)),
 stringsAsFactors = FALSE
)

me_summary <- aggregate(ME_value ~ Module + Group, data = me_long,
 FUN = function(x) c(mean = mean(x), se = sd(x)/sqrt(length(x))))
me_summary <- do.call(data.frame, me_summary)
colnames(me_summary) <- c("Module", "Group", "Mean", "SE")

sig_modules <- unique(cor_df$Module[cor_df$Trait %in% key_traits & cor_df$pvalue <0.05])
if (length(sig_modules) >0) {
 me_summary <- me_summary[me_summary$Module %in% sig_modules, ]
}
me_summary$Group <- factor(me_summary$Group, levels = c("NC", "CD", "FE"))

p_bar <- ggplot(me_summary, aes(x = Module, y = Mean, fill = Group)) +
 geom_bar(stat = "identity", position = position_dodge(width =0.8), width =0.7) +
 geom_errorbar(aes(ymin = Mean - SE, ymax = Mean + SE),
 position = position_dodge(width =0.8), width =0.2) +
 scale_fill_manual(values = c("NC" = "#4DAF4A", "CD" = "#E41A1C", "FE" = "#377EB8")) +
 labs(title = "Module Eigengene Expression by Group",
 x = "Module", y = "Module Eigengene (mean +/- SE)") +
 theme_bw(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 axis.text.x = element_text(angle =45, hjust =1))

pdf_bar <- file.path(figures_dir, "Module_eigengene_barplot.pdf")
pdf(pdf_bar, width = max(8, length(unique(me_summary$Module)) *0.6), height =6)
print(p_bar)
dev.off()
cat("Barplot PDF:", pdf_bar, "\n")

png_bar <- file.path(figures_dir, "Module_eigengene_barplot.png")
png(png_bar, width = max(8, length(unique(me_summary$Module)) *0.6) *300, 
 height =6 *300, res =300)
print(p_bar)
dev.off()
cat("Barplot PNG:", png_bar, "\n")

# ----9. Module dendrogram ----
cat("Plotting module dendrogram...\n")

pdf_dendro <- file.path(figures_dir, "Module_dendrogram.pdf")
pdf(pdf_dendro, width =12, height =6)
WGCNA::plotDendroAndColors(
 gene_tree, merged_colors,
 groupLabels = "Module Colors",
 dendroLabels = FALSE,
 hang =0.03, addGuide = TRUE, guideHang =0.05,
 main = "Gene (Metabolite) Cluster Dendrogram")
dev.off()
cat("Dendrogram PDF:", pdf_dendro, "\n")

png_dendro <- file.path(figures_dir, "Module_dendrogram.png")
png(png_dendro, width =12 *300, height =6 *300, res =300)
WGCNA::plotDendroAndColors(
 gene_tree, merged_colors,
 groupLabels = "Module Colors",
 dendroLabels = FALSE,
 hang =0.03, addGuide = TRUE, guideHang =0.05,
 main = "Gene (Metabolite) Cluster Dendrogram")
dev.off()
cat("Dendrogram PNG:", png_dendro, "\n")

# ----10. Module-Trait Linear Regression ----
cat("Running module-trait linear regression...\n")

reg_results_list <- list()
for (mod_name in colnames(MEs_aligned)) {
 mod_short <- gsub("^ME", "", mod_name)
 df <- data.frame(
 ME = MEs_aligned[, mod_name],
 is_CD = traits_aligned$is_CD,
 is_FE = traits_aligned$is_FE,
 is_NC = traits_aligned$is_NC
 )
 fit <- stats::lm(ME ~ is_FE + is_NC, data = df)
 s <- summary(fit)
 coefs <- coef(s)
 
 reg_results_list[[mod_name]] <- data.frame(
 Module = mod_short,
 Term = rownames(coefs),
 Estimate = coefs[, "Estimate"],
 StdError = coefs[, "Std. Error"],
 t_value = coefs[, "t value"],
 p_value = coefs[, "Pr(>|t|)"],
 R_squared = s$r.squared,
 Adj_R_squared = s$adj.r.squared,
 stringsAsFactors = FALSE
 )
}

reg_results <- do.call(rbind, reg_results_list)
reg_results$p_adj <- stats::p.adjust(reg_results$p_value, method = "BH")

reg_file <- file.path(tables_dir, "wgcna_module_trait_regression.csv")
write.csv(reg_results, reg_file, row.names = FALSE)
cat("Regression results saved to:", reg_file, "\n")

# ----11. Hub Network Visualization for Key Modules ----
cat("Creating hub network visualizations for key modules...\n")

sig_mods_for_hub <- unique(cor_df$Module[
 cor_df$Trait %in% c("is_FE", "is_CD") & 
 cor_df$pvalue <0.05 & 
 abs(cor_df$Correlation) >0.5
])

if (length(sig_mods_for_hub) ==0) {
 cat("No highly significant modules. Using top modules by FE correlation...\n")
 fe_cor <- cor_df[cor_df$Trait == "is_FE", ]
 sig_mods_for_hub <- head(fe_cor$Module[order(-abs(fe_cor$Correlation))],3)
}

cat("Key modules for hub network:", paste(sig_mods_for_hub, collapse = ", "), "\n")

for (mod_name in sig_mods_for_hub) {
 cat(" Plotting hub network for module:", mod_name, "\n")
 
 genes_in_mod <- rownames(expr_matrix)[merged_colors == mod_name]
 cat(" Genes in module:", length(genes_in_mod), "\n")
 
 if (length(genes_in_mod) <3) {
 cat(" Too few genes, skipping.\n")
 next
 }
 
 gene_idx <- which(merged_colors == mod_name)
 connectivity <- rowSums(TOM[gene_idx, gene_idx], na.rm = TRUE)
 names(connectivity) <- genes_in_mod
 
 n_hubs <- max(3, min(30, ceiling(length(genes_in_mod) *0.3)))
 hub_genes <- names(sort(connectivity, decreasing = TRUE))[1:n_hubs]
 cat(" Hub genes selected:", n_hubs, "\n")
 
 tom_hub <- TOM[match(hub_genes, rownames(expr_matrix)), 
 match(hub_genes, rownames(expr_matrix))]
 rownames(tom_hub) <- hub_genes
 colnames(tom_hub) <- hub_genes
 
 threshold <- stats::quantile(tom_hub[tom_hub >0], probs =0.7, na.rm = TRUE)
 
 g <- igraph::graph.adjacency(tom_hub > threshold, mode = "undirected", diag = FALSE)
 
 if (igraph::vcount(g) ==0) {
 cat(" No edges after threshold, skipping.\n")
 next
 }
 
 set.seed(42)
 layout <- igraph::layout_with_fr(g)
 
 igraph::V(g)$size <- connectivity[hub_genes] / max(connectivity[hub_genes]) *15 +5
 igraph::V(g)$color <- mod_name
 short_labels <- substr(hub_genes,1,20)
 igraph::V(g)$label <- short_labels
 
 pdf_hub <- file.path(figures_dir, paste0("Hub_network_", mod_name, ".pdf"))
 pdf(pdf_hub, width =10, height =8)
 plot(g, layout = layout,
 vertex.label = igraph::V(g)$label,
 vertex.size = igraph::V(g)$size,
 vertex.color = igraph::V(g)$color,
 vertex.frame.color = "gray50",
 vertex.label.color = "black",
 vertex.label.cex =0.6,
 edge.width = igraph::E(g)$weight *3,
 edge.color = rgb(0.5,0.5,0.5,0.3),
 main = paste("Hub Network -", mod_name, "Module"))
 dev.off()
 cat(" Hub network PDF:", pdf_hub, "\n")
 
 png_hub <- file.path(figures_dir, paste0("Hub_network_", mod_name, ".png"))
 png(png_hub, width =10 *300, height =8 *300, res =300)
 plot(g, layout = layout,
 vertex.label = igraph::V(g)$label,
 vertex.size = igraph::V(g)$size,
 vertex.color = igraph::V(g)$color,
 vertex.frame.color = "gray50",
 vertex.label.color = "black",
 vertex.label.cex =0.6,
 edge.width = igraph::E(g)$weight *3,
 edge.color = rgb(0.5,0.5,0.5,0.3),
 main = paste("Hub Network -", mod_name, "Module"))
 dev.off()
 cat(" Hub network PNG:", png_hub, "\n")
}

# ----12. Save for next step ----
rdata_file2 <- file.path(base_dir, "wgcna_step2_data.RData")
save(merged_colors, merged_MEs, gene_tree, TOM, adjacency,
 module_df, module_sizes, cor_matrix, pval_matrix, cor_df,
 reg_results, module_membership, MEs_aligned, traits_aligned,
 sample_to_group, file = rdata_file2)
cat("Step2 data saved to:", rdata_file2, "\n")

cat("\n=== WGCNA Step2 completed successfully! ===\n")
cat("Modules identified:", n_modules, "\n")
