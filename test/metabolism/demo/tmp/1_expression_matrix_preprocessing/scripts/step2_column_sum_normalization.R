# ============================================================
# Module1 Step2: Column-Sum Normalization (Relative Abundance)
# Description: Normalize expression matrix by sample column sum,
# converting to relative abundance in ppm units
# ============================================================

# --- Load required libraries ---
library(utils)

# --- Source helper scripts ---
source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/normalization.R")

# --- Define paths ---
input_expr_file <- "G:/OmicsWorks/test/metabolism/expression.csv"
input_meta_file <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"
output_dir <- "G:/OmicsWorks/test/metabolism/demo/tmp/1_expression_matrix_preprocessing"
figures_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/1_expression_matrix_preprocessing/figures"

output_norm_file <- file.path(output_dir, "preprocess_step2_normalized.csv")
output_before_plot <- file.path(figures_dir, "step2_colsums_before.png")
output_after_plot <- file.path(figures_dir, "step2_colsums_after.png")

# Create output directories
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(figures_dir, showWarnings = FALSE, recursive = TRUE)

cat("========================================================\n")
cat("Module1 Step2: Column-Sum Normalization (Relative Abundance)\n")
cat("========================================================\n\n")

# ============================================================
# Step2.1: Load Expression Data
# ============================================================
cat("[Step2.1] Loading expression matrix...\n")
expr_raw <- load_expression_matrix(input_expr_file)
cat(" Dimensions:", nrow(expr_raw), "features x", ncol(expr_raw), "samples\n")
cat(" Sample IDs:", paste(colnames(expr_raw), collapse = ", "), "\n\n")

# ============================================================
# Step2.2: Check & Impute Missing Values (half-min)
# ============================================================
cat("[Step2.2] Checking and imputing missing values...\n")
na_count <- sum(is.na(expr_raw))
cat(" NA values detected:", na_count, "\n")

if (na_count >0) {
 source("G:/OmicsWorks/agent/rscript/missing_value.R")
 expr_clean <- impute_half_min(expr_raw)
 cat(" Missing values imputed using half-minimum strategy.\n")
} else {
 expr_clean <- expr_raw
 cat(" No missing values found. Skipping imputation.\n")
}
cat("\n")

# ============================================================
# Step2.3: Column-Sum Normalization (Relative Abundance, ppm)
# ============================================================
cat("[Step2.3] Performing column-sum normalization (ppm)...\n")

# Calculate column sums before normalization
col_sums_before <- colSums(expr_clean)
cat(" Column sums BEFORE normalization:\n")
cat(" Range: [", min(col_sums_before), ", ", max(col_sums_before), "]\n", sep = "")
cat(" Mean :", round(mean(col_sums_before),2), "\n")
cat(" SD :", round(sd(col_sums_before),2), "\n\n")

# Perform normalization (ppm = parts per million)
expr_normalized <- normalize_sample_sum(expr_clean, scale_factor =1e6)

# Verify column sums after normalization
col_sums_after <- colSums(expr_normalized)
cat(" Column sums AFTER normalization:\n")
cat(" Range: [", min(col_sums_after), ", ", max(col_sums_after), "]\n", sep = "")
cat(" Mean :", round(mean(col_sums_after),2), "\n")
cat(" SD :", round(sd(col_sums_after),2), "\n")
cat(" (Expected: all ~1e6 ppm)\n\n")

# ============================================================
# Step2.4: Visualization - Column Sums Comparison
# ============================================================
cat("[Step2.4] Generating visualization...\n")

# Prepare data for plotting
plot_data <- data.frame(
 Sample = rep(names(col_sums_before),2),
 TotalSum = c(col_sums_before, col_sums_after),
 Stage = factor(rep(c("Before Normalization", "After Normalization (ppm)"),
 each = length(col_sums_before)),
 levels = c("Before Normalization", "After Normalization (ppm)"))
)

# Load sample metadata for coloring
sample_meta <- load_sample_metadata(input_meta_file)
meta_match <- sample_meta[match(names(col_sums_before), sample_meta$ID), ]
plot_data$Group <- factor(rep(as.character(meta_match$sample_info),2),
 levels = unique(sample_meta$sample_info))

# Barplot: before normalization
library(ggplot2)
p_before <- ggplot(plot_data[plot_data$Stage == "Before Normalization", ],
 aes(x = Sample, y = TotalSum, fill = Group)) +
 geom_bar(stat = "identity", color = "black", width =0.7) +
 scale_fill_manual(values = c("Clostridium difficile infection" = "#E64B35",
 "high iron diet before" = "#4DBBD5",
 "Standard (control)" = "#00A087")) +
 labs(title = "Column Sums Before Normalization",
 x = "Sample", y = "Total Intensity Sum",
 fill = "Group") +
 theme_bw(base_size =13) +
 theme(axis.text.x = element_text(angle =45, hjust =1),
 plot.title = element_text(hjust =0.5))

ggsave(output_before_plot, p_before, width =10, height =6, dpi =150)
cat(" Saved:", output_before_plot, "\n")

# Barplot: after normalization
p_after <- ggplot(plot_data[plot_data$Stage == "After Normalization (ppm)", ],
 aes(x = Sample, y = TotalSum, fill = Group)) +
 geom_bar(stat = "identity", color = "black", width =0.7) +
 scale_fill_manual(values = c("Clostridium difficile infection" = "#E64B35",
 "high iron diet before" = "#4DBBD5",
 "Standard (control)" = "#00A087")) +
 labs(title = "Column Sums After Normalization (ppm)",
 x = "Sample", y = "Relative Abundance (ppm)",
 fill = "Group") +
 theme_bw(base_size =13) +
 theme(axis.text.x = element_text(angle =45, hjust =1),
 plot.title = element_text(hjust =0.5))

ggsave(output_after_plot, p_after, width =10, height =6, dpi =150)
cat(" Saved:", output_after_plot, "\n\n")

# ============================================================
# Step2.5: Save Normalized Matrix
# ============================================================
cat("[Step2.5] Saving normalized expression matrix...\n")
write.csv(
 cbind(rownames(expr_normalized), as.data.frame(expr_normalized)),
 file = output_norm_file,
 row.names = FALSE
)
cat(" Saved:", output_norm_file, "\n")

# Also save as the general preprocessed output for downstream
# (since this is part of the full pipeline)
output_preprocessed <- "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv"
write.csv(
 cbind(rownames(expr_normalized), as.data.frame(expr_normalized)),
 file = output_preprocessed,
 row.names = FALSE
)
cat(" Also saved as preprocessed output:", output_preprocessed, "\n\n")

# ============================================================
# Summary
# ============================================================
cat("========================================================\n")
cat("STEP2 SUMMARY - Column-Sum Normalization\n")
cat("========================================================\n")
cat(" Input features :", nrow(expr_raw), "\n")
cat(" Output features :", nrow(expr_normalized), "\n")
cat(" Samples :", ncol(expr_normalized), "\n")
cat(" NA values imputed :", na_count, "\n")
cat(" Scale factor :1e6 (ppm)\n")
cat(" Before - Sum range : [", round(min(col_sums_before),1), ", ",
 round(max(col_sums_before),1), "]\n", sep = "")
cat(" After - Sum range : [", round(min(col_sums_after),1), ", ",
 round(max(col_sums_after),1), "]\n", sep = "")
cat(" Expression range : [", round(min(expr_normalized),4), ", ",
 round(max(expr_normalized),4), "]\n", sep = "")
cat(" Output file :", output_norm_file, "\n")
cat(" Figures :", output_before_plot, "\n")
cat(" ", output_after_plot, "\n")
cat("========================================================\n")
cat("Step2 completed successfully.\n")
