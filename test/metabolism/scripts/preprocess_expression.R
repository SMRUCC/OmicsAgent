# ============================================================
# Expression Matrix Preprocessing Script
# Dataset: Metabolomics expression data
# Steps:
#1. Load expression matrix and sample metadata
#2. Fill missing values with half of min positive per row
#3. Normalize by column sum (relative abundance, ppm)
#4. Log2 transformation (since max value >100)
#5. Median scaling per row (molecule)
#6. Save preprocessed matrix
# ============================================================

# Source R scripts from tools directory
source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/missing_value.R")
source("G:/OmicsWorks/agent/rscript/normalization.R")

# ------------------------------
# Step0: Set paths
# ------------------------------
input_expr <- "G:/OmicsWorks/test/metabolism/expression.csv"
input_meta <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"
output_dir <- "G:/OmicsWorks/test/metabolism/tmp"
output_file <- file.path(output_dir, "preprocessed_expression.csv")

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# ------------------------------
# Step1: Load data
# ------------------------------
cat("=== Step1: Loading expression matrix ===\n")
expr <- load_expression_matrix(input_expr)
meta <- load_sample_metadata(input_meta)

cat("Expression matrix:", nrow(expr), "features x", ncol(expr), "samples\n")
cat("Sample groups:", paste(levels(meta$sample_info), collapse = ", "), "\n")

# ------------------------------
# Step2: Fill missing values (half min positive per row)
# ------------------------------
cat("\n=== Step2: Missing value imputation ===\n")
cat("Current NA count:", sum(is.na(expr)), "\n")

# Even if0 NAs, we still call the function for consistent pipeline
expr_imputed <- impute_half_min(expr)
cat("After imputation NA count:", sum(is.na(expr_imputed)), "\n")

# ------------------------------
# Step3: Normalize by column sum (relative abundance, ppm)
# ------------------------------
cat("\n=== Step3: Column-sum normalization (relative abundance) ===\n")
cat("Column sums before normalization:\n")
print(round(colSums(expr_imputed),2))

# Convert to relative abundance (ppm scale)
expr_norm <- normalize_sample_sum(expr_imputed, scale_factor =1e6, pseudo_count =1)

cat("Column sums after normalization (should all be ~1e6):\n")
print(round(colSums(expr_norm),2))

# ------------------------------
# Step4: Log transformation
# ------------------------------
cat("\n=== Step4: Log transformation ===\n")
max_val <- max(expr_norm, na.rm = TRUE)
cat("Max value after normalization:", max_val, "\n")

if (max_val >100) {
 cat("Max value >100, applying log2 transformation.\n")
 expr_log <- transform_log(expr_norm, base =2, pseudo_count =1)
} else {
 cat("Max value <=100, no log transformation needed.\n")
 expr_log <- expr_norm
}

cat("After log2 transform - range: [", min(expr_log), ", ", max(expr_log), "]\n", sep="")

# ------------------------------
# Step5: Median scaling per row (molecule)
# ------------------------------
cat("\n=== Step5: Median scaling per molecule ===\n")
expr_scaled <- scale_feature_median(expr_log, log_transform = FALSE)

cat("After median scaling - range: [", min(expr_scaled), ", ", max(expr_scaled), "]\n", sep="")

# Check for any Inf/NaN values
if (any(is.infinite(as.matrix(expr_scaled))) || any(is.nan(as.matrix(expr_scaled)))) {
 cat("WARNING: Inf/NaN values detected after scaling!\n")
 # Replace Inf/NaN with NA and then impute
 expr_scaled[is.infinite(as.matrix(expr_scaled)) | is.nan(as.matrix(expr_scaled))] <- NA
 expr_scaled <- impute_half_min(expr_scaled)
}

# ------------------------------
# Step6: Save preprocessed matrix
# ------------------------------
cat("\n=== Step6: Saving preprocessed matrix ===\n")
save_result_table(expr_scaled, output_file, row_name_col = "")

cat("\n=== Preprocessing complete! ===\n")
cat("Output saved to:", output_file, "\n")
cat("Final matrix:", nrow(expr_scaled), "features x", ncol(expr_scaled), "samples\n")
cat("Summary statistics:\n")
cat(" Min:", round(min(expr_scaled),4), "\n")
cat(" Max:", round(max(expr_scaled),4), "\n")
cat(" Mean:", round(mean(as.vector(expr_scaled)),4), "\n")
cat(" Median:", round(median(as.vector(expr_scaled)),4), "\n")
