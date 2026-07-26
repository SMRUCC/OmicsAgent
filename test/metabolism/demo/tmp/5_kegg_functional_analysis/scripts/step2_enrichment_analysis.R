# ============================================================
# KEGG Functional Analysis - Step2: Enrichment & Visualization
# ============================================================
# Performs Fisher exact test enrichment for3 comparisons
# and generates publication-quality barplots
# ============================================================

options(repos = c(CRAN = "https://cloud.r-project.org"))
options(BioC_mirror = "https://bioconductor.org")

# ------ Install & load packages ------
for (pkg in c("ggplot2", "grDevices", "stats", "utils", "RColorBrewer")) {
 if (!requireNamespace(pkg, quietly = TRUE))
 install.packages(pkg, dependencies = TRUE)
 library(pkg, character.only = TRUE)
}

# ------ Paths ------
BASE_DIR <- "G:/OmicsWorks/test/metabolism/demo"
EXPR_FILE <- file.path(BASE_DIR, "tmp/preprocessed_expression.csv")
META_FILE <- "G:/OmicsWorks/test/metabolism/metabolites.csv"
SAMPLEINFO_FILE <- file.path(BASE_DIR, "tmp/1_expression_matrix_preprocessing/sampleinfo.csv")
LIMMA_ALL_FILE <- file.path(BASE_DIR, "tmp/4_limma_differential_analysis/tables/limma_all_comparisons_consolidated.csv")
OUT_DIR <- file.path(BASE_DIR, "tmp/5_kegg_functional_analysis")
TABLES_DIR <- file.path(OUT_DIR, "tables")
FIGURES_DIR <- file.path(BASE_DIR, "analysis/5_kegg_functional_analysis/figures")
for (d in c(OUT_DIR, TABLES_DIR, FIGURES_DIR)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

# Source helpers
source(file.path("G:/OmicsWorks/agent/rscript/enrichment.R"))
source(file.path("G:/OmicsWorks/agent/rscript/data_io.R"))

cat("========================================\n")
cat("KEGG Enrichment Analysis - Step2\n")
cat("========================================\n\n")

# ----1. Load expression matrix ----
cat("1. Loading expression matrix...\n")
expr_raw <- read.csv(EXPR_FILE, row.names =1, check.names = FALSE)
expr_mat <- as.matrix(expr_raw)
all_features <- rownames(expr_mat)
cat(" Total metabolites:", length(all_features), "\n")

# ----2. Load sample metadata ----
cat("2. Loading sample metadata...\n")
sample_meta <- read.csv(SAMPLEINFO_FILE, stringsAsFactors = FALSE)
rownames(sample_meta) <- sample_meta$ID
sample_meta_bio <- sample_meta[sample_meta$sample_info != "QC", , drop = FALSE]
cat(" Biological samples:", nrow(sample_meta_bio), "\n")
print(table(sample_meta_bio$sample_info))

# ----3. Load metabolite annotations ----
cat("\n3. Loading metabolite annotations...\n")
metab_anno <- read.csv(META_FILE, stringsAsFactors = FALSE)
rownames(metab_anno) <- make.unique(as.character(metab_anno$name))
common_names <- intersect(all_features, metab_anno$name)
cat(" Metabolites matched by name:", length(common_names), "\n")

expr_mat <- expr_mat[rownames(expr_mat) %in% common_names, , drop = FALSE]
anno_idx <- match(rownames(expr_mat), metab_anno$name)
metab_anno_sub <- metab_anno[anno_idx, , drop = FALSE]
rownames(metab_anno_sub) <- rownames(expr_mat)

# ----4. Build KEGG pathway background ----
cat("\n4. Building KEGG pathway background...\n")
split_field <- function(x) {
 if (is.na(x) || x == "" || x == "") return(character(0))
 parts <- trimws(unlist(strsplit(as.character(x), ";")))
 parts[parts != "" & parts != ""]
}

# Build pathway -> metabolite mapping from kegg_category
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

# Remove NULL/empty named entries
pathway_to_metab[[""]] <- NULL
pathway_to_metab[[""]] <- NULL

cat(" Total KEGG categories:", length(pathway_to_metab), "\n")

# Filter by size
min_size <-3; max_size <-200
pw_sizes <- sapply(pathway_to_metab, length)
pathway_to_metab <- pathway_to_metab[pw_sizes >= min_size & pw_sizes <= max_size]
cat(" After size filter (3-200):", length(pathway_to_metab), "pathways\n")
for (nm in names(sort(sapply(pathway_to_metab, length), decreasing = TRUE))) {
 cat(" ", nm, ":", length(pathway_to_metab[[nm]]), "mets\n")
}

metab_with_pathway <- unique(unlist(pathway_to_metab))
cat(" Metabolites with pathway mapping:", length(metab_with_pathway), "/", nrow(expr_mat), "\n")

# Save background
pw_bg <- data.frame(
 Pathway = names(pathway_to_metab),
 Class = sapply(names(pathway_to_metab), function(p) {
 ifelse(is.null(pathway_to_class[[p]]), "", pathway_to_class[[p]])
 }),
 N_Metabolites = sapply(pathway_to_metab, length),
 stringsAsFactors = FALSE
)
write.csv(pw_bg, file.path(TABLES_DIR, "kegg_pathway_background.csv"), row.names = FALSE)
cat(" Background table saved.\n")

# ----5. Load differential results ----
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
 cat(" ", comp, ":", length(sig_lists[[comp]]), "significant DE metabolites\n")
}

# ----6. Fisher Exact Enrichment ----
cat("\n========================================\n")
cat("6. Fisher Exact Enrichment Analysis\n")
cat("========================================\n\n")

enrich_results <- list()
for (comp in comparisons) {
 cat("--- Comparison:", comp, "---\n")
 sig_feats <- sig_lists[[comp]]
 if (length(sig_feats) <2) {
 cat(" Too few DE features. Skipping.\n")
 enrich_results[[comp]] <- data.frame()
 next
 }
 
 # Restrict to features with pathway mapping
 sig_with_pw <- intersect(sig_feats, metab_with_pathway)
 bg_with_pw <- intersect(all_features, metab_with_pathway)
 
 if (length(sig_with_pw) <2) {
 cat(" Too few DE features with pathway mapping. Skipping.\n")
 enrich_results[[comp]] <- data.frame()
 next
 }
 
 cat(" DE features with pathway:", length(sig_with_pw), "/", length(sig_feats), "\n")
 
 # Test each pathway
 res_list <- list()
 for (pw in names(pathway_to_metab)) {
 pw_feats <- pathway_to_metab[[pw]]
 a <- length(intersect(pw_feats, sig_with_pw))
 if (a <1) next
 b <- length(pw_feats) - a
 c <- length(sig_with_pw) - a
 d <- length(bg_with_pw) - length(pw_feats) - c
 ft <- tryCatch(fisher.test(matrix(c(a, b, c, d),2), alternative = "greater"),
 error = function(e) NULL)
 if (is.null(ft)) next
 p_class <- ifelse(is.null(pathway_to_class[[pw]]), "", pathway_to_class[[pw]])
 res_list[[length(res_list) +1]] <- data.frame(
 Pathway = pw,
 Class = p_class,
 Count_in_Sig = a,
 Count_in_BG = length(pw_feats),
 Sig_Size = length(sig_with_pw),
 Bg_Size = length(bg_with_pw),
 pvalue = ft$p.value,
 stringsAsFactors = FALSE
 )
 }
 
 if (length(res_list) ==0) {
 cat(" No enriched pathways found.\n")
 enrich_results[[comp]] <- data.frame()
 next
 }
 
 result <- do.call(rbind, res_list)
 result$pvalue_adj <- p.adjust(result$pvalue, method = "BH")
 result$enriched <- result$pvalue_adj <0.05
 result <- result[order(result$pvalue), ]
 
 enrich_results[[comp]] <- result
 cat(" Pathways tested:", nrow(result), "\n")
 cat(" Enriched (FDR<0.05):", sum(result$enriched), "\n")
 
 # Print top pathways
 if (nrow(result) >0) {
 cat(" Top5 by p-value:\n")
 for (i in 1:min(5, nrow(result))) {
 cat(" ", result$Pathway[i], "- p=", format(result$pvalue[i], digits =3),
 "adj.p=", format(result$pvalue_adj[i], digits =3),
 "count=", result$Count_in_Sig[i], "/", result$Count_in_BG[i], "\n")
 }
 }
 
 write.csv(result, file.path(TABLES_DIR, paste0("kegg_enrichment_", comp, ".csv")),
 row.names = FALSE)
 cat(" Saved.\n\n")
}

# ----7. Enrichment Barplots ----
cat("\n========================================\n")
cat("7. Visualization: Enrichment Barplots\n")
cat("========================================\n\n")

# Define KEGG class colors
class_palette <- c(
 "09100 Metabolism" = "#E64B35",
 "09110 Biosynthesis of other secondary metabolites" = "#4DBBD5",
 "09120 Genetic Information Processing" = "#00A087",
 "09130 Environmental Information Processing" = "#3C5488",
 "09140 Cellular Processes" = "#F39B7F",
 "09150 Organismal Systems" = "#8491B4",
 "09160 Human Diseases" = "#91D1C2"
)

for (comp in comparisons) {
 res <- enrich_results[[comp]]
 if (is.null(res) || nrow(res) ==0) {
 cat(" No results for", comp, "- skipping barplot.\n")
 next
 }
 
 # Top20 by p-value (if enriched exist, prioritize them)
 if (sum(res$enriched) >0) {
 enriched <- res[res$enriched, ]
 not_enriched <- res[!res$enriched, ]
 plot_data <- rbind(enriched, head(not_enriched, max(0,20 - nrow(enriched))))
 } else {
 plot_data <- head(res,20)
 }
 
 # Clean display names (strip numeric prefix)
 plot_data$DisplayName <- gsub("^[0-9]+\\s*", "", plot_data$Pathway)
 plot_data$DisplayName <- factor(plot_data$DisplayName, levels = rev(plot_data$DisplayName))
 
 # Extract major KEGG class (first level only)
 plot_data$MajorClass <- gsub("^[0-9]+\\s*", "", plot_data$Class)
 plot_data$MajorClass[is.na(plot_data$MajorClass) | plot_data$MajorClass == ""] <- "Unclassified"
 plot_data$MajorClass <- gsub("\\s+", " ", plot_data$MajorClass)
 
 # Create neg_log10_p for coloring
 plot_data$neg_log10_p <- -log10(plot_data$pvalue_adj)
 plot_data$neg_log10_p[is.infinite(plot_data$neg_log10_p)] <-3.0
 
 cat(" Plotting top", nrow(plot_data), "pathways for", comp, "\n")
 
 # Determine if any are enriched
 enrich_labels <- ifelse(plot_data$enriched, "*", "")
 
 p <- ggplot(plot_data, aes(x = DisplayName, y = Count_in_Sig, fill = MajorClass)) +
 geom_bar(stat = "identity", width =0.7, color = "grey30", size =0.3) +
 geom_text(aes(label = paste0(Count_in_Sig, enrich_labels)), 
 hjust = -0.15, size =3.2, fontface = ifelse(plot_data$enriched, "bold", "plain")) +
 coord_flip() +
 scale_fill_brewer(palette = "Set2", name = "KEGG Class") +
 labs(
 title = paste0("KEGG Pathway Enrichment - ", comp),
 subtitle = paste0("Fisher Exact Test (FDR <0.05: ", sum(res$enriched), " enriched)"),
 x = "KEGG Pathway", y = "Metabolite Count in Pathway"
 ) +
 theme_bw(base_size =12) +
 theme(
 plot.title = element_text(hjust =0.5, face = "bold", size =14),
 plot.subtitle = element_text(hjust =0.5, size =10, color = "grey40"),
 axis.text.y = element_text(size =10),
 axis.title = element_text(size =12),
 legend.position = "right",
 legend.title = element_text(size =10),
 panel.grid.major.y = element_blank()
 ) +
 ylim(0, max(plot_data$Count_in_Sig) *1.25) +
 scale_y_continuous(expand = expansion(mult = c(0,0.15)))
 
 # Add annotation for significant if any
 if (sum(plot_data$enriched) >0) {
 p <- p + annotate("text", x = Inf, y = Inf, label = "* FDR <0.05", 
 hjust =1.1, vjust =1.5, size =3, color = "red")
 }
 
 # Save
 h <- max(5, nrow(plot_data) *0.35 +1)
 
 pdf(file.path(FIGURES_DIR, paste0("Enrichment_barplot_", comp, ".pdf")),
 width =11, height = h)
 print(p)
 dev.off()
 
 png(file.path(FIGURES_DIR, paste0("Enrichment_barplot_", comp, ".png")),
 width =11 *300, height = h *300, res =300)
 print(p)
 dev.off()
 
 cat(" Saved barplot:", comp, "\n")
}

# ----8. Combined Summary Table ----
cat("\n========================================\n")
cat("8. Summary\n")
cat("========================================\n\n")

cat("Enrichment Results Summary:\n")
for (comp in comparisons) {
 res <- enrich_results[[comp]]
 if (is.null(res) || nrow(res) ==0) {
 cat(" ", comp, ": No pathways tested\n")
 } else {
 n_sig <- sum(res$enriched, na.rm = TRUE)
 n_test <- nrow(res)
 top_pw <- head(res$Pathway[order(res$pvalue)],3)
 cat(" ", comp, ":", n_sig, "/", n_test, "significant\n")
 cat(" Top pathways:", paste(gsub("^[0-9]+\\s*", "", top_pw), collapse = ", "), "\n")
 }
}

cat("\nOutput files:\n")
cat(" Tables:", TABLES_DIR, "\n")
for (f in list.files(TABLES_DIR, pattern = "kegg_enrichment")) cat(" ", f, "\n")
cat(" Figures:", FIGURES_DIR, "\n")
for (f in list.files(FIGURES_DIR, pattern = "Enrichment_barplot")) cat(" ", f, "\n")

cat("\n========================================\n")
cat("Step2 Complete!\n")
cat("========================================\n")
