# Check expression data before preprocessing
source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/missing_value.R")
source("G:/OmicsWorks/agent/rscript/normalization.R")

expr <- load_expression_matrix("G:/OmicsWorks/test/metabolism/expression.csv")
meta <- load_sample_metadata("G:/OmicsWorks/test/metabolism/sampleinfo.csv")

cat("=== Expression Matrix Info ===\n")
cat("Dimensions:", nrow(expr), "features x", ncol(expr), "samples\n")
cat("Sample IDs:", colnames(expr), "\n\n")

cat("=== Sample Info ===\n")
print(table(meta$sample_info))
cat("\n")

cat("=== Data Range ===\n")
cat("Min value:", min(expr, na.rm=TRUE), "\n")
cat("Max value:", max(expr, na.rm=TRUE), "\n")
cat("Mean value:", mean(expr, na.rm=TRUE), "\n")
cat("Median value:", median(expr, na.rm=TRUE), "\n\n")

cat("=== Missing Values ===\n")
cat("Total NA count:", sum(is.na(expr)), "\n")
cat("NA ratio:", mean(is.na(expr)) *100, "%\n")

# Check if values >100 exist (to determine if log transform needed)
cat("\n=== Values >100 ===\n")
cat("Number of values >100:", sum(expr >100, na.rm=TRUE), "\n")
cat("Number of values >10:", sum(expr >10, na.rm=TRUE), "\n")
cat("Number of values >5:", sum(expr >5, na.rm=TRUE), "\n")

# Per-feature NA counts
na_per_feature <- rowSums(is.na(expr))
cat("\n=== Features with NAs ===\n")
cat("Features with any NA:", sum(na_per_feature >0), "\n")
if (sum(na_per_feature >0) >0) {
 cat("Max NA per feature:", max(na_per_feature), "\n")
 cat("Features with NAs:\n")
 print(head(expr[na_per_feature >0, ],10))
}

# Check column sums
col_sums <- colSums(expr, na.rm=TRUE)
cat("\n=== Column Sums (by sample) ===\n")
print(round(col_sums,2))

# Check zeros
cat("\n=== Zero Values ===\n")
cat("Number of zeros:", sum(expr ==0, na.rm=TRUE), "\n")

# Check first few rows
cat("\n=== First5 Rows ===\n")
print(head(expr[,1:6],5))

# Save summary to file
sink("G:/OmicsWorks/test/metabolism/demo/tmp/data_check_summary.txt")
cat("=== Expression Matrix Info ===\n")
cat("Dimensions:", nrow(expr), "features x", ncol(expr), "samples\n")
cat("Sample IDs:", colnames(expr), "\n\n")
cat("=== Sample Info ===\n")
print(table(meta$sample_info))
cat("\n")
cat("=== Data Statistics ===\n")
cat("Min:", min(expr, na.rm=TRUE), "\n")
cat("Max:", max(expr, na.rm=TRUE), "\n")
cat("Mean:", mean(expr, na.rm=TRUE), "\n")
cat("Median:", median(expr, na.rm=TRUE), "\n")
cat("NA count:", sum(is.na(expr)), "\n")
cat("NA ratio:", mean(is.na(expr)) *100, "%\n")
cat("Values >100:", sum(expr >100, na.rm=TRUE), "\n")
cat("Values ==0:", sum(expr ==0, na.rm=TRUE), "\n")
cat("Column sums range:", min(col_sums), "-", max(col_sums), "\n")
sink()
