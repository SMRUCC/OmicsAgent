# Check data characteristics before preprocessing
source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/missing_value.R")

expr <- load_expression_matrix("G:/OmicsWorks/test/metabolism/expression.csv")
meta <- load_sample_metadata("G:/OmicsWorks/test/metabolism/sampleinfo.csv")

cat("Expression matrix dimensions:", nrow(expr), "features x", ncol(expr), "samples\n")
cat("Sample IDs in expression:", colnames(expr), "\n")
cat("\nSample info groups:\n")
print(table(meta$sample_info))

cat("\n--- Data range ---\n")
cat("Min value:", min(expr, na.rm=TRUE), "\n")
cat("Max value:", max(expr, na.rm=TRUE), "\n")
cat("Mean value:", mean(expr, na.rm=TRUE), "\n")
cat("Median value:", median(as.vector(expr), na.rm=TRUE), "\n")

cat("\n--- Missing values ---\n")
cat("Total NAs:", sum(is.na(expr)), "\n")
cat("NA ratio:", mean(is.na(expr)), "\n")

cat("\n--- Value distribution (percentiles) ---\n")
all_vals <- as.vector(expr)
cat("1%:", quantile(all_vals,0.01, na.rm=TRUE), "\n")
cat("5%:", quantile(all_vals,0.05, na.rm=TRUE), "\n")
cat("25%:", quantile(all_vals,0.25, na.rm=TRUE), "\n")
cat("50%:", quantile(all_vals,0.50, na.rm=TRUE), "\n")
cat("75%:", quantile(all_vals,0.75, na.rm=TRUE), "\n")
cat("95%:", quantile(all_vals,0.95, na.rm=TRUE), "\n")
cat("99%:", quantile(all_vals,0.99, na.rm=TRUE), "\n")

cat("\n--- Zero values ---\n")
cat("Number of zero values:", sum(expr ==0, na.rm=TRUE), "\n")
cat("Zero ratio:", mean(expr ==0, na.rm=TRUE), "\n")

cat("\n--- Column sums (per sample) ---\n")
col_sums <- colSums(expr, na.rm=TRUE)
print(round(col_sums,4))

cat("\n--- First few features check ---\n")
print(head(expr[,1:6],10))

cat("\n--- Check if data appears already log-transformed ---\n")
# If values are in range0.1-10, likely already normalized
# If values >100, likely raw counts/areas
cat("Values >100:", sum(all_vals >100, na.rm=TRUE), "\n")
cat("Values >10:", sum(all_vals >10, na.rm=TRUE), "\n")
cat("Values between0.01-10:", sum(all_vals >=0.01 & all_vals <=10, na.rm=TRUE), "/", length(all_vals), "\n")
