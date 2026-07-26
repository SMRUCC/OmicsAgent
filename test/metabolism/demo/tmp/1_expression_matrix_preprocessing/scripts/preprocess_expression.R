# ============================================================
# Module1: Expression Matrix Preprocessing
# Description: Missing value imputation, column-sum normalization,
# log2 transformation, and median scaling for 
# metabolomics expression data
# Author: Bioinformatics Analysis Pipeline
# ============================================================

# --- Load required libraries ---
library(utils)

# --- Source helper scripts ---
source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/missing_value.R")
source("G:/OmicsWorks/agent/rscript/normalization.R")

# --- Define paths ---
input_expr_file <- "G:/OmicsWorks/test/metabolism/expression.csv"
input_meta_file <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"
output_dir <- "G:/OmicsWorks/test/metabolism/demo/tmp/1_expression_matrix_preprocessing"
figures_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/1_expression_matrix_preprocessing/figures"
output_expr_file <- file.path(output_dir, "preprocessed_expression.csv")

# Create output directories
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(figures_dir, showWarnings = FALSE, recursive = TRUE)

cat("========================================\n")
cat("Module1: Expression Matrix Preprocessing\n")
cat("========================================\n\n")

# ============================================================
# Step0: Load Data
# ============================================================
cat("[Step0] Loading expression matrix...\n")
expr_raw <- load_expression_matrix(input_expr_file)
cat(" Dimensions:", nrow(expr_raw), "features x", ncol(expr_raw), "samples\n")
cat(" Samples:", paste(colnames(expr_raw), collapse = ", "), "\n\n")

cat("[Step0] Loading sample metadata...\n")
sample_meta <- load_sample_metadata(input_meta_file)
cat(" Groups:", paste(levels(sample_meta$sample_info), collapse = ", "), "\n")
print(table(sample_meta$sample_info))
cat("\n")

# ============================================================
# Step1: Missing Value Imputation (Half Minimum Positive Value)
# ============================================================
cat("[Step1] Missing value imputation (half-minimum strategy)...\n")
na_before <- sum(is.na(expr_raw))
cat(" NA values before imputation:", na_before, "\n")

expr_imputed <- impute_half_min(expr_raw)

na_after <- sum(is.na(expr_imputed))
cat(" NA values after imputation:", na_after, "\n")
cat(" Imputation complete.\n\n")

# ============================================================
# Step2: Column Sum Normalization (Relative Abundance, ppm)
# ============================================================
cat("[Step2] Column-sum normalization (relative abundance, ppm)...\n")
# Check column sums before normalization
col_sums_before <- colSums(expr_imputed)
cat(" Column sums range: [", min(col_sums_before), ", ", max(col_sums_before), "]\n", sep = "")

expr_norm <- normalize_sample_sum(expr_imputed, scale_factor =1e6)

col_sums_after <- colSums(expr_norm)
cat(" After normalization, column sums: [", min(col_sums_after), ", ", max(col_sums_after), "]\n", sep = "")
cat(" Normalization complete.\n\n")

# ============================================================
# Step3: Log2 Transformation (if max >100, data not log-transformed)
# ============================================================
max_val <- max(expr_norm, na.rm = TRUE)
cat("[Step3] Checking log transformation requirement...\n")
cat(" Max value in data:", max_val, "\n")

if (max_val >100) {
 cat(" Max >100, applying log2(x+1) transformation...\n")
 expr_log <- transform_log(expr_norm, base =2, pseudo_count =1)
 cat(" After log2: value range [", min(expr_log), ", ", max(expr_log), "]\n", sep = "")
} else {
 cat(" Max <=100, data appears already log-transformed. Skipping.\n")
 expr_log <- expr_norm
}
cat(" Log transformation complete.\n\n")

# ============================================================
# Step4: Median Scaling by Feature (Row)
# ============================================================
cat("[Step4] Median scaling by feature (row)...\n")
# Calculate feature medians before scaling
feature_medians <- apply(expr_log,1, median, na.rm = TRUE)
cat(" Feature medians range: [", min(feature_medians), ", ", max(feature_medians), "]\n", sep = "")

expr_scaled <- scale_feature_median(expr_log, log_transform = FALSE)
cat(" After scaling: value range [", min(expr_scaled), ", ", max(expr_scaled), "]\n", sep = "")
cat(" Median scaling complete.\n\n")

# ============================================================
# Step5: Summary Statistics and Output
# ============================================================
cat("[Step5] Generating summary statistics...\n")

# Save preprocessed matrix
write.csv(
 cbind(rownames(expr_scaled), as.data.frame(expr_scaled)),
 file = output_expr_file,
 row.names = FALSE
)
cat(" Preprocessed matrix saved to:", output_expr_file, "\n")

# Also save the sample metadata for downstream use
# (copy to output dir for easy reference)
file.copy(input_meta_file, file.path(output_dir, "sampleinfo.csv"), overwrite = TRUE)
cat(" Sample metadata copied to output directory.\n\n")

# ============================================================
# Summary
# ============================================================
cat("========================================\n")
cat("PREPROCESSING SUMMARY\n")
cat("========================================\n")
cat("Input features :", nrow(expr_raw), "\n")
cat("Output features:", nrow(expr_scaled), "\n")
cat("Samples :", ncol(expr_scaled), "\n")
cat("Groups :", paste(levels(sample_meta$sample_info), collapse = ", "), "\n")
cat("NA imputed :", na_before, "\n")
cat("Normalization : Column-sum (ppm)\n")
cat("Log transform :", ifelse(max_val >100, "log2(x+1)", "none"), "\n")
cat("Scaling : Feature-median\n")
cat("Output file :", output_expr_file, "\n")
cat("========================================\n")
cat("Module1 completed successfully.\n")
