lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Direct string replacement
# "in1:nrow" (no space between in and1) -> "in1:nrow" (with space)
lines <- gsub("in1:nrow", "in\u00201:nrow", lines, fixed=TRUE)
lines <- gsub("in1:n_perm", "in\u00201:n_perm", lines, fixed=TRUE)
writeLines(lines, "G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Fixed!\n")
# Verify
lines2 <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Remaining 'in1:' issues:\n")
cat(grep("in1:", lines2, value=TRUE), sep="\n")
