# Debug: how to get variance explained from mixOmics plsda
library(mixOmics)
X <- matrix(rnorm(30*10),30,10)
Y <- factor(rep(c("A","B","C"), each=10))
m <- plsda(X,Y,ncomp=2,scale=TRUE)

# Check what attributes are available
cat("Names in model:\n")
print(names(m))

# Check sdev / explained variance related fields
cat("\nnames(m$X):\n")
print(names(m$X))

# Try to compute variance explained manually
scores <- m$variates$X
cat("\nScores variances:\n")
print(apply(scores,2,var))
cat("Total variance:", sum(apply(scores,2,var)), "\n")

# Proportion
var_exp <- apply(scores,2,var) / sum(apply(scores,2,var))
cat("Proportion:\n")
print(var_exp)
