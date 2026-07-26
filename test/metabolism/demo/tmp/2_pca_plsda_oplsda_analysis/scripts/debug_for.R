lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Checking lines609-630:\n")
for (i in 609:min(630, length(lines))) {
 cat(i, ":", lines[i], "\n")
}
