# Quick check of data characteristics
expr <- read.csv("G:/OmicsWorks/test/metabolism/expression.csv", 
 row.names =1, check.names = FALSE, stringsAsFactors = FALSE)
cat("Dimensions:", nrow(expr), "x", ncol(expr), "\n")
cat("Max value:", max(as.matrix(expr), na.rm = TRUE), "\n")
cat("Min value:", min(as.matrix(expr), na.rm = TRUE), "\n")
cat("NA count:", sum(is.na(as.matrix(expr))), "\n")
cat("Zero count:", sum(as.matrix(expr) ==0, na.rm = TRUE), "\n")
cat("Values <0:", sum(as.matrix(expr) <0, na.rm = TRUE), "\n")

# Check sample names
cat("\nSample columns:\n")
print(colnames(expr))
