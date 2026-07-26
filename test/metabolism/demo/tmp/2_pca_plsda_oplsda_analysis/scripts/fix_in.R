lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Fix "in1" -> "in1" (add space after 'in')
# The pattern is: `in1` as in `for (i in 1:nrow)` should be `for (i in 1:nrow)`
# Let me replace "in1:" with "in1:" (with space)
lines <- gsub("in1:", "in1:", lines)
lines <- gsub("in1:n_perm", "in1:n_perm", lines)
writeLines(lines, "G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Fixed spacing!\n")
