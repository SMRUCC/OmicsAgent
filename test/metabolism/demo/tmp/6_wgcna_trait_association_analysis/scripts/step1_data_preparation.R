###############################################################
# WGCNA Trait Association Analysis - Step1: Data Preparation
# Reads expression matrix, builds traits (group encoding + GSVA),
# selects soft threshold power
###############################################################

# ----0. Output directories ----
base_dir <- "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis"
tables_dir <- file.path(base_dir, "tables")
figures_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/6_wgcna_trait_association_analysis/figures"
scripts_dir <- file.path(base_dir, "scripts")

for (d in c(tables_dir, figures_dir, scripts_dir)) {
 if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

cat("=== WGCNA Step1: Data Preparation ===\n")
cat("Output tables:", tables_dir, "\n")
cat("Output figures:", figures_dir, "\n")

# ----1. Install / load packages ----
required_pkgs <- c("WGCNA", "GSVA", "igraph", "ggplot2", "reshape2",
 "ComplexHeatmap", "circlize", "grid", "stats", "grDevices")

for (pkg in required_pkgs) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 cat("Installing missing package:", pkg, "\n")
 if (pkg %in% c("WGCNA", "GSVA")) {
 if (!requireNamespace("BiocManager", quietly = TRUE))
 install.packages("BiocManager", repos = "https://cloud.r-project.org")
 BiocManager::install(pkg, ask = FALSE, update = FALSE)
 } else {
 install.packages(pkg, repos = "https://cloud.r-project.org")
 }
 }
}

library(WGCNA)
library(GSVA)
library(ggplot2)
library(reshape2)
library(grDevices)

# Allow multi-threading for WGCNA
allowWGCNAThreads()
cat("WGCNA multi-threading enabled.\n")

# ----2. Load preprocessed expression matrix ----
expr_file <- "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv"
cat("Loading expression matrix from:", expr_file, "\n")

expr_raw <- read.csv(expr_file, row.names =1, check.names = FALSE)
cat("Expression matrix dimensions:", nrow(expr_raw), "metabolites x", ncol(expr_raw), "samples\n")

# Remove QC samples if present (they have "QC" in name)
qc_cols <- grep("QC", colnames(expr_raw), value = TRUE, ignore.case = TRUE)
if (length(qc_cols) >0) {
 cat("Removing QC samples:", paste(qc_cols, collapse = ", "), "\n")
 expr_raw <- expr_raw[, !colnames(expr_raw) %in% qc_cols]
}
cat("After QC removal:", ncol(expr_raw), "samples remaining\n")

# ----3. MAD calculation (full selection as <20000) ----
cat("Calculating MAD for", nrow(expr_raw), "metabolites...\n")
mad_values <- apply(expr_raw,1, mad, na.rm = TRUE)
mad_order <- order(mad_values, decreasing = TRUE)

# Since total metabolites (2059) <20000, select all
selected_features <- rownames(expr_raw)[mad_order]
expr_matrix <- expr_raw[selected_features, , drop = FALSE]
cat("Selected", length(selected_features), "metabolites (all, since <20000)\n")

# ----4. Load sample info and build group encoding traits ----
sampleinfo_file <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"
cat("Loading sample metadata from:", sampleinfo_file, "\n")
sample_info <- read.csv(sampleinfo_file, stringsAsFactors = FALSE)

# Filter out QC samples
sample_info <- sample_info[!grepl("QC", sample_info$sample_info, ignore.case = TRUE), ]
cat("Sample info rows after QC filter:", nrow(sample_info), "\n")

# Map sample ID to group
sample_group_map <- setNames(sample_info$sample_info, sample_info$sample_name)

# Build numeric trait data frame (samples as rows)
all_samples <- colnames(expr_matrix)
cat("Building group encoding traits for", length(all_samples), "samples...\n")

group_traits <- data.frame(
 row.names = all_samples,
 is_NC = as.numeric(sapply(all_samples, function(s) {
 grp <- sample_group_map[s]
 if (is.na(grp)) return(NA)
 as.numeric(grp == "Standard (control)")
 })),
 is_CD = as.numeric(sapply(all_samples, function(s) {
 grp <- sample_group_map[s]
 if (is.na(grp)) return(NA)
 as.numeric(grp == "Clostridium difficile infection")
 })),
 is_FE = as.numeric(sapply(all_samples, function(s) {
 grp <- sample_group_map[s]
 if (is.na(grp)) return(NA)
 as.numeric(grp == "high iron diet before")
 })),
 stringsAsFactors = FALSE
)

cat("Group traits summary:\n")
print(table(sapply(all_samples, function(s) sample_group_map[s])))

# Remove any rows with NA
na_rows <- apply(is.na(group_traits),1, any)
if (any(na_rows)) {
 cat("Removing", sum(na_rows), "samples with missing group info.\n")
 group_traits <- group_traits[!na_rows, , drop = FALSE]
 expr_matrix <- expr_matrix[, rownames(group_traits), drop = FALSE]
}

cat("Final samples for analysis:", nrow(group_traits), "\n")
cat("Final metabolites:", nrow(expr_matrix), "\n")

# ----5. Build GSVA gene sets from metabolites.csv ----
metabolites_file <- "G:/OmicsWorks/test/metabolism/metabolites.csv"
cat("Loading metabolite annotations from:", metabolites_file, "\n")
metab_anno <- read.csv(metabolites_file, row.names =1, check.names = FALSE)
cat("Metabolite annotation rows:", nrow(metab_anno), "\n")

# Clean HTML entities in names
clean_name <- function(x) {
 x <- gsub("&gamma;", "gamma", x)
 x <- gsub("&delta;", "delta", x)
 x <- gsub("&beta;", "beta", x)
 x <- gsub("&alpha;", "alpha", x)
 x <- gsub("&kappa;", "kappa", x)
 x <- gsub("&lt;", "<", x)
 x <- gsub("&gt;", ">", x)
 x <- gsub("&amp;", "&", x)
 x <- gsub("<[^>]+>", "", x) # Remove HTML tags
 x <- gsub("\\s+", " ", x)
 trimws(x)
}

metab_anno$name_clean <- clean_name(metab_anno$name)

# Determine mapping column: try name_clean first, then id
expr_rownames <- rownames(expr_matrix)
cat("First few expression rownames:", paste(head(expr_rownames), collapse = "; "), "\n")
cat("First few metabolite names:", paste(head(metab_anno$name_clean), collapse = "; "), "\n")

# Find overlap between expression rownames and annotation
overlap_name <- sum(expr_rownames %in% metab_anno$name_clean)
overlap_id <- sum(expr_rownames %in% as.character(metab_anno$id))

cat("Overlap with 'name_clean':", overlap_name, "\n")
cat("Overlap with 'id':", overlap_id, "\n")

if (overlap_name >= overlap_id && overlap_name >0) {
 map_col <- "name_clean"
 cat("Using 'name_clean' column for mapping.\n")
} else if (overlap_id >0) {
 map_col <- "id"
 cat("Using 'id' column for mapping.\n")
} else {
 # Try the rownames of metab_anno
 overlap_rn <- sum(expr_rownames %in% rownames(metab_anno))
 cat("Overlap with rownames:", overlap_rn, "\n")
 if (overlap_rn >0) {
 metab_anno$mapping_id <- rownames(metab_anno)
 map_col <- "mapping_id"
 cat("Using rownames for mapping.\n")
 } else {
 stop("Cannot map expression rownames to metabolite annotation!")
 }
}

# Build mapping from expression rowname -> annotation row
match_idx <- match(expr_rownames, metab_anno[[map_col]])
anno_matched <- metab_anno[match_idx, ]
rownames(anno_matched) <- expr_rownames

# Build gene sets from kegg_category column
cat("Building GSVA gene sets from kegg_category...\n")
kegg_cat_col <- "kegg_category"
if (!kegg_cat_col %in% colnames(anno_matched)) {
 # Try alternative column names
 alt_names <- grep("kegg|pathway|KEGG", colnames(anno_matched), value = TRUE, ignore.case = TRUE)
 cat("Available KEGG-related columns:", paste(alt_names, collapse = ", "), "\n")
 if (length(alt_names) >0) {
 kegg_cat_col <- alt_names[1]
 } else {
 stop("No kegg_category column found in metabolite annotation!")
 }
}

cat("Using column:", kegg_cat_col, "for KEGG pathway gene sets\n")

# Split semicolon-separated categories
kegg_raw <- as.character(anno_matched[[kegg_cat_col]])
kegg_raw[is.na(kegg_raw)] <- ""

gene_sets <- list()
for (i in seq_along(kegg_raw)) {
 if (kegg_raw[i] == "") next
 categories <- trimws(strsplit(kegg_raw[i], ";")[[1]])
 categories <- categories[categories != ""]
 for (cat_name in categories) {
 if (is.null(gene_sets[[cat_name]])) {
 gene_sets[[cat_name]] <- c()
 }
 gene_sets[[cat_name]] <- c(gene_sets[[cat_name]], expr_rownames[i])
 }
}

cat("Built", length(gene_sets), "KEGG pathway gene sets.\n")
cat("Pathway sizes:", paste(names(head(gene_sets,10)), 
 sapply(head(gene_sets,10), length), sep = "=", collapse = "; "), "\n")

# ----6. Run GSVA ----
cat("Running GSVA...\n")
# Filter gene sets with at least2 metabolites
gene_sets <- gene_sets[sapply(gene_sets, length) >=2]
cat("After min size filter:", length(gene_sets), "gene sets\n")

gsva_param <- GSVA::gsvaParam(
 exprData = as.matrix(expr_matrix),
 geneSets = gene_sets,
 kcdf = "Gaussian",
 minSize =2,
 maxSize =500
)
gsva_scores <- GSVA::gsva(gsva_param)

cat("GSVA result dimensions:", nrow(gsva_scores), "pathways x", ncol(gsva_scores), "samples\n")

# Save GSVA scores
gsva_file <- file.path(tables_dir, "wgcna_gsva_scores.csv")
write.csv(gsva_scores, gsva_file)
cat("GSVA scores saved to:", gsva_file, "\n")

# Transpose GSVA scores for trait use (samples as rows)
gsva_traits <- as.data.frame(t(gsva_scores))
cat("GSVA traits dimensions (samples x pathways):", nrow(gsva_traits), "x", ncol(gsva_traits), "\n")

# ----7. Combine all traits ----
# Ensure sample order consistency
common_samples <- intersect(rownames(group_traits), rownames(gsva_traits))
cat("Common samples between groups and GSVA:", length(common_samples), "\n")

group_traits <- group_traits[common_samples, , drop = FALSE]
gsva_traits <- gsva_traits[common_samples, , drop = FALSE]
expr_matrix <- expr_matrix[, common_samples, drop = FALSE]

all_traits <- cbind(group_traits, gsva_traits)
cat("Combined trait dimensions:", nrow(all_traits), "samples x", ncol(all_traits), "traits\n")
cat("Trait names:", paste(colnames(all_traits), collapse = ", "), "\n")

# Save combined traits
traits_file <- file.path(tables_dir, "wgcna_all_traits.csv")
write.csv(cbind(Sample = rownames(all_traits), all_traits), traits_file, row.names = FALSE)
cat("Combined traits saved to:", traits_file, "\n")

# ----8. Soft threshold selection ----
cat("Running pickSoftThreshold...\n")
powers <- c(1:10, seq(12,20, by =2))

# Transpose: samples as rows for WGCNA
datExpr <- as.data.frame(t(expr_matrix))

sft <- pickSoftThreshold(
 datExpr, 
 powerVector = powers,
 networkType = "signed",
 verbose =0
)

# Extract results
sft_df <- data.frame(
 Power = sft$fitIndices[,1],
 SFT_R_sq = -sign(sft$fitIndices[,3]) * sft$fitIndices[,2],
 Slope = sft$fitIndices[,5],
 Mean_k = sft$fitIndices[,5],
 Median_k = sft$fitIndices[,6],
 Max_k = sft$fitIndices[,7]
)

# Determine optimal power
power_estimate <- sft$powerEstimate
if (is.na(power_estimate)) {
 # Find first power where R² >=0.8
 good_idx <- which(sft_df$SFT_R_sq >=0.8)
 if (length(good_idx) >0) {
 power_estimate <- sft_df$Power[good_idx[1]]
 } else {
 power_estimate <-6 # default fallback
 }
}
cat("Selected soft threshold power:", power_estimate, "\n")

# Save soft threshold results
sft_file <- file.path(tables_dir, "wgcna_soft_threshold.csv")
write.csv(sft_df, sft_file, row.names = FALSE)
cat("Soft threshold results saved to:", sft_file, "\n")

# ----9. Plot soft threshold selection ----
cat("Plotting soft threshold selection...\n")

# Plot1: Scale Free Topology Model Fit
p1 <- ggplot(sft_df, aes(x = Power, y = SFT_R_sq)) +
 geom_point(size =3, color = "steelblue") +
 geom_line(color = "steelblue", alpha =0.5) +
 geom_hline(yintercept =0.8, linetype = "dashed", color = "red", alpha =0.7) +
 geom_hline(yintercept =0.9, linetype = "dashed", color = "darkred", alpha =0.5) +
 geom_text(aes(label = Power), vjust = -1, size =3.5) +
 scale_x_continuous(breaks = powers) +
 labs(
 title = "Scale Free Topology Model Fit (signed)",
 x = "Soft Threshold (Power)",
 y = expression("Scale Free Topology Model Fit, " ~ R^2)
 ) +
 theme_bw(base_size =14) +
 theme(
 plot.title = element_text(hjust =0.5, face = "bold"),
 panel.grid.minor = element_blank()
 )

# Plot2: Mean Connectivity
p2 <- ggplot(sft_df, aes(x = Power, y = Mean_k)) +
 geom_point(size =3, color = "steelblue") +
 geom_line(color = "steelblue", alpha =0.5) +
 geom_text(aes(label = Power), vjust = -1, size =3.5) +
 scale_x_continuous(breaks = powers) +
 labs(
 title = "Mean Connectivity",
 x = "Soft Threshold (Power)",
 y = "Mean Connectivity"
 ) +
 theme_bw(base_size =14) +
 theme(
 plot.title = element_text(hjust =0.5, face = "bold"),
 panel.grid.minor = element_blank()
 )

# Combine using gridExtra or cowplot
if (!requireNamespace("cowplot", quietly = TRUE)) {
 install.packages("cowplot", repos = "https://cloud.r-project.org")
}
library(cowplot)

combined_plot <- plot_grid(p1, p2, ncol =2, align = "h", labels = c("A", "B"))

# Save PDF
pdf_file <- file.path(figures_dir, "SoftThreshold_selection.pdf")
pdf(pdf_file, width =14, height =6)
print(combined_plot)
dev.off()
cat("PDF saved:", pdf_file, "\n")

# Save PNG
png_file <- file.path(figures_dir, "SoftThreshold_selection.png")
png(png_file, width =14 *300, height =6 *300, res =300)
print(combined_plot)
dev.off()
cat("PNG saved:", png_file, "\n")

# ----10. Save intermediate RData for next steps ----
rdata_file <- file.path(base_dir, "wgcna_step1_data.RData")
save(
 expr_matrix, datExpr, all_traits, group_traits, gsva_traits,
 gene_sets, gsva_scores, power_estimate, sft_df,
 selected_features, anno_matched,
 file = rdata_file
)
cat("Step1 data saved to:", rdata_file, "\n")

cat("\n=== WGCNA Step1 completed successfully! ===\n")
cat("Selected soft threshold power:", power_estimate, "\n")
cat("Number of traits:", ncol(all_traits), "\n")
cat("Number of samples:", nrow(all_traits), "\n")
cat("Number of metabolites:", nrow(expr_matrix), "\n")
cat("Number of GSVA pathways:", nrow(gsva_scores), "\n")
