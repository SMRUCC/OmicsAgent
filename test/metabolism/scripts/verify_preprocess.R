# Check preprocessed data characteristics
expr <- read.csv("G:/OmicsWorks/test/metabolism/tmp/preprocessed_expression.csv", row.names =1, check.names = FALSE)
expr_matrix <- as.matrix(expr)
mode(expr_matrix) <- "numeric"

cat("Dimensions:", nrow(expr_matrix), "molecules x", ncol(expr_matrix), "samples\n")
cat("Missing values:", sum(is.na(expr_matrix)), "\n")
cat("Zero values:", sum(expr_matrix ==0), "\n")
cat("Negative values:", sum(expr_matrix <0), "\n")
cat("Max value:", max(expr_matrix), "\n")
cat("Min value:", min(expr_matrix), "\n")
cat("Mean value:", mean(expr_matrix), "\n")
cat("Median value:", median(expr_matrix), "\n\n")

cat("Quantiles:\n")
print(quantile(expr_matrix, probs = c(0,0.01,0.05,0.25,0.5,0.75,0.95,0.99,1)))

cat("\nColumn sums (should be equal after relative abundance normalization):\n")
col_sums <- colSums(expr_matrix)
print(round(col_sums,4))

cat("\nRow medians (should be0 after median scaling):\n")
row_medians <- apply(expr_matrix,1, median)
print(round(head(row_medians),6))
cat("All row medians near zero:", all(abs(row_medians) <1e-10), "\n")
