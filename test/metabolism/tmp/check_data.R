# Check expression data summary
library(data.table)

expr <- fread("G:/OmicsWorks/test/metabolism/expression.csv", header=TRUE, data.table=FALSE)
cat("Dimensions:", nrow(expr), "rows x", ncol(expr), "cols\n")
cat("First column name:", colnames(expr)[1], "\n")
cat("Sample columns:", ncol(expr)-1, "\n")

# Check for NA/empty
na_count <- sum(is.na(expr))
cat("Total NA values:", na_count, "\n")

# Check for zeros
zero_count <- sum(expr[,-1] ==0, na.rm=TRUE)
cat("Total zero values:", zero_count, "\n")

# Summary stats
mat <- as.matrix(expr[,-1])
cat("Min value:", min(mat, na.rm=TRUE), "\n")
cat("Max value:", max(mat, na.rm=TRUE), "\n")
cat("Mean:", mean(mat, na.rm=TRUE), "\n")
cat("Median:", median(mat, na.rm=TRUE), "\n")

# Per row min positive
row_mins <- apply(mat,1, function(x) min(x[x >0], na.rm=TRUE))
cat("Min positive value per row - range:", min(row_mins), "to", max(row_mins), "\n")

# Check if values look log-transformed
cat("\nValue distribution (quantiles):\n")
print(quantile(mat, probs=c(0,0.01,0.05,0.25,0.5,0.75,0.95,0.99,1), na.rm=TRUE))

# Check sample sums
col_sums <- colSums(mat, na.rm=TRUE)
cat("\nColumn sums range:", min(col_sums), "to", max(col_sums), "\n")
cat("Column sums:\n")
print(round(col_sums,4))
