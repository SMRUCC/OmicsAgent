# Additional data checks
data <- read.csv("G:/OmicsWorks/test/metabolism/expression.csv", row.names =1, check.names = FALSE)

# Check molecules with high values
high_val <- apply(data,1, max)
cat("Number of molecules with max >100:", sum(high_val >100), "\n")
cat("Molecules with max >100:", paste(rownames(data)[high_val >100], collapse=", "), "\n")

# Check overall structure
cat("\nFirst few row names:", paste(head(rownames(data)), collapse=", "), "\n")
cat("Last few row names:", paste(tail(rownames(data)), collapse=", "), "\n")

# Check group means
cd_cols <- grep("CD", colnames(data), value=TRUE)
fe_cols <- grep("FE", colnames(data), value=TRUE)
nc_cols <- grep("NC", colnames(data), value=TRUE)
cat("\nCD samples:", length(cd_cols), "\n")
cat("FE samples:", length(fe_cols), "\n")
cat("NC samples:", length(nc_cols), "\n")
