# Additional inspection of expression data
source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/normalization.R")

expr <- load_expression_matrix("G:/OmicsWorks/test/metabolism/expression.csv")

# Check column sums
cat("Column sums:\n")
print(colSums(expr, na.rm=TRUE))

cat("\nColumn sums range:", range(colSums(expr, na.rm=TRUE)), "\n")

# Check distribution of values
cat("\nValue quantiles:\n")
print(quantile(as.vector(expr), probs=c(0,0.01,0.05,0.1,0.25,0.5,0.75,0.9,0.95,0.99,1)))

# Check for rows with very high values
max_per_row <- apply(expr,1, max, na.rm=TRUE)
cat("\nRows with max >100:\n")
high_rows <- which(max_per_row >100)
cat("Count:", length(high_rows), "\n")
if(length(high_rows) >0) {
 print(head(expr[high_rows,],3))
}

cat("\nRows with max >50:\n")
high_rows2 <- which(max_per_row >50)
cat("Count:", length(high_rows2), "\n")
