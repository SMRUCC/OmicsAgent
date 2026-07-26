# ============================================================
# KEGG Functional Analysis - Step3: GSVA & Visualization
# ============================================================
# This script performs:
#1. GSVA analysis (gene set variation analysis) using KEGG pathways
#2. LIMMA differential analysis on GSVA scores (3 comparisons)
#3. Visualization: heatmap, volcano plots, boxplots
# ============================================================

options(repos = c(CRAN = "https://cloud.r-project.org"))
options(BioC_mirror = "https://bioconductor.org")

# Load/install packages
for (pkg in c("GSVA", "limma", "ggplot2", "grDevices", "stats", "utils", 
 "ggrepel", "RColorBrewer", "ComplexHeatmap", "circlize", "grid")) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 if (pkg %in% c("GSVA", "limma", "ComplexHeatmap")) {
 if (!requireNamespace("BiocManager", quietly = TRUE))
 install.packages("BiocManager")
 BiocManager::install(pkg, ask = FALSE, update = FALSE)
 } else {
 install.packages(pkg, dependencies = TRUE)
 }
 }
 library(pkg, character.only = TRUE)
}

# Source helper scripts
source("G:/OmicsWorks/agent/rscript/enrichment.R")
source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/differential.R")

# ---- Paths ----
BASE_DIR <- "G:/OmicsWorks/test/metabolism/demo"
EXPR_FILE <- file.path(BASE_DIR, "tmp/preprocessed_expression.csv")
META_FILE <- "G:/OmicsWorks/test/metabolism/metabolites.csv"
SAMPLEINFO_FILE <- file.path(BASE_DIR, "tmp/1_expression_matrix_preprocessing/sampleinfo.csv")
COMPARISON_FILE <- file.path(BASE_DIR, "tmp/3_comparison_group_design/tables/comparison_design.csv")
OUT_DIR <- file.path(BASE_DIR, "tmp/5_kegg_functional_analysis")
TABLES_DIR <- file.path(OUT_DIR, "tables")
FIGURES_DIR <- file.path(BASE_DIR, "analysis/5_kegg_functional_analysis/figures")
for (d in c(OUT_DIR, TABLES_DIR, FIGURES_DIR)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

cat("========================================\n")
cat("GSVA Analysis - Step3\n")
cat("========================================\n\n")

# ======1. Load data ======
cat("1. Loading expression matrix...\n")
expr_raw <- read.csv(EXPR_FILE, row.names =1, check.names = FALSE)
expr_mat <- as.matrix(expr_raw)
cat(" Dim:", nrow(expr_mat), "x", ncol(expr_mat), "\n")

cat("2. Loading sample metadata...\n")
sample_meta <- read.csv(SAMPLEINFO_FILE, stringsAsFactors = FALSE)
rownames(sample_meta) <- sample_meta$ID
sample_meta_bio <- sample_meta[sample_meta$sample_info != "QC", , drop = FALSE]
bio_samples <- intersect(colnames(expr_mat), sample_meta_bio$ID)
expr_mat <- expr_mat[, bio_samples, drop = FALSE]
sample_meta_bio <- sample_meta_bio[bio_samples, , drop = FALSE]
cat(" Biological samples:", nrow(sample_meta_bio), "\n")
print(table(sample_meta_bio$sample_info))

cat("\n3. Loading metabolite annotations...\n")
metab_anno <- read.csv(META_FILE, stringsAsFactors = FALSE)
rownames(metab_anno) <- make.unique(as.character(metab_anno$name))
common_names <- intersect(rownames(expr_mat), metab_anno$name)
expr_mat <- expr_mat[rownames(expr_mat) %in% common_names, , drop = FALSE]
anno_idx <- match(rownames(expr_mat), metab_anno$name)
metab_anno_sub <- metab_anno[anno_idx, , drop = FALSE]
rownames(metab_anno_sub) <- rownames(expr_mat)
cat(" Matched metabolites:", nrow(expr_mat), "\n")

# ======2. Build KEGG gene sets ======
cat("\n4. Building KEGG gene sets from annotations...\n")
split_field <- function(x) {
 if (is.na(x) || x == "" || x == "") return(character(0))
 parts <- trimws(unlist(strsplit(as.character(x), ";")))
 parts[parts != "" & parts != ""]
}

pathway_to_metab <- list()
pathway_to_class <- list()

for (i in seq_len(nrow(metab_anno_sub))) {
 feat <- rownames(metab_anno_sub)[i]
 cats <- split_field(metab_anno_sub$kegg_category[i])
 if (length(cats) ==0) next
 for (cn in cats) {
 if (is.null(pathway_to_metab[[cn]])) pathway_to_metab[[cn]] <- c()
 pathway_to_metab[[cn]] <- c(pathway_to_metab[[cn]], feat)
 }
 cls <- split_field(metab_anno_sub$kegg_class[i])
 if (length(cls) >0) {
 for (j in seq_along(cats)) {
 if (j <= length(cls) && is.null(pathway_to_class[[cats[j]]]))
 pathway_to_class[[cats[j]]] <- cls[j]
 }
 }
}

# Remove empty named keys
pathway_to_metab[[""]] <- NULL
pathway_to_metab[[""]] <- NULL

# Filter by pathway size
min_size <-3
max_size <-200
pw_sizes <- sapply(pathway_to_metab, length)
pathway_to_metab <- pathway_to_metab[pw_sizes >= min_size & pw_sizes <= max_size]

# Build gene sets list for GSVA
gene_sets <- lapply(pathway_to_metab, function(x) intersect(x, rownames(expr_mat)))
gene_sets <- gene_sets[sapply(gene_sets, length) >= min_size]

n_metab_with_pathway <- length(unique(unlist(gene_sets)))
cat(" KEGG pathways:", length(gene_sets), "\n")
cat(" Metabolites mapped:", n_metab_with_pathway, "/", nrow(expr_mat), 
 sprintf("(%.1f%%)", n_metab_with_pathway/nrow(expr_mat)*100), "\n")

for (nm in names(sort(sapply(gene_sets, length), decreasing = TRUE))) {
 cls <- ifelse(is.null(pathway_to_class[[nm]]), "", gsub("^[0-9]+\\s*", "", pathway_to_class[[nm]]))
 cat(" ", nm, ":", length(gene_sets[[nm]]), "metabolites [", cls, "]\n")
}

# ======3. Run GSVA ======
cat("\n========================================\n")
cat("5. Running GSVA...\n")
cat("========================================\n\n")

cat(" Calling perform_gsva() from enrichment.R...\n")
gsva_scores <- perform_gsva(
 expr_matrix = expr_mat,
 gene_sets = gene_sets,
 method = "gsva",
 kcdf = "Gaussian",
 min_sz = min_size,
 max_sz = max_size
)

cat(" GSVA result:", nrow(gsva_scores), "pathways x", ncol(gsva_scores), "samples\n")

# Save GSVA scores
gsva_df <- cbind(Pathway = rownames(gsva_scores), as.data.frame(gsva_scores))
write.csv(gsva_df, file.path(TABLES_DIR, "kegg_gsva_scores.csv"), row.names = FALSE)
cat(" Saved: kegg_gsva_scores.csv\n")

# ======4. GSVA Differential Analysis ======
cat("\n========================================\n")
cat("6. GSVA Differential Analysis (LIMMA)\n")
cat("========================================\n\n")

# Create valid group names for limma
sample_meta_bio$group_valid <- make.names(sample_meta_bio$sample_info)
group_map <- unique(sample_meta_bio[, c("sample_info", "group_valid")])

comp_info <- read.csv(COMPARISON_FILE, stringsAsFactors = FALSE)
comparisons <- c("FE_vs_CD", "CD_vs_NC", "FE_vs_NC")

gsva_de_results <- list()

for (comp in comparisons) {
 cat("--- Comparison:", comp, "---\n")
  
 comp_row <- comp_info[comp_info$comparison_name == comp, ]
 if (nrow(comp_row) ==0) { cat(" Not found. Skip.\n"); next }
  
 trt_orig <- comp_row$treatment_group[1]
 ctrl_orig <- comp_row$control_group[1]
  
 trt <- group_map$group_valid[group_map$sample_info == trt_orig]
 ctrl <- group_map$group_valid[group_map$sample_info == ctrl_orig]
  
 cat(" ", trt_orig, "vs", ctrl_orig, "\n")
  
 if (length(trt) ==0 || length(ctrl) ==0) { cat(" Group not found.\n"); next }
  
 # Design matrix
 groups_valid <- factor(sample_meta_bio$group_valid)
 design <- model.matrix(~0 + groups_valid)
 colnames(design) <- levels(groups_valid)
  
 # Contrast
 cm <- limma::makeContrasts(contrasts = paste0(trt, " - ", ctrl), levels = design)
  
 # LIMMA
 fit <- limma::lmFit(gsva_scores, design)
 fit2 <- limma::eBayes(limma::contrasts.fit(fit, cm))
 tt <- limma::topTable(fit2, number = Inf, adjust.method = "BH", sort.by = "none")
  
 # Build result
 result <- data.frame(
 Pathway = rownames(tt),
 Class = sapply(rownames(tt), function(p) {
 ifelse(is.null(pathway_to_class[[p]]), "", pathway_to_class[[p]])
 }),
 logFC = tt$logFC,
 AveExpr = tt$AveExpr,
 t_statistic = tt$t,
 pvalue = tt$P.Value,
 pvalue_adj = tt$adj.P.Val,
 stringsAsFactors = FALSE
 )
 result$significant <- result$pvalue_adj <0.05
 result$Direction <- ifelse(result$significant & result$logFC >0, "Up",
 ifelse(result$significant & result$logFC <0, "Down", "Not Significant"))
  
 gsva_de_results[[comp]] <- result
  
 n_sig <- sum(result$significant)
 n_up <- sum(result$significant & result$logFC >0)
 n_down <- sum(result$significant & result$logFC <0)
 cat(" Significant (FDR<0.05):", n_sig, "/", nrow(result), 
 "(Up:", n_up, "Down:", n_down, ")\n")
  
 # Print top significant pathways
 if (n_sig >0) {
 top_sig <- head(result[result$significant, , drop = FALSE][order(result$pvalue_adj[result$significant]), ],5)
 for (i in 1:nrow(top_sig)) {
 cat(" ", gsub("^[0-9]+\\s*", "", top_sig$Pathway[i]), 
 "| logFC =", format(top_sig$logFC[i], digits =3),
 "| adj.P =", format(top_sig$pvalue_adj[i], digits =4), "\n")
 }
 }
  
 # Save
 write.csv(result, file.path(TABLES_DIR, paste0("kegg_gsva_differential_", comp, ".csv")),
 row.names = FALSE)
 cat(" Saved.\n\n")
}

# ======5. GSVA Heatmap ======
cat("\n========================================\n")
cat("7. Visualization\n")
cat("========================================\n\n")

cat("7a. GSVA Heatmap...\n")

sample_order <- sample_meta_bio$ID[order(sample_meta_bio$sample_info)]
gsva_plot <- gsva_scores[, sample_order, drop = FALSE]

# Map pathway class
pathway_cats <- sapply(rownames(gsva_plot), function(p) {
 cls <- ifelse(is.null(pathway_to_class[[p]]), "", pathway_to_class[[p]])
 cls <- gsub("^[0-9]+\\s*", "", cls)
 ifelse(cls == "", "Unclassified", cls)
})
pathway_cats[is.na(pathway_cats)] <- "Unclassified"

# Order by class, then hierarchical clustering within each class
cat_order <- order(pathway_cats)
gsva_plot <- gsva_plot[cat_order, , drop = FALSE]
pathway_cats <- pathway_cats[cat_order]

# Colors
n_cats <- length(unique(pathway_cats))
cat_colors <- setNames(
 brewer.pal(min(n_cats,12), "Set3")[1:n_cats],
 unique(pathway_cats)
)

group_levels <- levels(factor(sample_meta_bio$sample_info))
group_colors <- setNames(brewer.pal(length(group_levels), "Set1"), group_levels)

# Annotations
row_ha <- rowAnnotation(
 Category = pathway_cats,
 col = list(Category = cat_colors),
 show_annotation_name = FALSE,
 annotation_name_gp = gpar(fontsize =8)
)

col_ha <- HeatmapAnnotation(
 Group = sample_meta_bio[sample_order, "sample_info"],
 col = list(Group = group_colors),
 show_annotation_name = FALSE
)

# Color scale
max_abs <- max(abs(gsva_plot), na.rm = TRUE)
col_fun <- colorRamp2(c(-max_abs,0, max_abs), c("#4DBBD5", "white", "#E64B35"))

# Draw heatmap
ht <- Heatmap(
 gsva_plot,
 name = "GSVA Score",
 col = col_fun,
 top_annotation = col_ha,
 right_annotation = row_ha,
 show_row_names = TRUE,
 show_column_names = TRUE,
 column_names_gp = gpar(fontsize =8),
 row_names_gp = gpar(fontsize =7),
 row_split = pathway_cats,
 cluster_rows = TRUE,
 cluster_columns = FALSE,
 row_title_gp = gpar(fontsize =10),
 row_gap = unit(4, "mm"),
 column_title = "GSVA Pathway Activity",
 column_title_gp = gpar(fontsize =14, fontface = "bold"),
 heatmap_legend_param = list(title = "GSVA\nScore")
)

h <- max(8, nrow(gsva_plot) *0.12) +3
pdf(file.path(FIGURES_DIR, "GSVA_heatmap.pdf"), width =14, height = h)
draw(ht, heatmap_legend_side = "right")
dev.off()

png(file.path(FIGURES_DIR, "GSVA_heatmap.png"), width =14 *300, height = h *300, res =300)
draw(ht, heatmap_legend_side = "right")
dev.off()
cat(" Heatmap saved.\n")

# ======6. Volcano Plots ======
cat("\n7b. GSVA Volcano Plots...\n")
for (comp in comparisons) {
 res <- gsva_de_results[[comp]]
 if (is.null(res) || nrow(res) ==0) next
  
 res$neg_log10_p <- -log10(res$pvalue_adj)
  
 # Label top pathways
 sig_only <- res[res$significant, , drop = FALSE]
 if (nrow(sig_only) >0) {
 top_sig <- head(sig_only[order(abs(sig_only$logFC), decreasing = TRUE), ],10)
 res$label <- ifelse(res$Pathway %in% top_sig$Pathway,
 gsub("^[0-9]+\\s*", "", res$Pathway), "")
 } else {
 # Label top3 by logFC magnitude
 top3 <- head(res[order(abs(res$logFC), decreasing = TRUE), ],3)
 res$label <- ifelse(res$Pathway %in% top3$Pathway,
 gsub("^[0-9]+\\s*", "", res$Pathway), "")
 }
  
 n_up <- sum(res$significant & res$logFC >0)
 n_down <- sum(res$significant & res$logFC <0)
  
 p <- ggplot(res, aes(x = logFC, y = neg_log10_p, color = Direction)) +
 geom_point(aes(size = ifelse(significant,3,1.5)), alpha =0.7) +
 scale_size_identity() +
 geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "grey40", size =0.5) +
 geom_vline(xintercept =0, linetype = "dashed", color = "grey40", size =0.5) +
 geom_text_repel(aes(label = label), size =3.2, max.overlaps =20,
 box.padding =0.5, show.legend = FALSE, fontface = "bold") +
 scale_color_manual(
 values = c("Up" = "#E64B35", "Down" = "#4DBBD5", "Not Significant" = "grey75"),
 labels = c("Up" = paste0("Up (", n_up, ")"),
 "Down" = paste0("Down (", n_down, ")"),
 "Not Significant" = paste0("NS (", sum(!res$significant), ")"))
 ) +
 labs(
 title = paste0("GSVA Differential Pathways - ", comp),
 subtitle = paste0("FE (high iron diet before) vs CD (Clostridium difficile infection)"),
 x = "log2(Fold Change)", y = expression(-log[10](adjusted ~ P ~ value)),
 color = "Direction"
 ) +
 theme_bw(base_size =12) +
 theme(
 plot.title = element_text(hjust =0.5, face = "bold"),
 plot.subtitle = element_text(hjust =0.5, size =9, color = "grey40"),
 legend.position = "right"
 )
  
 pdf(file.path(FIGURES_DIR, paste0("GSVA_volcano_", comp, ".pdf")), width =10, height =8)
 print(p); dev.off()
  
 png(file.path(FIGURES_DIR, paste0("GSVA_volcano_", comp, ".png")),
 width =10 *300, height =8 *300, res =300)
 print(p); dev.off()
  
 cat(" Volcano plot saved:", comp, "\n")
}

# ======7. Boxplots ======
cat("\n7c. GSVA Boxplots for Significant Pathways...\n")
for (comp in comparisons) {
 res <- gsva_de_results[[comp]]
 if (is.null(res) || sum(res$significant) ==0) {
 cat(" No significant pathways for", comp, "\n")
 next
 }
  
 # Take top20 significant pathways max
 sig_pathways <- res$Pathway[res$significant]
 if (length(sig_pathways) >20) {
 sig_pathways <- sig_pathways[order(res$pvalue_adj[res$significant])][1:20]
 }
  
 # Gather data
 score_list <- list()
 for (pw in sig_pathways) {
 if (!pw %in% rownames(gsva_scores)) next
 for (sid in colnames(gsva_scores)) {
 grp <- sample_meta_bio[sid, "sample_info"]
 score_list[[length(score_list) +1]] <- data.frame(
 Pathway = gsub("^[0-9]+\\s*", "", substr(pw,1,50)),
 Group = grp,
 Score = gsva_scores[pw, sid],
 stringsAsFactors = FALSE
 )
 }
 }
 if (length(score_list) ==0) next
 scores_df <- do.call(rbind, score_list)
 scores_df$Group <- factor(scores_df$Group, levels = levels(factor(sample_meta_bio$sample_info)))
  
 p <- ggplot(scores_df, aes(x = Group, y = Score, fill = Group)) +
 geom_boxplot(outlier.shape = NA, alpha =0.7, color = "grey30", size =0.4) +
 geom_jitter(width =0.15, size =1.5, alpha =0.5, color = "grey30") +
 facet_wrap(~ Pathway, scales = "free_y", ncol = min(4, length(sig_pathways))) +
 scale_fill_manual(values = group_colors) +
 labs(
 title = paste0("GSVA Scores - Significant Pathways (", comp, ")"),
 x = "Group", y = "GSVA Score"
 ) +
 theme_bw(base_size =10) +
 theme(
 plot.title = element_text(hjust =0.5, face = "bold", size =12),
 axis.text.x = element_text(angle =45, hjust =1, size =7),
 axis.title = element_text(size =10),
 strip.text = element_text(size =7, face = "bold"),
 legend.position = "none"
 )
  
 n_col <- min(4, length(sig_pathways))
 n_row <- ceiling(length(sig_pathways) / n_col)
 w <- max(8, n_col *4)
 h <- max(6, n_row *3.5)
  
 pdf(file.path(FIGURES_DIR, paste0("GSVA_boxplot_", comp, ".pdf")), width = w, height = h)
 print(p); dev.off()
  
 png(file.path(FIGURES_DIR, paste0("GSVA_boxplot_", comp, ".png")),
 width = w *300, height = h *300, res =300)
 print(p); dev.off()
  
 cat(" Boxplot saved:", comp, "-", length(sig_pathways), "pathways\n")
}

# ====== Summary ======
cat("\n========================================\n")
cat("GSVA Analysis Complete!\n")
cat("========================================\n\n")

cat("GSVA Results Summary:\n")
for (comp in comparisons) {
 res <- gsva_de_results[[comp]]
 if (is.null(res)) next
 n_sig <- sum(res$significant)
 n_up <- sum(res$significant & res$logFC >0)
 n_down <- sum(res$significant & res$logFC <0)
 cat(" ", comp, ":", n_sig, "significant (", n_up, "up,", n_down, "down)\n")
 if (n_sig >0) {
 cat(" Top pathways:\n")
 for (i in 1:min(5, n_sig)) {
 idx <- which(res$significant)[i]
 cat(" -", gsub("^[0-9]+\\s*", "", res$Pathway[idx]),
 "| logFC =", format(res$logFC[idx], digits =3),
 "| adj.P =", format(res$pvalue_adj[idx], digits =4), "\n")
 }
 }
}

cat("\nOutput files:\n")
cat(" Tables:", TABLES_DIR, "\n")
for (f in list.files(TABLES_DIR, pattern = "kegg_gsva")) cat(" ", f, "\n")
cat(" Figures:", FIGURES_DIR, "\n")
for (f in list.files(FIGURES_DIR, pattern = "GSVA")) cat(" ", f, "\n")

cat("\n========================================\n")
cat("Step3 Complete!\n")
cat("========================================\n")
