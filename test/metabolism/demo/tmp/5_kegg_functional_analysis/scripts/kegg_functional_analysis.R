# ============================================================
# KEGG Functional Analysis (Fixed v2)
# ============================================================

options(repos = c(CRAN = "https://cloud.r-project.org"))
options(BioC_mirror = "https://bioconductor.org")

required_pkgs <- c("GSVA", "limma", "ggplot2", "grDevices", "stats", 
 "utils", "ggrepel", "RColorBrewer")
for (pkg in required_pkgs) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 if (pkg %in% c("GSVA", "limma")) {
 if (!requireNamespace("BiocManager", quietly = TRUE))
 install.packages("BiocManager")
 BiocManager::install(pkg, ask = FALSE, update = FALSE)
 } else {
 install.packages(pkg, dependencies = TRUE)
 }
 }
 library(pkg, character.only = TRUE)
}

if (!requireNamespace("ComplexHeatmap", quietly = TRUE)) {
 if (!requireNamespace("BiocManager", quietly = TRUE))
 install.packages("BiocManager")
 BiocManager::install("ComplexHeatmap", ask = FALSE, update = FALSE)
}
library(ComplexHeatmap)
library(circlize)
library(grid)

BASE_DIR <- "G:/OmicsWorks/test/metabolism/demo"
EXPR_FILE <- file.path(BASE_DIR, "tmp/preprocessed_expression.csv")
META_FILE <- "G:/OmicsWorks/test/metabolism/metabolites.csv"
SAMPLEINFO_FILE <- file.path(BASE_DIR, "tmp/1_expression_matrix_preprocessing/sampleinfo.csv")
COMPARISON_FILE <- file.path(BASE_DIR, "tmp/3_comparison_group_design/tables/comparison_design.csv")
LIMMA_ALL_FILE <- file.path(BASE_DIR, "tmp/4_limma_differential_analysis/tables/limma_all_comparisons_consolidated.csv")
OUT_DIR <- file.path(BASE_DIR, "tmp/5_kegg_functional_analysis")
TABLES_DIR <- file.path(OUT_DIR, "tables")
FIGURES_DIR <- file.path(BASE_DIR, "analysis/5_kegg_functional_analysis/figures")

for (d in c(OUT_DIR, TABLES_DIR, FIGURES_DIR, file.path(OUT_DIR, "scripts"))) {
 if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

cat("========================================\n")
cat("KEGG Functional Analysis v2\n")
cat("========================================\n\n")

# ======1. Load Data ======
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
cat(" Bio samples:", nrow(sample_meta_bio), "\n")
print(table(sample_meta_bio$sample_info))

# Create syntactically valid group names (replace spaces with dots)
sample_meta_bio$group_valid <- make.names(sample_meta_bio$sample_info)
cat("\n Valid group names:\n")
print(unique(sample_meta_bio$group_valid))

cat("\n3. Loading metabolite annotations...\n")
metab_anno <- read.csv(META_FILE, stringsAsFactors = FALSE)
rownames(metab_anno) <- make.unique(as.character(metab_anno$name))
cat(" Rows:", nrow(metab_anno), "\n")

# Match by name
common_names <- intersect(rownames(expr_mat), metab_anno$name)
expr_mat <- expr_mat[rownames(expr_mat) %in% common_names, , drop = FALSE]
anno_idx <- match(rownames(expr_mat), metab_anno$name)
metab_anno_sub <- metab_anno[anno_idx, , drop = FALSE]
rownames(metab_anno_sub) <- rownames(expr_mat)
cat(" Matched:", nrow(expr_mat), "metabolites\n")

# ======2. Build KEGG Background ======
cat("\n4. Building KEGG pathway background...\n")
split_field <- function(x) {
 if (is.na(x) || x == "" || x == "") return(character(0))
 parts <- trimws(unlist(strsplit(as.character(x), ";")))
 parts <- parts[parts != "" & parts != ""]
 return(parts)
}

pathway_to_metab <- list()
pathway_to_class <- list()

for (i in seq_len(nrow(metab_anno_sub))) {
 feat <- rownames(metab_anno_sub)[i]
 cats <- split_field(metab_anno_sub$kegg_category[i])
 if (length(cats) ==0) next
 for (cat_name in cats) {
 if (is.null(pathway_to_metab[[cat_name]])) pathway_to_metab[[cat_name]] <- c()
 pathway_to_metab[[cat_name]] <- c(pathway_to_metab[[cat_name]], feat)
 }
 cls <- split_field(metab_anno_sub$kegg_class[i])
 if (length(cls) >0) {
 for (j in seq_along(cats)) {
 if (j <= length(cls)) {
 if (is.null(pathway_to_class[[cats[j]]])) pathway_to_class[[cats[j]]] <- cls[j]
 }
 }
 }
}

# Remove NULL/empty named pathway
if ("" %in% names(pathway_to_metab)) {
 cat(" Removing '' named pathway...\n")
 pathway_to_metab[[""]] <- NULL
 pathway_to_class[[""]] <- NULL
}
if ("" %in% names(pathway_to_metab)) {
 pathway_to_metab[[""]] <- NULL
 pathway_to_class[[""]] <- NULL
}

cat(" Unique KEGG pathways:", length(pathway_to_metab), "\n")
pw_sizes <- sapply(pathway_to_metab, length)

# Display top
for (nm in names(head(sort(pw_sizes, decreasing = TRUE),20))) {
 cat(" ", nm, ":", pw_sizes[nm], "\n")
}

min_size <-3
max_size <-200
pathway_to_metab <- pathway_to_metab[pw_sizes >= min_size & pw_sizes <= max_size]
cat("\n After size filter:", length(pathway_to_metab), "pathways\n")

metab_with_pathway <- unique(unlist(pathway_to_metab))
cat(" Metabolites with pathway:", length(metab_with_pathway), "/", nrow(expr_mat), "\n")

pw_bg <- data.frame(
 Pathway = names(pathway_to_metab),
 Class = sapply(names(pathway_to_metab), function(p) {
 if (is.null(pathway_to_class[[p]])) "" else pathway_to_class[[p]]
 }),
 N_Metabolites = sapply(pathway_to_metab, length),
 stringsAsFactors = FALSE
)
write.csv(pw_bg, file.path(TABLES_DIR, "kegg_pathway_background.csv"), row.names = FALSE)

# ======3. Load DE results ======
cat("\n5. Loading differential analysis results...\n")
limma_all <- read.csv(LIMMA_ALL_FILE, stringsAsFactors = FALSE)

comparisons <- c("FE_vs_CD", "CD_vs_NC", "FE_vs_NC")
sig_lists <- list()
for (comp in comparisons) {
 sig_col <- paste0("sig_", comp)
 if (sig_col %in% colnames(limma_all)) {
 sig_lists[[comp]] <- limma_all$Feature[which(limma_all[[sig_col]] == TRUE)]
 } else {
 sig_lists[[comp]] <- character(0)
 }
 cat(" ", comp, ":", length(sig_lists[[comp]]), "significant\n")
}

# ======4. Enrichment (Fisher exact test) ======
cat("\n========================================\n")
cat("Step2: KEGG Enrichment\n")
cat("========================================\n\n")

enrich_results <- list()
for (comp in comparisons) {
 cat("---", comp, "---\n")
 sig_feats <- sig_lists[[comp]]
 if (length(sig_feats) <2) { cat(" Skip (too few).\n"); enrich_results[[comp]] <- data.frame(); next }
 
 sig_pw <- intersect(sig_feats, metab_with_pathway)
 bg_pw <- intersect(rownames(expr_mat), metab_with_pathway)
 if (length(sig_pw) <2) { cat(" Skip (too few with pathway).\n"); enrich_results[[comp]] <- data.frame(); next }
 
 res_list <- list()
 for (pw in names(pathway_to_metab)) {
 feats_in_pw <- pathway_to_metab[[pw]]
 in_pw_and_sig <- length(intersect(feats_in_pw, sig_pw))
 if (in_pw_and_sig <1) next
 in_pw_not_sig <- length(feats_in_pw) - in_pw_and_sig
 not_in_pw_sig <- length(sig_pw) - in_pw_and_sig
 not_in_pw_not_sig <- length(bg_pw) - length(feats_in_pw) - not_in_pw_sig
 
 ft <- tryCatch(fisher.test(matrix(c(in_pw_and_sig, in_pw_not_sig, not_in_pw_sig, not_in_pw_not_sig),2), 
 alternative = "greater"), error = function(e) NULL)
 if (is.null(ft)) next
 
 res_list[[length(res_list)+1]] <- data.frame(
 Pathway = pw,
 Class = ifelse(is.null(pathway_to_class[[pw]]), "", pathway_to_class[[pw]]),
 Count_in_Sig = in_pw_and_sig,
 Count_in_BG = length(feats_in_pw),
 pvalue = ft$p.value, stringsAsFactors = FALSE)
 }
 if (length(res_list)==0) { enrich_results[[comp]] <- data.frame(); cat(" No enrichment.\n"); next }
 
 result <- do.call(rbind, res_list)
 result$pvalue_adj <- p.adjust(result$pvalue, "BH")
 result$enriched <- result$pvalue_adj <0.05
 result <- result[order(result$pvalue), ]
 enrich_results[[comp]] <- result
 cat(" Enriched (FDR<0.05):", sum(result$enriched), "/", nrow(result), "\n")
 write.csv(result, file.path(TABLES_DIR, paste0("kegg_enrichment_", comp, ".csv")), row.names = FALSE)
}

# ====== Barplots ======
cat("\nGenerating enrichment barplots...\n")
for (comp in comparisons) {
 res <- enrich_results[[comp]]
 if (nrow(res) ==0) { cat(" No results for", comp, "\n"); next }
 
 plot_data <- head(res, min(20, nrow(res)))
 plot_data$neg_log10_p <- -log10(plot_data$pvalue_adj)
 # Use shortened display names
 plot_data$DisplayName <- gsub("^[0-9]+\\s*", "", plot_data$Pathway)
 plot_data$DisplayName <- factor(plot_data$DisplayName, levels = rev(plot_data$DisplayName))
 
 plot_data$ShortClass <- gsub("^[0-9]+\\s*", "", plot_data$Class)
 plot_data$ShortClass[plot_data$ShortClass == ""] <- "Unclassified"
 
 p <- ggplot(plot_data, aes(x = DisplayName, y = Count_in_Sig, fill = ShortClass)) +
 geom_bar(stat = "identity", width =0.7) +
 geom_text(aes(label = Count_in_Sig), hjust = -0.2, size =3) +
 coord_flip() + scale_fill_brewer(palette = "Set2", name = "KEGG Class") +
 labs(title = paste0("KEGG Enrichment - ", comp), x = "Pathway", y = "Metabolite Count in Pathway") +
 theme_bw(base_size =12) + ylim(0, max(plot_data$Count_in_Sig)*1.3) +
 theme(plot.title = element_text(hjust =0.5, face = "bold"), axis.text.y = element_text(size =9))
 
 h <- max(6, nrow(plot_data)*0.35)
 pdf(file.path(FIGURES_DIR, paste0("Enrichment_barplot_", comp, ".pdf")), width =10, height = h)
 print(p); dev.off()
 png(file.path(FIGURES_DIR, paste0("Enrichment_barplot_", comp, ".png")), width =10*300, height = h*300, res =300)
 print(p); dev.off()
 cat(" Barplot saved for", comp, "\n")
}

# ======5. GSVA ======
cat("\n========================================\n")
cat("Step3: GSVA Analysis\n")
cat("========================================\n\n")

gene_sets <- lapply(pathway_to_metab, function(x) intersect(x, rownames(expr_mat)))
gene_sets <- gene_sets[sapply(gene_sets, length) >= min_size]
cat(" Gene sets for GSVA:", length(gene_sets), "\n")

cat(" Running GSVA...\n")
gsva_param <- GSVA::gsvaParam(expr_mat, gene_sets, kcdf = "Gaussian", minSize = min_size, maxSize = max_size)
gsva_scores <- GSVA::gsva(gsva_param)
cat(" GSVA scores:", nrow(gsva_scores), "x", ncol(gsva_scores), "\n")

gsva_df <- cbind(Pathway = rownames(gsva_scores), as.data.frame(gsva_scores))
write.csv(gsva_df, file.path(TABLES_DIR, "kegg_gsva_scores.csv"), row.names = FALSE)

# ======6. GSVA Differential Analysis ======
cat("\n========================================\n")
cat("Step4: GSVA Differential (LIMMA)\n")
cat("========================================\n\n")

# We need to map group labels back to valid names for the design matrix
# The design matrix uses the original factors, but makeContrasts needs valid names
# Fix: use the valid group names directly

gsva_de_results <- list()
for (comp in comparisons) {
 cat("---", comp, "---\n")
 comp_info <- read.csv(COMPARISON_FILE, stringsAsFactors = FALSE)
 comp_row <- comp_info[comp_info$comparison_name == comp, ]
 if (nrow(comp_row) ==0) { cat(" Not found in design.\n"); next }
 
 trt_orig <- comp_row$treatment_group[1]
 ctrl_orig <- comp_row$control_group[1]
 
 # Map to valid names
 group_map <- unique(sample_meta_bio[, c("sample_info", "group_valid")])
 trt <- group_map$group_valid[group_map$sample_info == trt_orig]
 ctrl <- group_map$group_valid[group_map$sample_info == ctrl_orig]
 cat(" ", trt_orig, "->", trt, " vs ", ctrl_orig, "->", ctrl, "\n")
 
 if (length(trt) ==0 || length(ctrl) ==0) { cat(" Group not found.\n"); next }
 
 # Build design matrix using valid group names
 groups_valid <- factor(sample_meta_bio$group_valid)
 design <- model.matrix(~0 + groups_valid)
 colnames(design) <- levels(groups_valid)
 
 cm <- limma::makeContrasts(contrasts = paste0(trt, " - ", ctrl), levels = design)
 fit <- limma::lmFit(gsva_scores, design)
 fit2 <- limma::eBayes(limma::contrasts.fit(fit, cm))
 tt <- limma::topTable(fit2, number = Inf, adjust.method = "BH", sort.by = "none")
 
 result <- data.frame(
 Pathway = rownames(tt),
 Class = sapply(rownames(tt), function(p) ifelse(is.null(pathway_to_class[[p]]), "", pathway_to_class[[p]])),
 logFC = tt$logFC, AveExpr = tt$AveExpr, t_statistic = tt$t,
 pvalue = tt$P.Value, pvalue_adj = tt$adj.P.Val, stringsAsFactors = FALSE)
 result$significant <- result$pvalue_adj <0.05
 gsva_de_results[[comp]] <- result
 cat(" Significant:", sum(result$significant), "/", nrow(result), "\n")
 write.csv(result, file.path(TABLES_DIR, paste0("kegg_gsva_differential_", comp, ".csv")), row.names = FALSE)
}

# ======7. Visualizations ======
cat("\n========================================\n")
cat("Step5: Visualizations\n")
cat("========================================\n\n")

#7a. GSVA Heatmap
cat("7a. GSVA heatmap...\n")
sample_order <- sample_meta_bio$ID[order(sample_meta_bio$sample_info)]
gsva_plot <- gsva_scores[, sample_order, drop = FALSE]

# Get pathway class for each pathway
pathway_cats <- sapply(rownames(gsva_plot), function(p) {
 cls <- ifelse(is.null(pathway_to_class[[p]]), "", pathway_to_class[[p]])
 gsub("^[0-9]+\\s*", "", cls)
})
pathway_cats[pathway_cats == ""] <- "Unclassified"
pathway_cats[is.na(pathway_cats)] <- "Unclassified"

cat_order <- order(pathway_cats)
gsva_plot <- gsva_plot[cat_order, , drop = FALSE]
pathway_cats <- pathway_cats[cat_order]

n_cats <- length(unique(pathway_cats))
cat_colors <- setNames(brewer.pal(min(n_cats,12), "Set3")[1:n_cats], unique(pathway_cats))

# Group colors using valid names
group_levels <- unique(sample_meta_bio$sample_info)
group_colors <- setNames(brewer.pal(length(group_levels), "Set1"), group_levels)

row_ha <- rowAnnotation(Category = pathway_cats, col = list(Category = cat_colors), show_annotation_name = FALSE)
col_ha <- HeatmapAnnotation(Group = sample_meta_bio[sample_order, "sample_info"], 
 col = list(Group = group_colors), show_annotation_name = FALSE)

max_abs <- max(abs(gsva_plot), na.rm = TRUE)
col_fun <- colorRamp2(c(-max_abs,0, max_abs), c("#4DBBD5", "white", "#E64B35"))

if (nrow(gsva_plot) >0) {
 ht <- Heatmap(gsva_plot, name = "GSVA Score", col = col_fun, 
 top_annotation = col_ha, right_annotation = row_ha,
 show_row_names = TRUE, show_column_names = TRUE, 
 column_names_gp = gpar(fontsize =8),
 row_names_gp = gpar(fontsize =6),
 row_split = pathway_cats, cluster_rows = TRUE, cluster_columns = FALSE,
 row_title_gp = gpar(fontsize =10), row_gap = unit(4, "mm"),
 column_title = "GSVA Pathway Activity", column_title_gp = gpar(fontsize =14, face = "bold"))
 
 h <- max(8, nrow(gsva_plot)*0.1) +3
 pdf(file.path(FIGURES_DIR, "GSVA_heatmap.pdf"), width =14, height = h)
 draw(ht); dev.off()
 png(file.path(FIGURES_DIR, "GSVA_heatmap.png"), width =14*300, height = h*300, res =300)
 draw(ht); dev.off()
 cat(" Heatmap saved.\n")
}

#7b. Volcano Plots
cat("\n7b. GSVA volcano plots...\n")
for (comp in comparisons) {
 res <- gsva_de_results[[comp]]
 if (is.null(res) || nrow(res) ==0) next
 
 res$neg_log10_p <- -log10(res$pvalue_adj)
 res$direction <- "Not Significant"
 res$direction[res$significant & res$logFC >0] <- "Up"
 res$direction[res$significant & res$logFC <0] <- "Down"
 
 sig_only <- res[res$significant, , drop = FALSE]
 if (nrow(sig_only) >0) {
 top_sig <- head(sig_only[order(abs(sig_only$logFC), decreasing = TRUE), ],10)
 res$label <- ifelse(res$Pathway %in% top_sig$Pathway, 
 gsub("^[0-9]+\\s*", "", res$Pathway), "")
 } else { res$label <- "" }
 
 p <- ggplot(res, aes(x = logFC, y = neg_log10_p, color = direction)) +
 geom_point(alpha =0.7, size =2.5) +
 geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "grey50") +
 geom_vline(xintercept =0, linetype = "dashed", color = "grey50") +
 geom_text_repel(aes(label = label), size =3, max.overlaps =20, box.padding =0.5, show.legend = FALSE) +
 scale_color_manual(values = c("Up" = "#E64B35", "Down" = "#4DBBD5", "Not Significant" = "grey80")) +
 labs(title = paste0("GSVA Differential - ", comp), x = "log2(Fold Change)", y = "-log10(adj.P)", color = "Direction") +
 theme_bw(base_size =12) + theme(plot.title = element_text(hjust =0.5, face = "bold"))
 
 pdf(file.path(FIGURES_DIR, paste0("GSVA_volcano_", comp, ".pdf")), width =10, height =8); print(p); dev.off()
 png(file.path(FIGURES_DIR, paste0("GSVA_volcano_", comp, ".png")), width =10*300, height =8*300, res =300); print(p); dev.off()
 cat(" Volcano saved for", comp, "\n")
}

#7c. Boxplots
cat("\n7c. GSVA boxplots for significant pathways...\n")
for (comp in comparisons) {
 res <- gsva_de_results[[comp]]
 if (is.null(res) || sum(res$significant) ==0) { cat(" No sig for", comp, "\n"); next }
 
 sig_pathways <- res$Pathway[res$significant]
 if (length(sig_pathways) >20) sig_pathways <- sig_pathways[order(res$pvalue_adj[res$significant])][1:20]
 
 score_list <- list()
 for (pw in sig_pathways) {
 if (!pw %in% rownames(gsva_scores)) next
 for (sid in colnames(gsva_scores)) {
 grp <- sample_meta_bio[sid, "sample_info"]
 score_list[[length(score_list)+1]] <- data.frame(
 Pathway = gsub("^[0-9]+\\s*", "", substr(pw,1,50)),
 Group = grp, Score = gsva_scores[pw, sid], stringsAsFactors = FALSE)
 }
 }
 if (length(score_list) ==0) next
 scores_df <- do.call(rbind, score_list)
 scores_df$Group <- factor(scores_df$Group, levels = levels(factor(sample_meta_bio$sample_info)))
 
 p <- ggplot(scores_df, aes(x = Group, y = Score, fill = Group)) +
 geom_boxplot(outlier.shape = NA, alpha =0.7) + geom_jitter(width =0.2, size =1.5, alpha =0.5) +
 facet_wrap(~ Pathway, scales = "free_y", ncol = min(4, length(sig_pathways))) +
 scale_fill_manual(values = group_colors) +
 labs(title = paste0("GSVA Scores of Significant Pathways - ", comp), x = "Group", y = "GSVA Score") +
 theme_bw(base_size =10) + theme(plot.title = element_text(hjust =0.5, face = "bold"),
 axis.text.x = element_text(angle =45, hjust =1), strip.text = element_text(size =7), legend.position = "none")
 
 n_col <- min(4, length(sig_pathways)); n_row <- ceiling(length(sig_pathways)/n_col)
 w <- max(8, n_col*4); h <- max(6, n_row*3.5)
 pdf(file.path(FIGURES_DIR, paste0("GSVA_boxplot_", comp, ".pdf")), width = w, height = h); print(p); dev.off()
 png(file.path(FIGURES_DIR, paste0("GSVA_boxplot_", comp, ".png")), width = w*300, height = h*300, res =300); print(p); dev.off()
 cat(" Boxplot saved for", comp, "\n")
}

cat("\n====== Analysis Complete! ======\n")
cat(" Tables:", TABLES_DIR, "\n")
cat(" Figures:", FIGURES_DIR, "\n")
