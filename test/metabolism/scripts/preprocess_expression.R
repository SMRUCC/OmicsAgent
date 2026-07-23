###############################################################################
# Expression Matrix Preprocessing Script
# Data: Metabolomics expression data for CDI study
# Steps:
#1. Load expression matrix and sample metadata
#2. Fill missing values with half-minimum positive value per row
#3. Normalize by column sum (relative abundance, ppm)
#4. Apply log2 transformation (since max >100)
#5. Median scaling per row (molecule)
#6. Save preprocessed matrix to tmp/
###############################################################################

# Source the R scripts
source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/missing_value.R")
source("G:/OmicsWorks/agent/rscript/normalization.R")

# ============================================================
#1. Load Data
# ============================================================
cat("\n========================================\n")
cat("Step1: Loading expression matrix...\n")
expr_raw <- load_expression_matrix("G:/OmicsWorks/test/metabolism/expression.csv")
cat(" Dimensions:", nrow(expr_raw), "x", ncol(expr_raw), "\n")

meta_raw <- load_sample_metadata("G:/OmicsWorks/test/metabolism/sampleinfo.csv")
cat(" Sample metadata:", nrow(meta_raw), "samples\n")

# Subset metadata to only include samples present in expression matrix
meta <- meta_raw[meta_raw$ID %in% colnames(expr_raw), ]
cat(" Subset metadata to", nrow(meta), "samples matching expression matrix\n")

cat("\nSample groups:\n")
print(table(meta$sample_info))

# ============================================================
#2. Fill Missing Values
# ============================================================
cat("\n========================================\n")
cat("Step2: Imputing missing values...\n")
cat(" NA count before imputation:", sum(is.na(expr_raw)), "\n")
expr_imputed <- impute_half_min(expr_raw)
cat(" NA count after imputation:", sum(is.na(expr_imputed)), "\n")

# ============================================================
#3. Normalize by Column Sum (Relative Abundance)
# ============================================================
cat("\n========================================\n")
cat("Step3: Normalizing by column sum (relative abundance in ppm)...\n")

cat(" Column sums before normalization:\n")
print(round(colSums(expr_imputed),2))

# Column sum normalization to relative abundance (ppm units)
expr_norm <- normalize_sample_sum(expr_imputed, scale_factor =1e6, pseudo_count =1)

cat(" Column sums after normalization (should be ~1e6):\n")
print(round(colSums(expr_norm),2))

cat(" Data range after normalization:", 
 round(min(expr_norm),4), "to", round(max(expr_norm),4), "\n")

# ============================================================
#4. Log Transformation (since max >100)
# ============================================================
cat("\n========================================\n")
cat("Step4: Applying log transformation...\n")

max_val <- max(expr_norm, na.rm = TRUE)
cat(" Max value in normalized data:", round(max_val,4), "\n")

if (max_val >100) {
 cat(" Max >100, applying log2(x+1) transformation.\n")
 expr_log <- transform_log(expr_norm, base =2, pseudo_count =1)
} else {
 cat(" Max <=100, data appears already log-transformed. Skipping log transformation.\n")
 expr_log <- expr_norm
}

cat(" Data range after log2:", round(min(expr_log),4), "to", round(max(expr_log),4), "\n")

# ============================================================
#5. Median Scaling per Row
# ============================================================
cat("\n========================================\n")
cat("Step5: Median scaling per row (molecule)...\n")

expr_scaled <- scale_feature_median(expr_log, log_transform = FALSE)

cat(" Data range after median scaling:", 
 round(min(expr_scaled),4), "to", round(max(expr_scaled),4), "\n")

# Check that each row's median is now1
row_medians <- apply(expr_scaled,1, median, na.rm = TRUE)
cat(" Row median range:", round(min(row_medians),4), "to", round(max(row_medians),4), "\n")

# ============================================================
#6. Save Preprocessed Matrix
# ============================================================
cat("\n========================================\n")
cat("Step6: Saving preprocessed matrix...\n")

output_file <- "G:/OmicsWorks/test/metabolism/tmp/preprocessed_expression.csv"

# Save with row names as first column
save_result_table(expr_scaled, output_file, row_name_col = "Metabolite")

cat(" Preprocessed matrix saved to:", output_file, "\n")
cat(" Final dimensions:", nrow(expr_scaled), "x", ncol(expr_scaled), "\n")

# Also save the sample metadata for downstream use
meta_output <- "G:/OmicsWorks/test/metabolism/tmp/preprocessed_sampleinfo.csv"
write.csv(meta, meta_output, row.names = FALSE)
cat(" Sample metadata saved to:", meta_output, "\n")

cat("\n========================================\n")
cat("Preprocessing completed successfully!\n")
cat("========================================\n")

# Print summary statistics
cat("\nFinal data summary:\n")
cat(" Molecules:", nrow(expr_scaled), "\n")
cat(" Samples:", ncol(expr_scaled), "\n")
cat(" Groups: ", paste(levels(meta$sample_info), collapse = ", "), "\n")
cat(" Value range: [", round(min(expr_scaled),4), ", ", round(max(expr_scaled),4), "]\n")
