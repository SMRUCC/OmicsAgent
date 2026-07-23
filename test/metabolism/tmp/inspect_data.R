# Quick inspection of expression data
source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/missing_value.R")
source("G:/OmicsWorks/agent/rscript/normalization.R")

expr <- load_expression_matrix("G:/OmicsWorks/test/metabolism/expression.csv")
meta <- load_sample_metadata("G:/OmicsWorks/test/metabolism/sampleinfo.csv")

cat("Expression matrix dimensions:", nrow(expr), "x", ncol(expr), "\n")
cat("Sample names:", colnames(expr), "\n\n")

cat("Sample metadata groups:\n")
print(table(meta$sample_info))
cat("\n")

cat("Matching samples between expr and meta:\n")
cat("Expr samples in meta:", sum(colnames(expr) %in% meta$ID), "/", ncol(expr), "\n")
cat("Meta samples in expr:", sum(meta$ID %in% colnames(expr)), "/", nrow(meta), "\n\n")

cat("Data range: min =", min(expr, na.rm=TRUE), ", max =", max(expr, na.rm=TRUE), "\n")
cat("NA count:", sum(is.na(expr)), "\n")
cat("Zero count:", sum(expr ==0, na.rm=TRUE), "\n\n")

# Check if log transformation is needed
cat("Max value:", max(expr, na.rm=TRUE), "- needs log transform?", max(expr, na.rm=TRUE) >100, "\n\n")

# Get missing value stats
na_stats <- get_missing_stats(expr)
cat(na_stats$summary, "\n")

# Check first few rows
cat("\nFirst5 rows of expression data:\n")
print(head(expr[,1:5],5))

# Save a quick summary
write.csv(data.frame(
 feature = rownames(expr),
 mean = rowMeans(expr, na.rm=TRUE),
 median = apply(expr,1, median, na.rm=TRUE),
 min = apply(expr,1, min, na.rm=TRUE),
 max = apply(expr,1, max, na.rm=TRUE),
 na_count = rowSums(is.na(expr))
), "G:/OmicsWorks/test/metabolism/tmp/expression_summary.csv", row.names=FALSE)

cat("\nSummary saved to tmp/expression_summary.csv\n")
