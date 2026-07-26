lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Look for syntax issues - check what's before and after key lines
cat("Line595-625:\n")
for (i in 595:min(625, length(lines))) {
 cat(sprintf("%3d: %s\n", i, lines[i]))
}
