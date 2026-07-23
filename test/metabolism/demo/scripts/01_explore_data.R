# Explore expression data before preprocessing
source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/missing_value.R")
source("G:/OmicsWorks/agent/rscript/normalization.R")

# Load data
expr <- load_expression_matrix("G:/OmicsWorks/test/metabolism/expression.csv")
meta <- load_sample_metadata("G:/OmicsWorks/test/metabolism/sampleinfo.csv")

cat("Expression matrix dimensions:", nrow(expr), "x", ncol(expr), "\n")
cat("Sample names:", colnames(expr), "\n\n")

cat("Sample metadata:\n")
print(table(meta$sample_info))
cat("\n")

# Check for NA values
cat("Total NA values:", sum(is.na(expr)), "\n")
cat("NA ratio:", mean(is.na(expr)) *100, "%\n\n")

# Get value range
cat("Value range: [", min(expr, na.rm=TRUE), ", ", max(expr, na.rm=TRUE), "]\n")
cat("Mean:", mean(expr, na.rm=TRUE), "\n")
cat("Median:", median(unlist(expr), na.rm=TRUE), "\n\n")

# Check max per sample
max_per_sample <- apply(expr,2, max, na.rm=TRUE)
cat("Max per sample:", max_per_sample, "\n")
cat("Overall max value:", max(expr, na.rm=TRUE), "\n")

# Check if data appears log-transformed already
# If all values are small (<100), it might be log-scaled already
cat("\n--- Summary statistics ---\n")
print(summary(as.vector(expr)))

# Check zero values
cat("\nZero values:", sum(expr ==0, na.rm=TRUE), "\n")
