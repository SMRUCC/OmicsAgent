lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Fix the plsda call - remove center=TRUE
target <- grep("mixOmics::plsda", lines)
cat("Found plsda call at line", target, "\n")
cat("Before:", lines[target], "\n")
lines[target] <- gsub(", center = TRUE", "", lines[target])
cat("After:", lines[target], "\n")
writeLines(lines, "G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Fixed.\n")
