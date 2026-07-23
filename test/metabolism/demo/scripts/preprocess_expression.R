# ============================================================================
# Expression Matrix Preprocessing Pipeline
# Dataset: Metabolomics (LC-MS/MS) -2059 metabolites x18 samples
# Research: High-iron diet effect on CDI in mice
# ============================================================================

# Source reference R scripts
source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/missing_value.R")
source("G:/OmicsWorks/agent/rscript/normalization.R")

# ---- Step0: Load data ----
cat("=== Step0: Loading data ===\n")
expr_raw <- load_expression_matrix("G:/OmicsWorks/test/metabolism/expression.csv")
sample_meta <- load_sample_metadata("G:/OmicsWorks/test/metabolism/sampleinfo.csv")

cat("Expression matrix dimensions:", nrow(expr_raw), "x", ncol(expr_raw), "\n")
cat("Sample groups:\n")
print(table(sample_meta$sample_info))
cat("\n")

# Check if raw data needs log transformation (before normalization)
raw_max <- max(expr_raw, na.rm = TRUE)
raw_min <- min(expr_raw, na.rm = TRUE)
cat(sprintf("Raw data range: [%.4f, %.2f]\n", raw_min, raw_max))
needs_log <- raw_max >100
cat(sprintf("Needs log transformation (raw_max >100?): %s\n\n", ifelse(needs_log, "YES", "NO")))

# ---- Step1: Fill missing values with half of minimum positive value per row ----
cat("=== Step1: Missing value imputation ===\n")
cat("Number of NAs before imputation:", sum(is.na(expr_raw)), "\n")

# Filter metadata to match expression matrix sample columns
meta_matched <- sample_meta[sample_meta$ID %in% colnames(expr_raw), ]
cat("Matched samples:", nrow(meta_matched), "/", nrow(sample_meta), "\n")

# Impute NAs using half-minimum strategy
expr_imp <- impute_half_min(expr_raw)
cat("NAs after imputation:", sum(is.na(expr_imp)), "\n\n")

# ---- Step2: Normalize by column sum (relative expression) ----
cat("=== Step2: Column sum normalization ===\n")
expr_norm <- normalize_sample_sum(expr_imp, scale_factor =1, pseudo_count =0)
cat(sprintf("Normalized value range: [%.6f, %.6f]\n", min(expr_norm), max(expr_norm)))
cat("Sample sums after normalization (should all be1):\n")
print(round(colSums(expr_norm),10))
cat("\n")

# ---- Step3: Log transformation ----
cat("=== Step3: Log transformation ===\n")
if (needs_log) {
 cat(sprintf("Raw max=%.2f >100, applying log2(x+1) transformation\n", raw_max))
 expr_log <- transform_log(expr_norm, base =2, pseudo_count =1)
 cat(sprintf("Log2 value range: [%.4f, %.4f]\n", min(expr_log), max(expr_log)))
} else {
 cat("Raw max <=100, data may already be log-scaled. Skipping log transform.\n")
 expr_log <- expr_norm
}
cat("\n")

# ---- Step4: Median scaling per row (molecule) ----
cat("=== Step4: Median scaling per row ===\n")
row_medians <- apply(expr_log,1, median, na.rm = TRUE)
cat("Rows with median =0:", sum(row_medians ==0, na.rm = TRUE), "\n")

expr_scaled <- scale_feature_median(expr_log, log_transform = FALSE)
cat(sprintf("Scaled value range: [%.6f, %.2f]\n", min(expr_scaled), max(expr_scaled)))

# Check if any row median was zero and got replaced with1
zero_med_rows <- which(row_medians ==0)
if (length(zero_med_rows) >0) {
 cat("Warning:", length(zero_med_rows), "rows had median =0 (replaced with1 for division)\n")
}
cat("\n")

# ---- Save preprocessed matrix ----
cat("=== Saving preprocessed matrix ===\n")
output_path <- "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv"
save_result_table(expr_scaled, output_path, row_name_col = "metabolite")

# ---- Also save the normalized (but not scaled) version for downstream analysis ----
cat("=== Saving normalized-only matrix (optional) ===\n")
norm_output_path <- "G:/OmicsWorks/test/metabolism/demo/tmp/normalized_expression.csv"
save_result_table(expr_log, norm_output_path, row_name_col = "metabolite")

# ---- Summary report ----
cat("\n")
cat("====================================\n")
cat(" PREPROCESSING SUMMARY REPORT\n")
cat("====================================\n")
cat(sprintf(" Input file: expression.csv\n"))
cat(sprintf(" Samples: %d\n", ncol(expr_raw)))
cat(sprintf(" Metabolites: %d\n", nrow(expr_raw)))
cat(sprintf(" Missing values: %d (%.2f%%)\n", 
 sum(is.na(expr_raw)), mean(is.na(expr_raw)) *100))
cat(sprintf(" Imputation: half-minimum per row\n"))
cat(sprintf(" Normalization: column-sum (relative abundance)\n"))
cat(sprintf(" Log transform: %s (raw max=%.2f)\n", 
 ifelse(needs_log, "log2(x+1)", "none"), raw_max))
cat(sprintf(" Scaling: median per row\n"))
cat(sprintf(" Output file: preprocessed_expression.csv\n"))
cat(sprintf(" Output dims: %d x %d\n", nrow(expr_scaled), ncol(expr_scaled)))
cat("====================================\n")
