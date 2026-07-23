# ============================================================================
# Expression Matrix Preprocessing Script
# ============================================================================
# Topic:高铁饮食对感染艰难梭菌小鼠的代谢组学影响
# Dataset: Metabolomics expression matrix (LC-MS),2059 metabolites ×18 samples
# Groups: CD (Clostridium difficile infection, n=6), FE (high iron diet before, n=6),
# NC (Standard control, n=6)
#
# Preprocessing steps:
#1. Fill NA/zero values with half of minimum positive value per row
#2. Column-sum normalization to relative abundance (×1e6 for readability)
#3. Log2 transformation (if max value >100, indicating raw scale)
#4. Row median scaling (subtract row median)
#
# Output:
# - tmp/preprocessed_expression.csv : preprocessed matrix
# - tmp/preprocessing_summary.txt : summary statistics
# ============================================================================

# ---- Load helper functions ----
source("G:/OmicsWorks/agent/rscript/preprocess_expression.R")

# ---- File paths ----
input_file <- "G:/OmicsWorks/test/metabolism/expression.csv"
output_file <- "G:/OmicsWorks/test/metabolism/tmp/preprocessed_expression.csv"
summary_file <- "G:/OmicsWorks/test/metabolism/tmp/preprocessing_summary.txt"
sampleinfo_file <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"

# ---- Read original data for summary ----
cat("========================================\n")
cat("Step0: Reading input data\n")
cat("========================================\n")

expr_raw <- read.csv(input_file, row.names =1, check.names = FALSE,
 stringsAsFactors = FALSE)
sampleinfo <- read.csv(sampleinfo_file, stringsAsFactors = FALSE)

cat(sprintf("Expression matrix: %d molecules × %d samples\n",
 nrow(expr_raw), ncol(expr_raw)))
cat(sprintf("Sample info: %d rows\n", nrow(sampleinfo)))

# ---- Build sample-to-group mapping ----
# Exclude QC samples (not present in expression matrix, but keep mapping clean)
sample_groups <- setNames(sampleinfo$sample_info, sampleinfo$sample_name)
# Only keep samples that exist in expression matrix
samples_in_matrix <- colnames(expr_raw)
sample_groups <- sample_groups[names(sample_groups) %in% samples_in_matrix]

cat("\nSample groups in expression matrix:\n")
print(table(sample_groups))

# ---- Compute pre-processing statistics BEFORE processing ----
cat("\n========================================\n")
cat("Step1: Computing 'before' statistics\n")
cat("========================================\n")

expr_matrix_raw <- as.matrix(expr_raw)
mode(expr_matrix_raw) <- "numeric"

na_count_before <- sum(is.na(expr_matrix_raw))
zero_count_before <- sum(expr_matrix_raw ==0, na.rm = TRUE)
neg_count_before <- sum(expr_matrix_raw <0, na.rm = TRUE)
min_val_before <- min(expr_matrix_raw, na.rm = TRUE)
max_val_before <- max(expr_matrix_raw, na.rm = TRUE)
median_val_before <- median(expr_matrix_raw, na.rm = TRUE)
mean_val_before <- mean(expr_matrix_raw, na.rm = TRUE)
sd_val_before <- sd(expr_matrix_raw, na.rm = TRUE)

cat(sprintf(" NA values: %d\n", na_count_before))
cat(sprintf(" Zero values: %d\n", zero_count_before))
cat(sprintf(" Negative values: %d\n", neg_count_before))
cat(sprintf(" Value range: [%.4f, %.4f]\n", min_val_before, max_val_before))
cat(sprintf(" Median: %.4f\n", median_val_before))
cat(sprintf(" Mean ± SD: %.4f ± %.4f\n", mean_val_before, sd_val_before))

# ---- Determine if log transformation is needed ----
do_log_transform <- (max_val_before >100)
cat(sprintf("\n Max value = %.2f → %s log2 transformation\n",
 max_val_before,
 ifelse(do_log_transform, "APPLY", "SKIP (already log scale)")))

# ---- Run preprocessing via helper function ----
cat("\n========================================\n")
cat("Step2: Running preprocessing pipeline\n")
cat("========================================\n")

result <- preprocess_expression(
 input_file = input_file,
 output_file = output_file,
 do_log = do_log_transform,
 do_median_scale = TRUE,
 fill_na_method = "half_min_positive"
)

# ---- Compute post-processing statistics ----
cat("\n========================================\n")
cat("Step3: Computing 'after' statistics\n")
cat("========================================\n")

expr_processed <- result$matrix

na_count_after <- sum(is.na(expr_processed))
zero_count_after <- sum(expr_processed ==0, na.rm = TRUE)
min_val_after <- min(expr_processed, na.rm = TRUE)
max_val_after <- max(expr_processed, na.rm = TRUE)
median_val_after <- median(expr_processed, na.rm = TRUE)
mean_val_after <- mean(expr_processed, na.rm = TRUE)
sd_val_after <- sd(expr_processed, na.rm = TRUE)

cat(sprintf(" NA values: %d\n", na_count_after))
cat(sprintf(" Zero values: %d\n", zero_count_after))
cat(sprintf(" Value range: [%.4f, %.4f]\n", min_val_after, max_val_after))
cat(sprintf(" Median: %.4f\n", median_val_after))
cat(sprintf(" Mean ± SD: %.4f ± %.4f\n", mean_val_after, sd_val_after))

# ---- Verify row median scaling ----
row_medians_after <- apply(expr_processed,1, median, na.rm = TRUE)
max_abs_row_median <- max(abs(row_medians_after))
cat(sprintf("\n Max |row median| after scaling: %.6f (should be ~0)\n",
 max_abs_row_median))

# ---- Write summary table ----
cat("\n========================================\n")
cat("Step4: Writing summary report\n")
cat("========================================\n")

summary_lines <- c(
 "============================================================",
 "Expression Matrix Preprocessing Summary",
 "============================================================",
 "",
 paste("Script run at:", Sys.time()),
 "",
 "--- Input ---",
 paste("Expression file:", input_file),
 paste("Sample info file:", sampleinfo_file),
 "",
 "--- Dataset dimensions ---",
 paste("Molecules:", nrow(expr_raw)),
 paste("Samples:", ncol(expr_raw)),
 "",
 "--- Sample groups ---",
 paste(names(table(sample_groups)), "=", as.vector(table(sample_groups)),
 collapse = ", "),
 "",
 "--- Preprocessing steps applied ---",
 "1. Fill NA/0 values with half-min-positive per row (safety no-op)",
 "2. Column-sum normalization to relative abundance (×1e6)",
 paste("3. Log2 transformation:", ifelse(do_log_transform, "YES", "NO")),
 "4. Row median scaling (subtract row median): YES",
 "",
 "--- Statistics BEFORE preprocessing ---",
 paste(" NA count:", na_count_before),
 paste(" Zero count:", zero_count_before),
 paste(" Negative count:", neg_count_before),
 paste(" Value range: [", min_val_before, ", ", max_val_before, "]", sep = ""),
 paste(" Median:", round(median_val_before,4)),
 paste(" Mean ± SD:", round(mean_val_before,4), "±", round(sd_val_before,4)),
 "",
 "--- Statistics AFTER preprocessing ---",
 paste(" NA count:", na_count_after),
 paste(" Zero count:", zero_count_after),
 paste(" Value range: [", min_val_after, ", ", max_val_after, "]", sep = ""),
 paste(" Median:", round(median_val_after,4)),
 paste(" Mean ± SD:", round(mean_val_after,4), "±", round(sd_val_after,4)),
 paste(" Max |row median| after scaling:", round(max_abs_row_median,6)),
 "",
 "--- Output ---",
 paste("Preprocessed matrix:", output_file),
 paste("Summary report:", summary_file),
 "",
 "============================================================"
)

writeLines(summary_lines, summary_file)
cat("Summary written to:", summary_file, "\n")

# ---- Final message ----
cat("\n========================================\n")
cat("PREPROCESSING COMPLETE\n")
cat("========================================\n")
cat(sprintf("Output: %s\n", output_file))
cat(sprintf("Summary: %s\n", summary_file))
cat("\n")
