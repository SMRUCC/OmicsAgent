# ============================================================================
# Expression Matrix Preprocessing Script (v2 - Fixed log transform logic)
# Dataset: Metabolomics expression data (2059 metabolites x18 samples)
# Purpose: Standard preprocessing workflow for omics expression data
# Steps:
#1. Fill missing values (half-min per row) - not needed (0 NAs)
#2. Normalize by column sum (relative abundance)
#3. Log2 transformation (check on ORIGINAL data: max=283 >100 -> log needed)
#4. Median scaling per row (molecule)
# ============================================================================

library(utils)

source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/missing_value.R")
source("G:/OmicsWorks/agent/rscript/normalization.R")

# ---- Step0: Load data ----
cat("=== Step0: Loading Data ===\n")
expr <- load_expression_matrix("G:/OmicsWorks/test/metabolism/expression.csv")
meta <- load_sample_metadata("G:/OmicsWorks/test/metabolism/sampleinfo.csv")

cat("Original dimensions:", nrow(expr), "x", ncol(expr), "\n")
cat("Original data max:", max(expr, na.rm=TRUE), "\n")
cat("Sample groups:\n")
print(table(meta$sample_info))

# ---- Step1: Check and fill missing values ----
cat("\n=== Step1: Missing Value Imputation ===\n")
cat("NA count:", sum(is.na(expr)), "\n")

# No missing values, skip imputation
if (sum(is.na(expr)) >0) {
 expr <- impute_half_min(expr)
 cat("Missing values imputed.\n")
} else {
 cat("No missing values detected. Skipping imputation.\n")
}

# Check if log transformation is needed based on ORIGINAL data
# Original max =283 >100, so data is on non-log scale -> need log transform
need_log <- max(expr, na.rm=TRUE) >100
cat("Original max >100?", need_log, "- Log transformation will be applied.\n")

# ---- Step2: Normalize by column sum (relative abundance) ----
cat("\n=== Step2: Column-Sum Normalization (Relative Abundance) ===\n")
col_sums_before <- colSums(expr)
cat("Column sums before normalization: min=", round(min(col_sums_before),2),
 ", max=", round(max(col_sums_before),2), "\n")

# Relative abundance (fraction of total per sample)
expr_norm <- normalize_sample_sum(expr, scale_factor=1, pseudo_count=0)

col_sums_after <- colSums(expr_norm)
cat("Column sums after normalization:", round(unique(col_sums_after),6), "\n")

# ---- Step3: Log2 transformation (since original data max >100) ----
cat("\n=== Step3: Log2 Transformation ===\n")

if (need_log) {
 cat("Applying log2(x+1) transformation...\n")
 expr_log <- transform_log(expr_norm, base=2, pseudo_count=1)
 cat("After log2: min=", round(min(expr_log, na.rm=TRUE),4),
 ", max=", round(max(expr_log, na.rm=TRUE),4),
 ", mean=", round(mean(expr_log, na.rm=TRUE),4), "\n")
} else {
 cat("Max value <=100, data may already be log-transformed. Skipping.\n")
 expr_log <- expr_norm
}

# ---- Step4: Median scaling per row (molecule) ----
cat("\n=== Step4: Median Scaling per Molecule ===\n")
expr_scaled <- scale_feature_median(expr_log, log_transform=FALSE)

cat("After median scaling: min=", round(min(expr_scaled, na.rm=TRUE),4),
 ", max=", round(max(expr_scaled, na.rm=TRUE),4),
 ", median=", round(median(expr_scaled, na.rm=TRUE),4), "\n")

# ---- Validate output ----
cat("\n=== Validation ===\n")
cat("Any NA in output?", any(is.na(expr_scaled)), "\n")
cat("Number of features with median=1 (expected for all):",
 sum(apply(expr_scaled,1, function(x) identical(median(x),1))), "\n")
cat("Output dimensions:", nrow(expr_scaled), "x", ncol(expr_scaled), "\n")

# ---- Save preprocessed matrix ----
output_file <- "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv"
write.csv(cbind(molecule=rownames(expr_scaled), as.data.frame(expr_scaled)),
 output_file, row.names=FALSE)

cat("\n=== Preprocessing Complete ===\n")
cat("Output saved to:", output_file, "\n")

# ---- Write report ----
report <- paste0(
"=== Preprocessing Report ===\n",
"Date: ", Sys.time(), "\n",
"Input file: G:/OmicsWorks/test/metabolism/expression.csv\n",
"Sample metadata: G:/OmicsWorks/test/metabolism/sampleinfo.csv\n",
"Output file: ", output_file, "\n\n",
"Original data:\n",
" Dimensions:2059 molecules x18 samples\n",
" NA count: ", sum(is.na(expr_orig)), "\n",
" Min: ", round(min(expr_orig, na.rm=TRUE),4), "\n",
" Max: ", round(max(expr_orig, na.rm=TRUE),4), "\n",
" Column sum range: ", round(min(colSums(expr_orig, na.rm=TRUE)),2),
 " - ", round(max(colSums(expr_orig, na.rm=TRUE)),2), "\n\n",
"Samples:\n",
" Clostridium difficile infection: Fc16YH_CD1-Fc16YH_CD6 (6 samples)\n",
" high iron diet before: Fc16YH_FE1-Fc16YH_FE6 (6 samples)\n",
" Standard (control): Fc16YH_NC1-Fc16YH_NC6 (6 samples)\n\n",
"Preprocessing steps applied:\n",
"1. Missing value imputation (half-min per row):0 NAs found - skipped\n",
"2. Column-sum normalization (relative abundance): applied (scale_factor=1)\n",
"3. Log2 transformation (+1 pseudo-count): applied (original max=",
 round(max(expr_orig, na.rm=TRUE),2), ">100, non-log scale)\n",
"4. Median scaling per molecule: applied\n\n",
"Final data:\n",
" Dimensions: ", nrow(expr_scaled), " x ", ncol(expr_scaled), "\n",
" Min: ", round(min(expr_scaled, na.rm=TRUE),4), "\n",
" Max: ", round(max(expr_scaled, na.rm=TRUE),4), "\n",
" Median: ", round(median(expr_scaled, na.rm=TRUE),4), "\n"
)

# Need original data for report
expr_orig <- load_expression_matrix("G:/OmicsWorks/test/metabolism/expression.csv")
report <- paste0(
"=== Preprocessing Report ===\n",
"Date: ", Sys.time(), "\n",
"Input file: G:/OmicsWorks/test/metabolism/expression.csv\n",
"Sample metadata: G:/OmicsWorks/test/metabolism/sampleinfo.csv\n",
"Output file: ", output_file, "\n\n",
"Original data:\n",
" Dimensions:2059 molecules x18 samples\n",
" NA count: ", sum(is.na(expr_orig)), "\n",
" Min: ", round(min(expr_orig, na.rm=TRUE),4), "\n",
" Max: ", round(max(expr_orig, na.rm=TRUE),4), "\n",
" Column sum range: ", round(min(colSums(expr_orig, na.rm=TRUE)),2),
 " - ", round(max(colSums(expr_orig, na.rm=TRUE)),2), "\n\n",
"Samples:\n",
" Clostridium difficile infection: Fc16YH_CD1-Fc16YH_CD6 (6 samples)\n",
" high iron diet before: Fc16YH_FE1-Fc16YH_FE6 (6 samples)\n",
" Standard (control): Fc16YH_NC1-Fc16YH_NC6 (6 samples)\n\n",
"Preprocessing steps applied:\n",
"1. Missing value imputation (half-min per row):0 NAs found - skipped\n",
"2. Column-sum normalization (relative abundance): applied (scale_factor=1)\n",
"3. Log2 transformation (+1 pseudo-count): applied (original max=",
 round(max(expr_orig, na.rm=TRUE),2), ">100, non-log scale)\n",
"4. Median scaling per molecule: applied\n\n",
"Final data:\n",
" Dimensions: ", nrow(expr_scaled), " x ", ncol(expr_scaled), "\n",
" Min: ", round(min(expr_scaled, na.rm=TRUE),4), "\n",
" Max: ", round(max(expr_scaled, na.rm=TRUE),4), "\n",
" Median: ", round(median(expr_scaled, na.rm=TRUE),4), "\n"
)

writeLines(report, "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessing_report.txt")
cat("\nReport saved to: G:/OmicsWorks/test/metabolism/demo/tmp/preprocessing_report.txt\n")
