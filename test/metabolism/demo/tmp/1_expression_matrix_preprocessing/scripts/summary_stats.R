# Read the preprocessed data and gather summary statistics
mat <- read.csv("G:/OmicsWorks/test/metabolism/demo/tmp/1_expression_matrix_preprocessing/preprocessed_expression.csv", row.names=1, check.names=FALSE)
cat("=== FINAL PREPROCESSED MATRIX ===\n")
cat("Dimensions:", nrow(mat), "rows x", ncol(mat), "cols\n")
cat("Samples:", paste(colnames(mat), collapse=", "), "\n")
cat("Min:", min(mat), "\n")
cat("Max:", max(mat), "\n")
cat("Mean:", mean(as.matrix(mat)), "\n")
cat("Median:", median(as.matrix(mat)), "\n")
cat("SD:", sd(as.matrix(mat)), "\n\n")

# Check median per feature
medians <- apply(mat,1, median)
cat("Feature medians - min:", min(medians), "max:", max(medians), "\n")
cat("Features with median !=1:", sum(abs(medians-1)>0.01), "\n\n")

# Load raw data for comparison
raw <- read.csv("G:/OmicsWorks/test/metabolism/expression.csv", row.names=1, check.names=FALSE)
cat("=== RAW MATRIX ===\n")
cat("Dimensions:", nrow(raw), "rows x", ncol(raw), "cols\n")
cat("Min:", min(as.matrix(raw)), "\n")
cat("Max:", max(as.matrix(raw)), "\n")
cat("Mean:", mean(as.matrix(raw)), "\n")
cat("Median:", median(as.matrix(raw)), "\n")
cat("SD:", sd(as.matrix(raw)), "\n")
cat("NA count:", sum(is.na(raw)), "\n\n")

# Load step2 normalized
norm2 <- read.csv("G:/OmicsWorks/test/metabolism/demo/tmp/1_expression_matrix_preprocessing/preprocess_step2_normalized.csv", row.names=1, check.names=FALSE)
cat("=== STEP2 (PPM) ===\n")
cat("Min:", min(as.matrix(norm2)), "\n")
cat("Max:", max(as.matrix(norm2)), "\n")
cat("Mean:", mean(as.matrix(norm2)), "\n")
cat("ColSums: min=", min(colSums(norm2)), "max=", max(colSums(norm2)), "\n\n")

# Load step3 log2
log2m <- read.csv("G:/OmicsWorks/test/metabolism/demo/tmp/1_expression_matrix_preprocessing/preprocess_step3_log2.csv", row.names=1, check.names=FALSE)
cat("=== STEP3a (LOG2) ===\n")
cat("Min:", min(as.matrix(log2m)), "\n")
cat("Max:", max(as.matrix(log2m)), "\n")
cat("Mean:", mean(as.matrix(log2m)), "\n\n")

# Sample info
meta <- read.csv("G:/OmicsWorks/test/metabolism/sampleinfo.csv")
cat("=== SAMPLE INFO ===\n")
print(table(meta$sample_info))
cat("\n")

# Per-group stats on final matrix
cat("=== PER-GROUP MEANS (final scaled) ===\n")
cd_cols <- grep("CD", colnames(mat), value=TRUE)
fe_cols <- grep("FE", colnames(mat), value=TRUE)
nc_cols <- grep("NC", colnames(mat), value=TRUE)
cat("CD group mean:", mean(as.matrix(mat[,cd_cols])), "\n")
cat("FE group mean:", mean(as.matrix(mat[,fe_cols])), "\n")
cat("NC group mean:", mean(as.matrix(mat[,nc_cols])), "\n")
