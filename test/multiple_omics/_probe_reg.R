#!/usr/bin/env Rscript
set.seed(1)
source("G:/OmicsWorks/agent/rscript/multiomics/multiomics_data.R")
source("G:/OmicsWorks/agent/rscript/multiomics/cross_omics_regression.R")

# Synthetic data
n_samp <- 30
X <- matrix(rnorm(50 * n_samp), nrow = 50)
Y <- matrix(rnorm(40 * n_samp), nrow = 40)
rownames(X) <- paste0("x", 1:50)
rownames(Y) <- paste0("y", 1:40)
colnames(X) <- colnames(Y) <- paste0("s", 1:n_samp)

res <- run_cross_omics_regression(X, Y, x_name = "X", y_name = "Y", verbose = FALSE)

# Compare to lm() for a few pairs
for (i in 1:3) {
  for (j in 1:3) {
    fit <- lm(Y[j, ] ~ X[i, ])
    s <- summary(fit)
    row <- res$pairs[res$pairs$x_feature == rownames(X)[i] &
                     res$pairs$y_feature == rownames(Y)[j], ]
    cat(sprintf("pair %s-%s: slope %.6f vs %.6f | p %.4g vs %.4g | R2 %.6f vs %.6f\n",
                rownames(X)[i], rownames(Y)[j],
                row$slope, coef(s)[2, 1],
                row$p_value, coef(s)[2, 4],
                row$r_squared, s$r.squared))
  }
}
cat("OK: regression function works, n pairs =", nrow(res$pairs), "\n")
