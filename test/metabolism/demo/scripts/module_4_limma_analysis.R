# ============================================================================
# Module4: LIMMA Differential Analysis
# ============================================================================
# Topic:高铁饮食对感染艰难梭菌小鼠的代谢组学影响
# Dataset: Metabolomics expression matrix (LC-MS),2059 metabolites ×18 samples
# Groups: CD (Clostridium difficile infection, n=6),
# FE (high iron diet before, n=6),
# NC (Standard control, n=6)
#
# Comparisons (3 primary):
#1. FE_vs_CD (PRIMARY) - Effect of high-iron diet on CDI metabolic response
#2. CD_vs_NC (SECONDARY) - CDI baseline metabolic signature
#3. FE_vs_NC (SECONDARY) - Net effect of iron + infection vs healthy
#
# Workflow:
#1. Load preprocessed expression matrix & sample info
#2. Build design matrix and perform moderated F-test (ANOVA)
#3. Build contrast matrix and run pairwise limma comparisons
#4. Compute VIP scores via PLS-DA (mixOmics) for metabolomics integration
#5. Apply thresholds: adj.P.Val <0.05, VIP >1
#6. Top500 by |logFC| descending after filtering
#7. Generate plots: volcano, venn, heatmaps, p-value diagnostics
#8. Save all results as CSV tables
# ============================================================================

# ----0. Environment Setup ----
options(stringsAsFactors = FALSE)
options(ggrepel.max.overlaps = Inf)

# ----0.1 Define absolute paths ----
BASE_DIR <- "G:/OmicsWorks/test/metabolism"
DEMO_DIR <- file.path(BASE_DIR, "demo")
TMP_DIR <- file.path(BASE_DIR, "tmp")
TABLES_DIR <- file.path(DEMO_DIR, "tables")
SCRIPTS_DIR <- file.path(DEMO_DIR, "scripts")
RESULTS_DIR <- file.path(DEMO_DIR, "results")
FIGS_DIR <- file.path(RESULTS_DIR, "figures")
TABLES_OUT <- file.path(RESULTS_DIR, "tables")
CONCLUSIONS_DIR <- file.path(DEMO_DIR, "conclusions")

dir.create(TABLES_OUT, showWarnings = FALSE, recursive = TRUE)
dir.create(FIGS_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(CONCLUSIONS_DIR, showWarnings = FALSE, recursive = TRUE)

# ----0.2 Input file paths ----
EXPR_FILE <- file.path(TMP_DIR, "preprocessed_expression.csv")
SAMPLE_FILE <- file.path(BASE_DIR, "sampleinfo.csv")
ANNOT_FILE <- file.path(BASE_DIR, "metabolites.csv")
DESIGN_FILE <- file.path(TABLES_DIR, "comparison_design.csv")

# ----0.3 Output file paths ----
ANOVA_FILE <- file.path(TABLES_OUT, "anova_overall_f_test_results.csv")
VIP_FILE <- file.path(TABLES_OUT, "vip_scores.csv")
VIP_INT_FILE <- file.path(TABLES_OUT, "vip_integrated_results.csv")
TOP500_FILE <- file.path(TABLES_OUT, "top500_logFC_ranked.csv")
COMBINED_FILE <- file.path(TABLES_OUT, "combined_diff_results.csv")

cat("==============================================================\n")
cat("Module4: LIMMA Differential Analysis\n")
cat("==============================================================\n")

# ----1. Install / Load Required Packages ----
required_pkgs <- c("limma", "ggplot2", "pheatmap", "ggvenn",
 "ggrepel", "dplyr", "tidyr", "mixOmics")
for (pkg in required_pkgs) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 cat("Installing package:", pkg, "...\n")
 install.packages(pkg, repos = "https://cloud.r-project.org", quiet = TRUE)
 }
 library(pkg, character.only = TRUE)
}
cat("All required packages loaded.\n\n")

# ----2. Source Helper Functions ----
helper_script <- file.path("G:/OmicsWorks/agent/rscript/limma_diff_analysis.R")
if (file.exists(helper_script)) {
 source(helper_script)
 cat("Helper script loaded:", helper_script, "\n\n")
}

# ----3. Load Data ----
cat("Step1: Loading preprocessed expression matrix...\n")
expr_df <- read.csv(EXPR_FILE, row.names =1, check.names = FALSE)
expr_mat <- as.matrix(expr_df)
mode(expr_mat) <- "numeric"
cat(" Expression matrix dimensions:", nrow(expr_mat), "molecules x", ncol(expr_mat), "samples\n")

cat("Step2: Loading sample information...\n")
sample_info <- read.csv(SAMPLE_FILE, stringsAsFactors = FALSE, check.names = FALSE)
cat(" Sample info records:", nrow(sample_info), "\n")

cat("Step3: Loading metabolite annotations...\n")
annot <- read.csv(ANNOT_FILE, row.names =1, stringsAsFactors = FALSE, check.names = FALSE)
cat(" Annotation records:", nrow(annot), "\n")

cat("Step4: Loading comparison design...\n")
design_df <- read.csv(DESIGN_FILE, stringsAsFactors = FALSE, check.names = FALSE)
cat(" Comparisons defined:", nrow(design_df), "\n")

# ----4. Align Samples Between Expression Matrix and Sample Info ----
common_samples <- intersect(colnames(expr_mat), sample_info$ID)
cat(" Common samples between expression matrix and sample info:",
 length(common_samples), "\n")

expr_mat <- expr_mat[, common_samples, drop = FALSE]
sample_info <- sample_info[match(common_samples, sample_info$ID), , drop = FALSE]

# Define group factor
groups <- factor(sample_info$sample_info,
 levels = c("Standard (control)",
 "Clostridium difficile infection",
 "high iron diet before"))
# Short group names
group_map <- c("Standard (control)" = "NC",
 "Clostridium difficile infection" = "CD",
 "high iron diet before" = "FE")
group_short <- group_map[as.character(groups)]
names(group_short) <- sample_info$ID

cat(" Group distribution:\n")
print(table(groups))
cat("\n")

# ----5. Build Design Matrix ----
cat("Step5: Building design matrix...\n")
design <- model.matrix(~0 + groups)
colnames(design) <- group_map[levels(groups)]
rownames(design) <- sample_info$ID

cat(" Design matrix coefficients:", paste(colnames(design), collapse = ", "), "\n")
cat(" Design matrix rank:", qr(design)$rank, "\n")

# ----6. LIMMA: Fit Linear Model ----
cat("Step6: Fitting linear model (lmFit)...\n")
fit <- lmFit(expr_mat, design)

# ----7. Moderated F-test (Overall ANOVA) ----
cat("Step7: Performing moderated F-test (overall ANOVA)...\n")
fit_anova <- eBayes(fit)
anova_results <- topTable(fit_anova, coef =1:3, number = Inf, sort.by = "F")
anova_results$molecule_id <- rownames(anova_results)

# Count significant
n_anova_sig <- sum(anova_results$adj.P.Val <0.05, na.rm = TRUE)
cat(" Overall F-test: significant (adj.P <0.05):", n_anova_sig,
 "out of", nrow(anova_results), "\n")

write.csv(anova_results, ANOVA_FILE, row.names = FALSE)
cat(" Saved:", ANOVA_FILE, "\n")

# ----8. Build Contrast Matrix ----
cat("Step8: Building contrast matrix for pairwise comparisons...\n")

# Define comparisons
primary_comparisons <- list(
 FE_vs_CD = c("FE", "CD"),
 CD_vs_NC = c("CD", "NC"),
 FE_vs_NC = c("FE", "NC")
)

contrast_matrix <- makeContrasts(
 FE_vs_CD = FE - CD,
 CD_vs_NC = CD - NC,
 FE_vs_NC = FE - NC,
 levels = design
)

cat(" Contrasts defined:\n")
for (nm in names(primary_comparisons)) {
 cat(" ", nm, ":", primary_comparisons[[nm]][1], "-",
 primary_comparisons[[nm]][2], "\n")
}

# ----9. LIMMA: Contrast Fit and eBayes ----
cat("Step9: Running contrast fit and eBayes...\n")
fit2 <- contrasts.fit(fit, contrast_matrix)
fit2 <- eBayes(fit2, trend = TRUE, robust = TRUE)

# ----10. Extract Results for Each Comparison ----
cat("Step10: Extracting results for each comparison...\n")

all_results <- list()
sig_lists <- list()

for (comp_name in names(primary_comparisons)) {
 cat(" Processing:", comp_name, "...\n")

 tt <- topTable(fit2, coef = comp_name, number = Inf, sort.by = "P")
 tt$molecule_id <- rownames(tt)
 tt$comparison <- comp_name

 # Add regulation direction
 tt$regulation <- ifelse(tt$logFC >0, "up", "down")

 # Add contrast definition info
 trt_grp <- primary_comparisons[[comp_name]][1]
 ctrl_grp <- primary_comparisons[[comp_name]][2]
 tt$treatment <- trt_grp
 tt$control <- ctrl_grp

 all_results[[comp_name]] <- tt

 # Filter significant (adj.P.Val <0.05)
 sig <- tt[tt$adj.P.Val <0.05 & !is.na(tt$adj.P.Val), ]
 # Sort by |logFC| descending
 sig <- sig[order(abs(sig$logFC), decreasing = TRUE), ]
 sig_lists[[comp_name]] <- sig

 n_sig <- nrow(sig)
 cat(" Significant (adj.P <0.05):", n_sig, "molecules\n")
 cat(" Up-regulated:", sum(sig$logFC >0), "| Down-regulated:", sum(sig$logFC <0), "\n")

 # Save full results
 full_file <- file.path(TABLES_OUT, paste0("diff_", comp_name, "_all.csv"))
 write.csv(tt, full_file, row.names = FALSE)
 cat(" Saved:", full_file, "\n")

 # Save significant results (top500 by |logFC|)
 sig_out <- sig
 if (nrow(sig_out) >500) {
 sig_out <- sig_out[1:500, ]
 }
 sig_file <- file.path(TABLES_OUT, paste0("diff_", comp_name, "_significant.csv"))
 write.csv(sig_out, sig_file, row.names = FALSE)
 cat(" Saved:", sig_file, "\n")
}

cat("\n")

# ----11. Compute VIP Scores via PLS-DA (mixOmics) ----
cat("Step11: Computing PLS-DA VIP scores via mixOmics...\n")

# Prepare data for PLS-DA
# X = transposed expression matrix (samples x molecules)
# Y = group labels as factor
Y_factor <- factor(group_short[colnames(expr_mat)],
 levels = c("NC", "CD", "FE"))

# Run PLS-DA
plsda_result <- plsda(t(expr_mat), Y_factor, ncomp =2)

# Extract VIP scores
# vip() returns matrix: rows = variables (molecules), cols = components
vip_matrix <- vip(plsda_result)

cat(" VIP matrix dimensions:", nrow(vip_matrix), "(variables) x",
 ncol(vip_matrix), "(components)\n")

# Take VIP from first component (column1 = all variables' VIP for comp1)
if (ncol(vip_matrix) >=1) {
 vip_vec <- vip_matrix[,1]
} else {
 # Fallback
 vip_vec <- as.numeric(vip_matrix)
}

# Ensure names match (vip_matrix rownames should be molecule IDs)
if (is.null(names(vip_vec)) || any(names(vip_vec) == "")) {
 names(vip_vec) <- rownames(expr_mat)
}

vip_df <- data.frame(
 molecule_id = names(vip_vec),
 VIP_score = as.numeric(vip_vec),
 stringsAsFactors = FALSE
)
rownames(vip_df) <- NULL

# Save VIP scores
write.csv(vip_df, VIP_FILE, row.names = FALSE)
cat(" VIP scores saved:", VIP_FILE, "\n")
cat(" VIP >1 count:", sum(vip_df$VIP_score >1, na.rm = TRUE), "\n")

# ----12. Integrate VIP Scores with LIMMA Results ----
cat("Step12: Integrating VIP scores with LIMMA results...\n")

vip_integrated <- list()

for (comp_name in names(all_results)) {
 tt <- all_results[[comp_name]]
 # Merge VIP
 tt <- merge(tt, vip_df, by = "molecule_id", all.x = TRUE)
 # Define consensus category
 tt$consensus_category <- "Non-significant"
 tt$consensus_category[tt$adj.P.Val <0.05 & !is.na(tt$adj.P.Val)] <- "Significant only"
 tt$consensus_category[tt$VIP_score >1 & !is.na(tt$VIP_score)] <- "Discriminative only"
 tt$consensus_category[
 tt$adj.P.Val <0.05 & !is.na(tt$adj.P.Val) &
 tt$VIP_score >1 & !is.na(tt$VIP_score)
 ] <- "High-confidence (Both)"
 tt$consensus_category[is.na(tt$consensus_category)] <- "Non-significant"

 vip_integrated[[comp_name]] <- tt

 # Save VIP-integrated results
 vip_int_file <- file.path(TABLES_OUT, paste0("vip_integrated_", comp_name, ".csv"))
 write.csv(tt, vip_int_file, row.names = FALSE)
}

# Combined VIP-integrated table
combined_vip <- do.call(rbind, vip_integrated)
write.csv(combined_vip, VIP_INT_FILE, row.names = FALSE)
cat(" Saved:", VIP_INT_FILE, "\n")

# ----13. Top500 by |logFC| Ranking ----
cat("Step13: Creating Top500 |logFC| ranking table...\n")

top500_list <- list()
for (comp_name in names(primary_comparisons)) {
 sig <- sig_lists[[comp_name]]
 if (nrow(sig) >500) {
 sig_top <- sig[1:500, ]
 } else {
 sig_top <- sig
 }
 sig_top$rank_by_logFC <-1:nrow(sig_top)
 top500_list[[comp_name]] <- sig_top[, c("molecule_id", "logFC", "adj.P.Val",
 "AveExpr", "t", "B", "regulation",
 "rank_by_logFC", "comparison")]
}

top500_combined <- do.call(rbind, top500_list)
write.csv(top500_combined, TOP500_FILE, row.names = FALSE)
cat(" Saved:", TOP500_FILE, "\n")

# Count per comparison
for (comp_name in names(top500_list)) {
 cat(" ", comp_name, ":", nrow(top500_list[[comp_name]]), "molecules\n")
}

# ----14. Generate Volcano Plots ----
cat("Step14: Generating volcano plots...\n")

for (comp_name in names(all_results)) {
 tt <- all_results[[comp_name]]
 # Merge with annotation for labels
 annot_sub <- annot[, c("name", "super_class", "class"), drop = FALSE]
 annot_sub$molecule_id <- rownames(annot)
 tt <- merge(tt, annot_sub, by = "molecule_id", all.x = TRUE)

 # Define significance
 tt$significant <- tt$adj.P.Val <0.05 & !is.na(tt$adj.P.Val)
 tt$sig_label <- ""
 # Get top5 significant by |logFC|
 sig_tt <- tt[tt$significant, ]
 sig_tt <- sig_tt[order(abs(sig_tt$logFC), decreasing = TRUE), ]
 if (nrow(sig_tt) >5) {
 sig_tt <- sig_tt[1:5, ]
 }
 # Use name from annotation if available, else molecule_id
 label_col <- ifelse(!is.na(sig_tt$name) & nchar(sig_tt$name) >0,
 sig_tt$name, sig_tt$molecule_id)
 sig_tt$label <- label_col

 # Merge labels back
 tt$label <- ""
 tt$label[tt$molecule_id %in% sig_tt$molecule_id] <-
 sig_tt$label[match(tt$molecule_id[tt$molecule_id %in% sig_tt$molecule_id],
 sig_tt$molecule_id)]

 # Determine plot title
 grp <- primary_comparisons[[comp_name]]
 title_text <- paste0(comp_name, " (", grp[1], " vs ", grp[2], ")")

 # Volcano plot
 p <- ggplot(tt, aes(x = logFC, y = -log10(adj.P.Val), color = significant)) +
 geom_point(size =1.5, alpha =0.6) +
 scale_color_manual(values = c("FALSE" = "grey70", "TRUE" = "#E41A1C"),
 name = paste0("adj.P <0.05\n(n=", sum(tt$significant), ")")) +
 geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "blue", alpha =0.5) +
 geom_text_repel(data = subset(tt, label != ""),
 aes(label = label),
 size =3.5, color = "black",
 box.padding =0.5, point.padding =0.3,
 max.overlaps =20, fontface = "italic") +
 labs(x = "log2(Fold Change)",
 y = expression(-log[10](adj.P.Value)),
 title = title_text) +
 theme_bw(base_size =14) +
 theme(plot.title = element_text(hjust =0.5, face = "bold", size =16),
 legend.position = "right",
 panel.grid.minor = element_blank())

 # Save PNG and PDF
 png_file <- file.path(FIGS_DIR, paste0("volcano_", comp_name, ".png"))
 ggsave(png_file, p, width =10, height =7, dpi =300)
 pdf_file <- file.path(FIGS_DIR, paste0("volcano_", comp_name, ".pdf"))
 ggsave(pdf_file, p, width =10, height =7)
 cat(" Volcano plots saved:", comp_name, "\n")
}

# ----15. Venn Diagram ----
cat("Step15: Generating Venn diagram...\n")

# Extract significant molecule IDs for each comparison (named list)
venn_data <- list()
for (comp_name in names(primary_comparisons)) {
 sig_ids <- sig_lists[[comp_name]]$molecule_id
 if (length(sig_ids) >0) {
 venn_data[[comp_name]] <- sig_ids
 }
}

if (length(venn_data) >=2) {
 # ggvenn uses the list names as set names directly
 p_venn <- ggvenn(venn_data,
 fill_color = c("#E41A1C", "#377EB8", "#4DAF4A"),
 stroke_size =0.5,
 set_name_size =4,
 text_size =3) +
 ggtitle("Overlap of Significant Metabolites Across Comparisons") +
 theme(plot.title = element_text(hjust =0.5, face = "bold", size =14))

 png_file <- file.path(FIGS_DIR, "venn_diff_molecules.png")
 ggsave(png_file, p_venn, width =8, height =7, dpi =300)
 pdf_file <- file.path(FIGS_DIR, "venn_diff_molecules.pdf")
 ggsave(pdf_file, p_venn, width =8, height =7)
 cat(" Venn diagram saved\n")
} else {
 cat(" Skipping Venn: fewer than2 comparison sets with significant molecules\n")
}

# ----16. UpSet Plot ----
cat("Step16: Generating UpSet plot...\n")

if (length(venn_data) >=2) {
 # Prepare binary matrix
 all_molecules <- unique(unlist(venn_data))
 upset_mat <- data.frame(molecule = all_molecules, stringsAsFactors = FALSE)
 rownames(upset_mat) <- all_molecules
 for (nm in names(venn_data)) {
 upset_mat[[nm]] <- all_molecules %in% venn_data[[nm]]
 }

 # Create a custom UpSet-like visualization
 upset_counts <- upset_mat[, names(venn_data), drop = FALSE]
 upset_patterns <- apply(upset_counts,1, function(x) paste(as.integer(x), collapse = ""))
 pattern_counts_tbl <- sort(table(upset_patterns), decreasing = TRUE)

 # Create pattern data frame
 pattern_df <- data.frame(
 pattern = names(pattern_counts_tbl),
 count = as.integer(pattern_counts_tbl),
 stringsAsFactors = FALSE
 )

 # Decode patterns
 pattern_df$FE_vs_CD <- as.logical(as.integer(substr(pattern_df$pattern,1,1)))
 pattern_df$CD_vs_NC <- as.logical(as.integer(substr(pattern_df$pattern,2,2)))
 pattern_df$FE_vs_NC <- as.logical(as.integer(substr(pattern_df$pattern,3,3)))

 # Only show top patterns
 if (nrow(pattern_df) >15) {
 pattern_df <- pattern_df[1:15, ]
 }

 # Create a barplot
 pattern_df$label <- apply(pattern_df[, c("FE_vs_CD", "CD_vs_NC", "FE_vs_NC")],1,
 function(x) paste(names(venn_data)[x], collapse = " + "))

 p_upset <- ggplot(pattern_df, aes(x = reorder(label, count), y = count)) +
 geom_bar(stat = "identity", fill = "steelblue", color = "black", width =0.7) +
 coord_flip() +
 labs(x = "Intersection Pattern", y = "Number of Metabolites",
 title = "Overlap Patterns of Significant Metabolites") +
 theme_bw(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, face = "bold", size =14),
 axis.text.y = element_text(size =10))

 png_file <- file.path(FIGS_DIR, "upset_plot_patterns.png")
 ggsave(png_file, p_upset, width =10, height =7, dpi =300)
 pdf_file <- file.path(FIGS_DIR, "upset_plot_patterns.pdf")
 ggsave(pdf_file, p_upset, width =10, height =7)
 cat(" UpSet-like plot saved\n")
}

# ----17. Heatmaps ----
cat("Step17: Generating heatmaps...\n")

# ----17.1 Helper function for heatmaps ----
generate_heatmap <- function(expr_data, row_annot, col_annot, row_label_col,
 filename_png, filename_pdf,
 main_title = "", width =12, height =10,
 show_rownames = TRUE, fontsize_row =6) {

 if (is.null(expr_data) || nrow(expr_data) <2 || ncol(expr_data) <2) {
 cat(" Skipping heatmap: insufficient data\n")
 return(invisible(NULL))
 }

 # Row annotation
 ann_row <- NULL
 if (!is.null(row_annot) && ncol(row_annot) >0) {
 common_rows <- intersect(rownames(expr_data), rownames(row_annot))
 if (length(common_rows) >0) {
 ann_row <- row_annot[common_rows, , drop = FALSE]
 expr_data <- expr_data[common_rows, , drop = FALSE]
 }
 }

 # Column annotation
 ann_col <- NULL
 if (!is.null(col_annot) && ncol(col_annot) >0) {
 common_cols <- intersect(colnames(expr_data), rownames(col_annot))
 if (length(common_cols) >0) {
 ann_col <- col_annot[common_cols, , drop = FALSE]
 expr_data <- expr_data[, common_cols, drop = FALSE]
 }
 }

 # Build row labels
 labels_row <- rownames(expr_data)
 if (show_rownames && !is.null(row_label_col) &&
 row_label_col %in% colnames(row_annot)) {
 labels_row <- ifelse(!is.na(row_annot[rownames(expr_data), row_label_col]) &
 row_annot[rownames(expr_data), row_label_col] != "",
 as.character(row_annot[rownames(expr_data), row_label_col]),
 rownames(expr_data))
 }

 # Generate PNG heatmap
 pheatmap(expr_data,
 scale = "row",
 clustering_method = "ward.D2",
 annotation_col = ann_col,
 annotation_row = ann_row,
 labels_row = labels_row,
 show_rownames = show_rownames,
 show_colnames = TRUE,
 fontsize_row = fontsize_row,
 fontsize_col =8,
 main = main_title,
 filename = filename_png,
 width = width,
 height = height)
 cat(" Saved:", filename_png, "\n")

 # Generate PDF heatmap
 pheatmap(expr_data,
 scale = "row",
 clustering_method = "ward.D2",
 annotation_col = ann_col,
 annotation_row = ann_row,
 labels_row = labels_row,
 show_rownames = show_rownames,
 show_colnames = TRUE,
 fontsize_row = fontsize_row,
 fontsize_col =8,
 main = main_title,
 filename = filename_pdf,
 width = width,
 height = height)
 cat(" Saved:", filename_pdf, "\n")
}

# ----17.2 Prepare column annotation ----
col_annot <- data.frame(
 Group = group_short[colnames(expr_mat)],
 row.names = colnames(expr_mat),
 stringsAsFactors = FALSE
)

# ----17.3 Prepare row annotation (from metabolites.csv) ----
annot_for_heatmap <- data.frame(
 molecule_id = rownames(expr_mat),
 stringsAsFactors = FALSE,
 row.names = rownames(expr_mat)
)

# Merge with annotation
annot_sub <- annot[, c("name", "super_class", "class", "sub_class")]
annot_sub$molecule_id <- rownames(annot)

annot_merged <- merge(annot_for_heatmap, annot_sub, by = "molecule_id", all.x = TRUE)
rownames(annot_merged) <- annot_merged$molecule_id
annot_merged <- annot_merged[rownames(expr_mat), , drop = FALSE]

# Create row annotation data frame (for class/super_class)
row_annot_class <- NULL
if (any(!is.na(annot_merged$super_class) & annot_merged$super_class != "" &
 annot_merged$super_class != "")) {
 row_annot_class <- data.frame(
 SuperClass = annot_merged$super_class,
 Class = annot_merged$class,
 row.names = rownames(annot_merged),
 stringsAsFactors = FALSE
 )
 # Clean up empty values
 row_annot_class$SuperClass[is.na(row_annot_class$SuperClass) |
 row_annot_class$SuperClass == ""] <- "Unknown"
 row_annot_class$Class[is.na(row_annot_class$Class) |
 row_annot_class$Class == ""] <- "Unknown"
}

# ----17.4 Heatmap1: All significant metabolites across all comparisons ----
cat(" Heatmap1: All significant metabolites\n")
sig_all <- unique(unlist(lapply(sig_lists, function(x) x$molecule_id)))
cat(" Total unique significant molecules:", length(sig_all), "\n")

if (length(sig_all) >=2) {
 sig_expr <- expr_mat[intersect(sig_all, rownames(expr_mat)), , drop = FALSE]

 generate_heatmap(
 expr_data = sig_expr,
 row_annot = row_annot_class,
 col_annot = col_annot,
 row_label_col = "name",
 filename_png = file.path(FIGS_DIR, "heatmap_all_significant.png"),
 filename_pdf = file.path(FIGS_DIR, "heatmap_all_significant.pdf"),
 main_title = "All Significant Metabolites (adj.P <0.05)",
 width =14,
 height = max(8, min(30, nrow(sig_expr) *0.25)),
 show_rownames = nrow(sig_expr) <=100,
 fontsize_row =5
 )
} else {
 cat(" Skipping: fewer than2 significant molecules\n")
}

# ----17.5 Heatmap2: Top50 by |logFC| ----
cat(" Heatmap2: Top50 by |logFC|\n")
top50_list <- list()
for (comp_name in names(sig_lists)) {
 sig <- sig_lists[[comp_name]]
 if (nrow(sig) >0) {
 sig <- sig[1:min(50, nrow(sig)), ]
 top50_list[[comp_name]] <- sig$molecule_id
 }
}
top50_ids <- unique(unlist(top50_list))
cat(" Unique top molecules:", length(top50_ids), "\n")

if (length(top50_ids) >=2) {
 top50_expr <- expr_mat[intersect(top50_ids, rownames(expr_mat)), , drop = FALSE]

 # Sort columns by group
 group_order <- order(group_short[colnames(top50_expr)])
 top50_expr <- top50_expr[, group_order, drop = FALSE]

 generate_heatmap(
 expr_data = top50_expr,
 row_annot = row_annot_class,
 col_annot = col_annot,
 row_label_col = "name",
 filename_png = file.path(FIGS_DIR, "heatmap_top50_logFC.png"),
 filename_pdf = file.path(FIGS_DIR, "heatmap_top50_logFC.pdf"),
 main_title = "Top Metabolites by |logFC| (adj.P <0.05)",
 width =12,
 height = max(6, nrow(top50_expr) *0.35),
 show_rownames = TRUE,
 fontsize_row =7
 )
}

# ----17.6 Heatmap3: FE vs CD significant only ----
cat(" Heatmap3: FE vs CD significant metabolites\n")
fe_vs_cd_ids <- sig_lists[["FE_vs_CD"]]$molecule_id
if (length(fe_vs_cd_ids) >=2) {
 fe_cd_expr <- expr_mat[intersect(fe_vs_cd_ids, rownames(expr_mat)), , drop = FALSE]

 generate_heatmap(
 expr_data = fe_cd_expr,
 row_annot = row_annot_class,
 col_annot = col_annot,
 row_label_col = "name",
 filename_png = file.path(FIGS_DIR, "heatmap_FE_vs_CD.png"),
 filename_pdf = file.path(FIGS_DIR, "heatmap_FE_vs_CD.pdf"),
 main_title = "FE vs CD Significant Metabolites",
 width =12,
 height = max(8, min(30, nrow(fe_cd_expr) *0.25)),
 show_rownames = nrow(fe_cd_expr) <=80,
 fontsize_row =6
 )
} else {
 cat(" Skipping: fewer than2 significant molecules for FE vs CD\n")
}

# ----17.7 Heatmap4: Top500 expression profiles ----
cat(" Heatmap4: Top500 expression profiles\n")
top500_ids <- unique(top500_combined$molecule_id)
cat(" Unique molecules:", length(top500_ids), "\n")

if (length(top500_ids) >=2) {
 top500_expr <- expr_mat[intersect(top500_ids, rownames(expr_mat)), , drop = FALSE]

 # Sort columns by group
 group_order <- order(group_short[colnames(top500_expr)])
 top500_expr <- top500_expr[, group_order, drop = FALSE]

 generate_heatmap(
 expr_data = top500_expr,
 row_annot = row_annot_class,
 col_annot = col_annot,
 row_label_col = "name",
 filename_png = file.path(FIGS_DIR, "heatmap_top500_profiles.png"),
 filename_pdf = file.path(FIGS_DIR, "heatmap_top500_profiles.pdf"),
 main_title = "Top500 Metabolites by |logFC| - Expression Profiles",
 width =14,
 height =20,
 show_rownames = FALSE,
 fontsize_row =3
 )
}

# ----18. P-value Distribution Diagnostics ----
cat("Step18: Generating p-value distribution diagnostics...\n")

for (comp_name in names(all_results)) {
 tt <- all_results[[comp_name]]
 pval <- tt$P.Value[!is.na(tt$P.Value)]

 df_p <- data.frame(p_value = pval)

 p_hist <- ggplot(df_p, aes(x = p_value)) +
 geom_histogram(bins =50, fill = "steelblue", color = "black", alpha =0.7) +
 geom_hline(yintercept = length(pval) /50, linetype = "dashed", color = "red", alpha =0.5) +
 labs(x = "P-value", y = "Frequency",
 title = paste0("P-value Distribution: ", comp_name),
 subtitle = paste0("Total = ", length(pval),
 " | Significant (adj.P <0.05) = ",
 sum(tt$adj.P.Val <0.05, na.rm = TRUE))) +
 theme_bw(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, face = "bold", size =14))

 png_file <- file.path(FIGS_DIR, paste0("pvalue_distribution_", comp_name, ".png"))
 ggsave(png_file, p_hist, width =8, height =6, dpi =300)
 pdf_file <- file.path(FIGS_DIR, paste0("pvalue_distribution_", comp_name, ".pdf"))
 ggsave(pdf_file, p_hist, width =8, height =6)
 cat(" P-value distribution saved:", comp_name, "\n")
}

# ----19. Cross-Comparison Scatter Plot ----
cat("Step19: Generating cross-comparison scatter plot...\n")

# Merge logFC values from all comparisons
logFC_merged <- all_results[["FE_vs_CD"]][, c("molecule_id", "logFC", "adj.P.Val")]
names(logFC_merged)[2:3] <- c("logFC_FE_vs_CD", "adj.P.Val_FE_vs_CD")

tmp <- all_results[["CD_vs_NC"]][, c("molecule_id", "logFC", "adj.P.Val")]
names(tmp)[2:3] <- c("logFC_CD_vs_NC", "adj.P.Val_CD_vs_NC")
logFC_merged <- merge(logFC_merged, tmp, by = "molecule_id", all = TRUE)

tmp <- all_results[["FE_vs_NC"]][, c("molecule_id", "logFC", "adj.P.Val")]
names(tmp)[2:3] <- c("logFC_FE_vs_NC", "adj.P.Val_FE_vs_NC")
logFC_merged <- merge(logFC_merged, tmp, by = "molecule_id", all = TRUE)

# Scatter: FE_vs_CD logFC vs CD_vs_NC logFC
p_scatter <- ggplot(logFC_merged, aes(x = logFC_CD_vs_NC, y = logFC_FE_vs_CD)) +
 geom_point(aes(color = adj.P.Val_FE_vs_CD <0.05), alpha =0.6, size =1.5) +
 scale_color_manual(values = c("FALSE" = "grey70", "TRUE" = "#E41A1C"),
 name = "FE vs CD\nadj.P <0.05") +
 geom_hline(yintercept =0, linetype = "dashed", color = "darkgrey") +
 geom_vline(xintercept =0, linetype = "dashed", color = "darkgrey") +
 labs(x = "log2(FC): CD vs NC", y = "log2(FC): FE vs CD",
 title = "Cross-Comparison: logFC Correlation") +
 theme_bw(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, face = "bold", size =14))

png_file <- file.path(FIGS_DIR, "correlation_volcano_logFC_scatter.png")
ggsave(png_file, p_scatter, width =9, height =7, dpi =300)
pdf_file <- file.path(FIGS_DIR, "correlation_volcano_logFC_scatter.pdf")
ggsave(pdf_file, p_scatter, width =9, height =7)
cat(" Scatter plot saved\n")

# ----20. Cross-Comparison Trend Classification ----
cat("Step20: Classifying cross-comparison trend patterns...\n")

# For each molecule, compute group means
group_means <- sapply(levels(groups), function(grp) {
 samples <- sample_info$ID[groups == grp]
 samples <- intersect(samples, colnames(expr_mat))
 if (length(samples) >0) {
 rowMeans(expr_mat[, samples, drop = FALSE], na.rm = TRUE)
 } else {
 rep(NA, nrow(expr_mat))
 }
})
rownames(group_means) <- rownames(expr_mat)
colnames(group_means) <- c("NC_mean", "CD_mean", "FE_mean")

# Build combined results table
combined <- data.frame(
 molecule_id = rownames(anova_results),
 overall_F = anova_results$F,
 overall_P.Value = anova_results$P.Value,
 overall_adj.P.Val = anova_results$adj.P.Val,
 stringsAsFactors = FALSE
)

# Add group means
combined <- merge(combined, group_means, by.x = "molecule_id", by.y = "row.names",
 all.x = TRUE, sort = FALSE)

# Add per-comparison statistics
for (comp_name in names(all_results)) {
 tt <- all_results[[comp_name]]
 tt_sub <- tt[, c("molecule_id", "logFC", "AveExpr", "t", "P.Value",
 "adj.P.Val", "B", "regulation")]
 names(tt_sub)[-1] <- paste0(names(tt_sub)[-1], "_", comp_name)
 combined <- merge(combined, tt_sub, by = "molecule_id", all.x = TRUE, sort = FALSE)
}

# Add VIP scores
combined <- merge(combined, vip_df, by = "molecule_id", all.x = TRUE, sort = FALSE)

# Add metabolite annotation
annot_for_merge <- annot[, c("name", "formula", "exact_mass", "kegg", "hmdb",
 "super_class", "class", "sub_class", "kegg_category")]
annot_for_merge$molecule_id <- rownames(annot)
combined <- merge(combined, annot_for_merge, by = "molecule_id", all.x = TRUE, sort = FALSE)

# ----20.1 Trend classification logic ----
combined$trend_pattern <- "No significant change"

# Helper functions
is_sig <- function(p) !is.na(p) & p <0.05
is_up <- function(lfc) !is.na(lfc) & lfc >0
is_down <- function(lfc) !is.na(lfc) & lfc <0

for (i in 1:nrow(combined)) {
 cd_vs_nc_sig <- is_sig(combined$adj.P.Val_CD_vs_NC[i])
 fe_vs_cd_sig <- is_sig(combined$adj.P.Val_FE_vs_CD[i])
 fe_vs_nc_sig <- is_sig(combined$adj.P.Val_FE_vs_NC[i])

 cd_vs_nc_dir <- combined$logFC_CD_vs_NC[i]
 fe_vs_cd_dir <- combined$logFC_FE_vs_CD[i]
 fe_vs_nc_dir <- combined$logFC_FE_vs_NC[i]

 # Pattern1: Protective Rescue
 if (cd_vs_nc_sig && fe_vs_cd_sig) {
 if ((is_up(cd_vs_nc_dir) && is_down(fe_vs_cd_dir)) ||
 (is_down(cd_vs_nc_dir) && is_up(fe_vs_cd_dir))) {
 if (fe_vs_nc_sig) {
 combined$trend_pattern[i] <- "Partial Rescue (still differs from NC)"
 } else {
 combined$trend_pattern[i] <- "Full Rescue (restored to NC)"
 }
 next
 }
 }

 # Pattern2: Unique Protection
 if (fe_vs_cd_sig && !cd_vs_nc_sig) {
 combined$trend_pattern[i] <- "Unique Protection (iron-specific)"
 next
 }

 # Pattern3: Persistent Dysregulation
 if (cd_vs_nc_sig && fe_vs_nc_sig) {
 if ((is_up(cd_vs_nc_dir) && is_up(fe_vs_nc_dir)) ||
 (is_down(cd_vs_nc_dir) && is_down(fe_vs_nc_dir))) {
 combined$trend_pattern[i] <- "Persistent Dysregulation"
 next
 }
 }

 # Pattern4: Iron-specific
 if (fe_vs_cd_sig && fe_vs_nc_sig && !cd_vs_nc_sig) {
 combined$trend_pattern[i] <- "Iron-specific Alteration"
 next
 }

 # Pattern5: CDI-specific
 if (cd_vs_nc_sig && !fe_vs_cd_sig && !fe_vs_nc_sig) {
 combined$trend_pattern[i] <- "CDI-specific Only"
 next
 }
}

# Count patterns
cat(" Trend pattern counts:\n")
pattern_counts <- table(combined$trend_pattern)
print(pattern_counts)

# Save combined results
write.csv(combined, COMBINED_FILE, row.names = FALSE)
cat(" Saved:", COMBINED_FILE, "\n")

# ----21. Summary Statistics ----
cat("\n==============================================================\n")
cat("LIMMA Differential Analysis - Summary\n")
cat("==============================================================\n")
cat("Total molecules analyzed:", nrow(expr_mat), "\n")
cat("Total samples:", ncol(expr_mat), "\n")
cat("Groups:", paste(levels(groups), collapse = ", "), "\n")
cat("\nOverall F-test:\n")
cat(" Significant (adj.P <0.05):", n_anova_sig, "\n")
cat("\nPairwise comparisons:\n")
for (comp_name in names(sig_lists)) {
 n_sig <- nrow(sig_lists[[comp_name]])
 n_up <- sum(sig_lists[[comp_name]]$logFC >0)
 n_down <- sum(sig_lists[[comp_name]]$logFC <0)
 cat(" ", comp_name, ":", n_sig, "significant (", n_up, "up,", n_down, "down)\n")
}
cat("\nVIP score integration:\n")
cat(" VIP >1:", sum(vip_df$VIP_score >1, na.rm = TRUE), "\n")
cat("\nCross-comparison trend patterns:\n")
print(pattern_counts)
cat("\n")

# ----22. Check for Specific Key Metabolites of Interest ----
cat("Step22: Checking key metabolite patterns...\n")

key_metabolites <- c("L-proline", "Proline", "TUDCA",
 "Taurocholate", "Cholate", "Deoxycholate",
 "Butyrate", "Acetate", "Propionate",
 "Heme", "S100a8", "S100a9",
 "IL-1beta", "TNF-alpha", "CXCL1")

# Look for these in the annotation
annot_key <- annot[grepl(paste(key_metabolites, collapse = "|"),
 annot$name, ignore.case = TRUE), ]
if (nrow(annot_key) >0) {
 cat(" Key metabolites found in annotation:\n")
 for (i in 1:min(20, nrow(annot_key))) {
 mid <- rownames(annot_key)[i]
 mname <- annot_key$name[i]
 if (mid %in% combined$molecule_id) {
 idx <- which(combined$molecule_id == mid)
 cat(" ", mname, ":")
 cat(" FE_vs_CD logFC =", round(combined$logFC_FE_vs_CD[idx],3),
 "(adj.P =", format(combined$adj.P.Val_FE_vs_CD[idx], scientific = TRUE, digits =3), ")")
 cat(" | CD_vs_NC logFC =", round(combined$logFC_CD_vs_NC[idx],3),
 "(adj.P =", format(combined$adj.P.Val_CD_vs_NC[idx], scientific = TRUE, digits =3), ")")
 cat(" | Trend:", combined$trend_pattern[idx], "\n")
 }
 }
} else {
 cat(" No key metabolites found in annotation under expected names.\n")
 cat(" (Note: Metabolite names may differ due to database identifiers.)\n")
}

# ----23. Completion ----
cat("\n==============================================================\n")
cat("Module4 LIMMA Analysis Complete!\n")
cat("==============================================================\n")
cat("Output files:\n")
cat(" Tables:", TABLES_OUT, "\n")
cat(" Figures:", FIGS_DIR, "\n")
cat("\nGenerated tables:\n")
for (f in list.files(TABLES_OUT, pattern = "\\.csv$")) {
 cat(" -", f, "\n")
}
cat("\nGenerated figures:\n")
for (f in list.files(FIGS_DIR, pattern = "\\.(png|pdf)$")) {
 cat(" -", f, "\n")
}
cat("\n")
